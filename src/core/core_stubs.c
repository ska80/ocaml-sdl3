#define SDL_MAIN_HANDLED
#include "sdl3_stubs.h"

#include <SDL3/SDL_main.h>
#include <caml/threads.h>

#include <math.h>

/* SDL context and main thread. */

static SDL_ThreadID main_thread;
static bool         initialized;

CAMLprim value osdl_bind_main_thread(value unit) {
    (void)unit;

#ifdef SDL_PLATFORM_APPLE
    if (!SDL_IsMainThread()) caml_invalid_argument("Load Sdl3 on the main thread");
#endif

    main_thread = SDL_GetCurrentThreadID();
    return Val_unit;
}

CAMLprim value osdl_is_main_thread(value unit) {
    (void)unit;
    return Val_bool(SDL_GetCurrentThreadID() == main_thread);
}

CAMLprim value osdl_version(value unit) {
    (void)unit;
    return osdl_version_value(SDL_GetVersion());
}

CAMLprim value osdl_init(value subsystems) {
    CAMLparam1(subsystems);
    CAMLlocal1(context);

    /* Sdl3.subsystem constructor order. */
    static const SDL_InitFlags flags[] = {
        SDL_INIT_AUDIO,   SDL_INIT_VIDEO,  SDL_INIT_JOYSTICK, SDL_INIT_HAPTIC,
        SDL_INIT_GAMEPAD, SDL_INIT_EVENTS, SDL_INIT_SENSOR,   SDL_INIT_CAMERA,
    };

    osdl_require_thread(main_thread);
    context = osdl_new_handle(Val_unit);
    if (initialized) caml_invalid_argument("Sdl3.init: SDL is already open");

    SDL_InitFlags mask = 0;
    for (value v = subsystems; v != Val_emptylist; v = Field(v, 1))
        mask |= flags[Int_val(Field(v, 0))];

    SDL_SetMainReady();
    if (!SDL_Init(mask)) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "SDL_Init");
        SDL_Quit();
        osdl_raise_error(message);
    }

    initialized = true;
    CAMLreturn(osdl_publish(context, &initialized, "SDL_Init"));
}

CAMLprim value osdl_quit(value context) {
    if (osdl_take(context)) {
        SDL_Quit();
        initialized = false;
    }
    return Val_unit;
}

/* Temporary SDL arrays. The private OCaml wrapper creates the owner before
 * calling SDL and frees the array even if copying to OCaml raises. */

CAMLprim value osdl_snapshot_create(value unit) {
    (void)unit;
    return osdl_new_handle(Val_unit);
}

OSDL_DESTROY(osdl_snapshot_release, void, SDL_free)

static value osdl_id_list(const Uint32* ids, int count) {
    CAMLparam0();
    CAMLlocal2(list, id);

    list = Val_emptylist;
    for (int i = count; i > 0; --i) {
        id   = caml_copy_int32((int32_t)ids[i - 1]);
        list = caml_alloc_2(0, id, list);
    }
    CAMLreturn(list);
}

/* Displays. */

static void osdl_require_display_context(value context) {
    osdl_require_subsystem(context, SDL_INIT_VIDEO, "Start SDL with Video to query displays");
}

CAMLprim value osdl_display_list(value context, value snapshot) {
    CAMLparam2(context, snapshot);

    osdl_require_display_context(context);

    int            count;
    SDL_DisplayID* ids = SDL_GetDisplays(&count);
    osdl_publish(snapshot, ids, "SDL_GetDisplays");
    CAMLreturn(osdl_id_list(ids, count));
}

CAMLprim value osdl_display_primary(value context) {
    osdl_require_display_context(context);

    SDL_DisplayID id = SDL_GetPrimaryDisplay();
    if (!id) osdl_fail("SDL_GetPrimaryDisplay");
    return caml_copy_int32((int32_t)id);
}

CAMLprim value osdl_display_name(value context, value id) {
    osdl_require_display_context(context);

    const char* name = SDL_GetDisplayName((SDL_DisplayID)Int32_val(id));
    if (!name) osdl_fail("SDL_GetDisplayName");
    return caml_copy_string(name);
}

static value osdl_rect_value(SDL_Rect rect) {
    return caml_alloc_4(0, osdl_val_int(rect.x), osdl_val_int(rect.y), osdl_val_int(rect.w),
                        osdl_val_int(rect.h));
}

static value osdl_display_rect(value context, value id, bool usable) {
    osdl_require_display_context(context);

    SDL_DisplayID display = (SDL_DisplayID)Int32_val(id);
    SDL_Rect      rect;
    if (usable)
        osdl_check(SDL_GetDisplayUsableBounds(display, &rect), "SDL_GetDisplayUsableBounds");
    else
        osdl_check(SDL_GetDisplayBounds(display, &rect), "SDL_GetDisplayBounds");
    return osdl_rect_value(rect);
}

CAMLprim value osdl_display_bounds(value context, value id) {
    return osdl_display_rect(context, id, false);
}

CAMLprim value osdl_display_usable_bounds(value context, value id) {
    return osdl_display_rect(context, id, true);
}

CAMLprim value osdl_display_content_scale(value context, value id) {
    osdl_require_display_context(context);

    float scale = SDL_GetDisplayContentScale((SDL_DisplayID)Int32_val(id));
    if (!scale) osdl_fail("SDL_GetDisplayContentScale");
    return caml_copy_double(scale);
}

static value osdl_display_mode_value(SDL_DisplayMode mode) {
    CAMLparam0();
    CAMLlocal2(density, rate);

    density = caml_copy_double(mode.pixel_density);
    rate    = caml_copy_double(mode.refresh_rate);
    CAMLreturn(caml_alloc_4(0, osdl_val_int(mode.w), osdl_val_int(mode.h), density, rate));
}

CAMLprim value osdl_display_desktop_mode(value context, value id) {
    osdl_require_display_context(context);

    const SDL_DisplayMode* mode = SDL_GetDesktopDisplayMode((SDL_DisplayID)Int32_val(id));
    if (!mode) osdl_fail("SDL_GetDesktopDisplayMode");
    return osdl_display_mode_value(*mode);
}

CAMLprim value osdl_display_current_mode(value context, value id) {
    osdl_require_display_context(context);

    const SDL_DisplayMode* mode = SDL_GetCurrentDisplayMode((SDL_DisplayID)Int32_val(id));
    if (!mode) osdl_fail("SDL_GetCurrentDisplayMode");
    return osdl_display_mode_value(*mode);
}

CAMLprim value osdl_display_fullscreen_modes(value context, value id, value snapshot) {
    CAMLparam3(context, id, snapshot);
    CAMLlocal2(list, mode);

    osdl_require_display_context(context);

    int               count;
    SDL_DisplayMode** modes = SDL_GetFullscreenDisplayModes((SDL_DisplayID)Int32_val(id), &count);
    osdl_publish(snapshot, modes, "SDL_GetFullscreenDisplayModes");

    list = Val_emptylist;
    for (int i = count; i > 0; --i) {
        mode = osdl_display_mode_value(*modes[i - 1]);
        list = caml_alloc_2(0, mode, list);
    }
    CAMLreturn(list);
}

/* Windows. */

CAMLprim value osdl_window_create(value flags, value context, value title, value w, value h) {
    CAMLparam5(flags, context, title, w, h);
    CAMLlocal1(handle);

    /* Sdl3.Window.flag constructor order. */
    static const SDL_WindowFlags bits[] = {
        SDL_WINDOW_FULLSCREEN,         SDL_WINDOW_HIDDEN,
        SDL_WINDOW_RESIZABLE,          SDL_WINDOW_BORDERLESS,
        SDL_WINDOW_HIGH_PIXEL_DENSITY,
    };

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_WindowFlags mask = 0;
    for (value v = Is_long(flags) ? Val_emptylist : Some_val(flags); v != Val_emptylist;
         v       = Field(v, 1))
        mask |= bits[Int_val(Field(v, 0))];

    SDL_Window* window =
        SDL_CreateWindow(osdl_cstring(title), osdl_positive_int(w), osdl_positive_int(h), mask);
    CAMLreturn(osdl_publish(handle, window, "SDL_CreateWindow"));
}

OSDL_DESTROY(osdl_window_destroy, SDL_Window, SDL_DestroyWindow)

CAMLprim value osdl_window_id(value window) {
    SDL_WindowID id = SDL_GetWindowID(osdl_live(window));
    if (!id) osdl_fail("SDL_GetWindowID");
    return caml_copy_int32((int32_t)id);
}

CAMLprim value osdl_window_title(value window) {
    return caml_copy_string(SDL_GetWindowTitle(osdl_live(window)));
}

CAMLprim value osdl_window_size(value window) {
    int w, h;
    osdl_check(SDL_GetWindowSize(osdl_live(window), &w, &h), "SDL_GetWindowSize");
    return osdl_int_pair(w, h);
}

CAMLprim value osdl_window_size_in_pixels(value window) {
    int w, h;
    osdl_check(SDL_GetWindowSizeInPixels(osdl_live(window), &w, &h), "SDL_GetWindowSizeInPixels");
    return osdl_int_pair(w, h);
}

CAMLprim value osdl_window_position(value window) {
    int x, y;
    osdl_check(SDL_GetWindowPosition(osdl_live(window), &x, &y), "SDL_GetWindowPosition");
    return osdl_int_pair(x, y);
}

CAMLprim value osdl_window_display(value window) {
    SDL_DisplayID id = SDL_GetDisplayForWindow(osdl_live(window));
    if (!id) osdl_fail("SDL_GetDisplayForWindow");
    return caml_copy_int32((int32_t)id);
}

CAMLprim value osdl_window_display_scale(value window) {
    float scale = SDL_GetWindowDisplayScale(osdl_live(window));
    if (!scale) osdl_fail("SDL_GetWindowDisplayScale");
    return caml_copy_double(scale);
}

CAMLprim value osdl_window_set_title(value window, value title) {
    osdl_check(SDL_SetWindowTitle(osdl_live(window), osdl_cstring(title)), "SDL_SetWindowTitle");
    return Val_unit;
}

CAMLprim value osdl_window_set_size(value window, value w, value h) {
    osdl_check(SDL_SetWindowSize(osdl_live(window), osdl_positive_int(w), osdl_positive_int(h)),
               "SDL_SetWindowSize");
    return Val_unit;
}

static int osdl_window_coordinate(value coordinate) {
    int n = osdl_int(coordinate);
    if (SDL_WINDOWPOS_ISUNDEFINED(n) || SDL_WINDOWPOS_ISCENTERED(n))
        caml_invalid_argument("Window position is reserved for automatic placement");
    return n;
}

CAMLprim value osdl_window_set_position(value window, value x, value y) {
    SDL_Window* w  = osdl_live(window);
    int         px = osdl_window_coordinate(x), py = osdl_window_coordinate(y);

    osdl_check(SDL_SetWindowPosition(w, px, py), "SDL_SetWindowPosition");
    return Val_unit;
}

CAMLprim value osdl_window_set_resizable(value window, value enabled) {
    osdl_check(SDL_SetWindowResizable(osdl_live(window), Bool_val(enabled)),
               "SDL_SetWindowResizable");
    return Val_unit;
}

CAMLprim value osdl_window_set_fullscreen(value window, value fullscreen) {
    osdl_check(SDL_SetWindowFullscreen(osdl_live(window), Bool_val(fullscreen)),
               "SDL_SetWindowFullscreen");
    return Val_unit;
}

CAMLprim value osdl_window_set_mouse_grab(value window, value enabled) {
    osdl_check(SDL_SetWindowMouseGrab(osdl_live(window), Bool_val(enabled)),
               "SDL_SetWindowMouseGrab");
    return Val_unit;
}

CAMLprim value osdl_window_mouse_grab(value window) {
    return Val_bool(SDL_GetWindowMouseGrab(osdl_live(window)));
}

OSDL_ACTION(osdl_window_show, SDL_ShowWindow)
OSDL_ACTION(osdl_window_hide, SDL_HideWindow)
OSDL_ACTION(osdl_window_minimize, SDL_MinimizeWindow)
OSDL_ACTION(osdl_window_maximize, SDL_MaximizeWindow)
OSDL_ACTION(osdl_window_restore, SDL_RestoreWindow)

/* Rectangle and blend mode conversions for surfaces and rendering. */

static SDL_Rect osdl_rect(value v) {
    return (SDL_Rect){osdl_int(Field(v, 0)), osdl_int(Field(v, 1)), osdl_int(Field(v, 2)),
                      osdl_int(Field(v, 3))};
}

static bool osdl_read_frect(value v, SDL_FRect* rect) {
    /* Frect.t is a float-only record, even without flat float arrays. */
    double x = Double_flat_field(v, 0), y = Double_flat_field(v, 1);
    double w = Double_flat_field(v, 2), h = Double_flat_field(v, 3);
    if (!osdl_fits_float(x) || !osdl_fits_float(y) || !osdl_fits_float(w) || !osdl_fits_float(h))
        return false;

    *rect = (SDL_FRect){(float)x, (float)y, (float)w, (float)h};
    return true;
}

static SDL_FRect osdl_frect(value v) {
    SDL_FRect rect;
    if (!osdl_read_frect(v, &rect)) caml_invalid_argument("SDL argument is not a finite C float");
    return rect;
}

static const SDL_FRect* osdl_frect_option(value v, SDL_FRect* rect) {
    if (Is_long(v)) return NULL;
    *rect = osdl_frect(Some_val(v));
    return rect;
}

/* Constant constructors of Blend_mode.t. Custom holds an opaque int32. */
static const SDL_BlendMode osdl_standard_blends[] = {
    SDL_BLENDMODE_NONE, SDL_BLENDMODE_BLEND, SDL_BLENDMODE_ADD,
    SDL_BLENDMODE_MOD,  SDL_BLENDMODE_MUL,
};

static SDL_BlendMode osdl_blend_mode(value mode) {
    return Is_long(mode) ? osdl_standard_blends[Int_val(mode)]
                         : (SDL_BlendMode)Int32_val(Field(mode, 0));
}

CAMLprim value osdl_blend_mode_compose(value color, value alpha) {
    static const SDL_BlendFactor factors[] = {
        SDL_BLENDFACTOR_ZERO,      SDL_BLENDFACTOR_ONE,
        SDL_BLENDFACTOR_SRC_COLOR, SDL_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
        SDL_BLENDFACTOR_SRC_ALPHA, SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        SDL_BLENDFACTOR_DST_COLOR, SDL_BLENDFACTOR_ONE_MINUS_DST_COLOR,
        SDL_BLENDFACTOR_DST_ALPHA, SDL_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
    };
    static const SDL_BlendOperation operations[] = {
        SDL_BLENDOPERATION_ADD,     SDL_BLENDOPERATION_SUBTRACT, SDL_BLENDOPERATION_REV_SUBTRACT,
        SDL_BLENDOPERATION_MINIMUM, SDL_BLENDOPERATION_MAXIMUM,
    };
    /* Blend_mode.equation stores src, dst, and op in this order. */
    SDL_BlendMode mode = SDL_ComposeCustomBlendMode(
        factors[Int_val(Field(color, 0))], factors[Int_val(Field(color, 1))],
        operations[Int_val(Field(color, 2))], factors[Int_val(Field(alpha, 0))],
        factors[Int_val(Field(alpha, 1))], operations[Int_val(Field(alpha, 2))]);
    for (size_t i = 0; i < SDL_arraysize(osdl_standard_blends); ++i)
        if (mode == osdl_standard_blends[i]) return Val_int(i);

    CAMLparam0();
    CAMLlocal1(encoded);
    encoded = caml_copy_int32((int32_t)mode);
    CAMLreturn(caml_alloc_1(0, encoded));
}

static SDL_ScaleMode osdl_scale_mode(value mode) {
    /* Surface.scale_mode and Texture.scale_mode. */
    return Int_val(mode) == 0 ? SDL_SCALEMODE_NEAREST : SDL_SCALEMODE_LINEAR;
}

static SDL_FlipMode osdl_flip_mode(value mode) {
    /* Surface.flip and Texture.flip. */
    static const SDL_FlipMode modes[] = {SDL_FLIP_NONE, SDL_FLIP_HORIZONTAL, SDL_FLIP_VERTICAL,
                                         SDL_FLIP_HORIZONTAL | SDL_FLIP_VERTICAL};
    return modes[Int_val(mode)];
}

/* Surfaces. */

/* Pixel_format.t constructor order. */
static const SDL_PixelFormat osdl_pixel_formats[] = {
    SDL_PIXELFORMAT_RGBA32,
    SDL_PIXELFORMAT_BGRA32,
    SDL_PIXELFORMAT_RGB24,
    SDL_PIXELFORMAT_INDEX8,
};

static int osdl_pixel_format_index(SDL_PixelFormat format) {
    for (size_t i = 0; i < SDL_arraysize(osdl_pixel_formats); ++i)
        if (format == osdl_pixel_formats[i]) return (int)i;
    return -1;
}

static void osdl_check_surface_dimensions(int width, int height, int bpp) {
    /* SDL pads new surface rows to four bytes and uses int byte offsets. */
    Uint64 pitch = ((Uint64)width * bpp + 3) & ~(Uint64)3;
    if (pitch > INT_MAX || (height > 0 && pitch > (Uint64)(INT_MAX / height)))
        caml_invalid_argument("SDL surface is too large");
}

static void osdl_check_surface_storage(const SDL_Surface* s) {
    if (s->pitch < 0 || (s->h > 0 && s->pitch > INT_MAX / s->h))
        caml_invalid_argument("SDL surface is too large");
}

