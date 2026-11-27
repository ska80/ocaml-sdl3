#ifndef OCAML_SDL3_STUBS_H
#define OCAML_SDL3_STUBS_H

#include <SDL3/SDL.h>

#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/callback.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>

#include <float.h>
#include <limits.h>
#include <string.h>

/* Keep this in sync with the core requirement in config/discover.ml. */
#define OSDL_MIN_SDL_VERSION SDL_VERSIONNUM(3, 4, 20)
#if SDL_VERSION < OSDL_MIN_SDL_VERSION
    #error "Use SDL 3.4.20 or later to build Sdl3"
#endif

/* SDL errors. */

static inline void osdl_error_message(char* message, size_t size, const char* fn) {
    const char* error = SDL_GetError();
    SDL_snprintf(message, size, "%s: %s", fn, *error ? error : "unknown SDL error");
}

CAMLnoret static inline void osdl_raise_error(const char* message) {
    const value* exn = caml_named_value("ocaml-sdl3.error");
    if (!exn) caml_failwith(message);
    caml_raise_with_string(*exn, message);
}

CAMLnoret static inline void osdl_fail(const char* fn) {
    char message[1024];
    osdl_error_message(message, sizeof(message), fn);
    osdl_raise_error(message);
}

static inline void osdl_check(bool ok, const char* fn) {
    if (!ok) osdl_fail(fn);
}

/* Internal ABI shared by the four packages. A handle starts with two OCaml
 * fields: the custom cell and the parent handle (or unit). Some handles have
 * a third field for extra data, such as a buffer or another handle. The cell
 * stores no OCaml values or SDL finalizers. */
typedef struct {
    void*         ptr;
    size_t        children;
    /* Store the thread ID as bytes. Custom data only has word alignment. */
    unsigned char thread[sizeof(SDL_ThreadID)];
} osdl_cell;

static struct custom_operations osdl_handle_ops = {.identifier = "ocaml-sdl3.handle"};

static inline osdl_cell* osdl_cell_val(value handle) {
    return (osdl_cell*)Data_custom_val(Field(handle, 0));
}

static inline value osdl_parent(value handle) {
    return Field(handle, 1);
}

static inline value osdl_attachment(value handle) {
    return Field(handle, 2);
}

static inline void osdl_forget_attachment(value handle) {
    caml_modify(&Field(handle, 2), Val_unit);
}

static inline void osdl_require_thread(SDL_ThreadID thread) {
    if (SDL_GetCurrentThreadID() != thread)
        caml_invalid_argument("SDL resources must be used on the main thread");
}

static inline SDL_ThreadID osdl_cell_thread(const osdl_cell* cell) {
    SDL_ThreadID thread;
    memcpy(&thread, cell->thread, sizeof(thread));
    return thread;
}

static inline void* osdl_live(value handle) {
    osdl_cell* cell = osdl_cell_val(handle);
    osdl_require_thread(osdl_cell_thread(cell));
    if (!cell->ptr) caml_invalid_argument("SDL handle is closed");
    return cell->ptr;
}

static inline SDL_Surface* osdl_unlocked_surface(value surface) {
    SDL_Surface* pixels = osdl_live(surface);
    if (pixels->flags & SDL_SURFACE_LOCKED)
        caml_invalid_argument("Finish the SDL surface lock before using the surface");
    return pixels;
}

static inline void osdl_require_subsystem(value context, SDL_InitFlags flags, const char* message) {
    osdl_live(context);
    if (SDL_WasInit(flags) != flags) caml_invalid_argument(message);
}

static inline SDL_IOStream* osdl_unborrowed_io(value stream) {
    SDL_IOStream* io = osdl_live(stream);
    if (osdl_cell_val(stream)->children)
        caml_invalid_argument("Close the resource that uses this stream first");
    return io;
}

/* Stream attachments are unit, true for append files, or a bigarray. */
static inline bool osdl_append_io(value stream) {
    return osdl_attachment(stream) == Val_true;
}

static inline SDL_Window* osdl_unattached_window(value window) {
    SDL_Window* ptr = osdl_live(window);
    /* A window's only children are its renderer or GPU claim. */
    if (osdl_cell_val(window)->children)
        caml_invalid_argument("SDL window already has a renderer or GPU claim");
    return ptr;
}

/* Allocate before calling the SDL constructor, then publish without allocating.
 * This leaves no native resource to free if OCaml allocation fails. */
static inline value osdl_new_cell(value parent, struct custom_operations* ops) {
    CAMLparam1(parent);
    CAMLlocal1(cell);
    cell = caml_alloc_custom(ops, sizeof(osdl_cell), 0, 1);

    osdl_cell*   data = Data_custom_val(cell);
    SDL_ThreadID thread =
        parent == Val_unit ? SDL_GetCurrentThreadID() : osdl_cell_thread(osdl_cell_val(parent));
    data->ptr      = NULL;
    data->children = 0;
    memcpy(data->thread, &thread, sizeof(thread));

    CAMLreturn(cell);
}

static inline value osdl_new_handle_with_ops(value parent, struct custom_operations* ops) {
    CAMLparam1(parent);
    CAMLlocal1(cell);
    cell = osdl_new_cell(parent, ops);
    CAMLreturn(caml_alloc_2(0, cell, parent));
}

static inline value osdl_new_handle(value parent) {
    return osdl_new_handle_with_ops(parent, &osdl_handle_ops);
}

/* An attachment is traced by the GC but does not count as a parent. */
static inline value osdl_new_attached_handle(value parent, value attachment) {
    CAMLparam2(parent, attachment);
    CAMLlocal1(cell);
    cell = osdl_new_cell(parent, &osdl_handle_ops);
    CAMLreturn(caml_alloc_3(0, cell, parent, attachment));
}

static inline value osdl_publish(value handle, void* ptr, const char* fn) {
    if (!ptr) osdl_fail(fn);

    osdl_cell_val(handle)->ptr = ptr;
    value parent               = osdl_parent(handle);
    if (parent != Val_unit) ++osdl_cell_val(parent)->children;
    return handle;
}

/* Closing is idempotent. Refuse to close a parent while its children are live,
 * including when SDL itself would destroy the children implicitly. */
static inline void* osdl_take(value handle) {
    osdl_cell* cell = osdl_cell_val(handle);
    osdl_require_thread(osdl_cell_thread(cell));

    void* ptr = cell->ptr;
    if (!ptr) return NULL;
    if (cell->children) caml_invalid_argument("Close the child SDL handles first");

    cell->ptr    = NULL;
    value parent = osdl_parent(handle);
    if (parent != Val_unit) --osdl_cell_val(parent)->children;
    return ptr;
}

#define OSDL_DESTROY(primitive, type, destructor) \
    CAMLprim value primitive(value handle) {      \
        type* ptr = osdl_take(handle);            \
        if (ptr) destructor(ptr);                 \
        return Val_unit;                          \
    }