CAMLnoret static void osdl_surface_fail_and_destroy(SDL_Surface* surface, const char* fn) {
    char message[1024];
    osdl_error_message(message, sizeof(message), fn);
    SDL_DestroySurface(surface);
    osdl_raise_error(message);
}

static SDL_Palette* osdl_surface_palette(SDL_Surface* surface) {
    SDL_Palette* palette = SDL_GetSurfacePalette(surface);
    if (!palette) caml_invalid_argument("The surface needs a palette");
    return palette;
}

static void osdl_check_surface_byte_pixels(const SDL_Surface* s) {
    if (SDL_ISPIXELFORMAT_FOURCC(s->format) || SDL_BITSPERPIXEL(s->format) < 8 ||
        !SDL_BYTESPERPIXEL(s->format))
        caml_invalid_argument("Convert the surface to a format with whole bytes per pixel first");
}

CAMLprim value osdl_surface_create(value format, value context, value w, value h) {
    CAMLparam4(format, context, w, h);
    CAMLlocal1(handle);

    osdl_live(context);
    SDL_PixelFormat pixel_format =
        Is_long(format) ? SDL_PIXELFORMAT_RGBA32 : osdl_pixel_formats[Int_val(Some_val(format))];
    int width = osdl_positive_int(w), height = osdl_positive_int(h);
    osdl_check_surface_dimensions(width, height, SDL_BYTESPERPIXEL(pixel_format));

    handle               = osdl_new_handle(context);
    SDL_Surface* surface = SDL_CreateSurface(width, height, pixel_format);
    if (surface && pixel_format == SDL_PIXELFORMAT_INDEX8 && !SDL_CreateSurfacePalette(surface))
        osdl_surface_fail_and_destroy(surface, "SDL_CreateSurfacePalette");
    CAMLreturn(osdl_publish(handle, surface, "SDL_CreateSurface"));
}

CAMLprim value osdl_surface_load_bmp(value context, value path) {
    CAMLparam2(context, path);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    CAMLreturn(osdl_publish(handle, SDL_LoadBMP(osdl_cstring(path)), "SDL_LoadBMP"));
}

CAMLprim value osdl_surface_save_bmp(value surface, value path) {
    osdl_check(SDL_SaveBMP(osdl_unlocked_surface(surface), osdl_cstring(path)), "SDL_SaveBMP");
    return Val_unit;
}

CAMLprim value osdl_surface_load_bmp_io(value stream) {
    CAMLparam1(stream);
    CAMLlocal1(handle);

    SDL_IOStream* io = osdl_unborrowed_io(stream);
    handle           = osdl_new_handle(osdl_parent(stream));

    CAMLreturn(osdl_publish(handle, SDL_LoadBMP_IO(io, false), "SDL_LoadBMP_IO"));
}

CAMLprim value osdl_surface_save_bmp_io(value surface, value stream) {
    SDL_Surface*  s  = osdl_unlocked_surface(surface);
    SDL_IOStream* io = osdl_unborrowed_io(stream);
    if (osdl_append_io(stream)) caml_invalid_argument("BMP output cannot use an append stream");

    osdl_check(SDL_SaveBMP_IO(s, io, false), "SDL_SaveBMP_IO");
    return Val_unit;
}

OSDL_DESTROY(osdl_surface_destroy, SDL_Surface, SDL_DestroySurface)

CAMLprim value osdl_surface_size(value surface) {
    SDL_Surface* s = osdl_live(surface);
    return osdl_int_pair(s->w, s->h);
}

CAMLprim value osdl_surface_format(value surface) {
    SDL_Surface* s     = osdl_live(surface);
    int          index = osdl_pixel_format_index(s->format);
    return index < 0 ? Val_none : caml_alloc_some(Val_int(index));
}

CAMLprim value osdl_surface_fill(value rect, value surface, value color) {
    SDL_Surface* s = osdl_unlocked_surface(surface);
    osdl_check_surface_storage(s);
    SDL_Rect        r;
    const SDL_Rect* area = NULL;
    if (Is_block(rect)) {
        r    = osdl_rect(Some_val(rect));
        area = &r;
    }

    SDL_Color c     = osdl_color(color);
    Uint32    pixel = SDL_MapSurfaceRGBA(s, c.r, c.g, c.b, c.a);
    osdl_check(SDL_FillSurfaceRect(s, area, pixel), "SDL_FillSurfaceRect");
    return Val_unit;
}

static value osdl_surface_color_at(SDL_Surface* s, int x, int y) {
    SDL_Color c;
    osdl_check(SDL_ReadSurfacePixel(s, x, y, &c.r, &c.g, &c.b, &c.a), "SDL_ReadSurfacePixel");
    return caml_alloc_4(0, Val_int(c.r), Val_int(c.g), Val_int(c.b), Val_int(c.a));
}

CAMLprim value osdl_surface_read_pixel(value surface, value x, value y) {
    SDL_Surface* s = osdl_unlocked_surface(surface);
    osdl_check_surface_storage(s);
    return osdl_surface_color_at(s, osdl_int(x), osdl_int(y));
}

CAMLprim value osdl_surface_read_rgba(value surface, value buffer) {
    SDL_Surface* s = osdl_unlocked_surface(surface);
    osdl_check_surface_storage(s);
    if (!s->w || !s->h) return Val_unit;
    size_t capacity = (size_t)Caml_ba_array_val(buffer)->dim[0];
    if ((size_t)s->w > capacity / 4 / (size_t)s->h)
        caml_invalid_argument("SDL RGBA buffer is too small for the surface");

    SDL_Surface* pixels = s;
    if (s->format != SDL_PIXELFORMAT_RGBA32 || SDL_SurfaceHasColorKey(s)) {
        osdl_check_surface_dimensions(s->w, s->h, 4);
        pixels = SDL_ConvertSurface(s, SDL_PIXELFORMAT_RGBA32);
        if (!pixels) osdl_fail("SDL_ConvertSurface");
    }

    bool locked = SDL_MUSTLOCK(pixels);
    if (locked && !SDL_LockSurface(pixels)) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "SDL_LockSurface");
        if (pixels != s) SDL_DestroySurface(pixels);
        osdl_raise_error(message);
    }
    size_t       row = (size_t)pixels->w * 4;
    const Uint8* src = pixels->pixels;
    Uint8*       dst = Caml_ba_data_val(buffer);
    for (int y = 0; y < pixels->h; ++y)
        memcpy(dst + (size_t)y * row, src + (size_t)y * (size_t)pixels->pitch, row);
    if (locked) SDL_UnlockSurface(pixels);
    if (pixels != s) SDL_DestroySurface(pixels);
    return Val_unit;
}

/* Palette handles own a reference. A surface takes a separate SDL reference. */
#define OSDL_PALETTE_SIZE 256

static int osdl_palette_colors(value colors, int first, SDL_Color* entries) {
    mlsize_t count = Wosize_val(colors);
    if (first > OSDL_PALETTE_SIZE || count > (mlsize_t)(OSDL_PALETTE_SIZE - first))
        caml_invalid_argument("The color range must fit in the palette");
    for (mlsize_t i = 0; i < count; ++i)
        entries[i] = osdl_color(Field(colors, i));
    return (int)count;
}

CAMLprim value osdl_palette_create(value context, value colors) {
    CAMLparam2(context, colors);
    CAMLlocal1(handle);

    osdl_live(context);
    SDL_Color entries[OSDL_PALETTE_SIZE];
    int       count = osdl_palette_colors(colors, 0, entries);

    handle               = osdl_new_handle(context);
    SDL_Palette* palette = SDL_CreatePalette(OSDL_PALETTE_SIZE);
    if (palette && count && !SDL_SetPaletteColors(palette, entries, 0, count)) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "SDL_SetPaletteColors");
        SDL_DestroyPalette(palette);
        osdl_raise_error(message);
    }
    CAMLreturn(osdl_publish(handle, palette, "SDL_CreatePalette"));
}

CAMLprim value osdl_palette_set_colors(value palette, value first, value colors) {
    SDL_Palette* pal = osdl_live(palette);
    SDL_Color    entries[OSDL_PALETTE_SIZE];
    int          start = osdl_nonnegative_int(first);
    int          count = osdl_palette_colors(colors, start, entries);

    if (count) osdl_check(SDL_SetPaletteColors(pal, entries, start, count), "SDL_SetPaletteColors");
    return Val_unit;
}

OSDL_DESTROY(osdl_palette_destroy, SDL_Palette, SDL_DestroyPalette)

CAMLprim value osdl_surface_set_palette(value surface, value palette) {
    SDL_Surface* s   = osdl_unlocked_surface(surface);
    SDL_Palette* pal = osdl_live(palette);
    if (s->format != SDL_PIXELFORMAT_INDEX8)
        caml_invalid_argument("Palette replacement needs an Index8 surface");

    osdl_check(SDL_SetSurfacePalette(s, pal), "SDL_SetSurfacePalette");
    return Val_unit;
}

CAMLprim value osdl_surface_set_color_key(value surface, value key) {
    SDL_Surface* s       = osdl_unlocked_surface(surface);
    Uint32       pixel   = 0;
    bool         enabled = Is_block(key);
    if (enabled) {
        value spec    = Some_val(key);
        bool  indexed = SDL_ISPIXELFORMAT_INDEXED(s->format);
        /* Surface.color_key: Color is block tag 0, Index is tag 1. */
        if (Tag_val(spec) == 0) {
            if (indexed) osdl_surface_palette(s);
            if (SDL_ISPIXELFORMAT_FOURCC(s->format) || SDL_BYTESPERPIXEL(s->format) > 4)
                caml_invalid_argument("The surface format does not support a color key");
            SDL_Color c = osdl_color(Field(spec, 0));
            pixel       = SDL_MapSurfaceRGB(s, c.r, c.g, c.b);
        } else {
            if (!indexed) caml_invalid_argument("An index key needs an indexed surface");
            intnat index = Long_val(Field(spec, 0));
            if (index < 0 || index >= osdl_surface_palette(s)->ncolors)
                caml_invalid_argument("The color key index is outside the palette");
            pixel = (Uint32)index;
        }
    }

    osdl_check(SDL_SetSurfaceColorKey(s, enabled, pixel), "SDL_SetSurfaceColorKey");
    return Val_unit;
}

CAMLprim value osdl_surface_set_blend_mode(value surface, value mode) {
    osdl_check(SDL_SetSurfaceBlendMode(osdl_unlocked_surface(surface), osdl_blend_mode(mode)),
               "SDL_SetSurfaceBlendMode");
    return Val_unit;
}

/* Blits and transforms. */

static SDL_Surface* osdl_surface_for_blit(value surface) {
    SDL_Surface* s = osdl_unlocked_surface(surface);
    osdl_check_surface_storage(s);
    osdl_check_surface_byte_pixels(s);
    /* SDL 3.2.0 truncates blit offsets to Uint16. */
    if (s->w > SDL_MAX_UINT16 || s->h > SDL_MAX_UINT16)
        caml_invalid_argument("SDL surface is too wide or tall for a blit");
    if (SDL_ISPIXELFORMAT_INDEXED(s->format)) osdl_surface_palette(s);
    return s;
}

static SDL_Rect osdl_surface_blit_rect(value option, SDL_Rect fallback, bool position_only) {
    if (Is_long(option)) return fallback;
    value    rect = Some_val(option);
    SDL_Rect area = {osdl_int(Field(rect, 0)), osdl_int(Field(rect, 1)), 0, 0};
    if (!position_only) {
        area.w = osdl_nonnegative_int(Field(rect, 2));
        area.h = osdl_nonnegative_int(Field(rect, 3));
    }
    /* Leave space for the shifts SDL applies while clipping. */
    int limit = INT_MAX / 4;
    if (area.x < -limit || area.x > limit || area.y < -limit || area.y > limit || area.w > limit ||
        area.h > limit)
        caml_invalid_argument("The blit rectangle is outside the SDL range");
    return area;
}

CAMLprim value osdl_surface_blit(value src, value dst, value source, value target) {
    SDL_Surface* s = osdl_surface_for_blit(source);
    SDL_Surface* d = osdl_surface_for_blit(target);
    if (s == d) caml_invalid_argument("Blit between distinct surfaces");
    SDL_Rect from = osdl_surface_blit_rect(src, (SDL_Rect){0, 0, s->w, s->h}, false);
    SDL_Rect to   = osdl_surface_blit_rect(dst, (SDL_Rect){0}, true);
    if (!s->w || !s->h || !from.w || !from.h || !d->w || !d->h) return Val_unit;

    osdl_check(SDL_BlitSurface(s, Is_block(src) ? &from : NULL, d, Is_block(dst) ? &to : NULL),
               "SDL_BlitSurface");
    return Val_unit;
}

static void osdl_check_surface_scale_size(int width, int height) {
    /* SDL's linear scaler uses signed 16.16 steps. */
    if (width > SDL_MAX_SINT16 || height > SDL_MAX_SINT16)
        caml_invalid_argument("Scaled surface dimensions cannot exceed 32767 pixels");
}

/* SDL 3.2 expands a non-32-bit crop to the full source size before its
 * linear pass, so the result can use the wrong pixels. Convert first. */
static SDL_Surface* osdl_surface_prepare_linear_blit(SDL_Surface* s) {
    osdl_check_surface_dimensions(s->w, s->h, 4);
    SDL_BlendMode blend;
    osdl_check(SDL_GetSurfaceBlendMode(s, &blend), "SDL_GetSurfaceBlendMode");

    SDL_Surface* rgba = SDL_ConvertSurface(s, SDL_PIXELFORMAT_RGBA32);
    if (!rgba) osdl_fail("SDL_ConvertSurface");
    if (!SDL_SetSurfaceBlendMode(rgba, blend))
        osdl_surface_fail_and_destroy(rgba, "SDL_SetSurfaceBlendMode");
    return rgba;
}

CAMLprim value osdl_surface_blit_scaled(value src, value dst, value scale_mode, value source,
                                        value target) {
    SDL_Surface* s = osdl_surface_for_blit(source);
    SDL_Surface* d = osdl_surface_for_blit(target);
    if (s == d) caml_invalid_argument("Blit between distinct surfaces");
    SDL_Rect from = osdl_surface_blit_rect(src, (SDL_Rect){0, 0, s->w, s->h}, false);
    SDL_Rect to   = osdl_surface_blit_rect(dst, (SDL_Rect){0, 0, d->w, d->h}, false);
    if (from.x < 0 || from.y < 0 || from.x > s->w - from.w || from.y > s->h - from.h)
        caml_invalid_argument("The scaled blit source rectangle must lie inside the surface");
    if (!from.w || !from.h || !to.w || !to.h) return Val_unit;

    SDL_ScaleMode mode =
        Is_long(scale_mode) ? SDL_SCALEMODE_NEAREST : osdl_scale_mode(Some_val(scale_mode));
    SDL_Surface* rgba = NULL;
    if (from.w != to.w || from.h != to.h) {
        osdl_check_surface_scale_size(from.w, from.h);
        osdl_check_surface_scale_size(to.w, to.h);
        int bpp = SDL_max(SDL_BYTESPERPIXEL(s->format), SDL_BYTESPERPIXEL(d->format));
        osdl_check_surface_dimensions(to.w, to.h, SDL_max(bpp, 4));

        bool keyed = SDL_SurfaceHasColorKey(s);
        if (mode == SDL_SCALEMODE_LINEAR &&
            (keyed || SDL_ISPIXELFORMAT_INDEXED(s->format) || SDL_ISPIXELFORMAT_INDEXED(d->format)))
            caml_invalid_argument(
                "Use true-color surfaces without a source color key for linear blits");

        SDL_Rect clip, visible;
        osdl_check(SDL_GetSurfaceClipRect(d, &clip), "SDL_GetSurfaceClipRect");
        if (!SDL_GetRectIntersection(&to, &clip, &visible)) return Val_unit;
        bool clipped = visible.w != to.w || visible.h != to.h;
        bool old     = SDL_GetVersion() < SDL_VERSIONNUM(3, 4, 0);
        if (clipped) {
            /* On SDL 3.4, the clipped path scales a view of the source and
             * does not preserve the key or lock pixel storage first. */
            if (keyed || SDL_MUSTLOCK(s))
                caml_invalid_argument(
                    "Scale the source separately before a clipped blit with a color key or RLE");
            /* SDL 3.2 can round a clipped source extent down to zero and
             * still try to read a pixel outside the source. */
            if (old &&
                (2 * (Sint64)visible.w * from.w <= to.w || 2 * (Sint64)visible.h * from.h <= to.h))
                return Val_unit;
        }
        if (old && mode == SDL_SCALEMODE_LINEAR && (clipped || from.w != s->w || from.h != s->h) &&
            (SDL_BYTESPERPIXEL(s->format) != 4 || s->format == SDL_PIXELFORMAT_ARGB2101010)) {
            rgba = osdl_surface_prepare_linear_blit(s);
            s    = rgba;
        }
    }

    bool ok =
        SDL_BlitSurfaceScaled(s, Is_block(src) ? &from : NULL, d, Is_block(dst) ? &to : NULL, mode);
    if (rgba) {
        if (!ok) osdl_surface_fail_and_destroy(rgba, "SDL_BlitSurfaceScaled");
        SDL_DestroySurface(rgba);
    }
    osdl_check(ok, "SDL_BlitSurfaceScaled");
    return Val_unit;
}

CAMLprim value osdl_surface_convert(value surface, value format) {
    CAMLparam2(surface, format);
    CAMLlocal1(handle);

    SDL_Surface*    s     = osdl_unlocked_surface(surface);
    SDL_PixelFormat pixel = osdl_pixel_formats[Int_val(format)];
    osdl_check_surface_storage(s);
    osdl_check_surface_dimensions(s->w, s->h, SDL_BYTESPERPIXEL(pixel));

    handle = osdl_new_handle(osdl_parent(surface));
    CAMLreturn(osdl_publish(handle, SDL_ConvertSurface(s, pixel), "SDL_ConvertSurface"));
}