#define OSDL_ACTION(primitive, function)                    \
    CAMLprim value primitive(value handle) {                \
        osdl_check(function(osdl_live(handle)), #function); \
        return Val_unit;                                    \
    }

/* OCaml argument conversions. */

static inline const char* osdl_cstring(value v) {
    if (!caml_string_is_c_safe(v)) caml_invalid_argument("SDL string contains a NUL byte");
    return String_val(v);
}

static inline int osdl_int(value v) {
    intnat n = Long_val(v);
    if (n < INT_MIN || n > INT_MAX)
        caml_invalid_argument("SDL argument is outside the C int range");
    return (int)n;
}

static inline int osdl_positive_int(value v) {
    int n = osdl_int(v);
    if (n <= 0) caml_invalid_argument("SDL argument must be positive");
    return n;
}

static inline int osdl_nonnegative_int(value v) {
    int n = osdl_int(v);
    if (n < 0) caml_invalid_argument("SDL argument must not be negative");
    return n;
}

static inline bool osdl_fits_float(double n) {
    return n >= -FLT_MAX && n <= FLT_MAX;
}

static inline float osdl_float(double n) {
    if (!osdl_fits_float(n)) caml_invalid_argument("SDL argument is not a finite C float");
    return (float)n;
}

static inline Uint8 osdl_byte(value v) {
    intnat n = Long_val(v);
    if (n < 0 || n > 255) caml_invalid_argument("SDL argument must be in [0, 255]");
    return (Uint8)n;
}

static inline SDL_Color osdl_color(value v) {
    /* Sdl3.Color.t is private and already range-checked. */
    return (SDL_Color){Int_val(Field(v, 0)), Int_val(Field(v, 1)), Int_val(Field(v, 2)),
                       Int_val(Field(v, 3))};
}

/* Surface.flip and Texture.flip. */
static inline SDL_FlipMode osdl_flip_mode(value mode) {
    static const SDL_FlipMode modes[] = {SDL_FLIP_NONE, SDL_FLIP_HORIZONTAL, SDL_FLIP_VERTICAL,
                                         SDL_FLIP_HORIZONTAL_AND_VERTICAL};
    return modes[Int_val(mode)];
}

/* OCaml result values. */

static inline value osdl_val_int(int n) {
#ifndef ARCH_SIXTYFOUR
    if (n < Min_long || n > Max_long) caml_failwith("SDL result is outside the OCaml int range");
#endif
    return Val_int(n);
}

static inline value osdl_int_pair(int x, int y) {
    return caml_alloc_2(0, osdl_val_int(x), osdl_val_int(y));
}

static inline value osdl_rect_value(SDL_Rect rect) {
    return caml_alloc_4(0, osdl_val_int(rect.x), osdl_val_int(rect.y), osdl_val_int(rect.w),
                        osdl_val_int(rect.h));
}

static inline value osdl_float_pair(float x, float y) {
    CAMLparam0();
    CAMLlocal2(vx, vy);

    vx = caml_copy_double(x);
    vy = caml_copy_double(y);
    CAMLreturn(caml_alloc_2(0, vx, vy));
}

static inline value osdl_version_value(int version) {
    return caml_alloc_3(0, Val_int(SDL_VERSIONNUM_MAJOR(version)),
                        Val_int(SDL_VERSIONNUM_MINOR(version)),
                        Val_int(SDL_VERSIONNUM_MICRO(version)));
}

/* The OCaml module raises Sdl3.Error if the loaded library is too old. */
static inline value osdl_version_error(const char* library, int loaded, int minimum) {
    if (loaded >= minimum) return Val_none;

    CAMLparam0();
    CAMLlocal1(message);

    char text[128];
    SDL_snprintf(text, sizeof(text), "Loaded %s %d.%d.%d. Use %s %d.%d.%d or later", library,
                 SDL_VERSIONNUM_MAJOR(loaded), SDL_VERSIONNUM_MINOR(loaded),
                 SDL_VERSIONNUM_MICRO(loaded), library, SDL_VERSIONNUM_MAJOR(minimum),
                 SDL_VERSIONNUM_MINOR(minimum), SDL_VERSIONNUM_MICRO(minimum));
    message = caml_copy_string(text);
    CAMLreturn(caml_alloc_some(message));
}

/* Audio data shared by SDL and SDL_mixer. */

static inline SDL_AudioDeviceID osdl_audio_device_or_default(value             device,
                                                             SDL_AudioDeviceID fallback) {
    /* Sdl3.Audio.Device.id is an abstract int32. */
    return Is_long(device) ? fallback : (SDL_AudioDeviceID)Int32_val(Some_val(device));
}

static inline SDL_AudioSpec osdl_audio_spec(value v) {
    /* Sdl3.Audio.spec and Sdl3.Audio.format. */
    static const SDL_AudioFormat formats[] = {SDL_AUDIO_U8, SDL_AUDIO_S16, SDL_AUDIO_S32,
                                              SDL_AUDIO_F32};
    intnat                       channels  = Long_val(Field(v, 1));
    if (channels < 1 || channels > 8)
        caml_invalid_argument("SDL audio needs between 1 and 8 channels");
    return (SDL_AudioSpec){.format   = formats[Int_val(Field(v, 0))],
                           .channels = (int)channels,
                           .freq     = osdl_positive_int(Field(v, 2))};
}

static inline int osdl_audio_buffer_length(value buffer) {
    intnat size = Caml_ba_array_val(buffer)->dim[0];
    if (size > INT_MAX) caml_invalid_argument("SDL audio buffer is too large");
    return (int)size;
}

#endif /* OCAML_SDL3_STUBS_H */