/* SDL 3.2 scales indexed images by looking up colors again. Copy the exact
 * indices instead, so duplicate colors can still be changed separately. */
static SDL_Surface* osdl_scale_index8(SDL_Surface* source, int w, int h) {
    SDL_Surface* dest = SDL_CreateSurface(w, h, SDL_PIXELFORMAT_INDEX8);
    if (!dest) return NULL;

    SDL_Color     color;
    SDL_BlendMode blend;
    if (!SDL_GetSurfaceColorMod(source, &color.r, &color.g, &color.b) ||
        !SDL_GetSurfaceAlphaMod(source, &color.a) || !SDL_GetSurfaceBlendMode(source, &blend) ||
        !SDL_SetSurfacePalette(dest, SDL_GetSurfacePalette(source)) ||
        !SDL_SetSurfaceColorspace(dest, SDL_GetSurfaceColorspace(source)) ||
        !SDL_SetSurfaceColorMod(dest, color.r, color.g, color.b) ||
        !SDL_SetSurfaceAlphaMod(dest, color.a) || !SDL_SetSurfaceBlendMode(dest, blend))
        osdl_surface_fail_and_destroy(dest, "SDL_ScaleSurface");

    bool locked = SDL_MUSTLOCK(source);
    if (locked && !SDL_LockSurface(source)) osdl_surface_fail_and_destroy(dest, "SDL_LockSurface");
    const Uint8* src = source->pixels;
    if (!src) {
        if (locked) SDL_UnlockSurface(source);
        SDL_DestroySurface(dest);
        osdl_raise_error("SDL_ScaleSurface: No source pixels are available");
    }

    /* Use the same center-of-pixel sampling as SDL's nearest scaler. */
    Uint64 step_x = ((Uint64)source->w << 16) / w, step_y = ((Uint64)source->h << 16) / h;
    Uint64 y = step_y / 2;
    for (int row = 0; row < h; ++row, y += step_y) {
        const Uint8* in  = src + (size_t)(y >> 16) * source->pitch;
        Uint8*       out = (Uint8*)dest->pixels + (size_t)row * dest->pitch;
        Uint64       x   = step_x / 2;
        for (int col = 0; col < w; ++col, x += step_x)
            out[col] = in[x >> 16];
    }
    if (locked) SDL_UnlockSurface(source);
    return dest;
}

CAMLprim value osdl_surface_scale(value scale_mode, value surface, value w, value h) {
    CAMLparam4(scale_mode, surface, w, h);
    CAMLlocal1(handle);

    SDL_Surface* s = osdl_unlocked_surface(surface);
    osdl_check_surface_storage(s);
    osdl_check_surface_byte_pixels(s);
    if (!s->w || !s->h) caml_invalid_argument("Cannot scale an empty surface");
    int width = osdl_positive_int(w), height = osdl_positive_int(h);
    osdl_check_surface_scale_size(s->w, s->h);
    osdl_check_surface_scale_size(width, height);
    osdl_check_surface_dimensions(width, height, SDL_max(4, SDL_BYTESPERPIXEL(s->format)));

    bool indexed = s->format == SDL_PIXELFORMAT_INDEX8;
    if (indexed) osdl_surface_palette(s);
    SDL_ScaleMode mode  = indexed || Is_long(scale_mode) ? SDL_SCALEMODE_NEAREST
                                                         : osdl_scale_mode(Some_val(scale_mode));
    Uint32        key   = 0;
    bool          keyed = SDL_SurfaceHasColorKey(s);
    if (keyed) osdl_check(SDL_GetSurfaceColorKey(s, &key), "SDL_GetSurfaceColorKey");

    handle              = osdl_new_handle(osdl_parent(surface));
    SDL_Surface* scaled = indexed && SDL_GetVersion() < SDL_VERSIONNUM(3, 4, 0)
                            ? osdl_scale_index8(s, width, height)
                            : SDL_ScaleSurface(s, width, height, mode);
    /* SDL can copy the key flag but not the key value when scaling. */
    if (scaled && keyed && !SDL_SetSurfaceColorKey(scaled, true, key))
        osdl_surface_fail_and_destroy(scaled, "SDL_SetSurfaceColorKey");
    CAMLreturn(osdl_publish(handle, scaled, "SDL_ScaleSurface"));
}

CAMLprim value osdl_surface_flip(value surface, value flip) {
    SDL_Surface* s    = osdl_unlocked_surface(surface);
    SDL_FlipMode axes = osdl_flip_mode(flip);
    if (axes == SDL_FLIP_NONE) return Val_unit;
    osdl_check_surface_storage(s);
    if (SDL_ISPIXELFORMAT_FOURCC(s->format))
        caml_invalid_argument("Convert the surface before flipping it");

    bool locked = SDL_MUSTLOCK(s);
    if (locked) osdl_check(SDL_LockSurface(s), "SDL_LockSurface");
    /* SDL 3.2.0 only accepts one axis at a time. */
    bool ok = (!(axes & SDL_FLIP_HORIZONTAL) || SDL_FlipSurface(s, SDL_FLIP_HORIZONTAL)) &&
              (!(axes & SDL_FLIP_VERTICAL) || SDL_FlipSurface(s, SDL_FLIP_VERTICAL));
    char message[1024];
    if (!ok) osdl_error_message(message, sizeof(message), "SDL_FlipSurface");
    if (locked) SDL_UnlockSurface(s);
    if (!ok) osdl_raise_error(message);
    return Val_unit;
}

/* A lock is a child handle. Do not allow a software renderer to share the
 * surface with a lock, since its draws can reach the surface through SDL. */

CAMLprim value osdl_surface_prepare_lock(value surface) {
    osdl_unlocked_surface(surface);
    return osdl_new_handle(surface);
}

CAMLprim value osdl_surface_lock_pixels(value view) {
    value        surface = osdl_parent(view);
    SDL_Surface* s       = osdl_unlocked_surface(surface);
    if (osdl_cell_val(surface)->children)
        caml_invalid_argument("Destroy the software renderer before locking its surface");
    osdl_check_surface_storage(s);
    osdl_check_surface_byte_pixels(s);

    osdl_check(SDL_LockSurface(s), "SDL_LockSurface");
    int bpp = SDL_BYTESPERPIXEL(s->format);
    if ((s->w && s->h) &&
        (!s->pixels || s->pitch < 0 || s->w > s->pitch / bpp || s->pitch > INT_MAX / s->h)) {
        SDL_UnlockSurface(s);
        osdl_raise_error("SDL_LockSurface: SDL returned invalid pixel storage");
    }
    osdl_publish(view, s, "SDL_LockSurface");
    return Val_unit;
}

CAMLprim value osdl_surface_unlock_pixels(value view) {
    SDL_Surface* s = osdl_take(view);
    if (s) {
        SDL_UnlockSurface(s);
        Store_field(view, 1, Val_unit);
    }
    return Val_unit;
}

CAMLprim value osdl_surface_locked_size(value view) {
    SDL_Surface* s = osdl_live(view);
    return osdl_int_pair(s->w, s->h);
}

static void osdl_check_surface_point(const SDL_Surface* s, int x, int y) {
    if (x < 0 || x >= s->w || y < 0 || y >= s->h)
        caml_invalid_argument("The pixel is outside the locked surface");
}

CAMLprim value osdl_surface_locked_read_pixel(value view, value x, value y) {
    SDL_Surface* s  = osdl_live(view);
    int          px = osdl_int(x), py = osdl_int(y);
    osdl_check_surface_point(s, px, py);

    return osdl_surface_color_at(s, px, py);
}

CAMLprim value osdl_surface_locked_set_pixel(value view, value x, value y, value color) {
    SDL_Surface* s  = osdl_live(view);
    int          px = osdl_int(x), py = osdl_int(y);
    osdl_check_surface_point(s, px, py);
    if (SDL_ISPIXELFORMAT_INDEXED(s->format)) osdl_surface_palette(s);
    SDL_Color c = osdl_color(color);

    osdl_check(SDL_WriteSurfacePixel(s, px, py, c.r, c.g, c.b, c.a), "SDL_WriteSurfacePixel");
    return Val_unit;
}

static Uint8* osdl_surface_index_at(SDL_Surface* s, value x, value y) {
    if (s->format != SDL_PIXELFORMAT_INDEX8)
        caml_invalid_argument("Pixel indices need an Index8 surface");
    int px = osdl_int(x), py = osdl_int(y);
    osdl_check_surface_point(s, px, py);
    return (Uint8*)s->pixels + (size_t)py * s->pitch + px;
}

CAMLprim value osdl_surface_locked_read_index(value view, value x, value y) {
    return Val_int(*osdl_surface_index_at(osdl_live(view), x, y));
}

CAMLprim value osdl_surface_locked_set_index(value view, value x, value y, value index) {
    SDL_Surface* s     = osdl_live(view);
    Uint8*       pixel = osdl_surface_index_at(s, x, y);
    intnat       i     = Long_val(index);
    if (i < 0 || i >= osdl_surface_palette(s)->ncolors)
        caml_invalid_argument("The pixel index is outside the palette");

    *pixel = (Uint8)i;
    return Val_unit;
}

static value osdl_surface_copy_pixels(value view, value buffer, value pitch, bool write) {
    SDL_Surface* s = osdl_live(view);
    if (osdl_pixel_format_index(s->format) < 0)
        caml_invalid_argument("Convert to RGBA, BGRA, RGB24, or Index8 before copying pixel rows");
    size_t row_bytes = (size_t)s->w * SDL_BYTESPERPIXEL(s->format);
    size_t stride    = osdl_nonnegative_int(pitch);
    if (!s->w || !s->h) return Val_unit;
    if (stride < row_bytes) caml_invalid_argument("The pitch must cover one pixel row");
    size_t length = Caml_ba_array_val(buffer)->dim[0];
    if (length < row_bytes || (size_t)(s->h - 1) > (length - row_bytes) / stride)
        caml_invalid_argument("The buffer does not cover the locked surface");
    Uint8* bytes = Caml_ba_data_val(buffer);

    /* A file can supply a smaller palette. Validate all indices before a
     * write so SDL's blitters can safely look them up later. */
    if (write && s->format == SDL_PIXELFORMAT_INDEX8) {
        int count = osdl_surface_palette(s)->ncolors;
        if (count < OSDL_PALETTE_SIZE) {
            for (int y = 0; y < s->h; ++y) {
                const Uint8* row = bytes + (size_t)y * stride;
                for (int x = 0; x < s->w; ++x)
                    if (row[x] >= count)
                        caml_invalid_argument("A pixel index is outside the palette");
            }
        }
    }

    const Uint8* src       = write ? bytes : s->pixels;
    Uint8*       dst       = write ? s->pixels : bytes;
    size_t       src_pitch = write ? stride : (size_t)s->pitch;
    size_t       dst_pitch = write ? (size_t)s->pitch : stride;
    if (src_pitch == row_bytes && dst_pitch == row_bytes)
        memcpy(dst, src, row_bytes * (size_t)s->h);
    else
        for (int y = 0; y < s->h; ++y)
            memcpy(dst + (size_t)y * dst_pitch, src + (size_t)y * src_pitch, row_bytes);
    return Val_unit;
}

CAMLprim value osdl_surface_locked_copy_from(value view, value buffer, value pitch) {
    return osdl_surface_copy_pixels(view, buffer, pitch, true);
}

CAMLprim value osdl_surface_locked_copy_to(value view, value buffer, value pitch) {
    return osdl_surface_copy_pixels(view, buffer, pitch, false);
}

/* Renderers. */

CAMLprim value osdl_renderer_drivers(value unit) {
    CAMLparam0();
    CAMLlocal2(list, name);
    (void)unit;

    list = Val_emptylist;
    for (int i = SDL_GetNumRenderDrivers(); i > 0; --i) {
        const char* driver = SDL_GetRenderDriver(i - 1);
        if (!driver) osdl_fail("SDL_GetRenderDriver");
        name = caml_copy_string(driver);
        list = caml_alloc_2(0, name, list);
    }
    CAMLreturn(list);
}

static SDL_Texture* osdl_texture_unlocked(value texture) {
    SDL_Texture* t = osdl_live(texture);
    if (osdl_cell_val(texture)->children)
        caml_invalid_argument("Finish the SDL texture lock before using the texture");
    return t;
}

static SDL_Texture* osdl_texture_for_renderer(value texture, value renderer) {
    SDL_Texture* t = osdl_texture_unlocked(texture);
    if (osdl_parent(texture) != renderer)
        caml_invalid_argument("Use the renderer that owns the texture");
    return t;
}

CAMLprim value osdl_renderer_create(value driver, value window) {
    CAMLparam2(driver, window);
    CAMLlocal1(handle);

    handle = osdl_new_handle(window);

    const char*   name     = Is_long(driver) ? NULL : osdl_cstring(Some_val(driver));
    SDL_Renderer* renderer = SDL_CreateRenderer(osdl_unattached_window(window), name);
    CAMLreturn(osdl_publish(handle, renderer, "SDL_CreateRenderer"));
}

CAMLprim value osdl_renderer_create_software(value surface) {
    CAMLparam1(surface);
    CAMLlocal1(handle);

    handle = osdl_new_handle(surface);

    SDL_Renderer* renderer = SDL_CreateSoftwareRenderer(osdl_unlocked_surface(surface));
    CAMLreturn(osdl_publish(handle, renderer, "SDL_CreateSoftwareRenderer"));
}

OSDL_DESTROY(osdl_renderer_destroy, SDL_Renderer, SDL_DestroyRenderer)

CAMLprim value osdl_renderer_name(value renderer) {
    const char* name = SDL_GetRendererName(osdl_live(renderer));
    if (!name) osdl_fail("SDL_GetRendererName");
    return caml_copy_string(name);
}

static SDL_PropertiesID osdl_renderer_properties(value renderer) {
    SDL_PropertiesID props = SDL_GetRendererProperties(osdl_live(renderer));
    if (!props) osdl_fail("SDL_GetRendererProperties");
    return props;
}

CAMLprim value osdl_renderer_max_texture_size(value renderer) {
    SDL_PropertiesID props = osdl_renderer_properties(renderer);
    Sint64 size = SDL_GetNumberProperty(props, SDL_PROP_RENDERER_MAX_TEXTURE_SIZE_NUMBER, 0);
    if (size <= 0) return Val_none;
    if (size > Max_long) osdl_raise_error("SDL_GetRendererProperties: Texture limit is too large");
    return caml_alloc_some(Val_long((intnat)size));
}

CAMLprim value osdl_renderer_texture_formats(value renderer) {
    CAMLparam1(renderer);
    CAMLlocal2(list, name);

    SDL_PropertiesID       props = osdl_renderer_properties(renderer);
    const SDL_PixelFormat* formats =
        SDL_GetPointerProperty(props, SDL_PROP_RENDERER_TEXTURE_FORMATS_POINTER, NULL);
    if (!formats) CAMLreturn(Val_emptylist);

    const SDL_PixelFormat* end = formats;
    while (*end != SDL_PIXELFORMAT_UNKNOWN)
        ++end;
    list = Val_emptylist;
    while (end != formats) {
        name = caml_copy_string(SDL_GetPixelFormatName(*--end));
        list = caml_alloc_2(0, name, list);
    }
    CAMLreturn(list);
}

CAMLprim value osdl_renderer_output_size(value renderer) {
    int w, h;
    osdl_check(SDL_GetRenderOutputSize(osdl_live(renderer), &w, &h), "SDL_GetRenderOutputSize");
    return osdl_int_pair(w, h);
}

CAMLprim value osdl_renderer_current_output_size(value renderer) {
    int w, h;
    osdl_check(SDL_GetCurrentRenderOutputSize(osdl_live(renderer), &w, &h),
               "SDL_GetCurrentRenderOutputSize");
    return osdl_int_pair(w, h);
}

CAMLprim value osdl_renderer_set_vsync(value renderer, value enabled) {
    osdl_check(SDL_SetRenderVSync(osdl_live(renderer), Bool_val(enabled) ? 1 : 0),
               "SDL_SetRenderVSync");
    return Val_unit;
}

CAMLprim value osdl_renderer_vsync(value renderer) {
    int interval;
    osdl_check(SDL_GetRenderVSync(osdl_live(renderer), &interval), "SDL_GetRenderVSync");
    return osdl_val_int(interval);
}

CAMLprim value osdl_renderer_set_target(value renderer, value target) {
    SDL_Renderer* r = osdl_live(renderer);
    SDL_Texture* t = Is_long(target) ? NULL : osdl_texture_for_renderer(Some_val(target), renderer);

    osdl_check(SDL_SetRenderTarget(r, t), "SDL_SetRenderTarget");
    return Val_unit;
}

typedef struct {
    SDL_FPoint scale;
    SDL_FPoint offset;
} osdl_render_view;

static const osdl_render_view osdl_unit_view = {
    {1, 1},
    {0, 0}
};

static bool osdl_old_logical_target(SDL_Renderer* renderer) {
    return SDL_GetRenderTarget(renderer) && SDL_GetVersion() < SDL_VERSIONNUM(3, 2, 6);
}

static SDL_FPoint osdl_render_scale(SDL_Renderer* renderer) {
    SDL_FPoint scale;
    osdl_check(SDL_GetRenderScale(renderer, &scale.x, &scale.y), "SDL_GetRenderScale");
    return scale;
}

static osdl_render_view osdl_logical_view(SDL_Renderer* renderer) {
    /* Before SDL 3.2.6, logical presentation only affected the default target. */
    if (osdl_old_logical_target(renderer)) return osdl_unit_view;

    int                             w, h;
    SDL_RendererLogicalPresentation mode;
    osdl_check(SDL_GetRenderLogicalPresentation(renderer, &w, &h, &mode),
               "SDL_GetRenderLogicalPresentation");
    if (mode == SDL_LOGICAL_PRESENTATION_DISABLED || w <= 0 || h <= 0) return osdl_unit_view;

    SDL_FRect rect;
    osdl_check(SDL_GetRenderLogicalPresentationRect(renderer, &rect),
               "SDL_GetRenderLogicalPresentationRect");
    return (osdl_render_view){
        {rect.w / w, rect.h / h},
        {rect.x,     rect.y    }
    };
}

static osdl_render_view osdl_scale_view(osdl_render_view view, SDL_FPoint scale) {
    view.scale.x *= scale.x;
    view.scale.y *= scale.y;
    return view;
}

static osdl_render_view osdl_current_view(SDL_Renderer* renderer) {
    return osdl_scale_view(osdl_logical_view(renderer), osdl_render_scale(renderer));
}

static SDL_Rect osdl_explicit_viewport(SDL_Renderer* renderer) {
    SDL_Rect rect = {0};
    if (SDL_RenderViewportSet(renderer))
        osdl_check(SDL_GetRenderViewport(renderer, &rect), "SDL_GetRenderViewport");
    return rect;
}

/* Include the viewport origin and both scales in software drawing limits. */
static osdl_render_view osdl_pixel_view(SDL_Renderer* renderer, osdl_render_view view) {
    SDL_Rect viewport = osdl_explicit_viewport(renderer);
    view.offset.x     = SDL_floorf(viewport.x * view.scale.x + view.offset.x);
    view.offset.y     = SDL_floorf(viewport.y * view.scale.y + view.offset.y);
    return view;
}

static osdl_render_view osdl_software_view(SDL_Renderer* renderer) {
    return osdl_pixel_view(renderer, osdl_current_view(renderer));
}

static bool osdl_software_renderer(SDL_Renderer* renderer) {
    const char* driver = SDL_GetRendererName(renderer);
    return driver && strcmp(driver, SDL_SOFTWARE_RENDERER) == 0;
}

/* SDL stores pixel rectangles in signed ints and adds the clip origin to the
 * viewport origin. Leave room for these sums and SDL's rounded endpoints. */
static const double osdl_view_limit = INT_MAX / 4.0;

static void osdl_check_view_rect(SDL_Rect rect, osdl_render_view view) {
    double x = fabs((double)rect.x * view.scale.x) + fabs(view.offset.x);
    double y = fabs((double)rect.y * view.scale.y) + fabs(view.offset.y);
    double w = (double)rect.w * view.scale.x;
    double h = (double)rect.h * view.scale.y;
    if (!(x <= osdl_view_limit && y <= osdl_view_limit && w <= osdl_view_limit &&
          h <= osdl_view_limit))
        caml_invalid_argument("The scaled viewport or clip rectangle is outside the SDL range");
}

static void osdl_check_view_state(SDL_Renderer* renderer, osdl_render_view view) {
    osdl_check_view_rect(osdl_explicit_viewport(renderer), view);
    if (SDL_RenderClipEnabled(renderer)) {
        SDL_Rect rect;
        osdl_check(SDL_GetRenderClipRect(renderer, &rect), "SDL_GetRenderClipRect");
        view.offset = (SDL_FPoint){0, 0};
        osdl_check_view_rect(rect, view);
    }
}

static void osdl_check_viewport_size(int w, int h, SDL_FPoint scale) {
    /* SDL_GetRenderViewport divides by the effective scale before casting. */
    if (!(scale.x > 0 && scale.y > 0 && (double)SDL_ceilf((float)w / scale.x) <= INT_MAX &&
          (double)SDL_ceilf((float)h / scale.y) <= INT_MAX))
        caml_invalid_argument("The automatic viewport is outside the SDL range");
}

static void osdl_check_automatic_viewport(SDL_Renderer* renderer, SDL_FPoint scale) {
    int w, h;
    osdl_check(SDL_GetCurrentRenderOutputSize(renderer, &w, &h), "SDL_GetCurrentRenderOutputSize");
    osdl_check_viewport_size(w, h, scale);
}

static osdl_render_view osdl_check_presentation(SDL_Renderer* renderer, int w, int h,
                                                SDL_RendererLogicalPresentation mode,
                                                SDL_FPoint                      scale) {
    SDL_Texture* target = SDL_GetRenderTarget(renderer);
    int          output_w, output_h;
    if (target) {
        output_w = target->w;
        output_h = target->h;
    } else {
        osdl_check(SDL_GetRenderOutputSize(renderer, &output_w, &output_h),
                   "SDL_GetRenderOutputSize");
    }
    if (mode == SDL_LOGICAL_PRESENTATION_DISABLED) {
        osdl_check_viewport_size(output_w, output_h, scale);
        return osdl_unit_view;
    }
    if (w > osdl_view_limit || h > osdl_view_limit)
        caml_invalid_argument("The logical presentation size is outside the SDL range");
    /* SDL uses the presentation rectangle as the pixel size. Dividing it
     * by the logical scale gives the requested logical size again. */
    osdl_check_viewport_size(w, h, scale);

    /* Bound the new scale and offset before SDL updates the existing
     * viewport and clip rectangle. Allow for rounding the output to pixels. */
    float sx = (float)output_w / w, sy = (float)output_h / h;
    if (mode == SDL_LOGICAL_PRESENTATION_INTEGER_SCALE) {
        sx = sy = SDL_max(1.0f, SDL_floorf(SDL_min(sx, sy)));
    } else if (mode != SDL_LOGICAL_PRESENTATION_STRETCH &&
               (output_h <= 0 || SDL_fabsf((float)w / h - (float)output_w / output_h) >= 0.0001f)) {
        sx = sy = mode == SDL_LOGICAL_PRESENTATION_LETTERBOX ? SDL_min(sx, sy) : SDL_max(sx, sy);
    }
    double width = (double)w * sx, height = (double)h * sy;
    if (!(width <= osdl_view_limit && height <= osdl_view_limit))
        caml_invalid_argument("The logical presentation rectangle is outside the SDL range");

    return (osdl_render_view){
        {sx,                                 sy                                 },
        {0.5 * fabs(output_w - width) + 1.0, 0.5 * fabs(output_h - height) + 1.0}
    };
}

CAMLprim value osdl_renderer_set_logical_presentation(value renderer, value size) {
    static const SDL_RendererLogicalPresentation modes[] = {
        SDL_LOGICAL_PRESENTATION_STRETCH,
        SDL_LOGICAL_PRESENTATION_LETTERBOX,
        SDL_LOGICAL_PRESENTATION_OVERSCAN,
        SDL_LOGICAL_PRESENTATION_INTEGER_SCALE,
    };

    SDL_RendererLogicalPresentation mode = SDL_LOGICAL_PRESENTATION_DISABLED;
    int                             w = 0, h = 0;
    if (Is_block(size)) {
        value v = Some_val(size);
        w       = osdl_positive_int(Field(v, 0));
        h       = osdl_positive_int(Field(v, 1));
        mode    = modes[Int_val(Field(v, 2))];
    }

    SDL_Renderer* r = osdl_live(renderer);
    if (osdl_old_logical_target(r))
        caml_invalid_argument(
            "Restore the default target before setting logical presentation on SDL before 3.2.6");
    SDL_FPoint       scale = osdl_render_scale(r);
    osdl_render_view view  = osdl_check_presentation(r, w, h, mode, scale);
    osdl_check_view_state(r, osdl_scale_view(view, scale));

    osdl_check(SDL_SetRenderLogicalPresentation(r, w, h, mode), "SDL_SetRenderLogicalPresentation");
    return Val_unit;
}

CAMLprim value osdl_renderer_logical_presentation_rect(value renderer) {
    SDL_Renderer*                   r = osdl_live(renderer);
    SDL_RendererLogicalPresentation mode;
    SDL_FRect                       rect;
    osdl_check(SDL_GetRenderLogicalPresentation(r, NULL, NULL, &mode),
               "SDL_GetRenderLogicalPresentation");
    if (mode == SDL_LOGICAL_PRESENTATION_DISABLED) {
        /* SDL can leave logical_dst_rect unset until the first update. */
        int w, h;
        if (osdl_old_logical_target(r))
            osdl_check(SDL_GetRenderOutputSize(r, &w, &h), "SDL_GetRenderOutputSize");
        else
            osdl_check(SDL_GetCurrentRenderOutputSize(r, &w, &h), "SDL_GetCurrentRenderOutputSize");
        rect = (SDL_FRect){0, 0, (float)w, (float)h};
    } else {
        osdl_check(SDL_GetRenderLogicalPresentationRect(r, &rect),
                   "SDL_GetRenderLogicalPresentationRect");
    }

    /* Sdl3.Frect.t contains four floats in this order. */
    value result = caml_alloc_small(4 * Double_wosize, Double_array_tag);
    Store_double_flat_field(result, 0, rect.x);
    Store_double_flat_field(result, 1, rect.y);
    Store_double_flat_field(result, 2, rect.w);
    Store_double_flat_field(result, 3, rect.h);
    return result;
}

static const SDL_Rect* osdl_view_rect_option(value rect, SDL_Rect* storage) {
    if (Is_long(rect)) return NULL;
    *storage = osdl_rect(Some_val(rect));
    if (storage->w < 0 || storage->h < 0)
        caml_invalid_argument("A viewport or clip rectangle cannot have a negative size");
    return storage;
}

CAMLprim value osdl_renderer_set_viewport(value renderer, value rect) {
    SDL_Renderer*   r = osdl_live(renderer);
    SDL_Rect        storage;
    const SDL_Rect* area = osdl_view_rect_option(rect, &storage);
    if (area) osdl_check_view_rect(*area, osdl_current_view(r));

    osdl_check(SDL_SetRenderViewport(r, area), "SDL_SetRenderViewport");
    return Val_unit;
}

CAMLprim value osdl_renderer_viewport(value renderer) {
    SDL_Renderer* r = osdl_live(renderer);
    if (!SDL_RenderViewportSet(r)) osdl_check_automatic_viewport(r, osdl_current_view(r).scale);

    SDL_Rect rect;
    osdl_check(SDL_GetRenderViewport(r, &rect), "SDL_GetRenderViewport");
    return osdl_rect_value(rect);
}

CAMLprim value osdl_renderer_viewport_is_set(value renderer) {
    return Val_bool(SDL_RenderViewportSet(osdl_live(renderer)));
}

CAMLprim value osdl_renderer_set_clip_rect(value renderer, value rect) {
    SDL_Renderer*   r = osdl_live(renderer);
    SDL_Rect        storage;
    const SDL_Rect* area = osdl_view_rect_option(rect, &storage);
    if (area) {
        osdl_render_view view = osdl_current_view(r);
        view.offset           = (SDL_FPoint){0, 0};
        osdl_check_view_rect(*area, view);
    }

    osdl_check(SDL_SetRenderClipRect(r, area), "SDL_SetRenderClipRect");
    return Val_unit;
}

CAMLprim value osdl_renderer_clip_rect(value renderer) {
    SDL_Renderer* r = osdl_live(renderer);
    if (!SDL_RenderClipEnabled(r)) return Val_none;

    SDL_Rect rect;
    osdl_check(SDL_GetRenderClipRect(r, &rect), "SDL_GetRenderClipRect");
    return caml_alloc_some(osdl_rect_value(rect));
}

CAMLprim value osdl_renderer_set_scale(value renderer, value x, value y) {
    SDL_Renderer* r     = osdl_live(renderer);
    SDL_FPoint    scale = {osdl_float(Double_val(x)), osdl_float(Double_val(y))};
    if (!(scale.x > 0 && scale.y > 0 && scale.x <= osdl_view_limit && scale.y <= osdl_view_limit))
        caml_invalid_argument("Render scales must be positive and within the SDL range");
    osdl_render_view view = osdl_scale_view(osdl_logical_view(r), scale);
    osdl_check_view_state(r, view);
    osdl_check_automatic_viewport(r, view.scale);

    osdl_check(SDL_SetRenderScale(r, scale.x, scale.y), "SDL_SetRenderScale");
    return Val_unit;
}

CAMLprim value osdl_renderer_scale(value renderer) {
    SDL_FPoint scale = osdl_render_scale(osdl_live(renderer));
    return osdl_float_pair(scale.x, scale.y);
}

static value osdl_renderer_coordinates(value renderer, value x, value y, bool from_window) {
    SDL_Renderer* r  = osdl_live(renderer);
    float         cx = osdl_float(Double_val(x)), cy = osdl_float(Double_val(y));

    if (from_window)
        osdl_check(SDL_RenderCoordinatesFromWindow(r, cx, cy, &cx, &cy),
                   "SDL_RenderCoordinatesFromWindow");
    else
        osdl_check(SDL_RenderCoordinatesToWindow(r, cx, cy, &cx, &cy),
                   "SDL_RenderCoordinatesToWindow");
    if (!osdl_fits_float(cx) || !osdl_fits_float(cy))
        caml_invalid_argument("The converted coordinates must be finite C floats");
    return osdl_float_pair(cx, cy);
}

CAMLprim value osdl_renderer_coordinates_from_window(value renderer, value x, value y) {
    return osdl_renderer_coordinates(renderer, x, y, true);
}

CAMLprim value osdl_renderer_coordinates_to_window(value renderer, value x, value y) {
    return osdl_renderer_coordinates(renderer, x, y, false);
}

CAMLprim value osdl_renderer_set_draw_color(value renderer, value color) {
    SDL_Color c = osdl_color(color);
    osdl_check(SDL_SetRenderDrawColor(osdl_live(renderer), c.r, c.g, c.b, c.a),
               "SDL_SetRenderDrawColor");
    return Val_unit;
}

CAMLprim value osdl_renderer_set_draw_blend_mode(value renderer, value mode) {
    osdl_check(SDL_SetRenderDrawBlendMode(osdl_live(renderer), osdl_blend_mode(mode)),
               "SDL_SetRenderDrawBlendMode");
    return Val_unit;
}

OSDL_ACTION(osdl_renderer_clear, SDL_RenderClear)

CAMLprim value osdl_renderer_fill_rect(value renderer, value rect) {
    SDL_FRect r = osdl_frect(rect);
    osdl_check(SDL_RenderFillRect(osdl_live(renderer), &r), "SDL_RenderFillRect");
    return Val_unit;
}

CAMLprim value osdl_renderer_draw_rect(value renderer, value rect) {
    SDL_FRect r = osdl_frect(rect);
    osdl_check(SDL_RenderRect(osdl_live(renderer), &r), "SDL_RenderRect");
    return Val_unit;
}

static value osdl_renderer_rects(value renderer, value rects, bool fill) {
    SDL_Renderer* r     = osdl_live(renderer);
    mlsize_t      count = Wosize_val(rects);
    if (count == 0) return Val_unit;
    /* SDL can expand each filled rectangle into eight float coordinates. */
    if (count > INT_MAX / 8 || count > SIZE_MAX / (8 * sizeof(float)))
        caml_invalid_argument("SDL rectangle array is too large");

    SDL_FRect  stack[32];
    SDL_FRect* native = stack;
    if (count > SDL_arraysize(stack)) {
        native = SDL_malloc(count * sizeof(*native));
        if (!native) caml_raise_out_of_memory();
    }

    mlsize_t i = 0;
    while (i < count && osdl_read_frect(Field(rects, i), &native[i]))
        ++i;
    bool ok = i == count && (fill ? SDL_RenderFillRects(r, native, (int)count)
                                  : SDL_RenderRects(r, native, (int)count));
    if (native != stack) SDL_free(native);

    if (i != count) caml_invalid_argument("SDL argument is not a finite C float");
    osdl_check(ok, fill ? "SDL_RenderFillRects" : "SDL_RenderRects");
    return Val_unit;
}

CAMLprim value osdl_renderer_fill_rects(value renderer, value rects) {
    return osdl_renderer_rects(renderer, rects, true);
}

CAMLprim value osdl_renderer_draw_rects(value renderer, value rects) {
    return osdl_renderer_rects(renderer, rects, false);
}

CAMLprim value osdl_renderer_draw_line(value renderer, value x1, value y1, value x2, value y2) {
    osdl_check(SDL_RenderLine(osdl_live(renderer), osdl_float(Double_val(x1)),
                              osdl_float(Double_val(y1)), osdl_float(Double_val(x2)),
                              osdl_float(Double_val(y2))),
               "SDL_RenderLine");
    return Val_unit;
}

static SDL_Rect osdl_read_pixels_area(SDL_Rect rect, int w, int h) {
    /* SDL only clips to the viewport, which can extend past the target. Clip
     * to the physical bounds first. Use wide sums for untrusted endpoints. */
    int x = SDL_max(rect.x, 0), y = SDL_max(rect.y, 0);
    int right  = (int)SDL_min((Sint64)rect.x + rect.w, w);
    int bottom = (int)SDL_min((Sint64)rect.y + rect.h, h);
    if (right <= x || bottom <= y)
        osdl_raise_error("SDL_RenderReadPixels: The read area does not overlap the target");
    return (SDL_Rect){x, y, right - x, bottom - y};
}

static void osdl_readback_palette(SDL_Surface* pixels, const SDL_Palette* palette) {
    /* SDL's software readback copies indices but not the palette. Keep the
     * result independent of later changes to the original palette. */
    SDL_Palette* copy = SDL_CreatePalette(palette->ncolors);
    if (!copy) osdl_surface_fail_and_destroy(pixels, "SDL_CreatePalette");
    bool ok = SDL_SetPaletteColors(copy, palette->colors, 0, palette->ncolors) &&
              SDL_SetSurfacePalette(pixels, copy);
    SDL_DestroyPalette(copy);
    if (!ok) osdl_surface_fail_and_destroy(pixels, "SDL_RenderReadPixels");
}

CAMLprim value osdl_renderer_read_pixels(value rect, value renderer) {
    CAMLparam2(rect, renderer);
    CAMLlocal1(handle);

    /* A renderer's parent is either a window or a surface. The copy only
     * depends on their context, not on the renderer or its target. */
    handle = osdl_new_handle(osdl_parent(osdl_parent(renderer)));

    SDL_Renderer* r        = osdl_live(renderer);
    bool          has_rect = Is_block(rect);
    SDL_Rect      requested;
    if (has_rect) {
        requested = osdl_rect(Some_val(rect));
        if (requested.w <= 0 || requested.h <= 0)
            caml_invalid_argument("The read area must have positive dimensions");
    }

    SDL_Texture* target  = SDL_GetRenderTarget(r);
    SDL_Palette* palette = NULL;
    int          w, h;
    if (target) {
        w = target->w;
        h = target->h;
    } else if (SDL_GetRenderWindow(r)) {
        /* SDL's Vulkan swapchain images lack VK_IMAGE_USAGE_TRANSFER_SRC_BIT. */
        const char* name = SDL_GetRendererName(r);
        if (name && strcmp(name, "vulkan") == 0)
            osdl_raise_error("SDL_RenderReadPixels: Use a texture target with the Vulkan renderer");
        osdl_check(SDL_GetRenderOutputSize(r, &w, &h), "SDL_GetRenderOutputSize");
    } else {
        SDL_Surface* backing = osdl_unlocked_surface(osdl_parent(renderer));
        osdl_check_surface_byte_pixels(backing);
        osdl_check_surface_storage(backing);
        if (SDL_ISPIXELFORMAT_INDEXED(backing->format)) palette = osdl_surface_palette(backing);
        w = backing->w;
        h = backing->h;
    }
    SDL_Rect area = osdl_read_pixels_area(has_rect ? requested : (SDL_Rect){0, 0, w, h}, w, h);

    SDL_ClearError();
    SDL_Surface* pixels = SDL_RenderReadPixels(r, &area);
    if (!pixels && !*SDL_GetError()) osdl_raise_error("SDL_RenderReadPixels: No pixels were read");
    if (pixels && palette && SDL_ISPIXELFORMAT_INDEXED(pixels->format))
        osdl_readback_palette(pixels, palette);
    CAMLreturn(osdl_publish(handle, pixels, "SDL_RenderReadPixels"));
}

CAMLprim value osdl_renderer_present(value renderer) {
    SDL_Renderer* r = osdl_live(renderer);
    if (SDL_GetRenderTarget(r))
        caml_invalid_argument("Restore the default render target before presenting");

    osdl_check(SDL_RenderPresent(r), "SDL_RenderPresent");
    return Val_unit;
}

/* Textures. */

/* Only render-target textures need an SDL target lookup when drawn. */
static struct custom_operations osdl_target_ops = {.identifier = "ocaml-sdl3.target"};

static bool osdl_texture_can_be_target(value texture) {
    return Custom_ops_val(Field(texture, 0)) == &osdl_target_ops;
}

CAMLprim value osdl_texture_of_surface(value renderer, value surface) {
    CAMLparam2(renderer, surface);
    CAMLlocal1(handle);

    handle = osdl_new_handle(renderer);

    SDL_Texture* texture =
        SDL_CreateTextureFromSurface(osdl_live(renderer), osdl_unlocked_surface(surface));
    CAMLreturn(osdl_publish(handle, texture, "SDL_CreateTextureFromSurface"));
}

static value osdl_texture_create(value renderer, value w, value h, SDL_TextureAccess access) {
    CAMLparam3(renderer, w, h);
    CAMLlocal1(handle);

    handle = osdl_new_handle_with_ops(
        renderer, access == SDL_TEXTUREACCESS_TARGET ? &osdl_target_ops : &osdl_handle_ops);

    SDL_Renderer* r     = osdl_live(renderer);
    int           width = osdl_positive_int(w), height = osdl_positive_int(h);
    /* Keep pixel offsets in range on renderers that use int arithmetic. */
    if (width > INT_MAX / 4 / height) caml_invalid_argument("SDL RGBA texture is too large");

    SDL_Texture* texture = SDL_CreateTexture(r, SDL_PIXELFORMAT_RGBA32, access, width, height);
    CAMLreturn(osdl_publish(handle, texture, "SDL_CreateTexture"));
}

CAMLprim value osdl_texture_create_streaming(value renderer, value w, value h) {
    return osdl_texture_create(renderer, w, h, SDL_TEXTUREACCESS_STREAMING);
}

CAMLprim value osdl_texture_create_target(value renderer, value w, value h) {
    return osdl_texture_create(renderer, w, h, SDL_TEXTUREACCESS_TARGET);
}

static SDL_Rect osdl_texture_region(SDL_Texture* texture, value rect) {
    if (Is_long(rect)) return (SDL_Rect){0, 0, texture->w, texture->h};

    SDL_Rect area = osdl_rect(Some_val(rect));
    if (area.x < 0 || area.y < 0 || area.w <= 0 || area.h <= 0 || area.x > texture->w - area.w ||
        area.y > texture->h - area.h)
        caml_invalid_argument(
            "SDL rectangle must be inside the texture and have positive dimensions");
    return area;
}

static int osdl_rgba_pitch(value pitch, int width) {
    int stride = osdl_positive_int(pitch);
    if (stride % 4 || stride / 4 < width)
        caml_invalid_argument("SDL RGBA pitch must be a multiple of four and cover a row");
    return stride;
}

CAMLprim value osdl_texture_update(value rect, value texture, value buffer, value pitch) {
    SDL_Texture* t      = osdl_texture_unlocked(texture);
    SDL_Rect     area   = osdl_texture_region(t, rect);
    int          stride = osdl_rgba_pitch(pitch, area.w);
    if (area.h > INT_MAX / stride) caml_invalid_argument("SDL texture upload is too large");
    if (Caml_ba_array_val(buffer)->dim[0] < stride * area.h)
        caml_invalid_argument("SDL texture upload buffer is too small");

    osdl_check(
        SDL_UpdateTexture(t, Is_block(rect) ? &area : NULL, Caml_ba_data_val(buffer), stride),
        "SDL_UpdateTexture");
    return Val_unit;
}

/* A lock is the texture's only child. The custom cell keeps all pixel data
 * private. Only the OCaml wrapper can acquire or release the lock. */
typedef struct {
    osdl_cell cell;
    int       width, height, pitch;
    bool      initialized;
} osdl_texture_lock;

CAMLprim value osdl_texture_prepare_lock(value texture) {
    CAMLparam1(texture);
    CAMLlocal1(cell);

    osdl_texture_unlocked(texture);
    cell                    = caml_alloc_custom(&osdl_handle_ops, sizeof(osdl_texture_lock), 0, 1);
    osdl_texture_lock* lock = Data_custom_val(cell);
    lock->cell              = (osdl_cell){0};
    memcpy(lock->cell.thread, osdl_cell_val(texture)->thread, sizeof(lock->cell.thread));
    CAMLreturn(caml_alloc_2(0, cell, texture));
}

CAMLprim value osdl_texture_lock_pixels(value rect, value view) {
    value        texture   = osdl_parent(view);
    SDL_Texture* t         = osdl_texture_unlocked(texture);
    SDL_Rect     area      = osdl_texture_region(t, rect);
    size_t       row_bytes = 4 * (size_t)area.w;

    void* pixels = NULL;
    int   pitch  = 0;
    osdl_check(SDL_LockTexture(t, Is_block(rect) ? &area : NULL, &pixels, &pitch),
               "SDL_LockTexture");
    if (!pixels || pitch <= 0 || (size_t)pitch < row_bytes ||
        (size_t)(area.h - 1) > (SIZE_MAX - row_bytes) / (size_t)pitch) {
        SDL_UnlockTexture(t);
        osdl_raise_error("SDL_LockTexture: SDL returned invalid pixel storage");
    }

    osdl_texture_lock* lock = (osdl_texture_lock*)osdl_cell_val(view);
    lock->width             = area.w;
    lock->height            = area.h;
    lock->pitch             = pitch;

    /* A whole-region write can skip the initial clear. */
    lock->initialized = false;
    osdl_publish(view, pixels, "SDL_LockTexture");
    return Val_unit;
}

static Uint32 osdl_rgba_pixel(value color) {
    SDL_Color c       = osdl_color(color);
    Uint8     bytes[] = {c.r, c.g, c.b, c.a};
    Uint32    pixel;
    memcpy(&pixel, bytes, sizeof(pixel));
    return pixel;
}

static void osdl_locked_fill(osdl_texture_lock* lock, Uint8* pixels, Uint32 pixel) {
    size_t pitch = lock->pitch, rows = lock->height;
    size_t row_bytes = 4 * (size_t)lock->width;
    if (pitch == row_bytes) {
        row_bytes *= rows;
        rows = 1;
    }
    for (size_t y = 0; y < rows; ++y) {
        Uint8* row = pixels + y * pitch;
        if (!pixel)
            memset(row, 0, row_bytes);
        else
            for (size_t i = 0; i < row_bytes; i += 4)
                memcpy(row + i, &pixel, sizeof(pixel));
    }
    lock->initialized = true;
}

CAMLprim value osdl_texture_unlock_pixels(value view) {
    Uint8* pixels = osdl_take(view);
    if (pixels) {
        osdl_texture_lock* lock = (osdl_texture_lock*)osdl_cell_val(view);
        SDL_Texture*       t    = osdl_cell_val(osdl_parent(view))->ptr;
        if (!lock->initialized) osdl_locked_fill(lock, pixels, 0);
        SDL_UnlockTexture(t);
        Store_field(view, 1, Val_unit);
    }
    return Val_unit;
}

static osdl_texture_lock* osdl_live_lock(value view) {
    osdl_live(view);
    return (osdl_texture_lock*)osdl_cell_val(view);
}

CAMLprim value osdl_locked_pixels_size(value view) {
    osdl_texture_lock* lock = osdl_live_lock(view);
    return osdl_int_pair(lock->width, lock->height);
}

CAMLprim value osdl_locked_pixels_fill(value view, value color) {
    osdl_texture_lock* lock = osdl_live_lock(view);
    osdl_locked_fill(lock, lock->cell.ptr, osdl_rgba_pixel(color));
    return Val_unit;
}

CAMLprim value osdl_locked_pixels_set_pixel(value view, value vx, value vy, value color) {
    osdl_texture_lock* lock = osdl_live_lock(view);
    intnat             x = Long_val(vx), y = Long_val(vy);
    if (x < 0 || x >= lock->width || y < 0 || y >= lock->height)
        caml_invalid_argument("SDL pixel is outside the locked rectangle");

    Uint8* pixels = lock->cell.ptr;
    if (!lock->initialized) osdl_locked_fill(lock, pixels, 0);
    Uint32 pixel = osdl_rgba_pixel(color);
    memcpy(pixels + (size_t)y * lock->pitch + 4 * (size_t)x, &pixel, sizeof(pixel));
    return Val_unit;
}

CAMLprim value osdl_locked_pixels_copy_from(value view, value buffer, value pitch) {
    osdl_texture_lock* lock      = osdl_live_lock(view);
    size_t             row_bytes = 4 * (size_t)lock->width;
    size_t             stride    = osdl_rgba_pitch(pitch, lock->width);
    size_t             length    = Caml_ba_array_val(buffer)->dim[0];
    if (length < row_bytes || (size_t)(lock->height - 1) > (length - row_bytes) / stride)
        caml_invalid_argument("The RGBA source buffer does not cover the locked rectangle");

    const Uint8* src = Caml_ba_data_val(buffer);
    Uint8*       dst = lock->cell.ptr;
    if (stride == row_bytes && (size_t)lock->pitch == row_bytes)
        memcpy(dst, src, row_bytes * (size_t)lock->height);
    else
        for (int y = 0; y < lock->height; ++y)
            memcpy(dst + (size_t)y * lock->pitch, src + (size_t)y * stride, row_bytes);
    lock->initialized = true;
    return Val_unit;
}

CAMLprim value osdl_texture_destroy(value texture) {
    if (osdl_texture_can_be_target(texture)) {
        osdl_cell* cell = osdl_cell_val(texture);
        osdl_require_thread(osdl_cell_thread(cell));
        SDL_Texture* t = cell->ptr;
        if (!t) return Val_unit;

        SDL_Renderer* r = osdl_live(osdl_parent(texture));
        if (SDL_GetRenderTarget(r) == t)
            osdl_check(SDL_SetRenderTarget(r, NULL), "SDL_SetRenderTarget");
    }

    SDL_Texture* t = osdl_take(texture);
    if (t) SDL_DestroyTexture(t);
    return Val_unit;
}

CAMLprim value osdl_texture_size(value texture) {
    float w, h;
    osdl_check(SDL_GetTextureSize(osdl_live(texture), &w, &h), "SDL_GetTextureSize");
    return osdl_float_pair(w, h);
}

CAMLprim value osdl_texture_set_scale_mode(value texture, value mode) {
    osdl_check(SDL_SetTextureScaleMode(osdl_live(texture), osdl_scale_mode(mode)),
               "SDL_SetTextureScaleMode");
    return Val_unit;
}

CAMLprim value osdl_texture_set_blend_mode(value texture, value mode) {
    osdl_check(SDL_SetTextureBlendMode(osdl_live(texture), osdl_blend_mode(mode)),
               "SDL_SetTextureBlendMode");
    return Val_unit;
}

CAMLprim value osdl_texture_set_color_mod(value texture, value color) {
    SDL_Texture* t = osdl_live(texture);
    SDL_Color    c = osdl_color(color);
    osdl_check(SDL_SetTextureColorMod(t, c.r, c.g, c.b), "SDL_SetTextureColorMod");
    return Val_unit;
}

CAMLprim value osdl_texture_set_alpha_mod(value texture, value alpha) {
    osdl_check(SDL_SetTextureAlphaMod(osdl_live(texture), osdl_byte(alpha)),
               "SDL_SetTextureAlphaMod");
    return Val_unit;
}

static SDL_Texture* osdl_texture_source(value texture, value renderer, SDL_Renderer* r) {
    SDL_Texture* t = osdl_texture_for_renderer(texture, renderer);
    if (osdl_texture_can_be_target(texture) && SDL_GetRenderTarget(r) == t)
        caml_invalid_argument("Do not draw a texture into itself");
    return t;
}

CAMLprim value osdl_texture_draw(value src, value dst, value renderer, value texture) {
    SDL_Renderer*    r = osdl_live(renderer);
    SDL_Texture*     t = osdl_texture_source(texture, renderer, r);
    SDL_FRect        s, d;
    const SDL_FRect* source = osdl_frect_option(src, &s);
    const SDL_FRect* dest   = osdl_frect_option(dst, &d);

    osdl_check(SDL_RenderTexture(r, t, source, dest), "SDL_RenderTexture");
    return Val_unit;
}

static inline SDL_Vertex osdl_sprite_vertex(float x, float y, float u, float v, SDL_FColor color) {
    SDL_FPoint position = {x, y};
    SDL_FPoint uv       = {u, v};
    return (SDL_Vertex){.position = position, .color = color, .tex_coord = uv};
}

CAMLprim value osdl_texture_draw_sprites(value renderer, value texture, value positions,
                                         value tints, value count) {
    SDL_Renderer* r = osdl_live(renderer);
    SDL_Texture*  t = osdl_texture_source(texture, renderer, r);

    mlsize_t n = osdl_nonnegative_int(count);
    if (n > Wosize_val(tints) || n > Wosize_val(positions) / Double_wosize / 2)
        caml_invalid_argument("The sprite count exceeds the array lengths");
    if (!n) return Val_unit;

    for (mlsize_t i = 0; i < n * 2; ++i) {
        if (!osdl_fits_float(Double_flat_field(positions, i)))
            caml_invalid_argument("Sprite coordinates must be finite C floats");
    }

    float w, h;
    osdl_check(SDL_GetTextureSize(t, &w, &h), "SDL_GetTextureSize");

    /* SDL's software renderer can turn these quads into texture copies. It
     * sets the texture modulation for each copy and leaves the last one set. */
    const char* driver   = SDL_GetRendererName(r);
    bool        software = driver && strcmp(driver, SDL_SOFTWARE_RENDERER) == 0;
    SDL_FColor  saved    = {0};
    if (software) {
        osdl_check(SDL_GetTextureColorModFloat(t, &saved.r, &saved.g, &saved.b),
                   "SDL_GetTextureColorModFloat");
        osdl_check(SDL_GetTextureAlphaModFloat(t, &saved.a), "SDL_GetTextureAlphaModFloat");
    }

    /* Reuse a bounded amount of stack space, even for very large batches. */
    enum { sprites_per_chunk = 512 };
    SDL_Vertex vertices[4 * sprites_per_chunk];
    int        indices[6 * sprites_per_chunk];
    int        capacity = n < sprites_per_chunk ? (int)n : sprites_per_chunk;
    for (int j = 0; j < capacity; ++j) {
        int v = j * 4, k = j * 6;
        indices[k]     = v;
        indices[k + 1] = v + 1;
        indices[k + 2] = v + 2;
        indices[k + 3] = v;
        indices[k + 4] = v + 2;
        indices[k + 5] = v + 3;
    }

    bool ok = true;
    for (mlsize_t first = 0; first < n;) {
        int batch = n - first < (mlsize_t)capacity ? (int)(n - first) : capacity;
        for (int j = 0; j < batch; ++j) {
            mlsize_t    i     = first + j;
            float       x     = (float)Double_flat_field(positions, i * 2);
            float       y     = (float)Double_flat_field(positions, i * 2 + 1);
            SDL_Color   c     = osdl_color(Field(tints, i));
            const float norm  = 1.0f / 255.0f;
            SDL_FColor  color = {c.r * norm, c.g * norm, c.b * norm, c.a * norm};
            SDL_Vertex* v     = &vertices[j * 4];

            v[0] = osdl_sprite_vertex(x, y, 0.0f, 0.0f, color);
            v[1] = osdl_sprite_vertex(x + w, y, 1.0f, 0.0f, color);
            v[2] = osdl_sprite_vertex(x + w, y + h, 1.0f, 1.0f, color);
            v[3] = osdl_sprite_vertex(x, y + h, 0.0f, 1.0f, color);
        }
        ok = SDL_RenderGeometry(r, t, vertices, 4 * batch, indices, 6 * batch);
        if (!ok) break;
        first += batch;
    }

    if (software) {
        char message[1024];
        if (!ok) osdl_error_message(message, sizeof(message), "SDL_RenderGeometry");
        /* These setters only change the modulation of the live texture. */
        SDL_SetTextureColorModFloat(t, saved.r, saved.g, saved.b);
        SDL_SetTextureAlphaModFloat(t, saved.a);
        if (!ok) osdl_raise_error(message);
    }
    osdl_check(ok, "SDL_RenderGeometry");
    return Val_unit;
}

static SDL_FPoint osdl_float_point(value point) {
    return (SDL_FPoint){osdl_float(Double_val(Field(point, 0))),
                        osdl_float(Double_val(Field(point, 1)))};
}

static SDL_FRect osdl_texture_copy_region(value src, SDL_Texture* texture) {
    SDL_FRect rect = Is_long(src) ? (SDL_FRect){0, 0, (float)texture->w, (float)texture->h}
                                  : osdl_frect(Some_val(src));
    if (!(rect.x >= 0 && rect.y >= 0 && rect.w > 0 && rect.h > 0 && rect.x < (double)texture->w &&
          rect.y < (double)texture->h && (double)rect.x + rect.w <= texture->w &&
          (double)rect.y + rect.h <= texture->h))
        caml_invalid_argument(
            "The source rectangle must have positive size and lie inside the texture");
    return rect;
}

static SDL_FRect osdl_texture_destination(value dst, SDL_Renderer* renderer,
                                          osdl_render_view view) {
    if (Is_block(dst)) {
        SDL_FRect rect = osdl_frect(Some_val(dst));
        if (rect.w < 0 || rect.h < 0)
            caml_invalid_argument("The destination rectangle cannot have a negative size");
        return rect;
    }

    SDL_Rect viewport;
    if (SDL_RenderViewportSet(renderer)) {
        osdl_check(SDL_GetRenderViewport(renderer, &viewport), "SDL_GetRenderViewport");
        return (SDL_FRect){0, 0, (float)viewport.w, (float)viewport.h};
    }
    /* SDL's default destination is local to the viewport. Its size has
     * fractional precision, unlike the automatic SDL_GetRenderViewport. */
    int w, h;
    osdl_check(SDL_GetCurrentRenderOutputSize(renderer, &w, &h), "SDL_GetCurrentRenderOutputSize");
    if (w == 0 || h == 0) return (SDL_FRect){0};
    return (SDL_FRect){0, 0, (float)w / view.scale.x, (float)h / view.scale.y};
}

static float osdl_texture_draw_scale(value scale) {
    return Is_long(scale) ? 1.0f : osdl_float(Double_val(Some_val(scale)));
}

static void osdl_texture_copy_bounds(double x, double y, osdl_render_view view, bool software) {
    double px = x * view.scale.x + fabs(view.offset.x);
    double py = y * view.scale.y + fabs(view.offset.y);
    if (!osdl_fits_float(x) || !osdl_fits_float(y) || !osdl_fits_float(px) || !osdl_fits_float(py))
        caml_invalid_argument("Texture draw coordinates must fit finite C floats");
    if (software && !(px <= osdl_view_limit && py <= osdl_view_limit))
        caml_invalid_argument("Texture coordinates are outside the software renderer range");
}

static void osdl_software_rotation_bounds(osdl_render_view view, double x, double y, double width,
                                          double height, SDL_FPoint pivot, double angle,
                                          bool rotate_or_flip) {
    double reach = width + height;
    /* The rotation path uses signed byte offsets into its scaled surface. */
    if (rotate_or_flip && 4.0 * width * height > INT_MAX)
        caml_invalid_argument("The software texture copy is too large to rotate or flip");
    if (angle != 0.0) {
        double px = fabs(pivot.x), py = fabs(pivot.y);
        /* SDL uses signed 16.16 coordinates for oblique rotations. Leave
         * room for its pixel-center and rounding offsets. */
        if (fmod(angle, 90.0) != 0.0 && (reach > 32752 || px > 32766 || py > 32766))
            caml_invalid_argument("Texture size or pivot is outside the software rotation range");
        reach += 2.0 * (px + py);
    }
    double ox = fabs(view.offset.x), oy = fabs(view.offset.y);
    if (rotate_or_flip && view.scale.x > 0 && view.scale.y > 0) {
        /* The rotation path adds an offset before its final scale. SDL
         * versions differ in whether they divide the offset by that scale. */
        ox = SDL_max(ox, ox / view.scale.x);
        oy = SDL_max(oy, oy / view.scale.y);
    }
    double px = (fabs(x) + reach + ox) * SDL_max(1.0, view.scale.x);
    double py = (fabs(y) + reach + oy) * SDL_max(1.0, view.scale.y);
    if (!(px <= osdl_view_limit && py <= osdl_view_limit))
        caml_invalid_argument("Texture coordinates are outside the software renderer range");
}

CAMLprim value osdl_texture_draw_rotated(value src, value dst, value flip, value pivot,
                                         value renderer, value texture, value angle) {
    SDL_Renderer*    r = osdl_live(renderer);
    SDL_Texture*     t = osdl_texture_source(texture, renderer, r);
    SDL_FRect        s;
    const SDL_FRect* source  = osdl_frect_option(src, &s);
    SDL_FlipMode     mode    = Is_long(flip) ? SDL_FLIP_NONE : osdl_flip_mode(Some_val(flip));
    double           degrees = Double_val(angle);
    if (!isfinite(degrees)) caml_invalid_argument("SDL rotation must be finite");
    /* Some SDL versions cast angle / 360 to int in their fast path. */
    if (degrees <= -360.0 || degrees >= 360.0) degrees = fmod(degrees, 360.0);

    osdl_render_view view = osdl_current_view(r);
    SDL_FRect        d    = osdl_texture_destination(dst, r, view);
    SDL_FPoint       p =
        Is_long(pivot) ? (SDL_FPoint){d.w / 2, d.h / 2} : osdl_float_point(Some_val(pivot));
    bool rotated  = degrees != 0.0 || mode != SDL_FLIP_NONE;
    bool software = osdl_software_renderer(r);
    if (!d.w || !d.h) return Val_unit;
    if (software) {
        osdl_software_rotation_bounds(osdl_pixel_view(r, view), d.x, d.y, d.w, d.h, p, degrees,
                                      rotated);
        /* SDL rotates an intermediate surface of integer size. */
        if (rotated && (d.w < 1 || d.h < 1)) return Val_unit;
    } else {
        double reach = degrees == 0.0 ? 0 : (double)d.w + d.h + 2 * (fabs(p.x) + fabs(p.y));
        osdl_texture_copy_bounds(fabs(d.x) + d.w + reach, fabs(d.y) + d.h + reach, view, false);
    }

    osdl_check(
        SDL_RenderTextureRotated(r, t, source, &d, degrees, Is_long(pivot) ? NULL : &p, mode),
        "SDL_RenderTextureRotated");
    return Val_unit;
}

CAMLprim value osdl_texture_draw_rotated_byte(value* argv, int argc) {
    (void)argc;
    return osdl_texture_draw_rotated(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

/* Software SDL turns affine copies and custom geometry into triangles. */
static int osdl_software_geometry_target_width(SDL_Renderer* renderer) {
    SDL_Texture* target = SDL_GetRenderTarget(renderer);
    int          w, h;
    if (target) {
        w = target->w;
        h = target->h;
    } else {
        osdl_check(SDL_GetRenderOutputSize(renderer, &w, &h), "SDL_GetRenderOutputSize");
    }
    if ((Sint64)w * h > INT_MAX / 4)
        caml_invalid_argument("The software geometry target is too large");
    return w;
}

static void osdl_software_geometry_position(osdl_render_view view, int w, double x, double y) {
    /* The rasterizer uses fixed-point coordinates and signed byte offsets. */
    double px = fabs(x) * view.scale.x + fabs(view.offset.x) + 1.0;
    double py = fabs(y) * view.scale.y + fabs(view.offset.y) + 1.0;
    if (!(px <= (1 << 24) && py <= (1 << 24) && 4.0 * (px + py * w) <= INT_MAX))
        caml_invalid_argument("Geometry positions are outside the software renderer range");
}

static void osdl_software_geometry_texture(SDL_Texture* t) {
    if (t->w > (1 << 24) || t->h > (1 << 24) || (Sint64)t->w * t->h > INT_MAX / 4)
        caml_invalid_argument("The software geometry texture is too large");
}

static void osdl_software_geometry_area(osdl_render_view view, double dx, double dy, double uv) {
    /* SDL stores edge weights and a texture coordinate times the area in ints. */
    double area = 4.0 * (dx * view.scale.x + 2.0) * (dy * view.scale.y + 2.0);
    if (2.0 * area > INT_MAX || area * uv > INT_MAX)
        caml_invalid_argument("A textured triangle is too large for the software renderer");
}

static void osdl_affine_software_bounds(SDL_Renderer* renderer, SDL_Texture* t,
                                        osdl_render_view view, SDL_FRect src, const SDL_FPoint* p) {
    int target_width = osdl_software_geometry_target_width(renderer);
    osdl_software_geometry_texture(t);

    /* Both triangles must start inside the texture after conversion back to
     * integer texels, even if the source selects a fraction of a texel. */
    float u = src.x / t->w, v = src.y / t->h;
    if (u * t->w >= t->w || v * t->h >= t->h)
        caml_invalid_argument("The affine source rectangle is too close to the texture edge");

    double min_x = p[0].x, max_x = min_x, min_y = p[0].y, max_y = min_y;
    for (int i = 0; i < 4; ++i) {
        osdl_software_geometry_position(view, target_width, p[i].x, p[i].y);
        min_x = SDL_min(min_x, p[i].x);
        max_x = SDL_max(max_x, p[i].x);
        min_y = SDL_min(min_y, p[i].y);
        max_y = SDL_max(max_y, p[i].y);
    }
    /* Use the whole parallelogram's bounds for both triangles. */
    double edge = SDL_max((double)src.x + src.w, (double)src.y + src.h);
    osdl_software_geometry_area(view, max_x - min_x, max_y - min_y, SDL_ceil(edge) + 1);
}

CAMLprim value osdl_texture_draw_affine(value src, value renderer, value texture, value origin,
                                        value right, value down) {
    SDL_Renderer* r   = osdl_live(renderer);
    SDL_Texture*  t   = osdl_texture_source(texture, renderer, r);
    SDL_FRect     s   = osdl_texture_copy_region(src, t);
    SDL_FPoint    p[] = {
        osdl_float_point(origin), osdl_float_point(right), osdl_float_point(down), {0, 0}
    };
    /* SDL adds the two corners before subtracting the origin. */
    float sum_x = osdl_float((double)p[1].x + p[2].x), sum_y = osdl_float((double)p[1].y + p[2].y);
    p[3] = (SDL_FPoint){osdl_float((double)sum_x - p[0].x), osdl_float((double)sum_y - p[0].y)};

    osdl_render_view view = osdl_current_view(r);
    if (osdl_software_renderer(r)) {
        osdl_affine_software_bounds(r, t, osdl_pixel_view(r, view), s, p);
    } else {
        for (int i = 0; i < 4; ++i)
            osdl_texture_copy_bounds(fabs(p[i].x), fabs(p[i].y), view, false);
    }

    osdl_check(SDL_RenderTextureAffine(r, t, &s, &p[0], &p[1], &p[2]), "SDL_RenderTextureAffine");
    return Val_unit;
}

CAMLprim value osdl_texture_draw_affine_byte(value* argv, int argc) {
    (void)argc;
    return osdl_texture_draw_affine(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

static bool osdl_power_of_two(int size) {
    return size > 0 && !(size & (size - 1));
}

CAMLprim value osdl_texture_draw_tiled(value src, value dst, value scale, value renderer,
                                       value texture) {
    SDL_Renderer*    r    = osdl_live(renderer);
    SDL_Texture*     t    = osdl_texture_source(texture, renderer, r);
    SDL_FRect        s    = osdl_texture_copy_region(src, t);
    osdl_render_view view = osdl_current_view(r);
    SDL_FRect        d    = osdl_texture_destination(dst, r, view);
    float            zoom = osdl_texture_draw_scale(scale);

    float tw = s.w * zoom, th = s.h * zoom;
    if (!(tw > 0 && th > 0 && osdl_fits_float(tw) && osdl_fits_float(th)))
        caml_invalid_argument("Tile sizes must be positive and fit finite C floats");
    if (!d.w || !d.h) return Val_unit;
    bool software = osdl_software_renderer(r);
    if (software) view = osdl_pixel_view(r, view);
    osdl_texture_copy_bounds(fabs(d.x) + d.w, fabs(d.y) + d.h, view, software);

    /* Atlas regions and some renderers queue one copy per tile, even when
     * the output clips most of the copies. Keep SDL's counts and work bounded. */
    double columns = SDL_ceilf(d.w / tw), rows = SDL_ceilf(d.h / th);
    bool   may_iterate = software || s.x != 0 || s.y != 0 || s.w != (float)t->w ||
                       s.h != (float)t->h || !osdl_power_of_two(t->w) || !osdl_power_of_two(t->h);
    if (!(columns <= INT_MAX && rows <= INT_MAX) || (may_iterate && columns * rows > 1048576))
        caml_invalid_argument("The destination needs too many texture tiles");

    osdl_check(SDL_RenderTextureTiled(r, t, &s, zoom, &d), "SDL_RenderTextureTiled");
    return Val_unit;
}

CAMLprim value osdl_texture_draw_nine_slice(value src, value dst, value scale, value renderer,
                                            value texture, value borders) {
    SDL_Renderer*    r    = osdl_live(renderer);
    SDL_Texture*     t    = osdl_texture_source(texture, renderer, r);
    SDL_FRect        s    = osdl_texture_copy_region(src, t);
    osdl_render_view view = osdl_current_view(r);
    SDL_FRect        d    = osdl_texture_destination(dst, r, view);
    float            zoom = osdl_texture_draw_scale(scale);
    /* Texture.borders is a float-only record in this order. */
    float            l    = osdl_float(Double_flat_field(borders, 0)),
          rt              = osdl_float(Double_flat_field(borders, 1));
    float top             = osdl_float(Double_flat_field(borders, 2)),
          b               = osdl_float(Double_flat_field(borders, 3));
    if (zoom < 0) caml_invalid_argument("The nine-slice scale must not be negative");
    if (l < 0 || rt < 0 || top < 0 || b < 0 || s.w - l - rt <= 0 || s.h - top - b <= 0)
        caml_invalid_argument(
            "Nine-slice borders must be nonnegative and leave room for the source center");

    float corner_scale = zoom == 0.0f ? 1.0f : zoom;
    if (!(d.w - SDL_ceilf(l * corner_scale) - SDL_ceilf(rt * corner_scale) >= 0 &&
          d.h - SDL_ceilf(top * corner_scale) - SDL_ceilf(b * corner_scale) >= 0))
        caml_invalid_argument("The destination is too small for the scaled nine-slice borders");
    if (!d.w || !d.h) return Val_unit;
    bool software = osdl_software_renderer(r);
    if (software) view = osdl_pixel_view(r, view);
    osdl_texture_copy_bounds(fabs(d.x) + d.w, fabs(d.y) + d.h, view, software);

    osdl_check(SDL_RenderTexture9Grid(r, t, &s, l, rt, top, b, zoom, &d), "SDL_RenderTexture9Grid");
    return Val_unit;
}

CAMLprim value osdl_texture_draw_nine_slice_byte(value* argv, int argc) {
    (void)argc;
    return osdl_texture_draw_nine_slice(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/* Ordered sprite batches. */

/* Only the positions are exposed to OCaml. Cache the transformed corners
 * relative to each position so moving a sprite does not recompute its rotation. */
typedef struct {
    SDL_Rect   source;
    SDL_FPoint size, pivot, corners[4];
    double     angle;
    SDL_Color  color; /* Render color, with opacity applied to alpha. */
    Uint8      flip, tint_alpha, opacity;
} osdl_sprite;

static inline osdl_sprite* osdl_sprite_at(value storage, intnat i) {
    return &((osdl_sprite*)Caml_ba_data_val(storage))[i];
}

static inline void osdl_sprite_apply_opacity(osdl_sprite* sprite) {
    sprite->color.a = (sprite->tint_alpha * sprite->opacity + 127) / 255;
}

static inline void osdl_sprite_set_tint(osdl_sprite* sprite, SDL_Color tint) {
    sprite->color      = tint;
    sprite->tint_alpha = tint.a;
    osdl_sprite_apply_opacity(sprite);
}

CAMLprim value osdl_sprite_batch_alloc(value capacity) {
    CAMLparam1(capacity);

    size_t n = osdl_nonnegative_int(capacity);
    if (n > (size_t)Max_long / sizeof(osdl_sprite))
        caml_invalid_argument("Sprite batch capacity is out of range");

    CAMLreturn(caml_ba_alloc_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT | CAML_BA_MANAGED, 1, NULL,
                                  (intnat)(n * sizeof(osdl_sprite))));
}

static inline SDL_FPoint osdl_sprite_point(double x, double y) {
    return (SDL_FPoint){osdl_float(x), osdl_float(y)};
}

static void osdl_sprite_corners(osdl_sprite* sprite) {
    /* Make right angles exact. Positive angles turn clockwise in screen space. */
    double c, s;
    int    quarter = (int)(sprite->angle / 90.0);
    if (sprite->angle == quarter * 90.0) {
        static const double cosine[] = {1, 0, -1, 0}, sine[] = {0, 1, 0, -1};
        int                 i = (quarter + 4) % 4;
        c                     = cosine[i];
        s                     = sine[i];
    } else {
        double radians = sprite->angle * (SDL_PI_D / 180.0);
        c              = cos(radians);
        s              = sin(radians);
    }

    double x  = sprite->pivot.x * (1.0 - c) + sprite->pivot.y * s;
    double y  = sprite->pivot.y * (1.0 - c) - sprite->pivot.x * s;
    double wx = sprite->size.x * c, wy = sprite->size.x * s;
    double hx = -sprite->size.y * s, hy = sprite->size.y * c;
    sprite->corners[0] = osdl_sprite_point(x, y);
    sprite->corners[1] = osdl_sprite_point(x + wx, y + wy);
    sprite->corners[2] = osdl_sprite_point(x + wx + hx, y + wy + hy);
    sprite->corners[3] = osdl_sprite_point(x + hx, y + hy);
}

CAMLprim value osdl_sprite_batch_write(value storage, value index, value source, double w, double h,
                                       double px, double py, double angle, value tint,
                                       value opacity, value flip) {
    static const Uint8 modes[] = {SDL_FLIP_NONE, SDL_FLIP_HORIZONTAL, SDL_FLIP_VERTICAL,
                                  SDL_FLIP_HORIZONTAL | SDL_FLIP_VERTICAL};

    size_t i = osdl_nonnegative_int(index);
    if (i >= (size_t)Caml_ba_array_val(storage)->dim[0] / sizeof(osdl_sprite))
        caml_invalid_argument("The sprite batch is full");

    osdl_sprite sprite = {.source = osdl_rect(source),
                          .size   = osdl_sprite_point(w, h),
                          .pivot  = osdl_sprite_point(px, py),
                          .flip   = modes[Int_val(flip)]};
    if (sprite.source.x < 0 || sprite.source.y < 0 || sprite.source.w <= 0 || sprite.source.h <= 0)
        caml_invalid_argument("Sprite source coordinates must be nonnegative and sizes positive");
    if (sprite.size.x <= 0 || sprite.size.y <= 0)
        caml_invalid_argument("Sprite destination sizes must be positive");
    if (!isfinite(angle)) caml_invalid_argument("Sprite rotation must be finite");

    sprite.angle   = angle > -360.0 && angle < 360.0 ? angle : fmod(angle, 360.0);
    sprite.opacity = osdl_byte(opacity);
    osdl_sprite_set_tint(&sprite, osdl_color(tint));
    osdl_sprite_corners(&sprite);
    *osdl_sprite_at(storage, i) = sprite;
    return Val_unit;
}

CAMLprim value osdl_sprite_batch_write_byte(value* argv, int argc) {
    (void)argc;
    return osdl_sprite_batch_write(argv[0], argv[1], argv[2], Double_val(argv[3]),
                                   Double_val(argv[4]), Double_val(argv[5]), Double_val(argv[6]),
                                   Double_val(argv[7]), argv[8], argv[9], argv[10]);
}

/* The OCaml wrappers check the live index and opacity. These calls do not allocate. */
CAMLprim value osdl_sprite_batch_set_tint(value storage, value index, value tint) {
    osdl_sprite_set_tint(osdl_sprite_at(storage, Long_val(index)), osdl_color(tint));
    return Val_unit;
}

CAMLprim value osdl_sprite_batch_set_opacity(value storage, value index, value opacity) {
    osdl_sprite* sprite = osdl_sprite_at(storage, Long_val(index));
    sprite->opacity     = Int_val(opacity);
    osdl_sprite_apply_opacity(sprite);
    return Val_unit;
}

static void osdl_sprite_software_bounds(const osdl_sprite* sprite, double x, double y,
                                        osdl_render_view view) {
    bool rotate_or_flip = sprite->angle != 0.0 || sprite->flip != SDL_FLIP_NONE;
    osdl_software_rotation_bounds(view, x, y, sprite->size.x, sprite->size.y, sprite->pivot,
                                  sprite->angle, rotate_or_flip);
}

static void osdl_sprite_batch_software(SDL_Renderer* r, SDL_Texture* t, const osdl_sprite* sprites,
                                       value positions, mlsize_t count) {
    SDL_FColor saved;
    osdl_check(SDL_GetTextureColorModFloat(t, &saved.r, &saved.g, &saved.b),
               "SDL_GetTextureColorModFloat");
    osdl_check(SDL_GetTextureAlphaModFloat(t, &saved.a), "SDL_GetTextureAlphaModFloat");

    /* SDL's software geometry path can treat a rotated quad as an ordinary
     * copy and lose the orientation of the source. Use its copy path directly. */
    const char* failed = NULL;
    for (mlsize_t i = 0; i < count; ++i) {
        const osdl_sprite* s              = &sprites[i];
        bool               rotate_or_flip = s->angle != 0.0 || s->flip != SDL_FLIP_NONE;
        /* SDL truncates these sizes before rotating the intermediate surface. */
        if (rotate_or_flip && (s->size.x < 1.0f || s->size.y < 1.0f)) continue;

        SDL_FRect source = {s->source.x, s->source.y, s->source.w, s->source.h};
        SDL_FRect dest   = {Double_flat_field(positions, i * 2),
                            Double_flat_field(positions, i * 2 + 1), s->size.x, s->size.y};
        if (!SDL_SetTextureColorMod(t, s->color.r, s->color.g, s->color.b)) {
            failed = "SDL_SetTextureColorMod";
        } else if (!SDL_SetTextureAlphaMod(t, s->color.a)) {
            failed = "SDL_SetTextureAlphaMod";
        } else if (!rotate_or_flip) {
            if (!SDL_RenderTexture(r, t, &source, &dest)) failed = "SDL_RenderTexture";
        } else if (!SDL_RenderTextureRotated(r, t, &source, &dest, s->angle,
                                             s->angle == 0.0 ? NULL : &s->pivot,
                                             (SDL_FlipMode)s->flip)) {
            failed = "SDL_RenderTextureRotated";
        }
        if (failed) break;
    }

    char message[1024];
    if (failed) osdl_error_message(message, sizeof(message), failed);
    bool color_ok = SDL_SetTextureColorModFloat(t, saved.r, saved.g, saved.b);
    bool alpha_ok = SDL_SetTextureAlphaModFloat(t, saved.a);
    if (failed) osdl_raise_error(message);
    osdl_check(color_ok && alpha_ok,
               color_ok ? "SDL_SetTextureAlphaModFloat" : "SDL_SetTextureColorModFloat");
}

static void osdl_sprite_batch_geometry(SDL_Renderer* r, SDL_Texture* t, const osdl_sprite* sprites,
                                       value positions, mlsize_t count) {
    enum { chunk_size = 512 };
    SDL_Vertex vertices[4 * chunk_size];
    int        indices[6 * chunk_size];
    int        capacity = count < chunk_size ? (int)count : chunk_size;
    for (int j = 0; j < capacity; ++j) {
        int v = 4 * j, k = 6 * j;
        indices[k]     = v;
        indices[k + 1] = v + 1;
        indices[k + 2] = v + 2;
        indices[k + 3] = v;
        indices[k + 4] = v + 2;
        indices[k + 5] = v + 3;
    }

    float tw = (float)t->w, th = (float)t->h;
    for (mlsize_t first = 0; first < count;) {
        int batch = count - first < (mlsize_t)capacity ? (int)(count - first) : capacity;
        for (int j = 0; j < batch; ++j) {
            mlsize_t           i = first + j;
            const osdl_sprite* s = &sprites[i];
            double             x = Double_flat_field(positions, i * 2);
            double             y = Double_flat_field(positions, i * 2 + 1);
            float              u = s->source.x / tw, u1 = (s->source.x + s->source.w) / tw;
            float              v = s->source.y / th, v1 = (s->source.y + s->source.h) / th;
            if (s->flip & SDL_FLIP_HORIZONTAL) {
                float tmp = u;
                u         = u1;
                u1        = tmp;
            }
            if (s->flip & SDL_FLIP_VERTICAL) {
                float tmp = v;
                v         = v1;
                v1        = tmp;
            }
            const float norm  = 1.0f / 255.0f;
            SDL_FColor  color = {s->color.r * norm, s->color.g * norm, s->color.b * norm,
                                 s->color.a * norm};
            SDL_Vertex* quad  = &vertices[j * 4];
            quad[0] = osdl_sprite_vertex(x + s->corners[0].x, y + s->corners[0].y, u, v, color);
            quad[1] = osdl_sprite_vertex(x + s->corners[1].x, y + s->corners[1].y, u1, v, color);
            quad[2] = osdl_sprite_vertex(x + s->corners[2].x, y + s->corners[2].y, u1, v1, color);
            quad[3] = osdl_sprite_vertex(x + s->corners[3].x, y + s->corners[3].y, u, v1, color);
        }
        osdl_check(SDL_RenderGeometry(r, t, vertices, batch * 4, indices, batch * 6),
                   "SDL_RenderGeometry");
        first += batch;
    }
}

CAMLprim value osdl_sprite_batch_draw(value renderer, value texture, value positions, value storage,
                                      value length) {
    SDL_Renderer* r = osdl_live(renderer);
    SDL_Texture*  t = osdl_texture_source(texture, renderer, r);

    mlsize_t count = osdl_nonnegative_int(length);
    if (count > Wosize_val(positions) / Double_wosize / 2 ||
        count > (size_t)Caml_ba_array_val(storage)->dim[0] / sizeof(osdl_sprite))
        caml_invalid_argument("The sprite count exceeds the batch capacity");
    if (!count) return Val_unit;

    const osdl_sprite* sprites  = Caml_ba_data_val(storage);
    const char*        driver   = SDL_GetRendererName(r);
    bool               software = driver && strcmp(driver, SDL_SOFTWARE_RENDERER) == 0;
    osdl_render_view   view     = software ? osdl_software_view(r) : osdl_unit_view;

    /* Validate the whole batch before any draw. The caller can edit the
     * positions or reuse the batch with a texture of a different size. */
    for (mlsize_t i = 0; i < count; ++i) {
        const osdl_sprite* s = &sprites[i];
        double             x = Double_flat_field(positions, i * 2);
        double             y = Double_flat_field(positions, i * 2 + 1);
        if (s->source.x > t->w - s->source.w || s->source.y > t->h - s->source.h)
            caml_invalid_argument("The sprite source rectangle is outside the texture");
        if (!osdl_fits_float(x) || !osdl_fits_float(y))
            caml_invalid_argument("Sprite positions must be finite C floats");
        for (int j = 0; j < 4; ++j) {
            if (!osdl_fits_float(x + s->corners[j].x) || !osdl_fits_float(y + s->corners[j].y))
                caml_invalid_argument("Transformed sprite corners must be finite C floats");
        }
        if (software) osdl_sprite_software_bounds(s, x, y, view);
    }

    if (software)
        osdl_sprite_batch_software(r, t, sprites, positions, count);
    else
        osdl_sprite_batch_geometry(r, t, sprites, positions, count);
    return Val_unit;
}

/* Triangle lists. */

_Static_assert(sizeof(SDL_FColor) == 4 * sizeof(float), "SDL_FColor must use packed floats");
_Static_assert(_Alignof(SDL_FColor) == _Alignof(float), "SDL_FColor must have float alignment");

typedef struct {
    SDL_Texture*  texture;
    const float*  xy;
    const float*  rgba;
    const float*  uv;
    const Uint32* indices;
    int           vertices;
    int           count;
} osdl_geometry;

static int osdl_geometry_count(value count) {
    int n = osdl_nonnegative_int(count);
    /* SDL uses signed byte offsets and can expand indices into vertices. */
    if (n > INT_MAX / (int)sizeof(SDL_Vertex)) caml_invalid_argument("Geometry count is too large");
    return n;
}

static const void* osdl_geometry_data(value buffer, int count, int components,
                                      const char* message) {
    if (count > Caml_ba_array_val(buffer)->dim[0] / components) caml_invalid_argument(message);
    return Caml_ba_data_val(buffer);
}

static void osdl_geometry_check_unit(const float* data, int count, const char* message) {
    for (int i = 0; i < count; ++i)
        if (!(data[i] >= 0.0f && data[i] <= 1.0f)) caml_invalid_argument(message);
}

static inline int osdl_geometry_vertex(const osdl_geometry* geometry, int i) {
    return geometry->indices ? (int)geometry->indices[i] : i;
}

static void osdl_geometry_software_bounds(SDL_Renderer* renderer, const osdl_geometry* geometry) {
    osdl_render_view view = osdl_software_view(renderer);
    int              w    = osdl_software_geometry_target_width(renderer);
    for (int i = 0; i < geometry->vertices; ++i)
        osdl_software_geometry_position(view, w, geometry->xy[2 * i], geometry->xy[2 * i + 1]);

    SDL_Texture* t = geometry->texture;
    if (!t) return;
    osdl_software_geometry_texture(t);
    for (int i = 0; i < geometry->count; i += 3) {
        int          a  = 2 * osdl_geometry_vertex(geometry, i);
        int          b  = 2 * osdl_geometry_vertex(geometry, i + 1);
        int          c  = 2 * osdl_geometry_vertex(geometry, i + 2);
        const float* xy = geometry->xy;
        double       dx =
            (double)SDL_max(xy[a], SDL_max(xy[b], xy[c])) - SDL_min(xy[a], SDL_min(xy[b], xy[c]));
        double dy = (double)SDL_max(xy[a + 1], SDL_max(xy[b + 1], xy[c + 1])) -
                    SDL_min(xy[a + 1], SDL_min(xy[b + 1], xy[c + 1]));
        int u = (int)(geometry->uv[c] * t->w);
        int v = (int)(geometry->uv[c + 1] * t->h);
        osdl_software_geometry_area(view, dx, dy, SDL_max(u, v));
    }
}

static void osdl_geometry_draw_software(SDL_Renderer* renderer, const osdl_geometry* geometry) {
    /* SDL can fold adjacent triangles into a rectangle. That path can ignore
     * the blend mode or change how the texture maps to the triangles. */
    for (int i = 0; i < geometry->count; i += 3) {
        SDL_Vertex triangle[3];
        for (int j = 0; j < 3; ++j) {
            int          v        = osdl_geometry_vertex(geometry, i + j);
            const float* xy       = geometry->xy + 2 * v;
            const float* rgba     = geometry->rgba + 4 * v;
            const float* uv       = geometry->uv ? geometry->uv + 2 * v : NULL;
            SDL_FPoint   position = {xy[0], xy[1]};
            SDL_FColor   color    = {rgba[0], rgba[1], rgba[2], rgba[3]};
            SDL_FPoint   texcoord = {uv ? uv[0] : 0.0f, uv ? uv[1] : 0.0f};
            triangle[j] = (SDL_Vertex){.position = position, .color = color, .tex_coord = texcoord};
        }
        if (geometry->texture) {
            /* SDL 3.2.0 does not clamp the last texel when all three
             * coordinates on one axis are one. Keep that edge in bounds. */
            const float last = 1.0f - FLT_EPSILON / 2.0f;
            if (triangle[0].tex_coord.x == 1 && triangle[1].tex_coord.x == 1 &&
                triangle[2].tex_coord.x == 1)
                for (int j = 0; j < 3; ++j)
                    triangle[j].tex_coord.x = last;
            if (triangle[0].tex_coord.y == 1 && triangle[1].tex_coord.y == 1 &&
                triangle[2].tex_coord.y == 1)
                for (int j = 0; j < 3; ++j)
                    triangle[j].tex_coord.y = last;
        }
        osdl_check(SDL_RenderGeometry(renderer, geometry->texture, triangle, 3, NULL, 0),
                   "SDL_RenderGeometry");
    }
}

CAMLprim value osdl_renderer_draw_geometry(value texture, value indices, value renderer,
                                           value positions, value colors, value vertex_count) {
    SDL_Renderer* r = osdl_live(renderer);
    osdl_geometry g = {0};
    if (Is_block(texture))
        g.texture = osdl_texture_source(Field(Some_val(texture), 0), renderer, r);

    g.vertices = osdl_geometry_count(vertex_count);
    g.xy   = osdl_geometry_data(positions, g.vertices, 2, "Geometry position buffer is too short");
    g.rgba = osdl_geometry_data(colors, g.vertices, 4, "Geometry color buffer is too short");
    if (g.texture)
        g.uv = osdl_geometry_data(Field(Some_val(texture), 1), g.vertices, 2,
                                  "Geometry texture coordinate buffer is too short");

    g.count = g.vertices;
    if (Is_block(indices)) {
        value pair = Some_val(indices);
        g.count    = osdl_geometry_count(Field(pair, 1));
        g.indices =
            osdl_geometry_data(Field(pair, 0), g.count, 1, "Geometry index buffer is too short");
    }
    if (g.count % 3 != 0)
        caml_invalid_argument("Geometry needs three vertices or indices per triangle");
    if (!g.count) return Val_unit;

    for (int i = 0; i < 2 * g.vertices; ++i)
        if (!isfinite(g.xy[i])) caml_invalid_argument("Geometry positions must be finite");
    osdl_geometry_check_unit(g.rgba, 4 * g.vertices, "Geometry colors must be between 0 and 1");
    if (g.uv)
        osdl_geometry_check_unit(g.uv, 2 * g.vertices,
                                 "Geometry texture coordinates must be between 0 and 1");
    if (g.indices)
        for (int i = 0; i < g.count; ++i)
            if (g.indices[i] >= (Uint32)g.vertices)
                caml_invalid_argument("Geometry index is outside the vertex range");

    const char* driver = SDL_GetRendererName(r);
    if (!driver) osdl_fail("SDL_GetRendererName");
    if (strcmp(driver, SDL_SOFTWARE_RENDERER) == 0) {
        osdl_geometry_software_bounds(r, &g);
        osdl_geometry_draw_software(r, &g);
    } else {
        osdl_check(SDL_RenderGeometryRaw(r, g.texture, g.xy, 2 * sizeof(float),
                                         (const SDL_FColor*)g.rgba, sizeof(SDL_FColor), g.uv,
                                         2 * sizeof(float), g.vertices, g.indices,
                                         g.indices ? g.count : 0, sizeof(Uint32)),
                   "SDL_RenderGeometryRaw");
    }
    return Val_unit;
}

CAMLprim value osdl_renderer_draw_geometry_byte(value* argv, int argc) {
    (void)argc;
    return osdl_renderer_draw_geometry(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/* Keyboard. */

CAMLprim value osdl_scancode_escape(value unit) {
    (void)unit;
    return Val_int(SDL_SCANCODE_ESCAPE);
}

CAMLprim value osdl_scancode_of_name(value name) {
    osdl_require_thread(main_thread);
    SDL_Scancode code = SDL_GetScancodeFromName(osdl_cstring(name));
    return code == SDL_SCANCODE_UNKNOWN ? Val_none : caml_alloc_some(Val_int(code));
}

CAMLprim value osdl_scancode_name(value scancode) {
    osdl_require_thread(main_thread);
    return caml_copy_string(SDL_GetScancodeName(Int_val(scancode)));
}

CAMLprim value osdl_keycode_name(value keycode) {
    osdl_require_thread(main_thread);
    return caml_copy_string(SDL_GetKeyName((Uint32)Int32_val(keycode)));
}

CAMLprim value osdl_keymod_has(value modifiers, value flag) {
    static const SDL_Keymod bits[] = {SDL_KMOD_SHIFT, SDL_KMOD_CTRL, SDL_KMOD_ALT,
                                      SDL_KMOD_GUI,   SDL_KMOD_CAPS, SDL_KMOD_NUM};
    return Val_bool((Int_val(modifiers) & bits[Int_val(flag)]) != 0);
}

CAMLprim value osdl_keyboard_pressed(value context, value scancode) {
    osdl_live(context);
    int         count;
    const bool* keys = SDL_GetKeyboardState(&count);
    int         i    = Int_val(scancode);
    return Val_bool(keys && i >= 0 && i < count && keys[i]);
}

OSDL_ACTION(osdl_keyboard_start_text_input, SDL_StartTextInput)
OSDL_ACTION(osdl_keyboard_stop_text_input, SDL_StopTextInput)

/* Mouse state and movement. Button conversions are shared with events. */

static void osdl_require_mouse_context(value context) {
    osdl_require_subsystem(context, SDL_INIT_VIDEO, "Start SDL with Video to use the mouse");
}

typedef SDL_MouseButtonFlags(SDLCALL* osdl_mouse_query)(float*, float*);

static value osdl_mouse_read_state(value context, osdl_mouse_query query) {
    CAMLparam1(context);
    CAMLlocal3(x_value, y_value, buttons);

    osdl_require_mouse_context(context);

    float                x, y;
    SDL_MouseButtonFlags mask = query(&x, &y);

    /* Mouse.state and Mouse.relative_state store two coordinates, then buttons. */
    x_value = caml_copy_double(x);
    y_value = caml_copy_double(y);
    buttons = caml_copy_int32((int32_t)mask);
    CAMLreturn(caml_alloc_3(0, x_value, y_value, buttons));
}

CAMLprim value osdl_mouse_state(value context) {
    return osdl_mouse_read_state(context, SDL_GetMouseState);
}

CAMLprim value osdl_mouse_global_state(value context) {
    return osdl_mouse_read_state(context, SDL_GetGlobalMouseState);
}

CAMLprim value osdl_mouse_relative_state(value context) {
    return osdl_mouse_read_state(context, SDL_GetRelativeMouseState);
}

CAMLprim value osdl_mouse_set_relative_mode(value window, value enabled) {
    osdl_check(SDL_SetWindowRelativeMouseMode(osdl_live(window), Bool_val(enabled)),
               "SDL_SetWindowRelativeMouseMode");
    return Val_unit;
}

CAMLprim value osdl_mouse_capture(value context, value enabled) {
    osdl_require_mouse_context(context);

    osdl_check(SDL_CaptureMouse(Bool_val(enabled)), "SDL_CaptureMouse");
    return Val_unit;
}

CAMLprim value osdl_mouse_warp_in_window(value window, value x, value y) {
    SDL_Window* w  = osdl_live(window);
    float       px = osdl_float(Double_val(x)), py = osdl_float(Double_val(y));
    /* Some video drivers round and cast the coordinates to int. */
    if ((double)px < INT_MIN || (double)px > INT_MAX || (double)py < INT_MIN ||
        (double)py > INT_MAX)
        caml_invalid_argument("Mouse warp coordinates are outside the C int range");

    SDL_WarpMouseInWindow(w, px, py);
    return Val_unit;
}

/* Cursors are context children, independent of windows and source surfaces. */

CAMLprim value osdl_cursor_create_color(value surface, value hot_x, value hot_y) {
    CAMLparam3(surface, hot_x, hot_y);
    CAMLlocal1(handle);

    handle = osdl_new_handle(osdl_parent(surface));

    SDL_Surface* s = osdl_unlocked_surface(surface);
    osdl_require_mouse_context(osdl_parent(surface));
    int x = osdl_int(hot_x), y = osdl_int(hot_y);
    if (x < 0 || x >= s->w || y < 0 || y >= s->h)
        caml_invalid_argument("The cursor hot spot must lie inside the surface");

    SDL_Cursor* cursor = SDL_CreateColorCursor(s, x, y);
    CAMLreturn(osdl_publish(handle, cursor, "SDL_CreateColorCursor"));
}

CAMLprim value osdl_cursor_create_system(value context, value system) {
    CAMLparam2(context, system);
    CAMLlocal1(handle);

    /* Mouse.Cursor.system constructor order. */
    static const SDL_SystemCursor styles[] = {
        SDL_SYSTEM_CURSOR_DEFAULT,     SDL_SYSTEM_CURSOR_TEXT,        SDL_SYSTEM_CURSOR_WAIT,
        SDL_SYSTEM_CURSOR_CROSSHAIR,   SDL_SYSTEM_CURSOR_PROGRESS,    SDL_SYSTEM_CURSOR_NWSE_RESIZE,
        SDL_SYSTEM_CURSOR_NESW_RESIZE, SDL_SYSTEM_CURSOR_EW_RESIZE,   SDL_SYSTEM_CURSOR_NS_RESIZE,
        SDL_SYSTEM_CURSOR_MOVE,        SDL_SYSTEM_CURSOR_NOT_ALLOWED, SDL_SYSTEM_CURSOR_POINTER,
        SDL_SYSTEM_CURSOR_NW_RESIZE,   SDL_SYSTEM_CURSOR_N_RESIZE,    SDL_SYSTEM_CURSOR_NE_RESIZE,
        SDL_SYSTEM_CURSOR_E_RESIZE,    SDL_SYSTEM_CURSOR_SE_RESIZE,   SDL_SYSTEM_CURSOR_S_RESIZE,
        SDL_SYSTEM_CURSOR_SW_RESIZE,   SDL_SYSTEM_CURSOR_W_RESIZE,
    };

    handle = osdl_new_handle(context);
    osdl_require_mouse_context(context);

    SDL_Cursor* cursor = SDL_CreateSystemCursor(styles[Int_val(system)]);
    CAMLreturn(osdl_publish(handle, cursor, "SDL_CreateSystemCursor"));
}

static SDL_Cursor* osdl_default_cursor(void) {
    SDL_Cursor* cursor = SDL_GetDefaultCursor();
    if (!cursor) osdl_raise_error("SDL_GetDefaultCursor: No default cursor is available");
    return cursor;
}

CAMLprim value osdl_cursor_set(value handle) {
    SDL_Cursor* cursor = osdl_live(handle);
    /* SDL needs a default to switch back to when this cursor is destroyed. */
    (void)osdl_default_cursor();

    osdl_check(SDL_SetCursor(cursor), "SDL_SetCursor");
    return Val_unit;
}

CAMLprim value osdl_cursor_reset(value context) {
    osdl_require_mouse_context(context);

    osdl_check(SDL_SetCursor(osdl_default_cursor()), "SDL_SetCursor");
    return Val_unit;
}

OSDL_DESTROY(osdl_cursor_destroy, SDL_Cursor, SDL_DestroyCursor)

CAMLprim value osdl_cursor_show(value context) {
    osdl_require_mouse_context(context);

    osdl_check(SDL_ShowCursor(), "SDL_ShowCursor");
    return Val_unit;
}

CAMLprim value osdl_cursor_hide(value context) {
    osdl_require_mouse_context(context);

    osdl_check(SDL_HideCursor(), "SDL_HideCursor");
    return Val_unit;
}

CAMLprim value osdl_cursor_visible(value context) {
    osdl_require_mouse_context(context);
    return Val_bool(SDL_CursorVisible());
}

/* Gamepad discovery and handles. State queries share the event tables. */

static void osdl_require_gamepad_context(value context) {
    osdl_require_subsystem(context, SDL_INIT_GAMEPAD, "Start SDL with Gamepad to use gamepads");
}

CAMLprim value osdl_gamepad_list(value context, value snapshot) {
    CAMLparam2(context, snapshot);

    osdl_require_gamepad_context(context);

    int             count;
    SDL_JoystickID* ids = SDL_GetGamepads(&count);
    osdl_publish(snapshot, ids, "SDL_GetGamepads");
    CAMLreturn(osdl_id_list(ids, count));
}

CAMLprim value osdl_gamepad_name_for_id(value context, value id) {
    osdl_require_gamepad_context(context);

    const char* name = SDL_GetGamepadNameForID((SDL_JoystickID)Int32_val(id));
    if (!name) osdl_fail("SDL_GetGamepadNameForID");
    return caml_copy_string(name);
}

CAMLprim value osdl_gamepad_open(value context, value id) {
    CAMLparam2(context, id);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    CAMLreturn(osdl_publish(handle, SDL_OpenGamepad((Uint32)Int32_val(id)), "SDL_OpenGamepad"));
}

OSDL_DESTROY(osdl_gamepad_close, SDL_Gamepad, SDL_CloseGamepad)

CAMLprim value osdl_gamepad_connected(value gamepad) {
    return Val_bool(SDL_GamepadConnected(osdl_live(gamepad)));
}

CAMLprim value osdl_gamepad_id(value gamepad) {
    SDL_JoystickID id = SDL_GetGamepadID(osdl_live(gamepad));
    if (!id) osdl_fail("SDL_GetGamepadID");
    return caml_copy_int32((int32_t)id);
}

CAMLprim value osdl_gamepad_name(value gamepad) {
    const char* name = SDL_GetGamepadName(osdl_live(gamepad));
    if (!name) osdl_fail("SDL_GetGamepadName");
    return caml_copy_string(name);
}

/* Audio devices and queued streams. */

static void osdl_require_audio_context(value context) {
    osdl_require_subsystem(context, SDL_INIT_AUDIO, "Start SDL with Audio to use audio devices");
}

static value osdl_audio_devices(value context, value snapshot, bool recording) {
    CAMLparam2(context, snapshot);

    osdl_require_audio_context(context);

    int                count;
    SDL_AudioDeviceID* ids =
        recording ? SDL_GetAudioRecordingDevices(&count) : SDL_GetAudioPlaybackDevices(&count);
    osdl_publish(snapshot, ids,
                 recording ? "SDL_GetAudioRecordingDevices" : "SDL_GetAudioPlaybackDevices");
    CAMLreturn(osdl_id_list(ids, count));
}

CAMLprim value osdl_audio_playback_devices(value context, value snapshot) {
    return osdl_audio_devices(context, snapshot, false);
}

CAMLprim value osdl_audio_recording_devices(value context, value snapshot) {
    return osdl_audio_devices(context, snapshot, true);
}

CAMLprim value osdl_audio_device_name(value context, value id) {
    osdl_require_audio_context(context);

    const char* name = SDL_GetAudioDeviceName((SDL_AudioDeviceID)Int32_val(id));
    if (!name) osdl_fail("SDL_GetAudioDeviceName");
    return caml_copy_string(name);
}

static value osdl_audio_open(value device, value context, value spec, bool recording) {
    CAMLparam3(device, context, spec);
    CAMLlocal1(handle);

    osdl_require_audio_context(context);
    SDL_AudioSpec     format = osdl_audio_spec(spec);
    SDL_AudioDeviceID id     = osdl_audio_device_or_default(
        device, recording ? SDL_AUDIO_DEVICE_DEFAULT_RECORDING : SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK);

    /* Remember the output sample alignment without a stream query on each read. */
    handle = recording
               ? osdl_new_attached_handle(context, Val_int(SDL_AUDIO_BYTESIZE(format.format)))
               : osdl_new_handle(context);

    SDL_AudioStream* stream = SDL_OpenAudioDeviceStream(id, &format, NULL, NULL);
    CAMLreturn(osdl_publish(handle, stream, "SDL_OpenAudioDeviceStream"));
}

CAMLprim value osdl_audio_open_playback(value device, value context, value spec) {
    return osdl_audio_open(device, context, spec, false);
}

CAMLprim value osdl_audio_open_recording(value device, value context, value spec) {
    return osdl_audio_open(device, context, spec, true);
}

OSDL_DESTROY(osdl_audio_close, SDL_AudioStream, SDL_DestroyAudioStream)
OSDL_ACTION(osdl_audio_pause, SDL_PauseAudioStreamDevice)
OSDL_ACTION(osdl_audio_resume, SDL_ResumeAudioStreamDevice)
OSDL_ACTION(osdl_audio_clear, SDL_ClearAudioStream)
OSDL_ACTION(osdl_audio_flush, SDL_FlushAudioStream)

CAMLprim value osdl_audio_queue(value stream, value buffer) {
    SDL_AudioStream* s    = osdl_live(stream);
    int              size = osdl_audio_buffer_length(buffer);
    if (size)
        osdl_check(SDL_PutAudioStreamData(s, Caml_ba_data_val(buffer), size),
                   "SDL_PutAudioStreamData");
    return Val_unit;
}

CAMLprim value osdl_audio_queued_bytes(value stream) {
    int size = SDL_GetAudioStreamQueued(osdl_live(stream));
    if (size < 0) osdl_fail("SDL_GetAudioStreamQueued");
    return osdl_val_int(size);
}

CAMLprim value osdl_audio_available_bytes(value stream) {
    int size = SDL_GetAudioStreamAvailable(osdl_live(stream));
    if (size < 0) osdl_fail("SDL_GetAudioStreamAvailable");
    return osdl_val_int(size);
}

CAMLprim value osdl_audio_read(value stream, value buffer) {
    SDL_AudioStream* s    = osdl_live(stream);
    int              size = osdl_audio_buffer_length(buffer);
    if (!size) return Val_int(0);

    void* dst = Caml_ba_data_val(buffer);
    if ((uintptr_t)dst % Int_val(osdl_attachment(stream)))
        caml_invalid_argument("SDL recording buffer must align to its sample size");

    int bytes_read = SDL_GetAudioStreamData(s, dst, size);
    if (bytes_read < 0) osdl_fail("SDL_GetAudioStreamData");
    return osdl_val_int(bytes_read);
}

/* Timers. */

CAMLprim int64_t osdl_ticks_ns(value unit) {
    (void)unit;
    return (int64_t)SDL_GetTicksNS();
}

CAMLprim value osdl_ticks_ns_byte(value unit) {
    return caml_copy_int64(osdl_ticks_ns(unit));
}

CAMLprim int64_t osdl_ticks_ms(value unit) {
    (void)unit;
    return (int64_t)SDL_GetTicks();
}

CAMLprim value osdl_ticks_ms_byte(value unit) {
    return caml_copy_int64(osdl_ticks_ms(unit));
}

CAMLprim value osdl_delay_ns(int64_t ns) {
    if (ns < 0) caml_invalid_argument("Sdl3.Timer.delay_ns: duration must not be negative");

    caml_release_runtime_system();
    SDL_DelayNS((Uint64)ns);
    caml_acquire_runtime_system();

    return Val_unit;
}

CAMLprim value osdl_delay_ns_byte(value ns) {
    return osdl_delay_ns(Int64_val(ns));
}
