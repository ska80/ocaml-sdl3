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

CAMLprim value osdl_window_set_title(value window, value title) {
    osdl_check(SDL_SetWindowTitle(osdl_live(window), osdl_cstring(title)), "SDL_SetWindowTitle");
    return Val_unit;
}

CAMLprim value osdl_window_set_size(value window, value w, value h) {
    osdl_check(SDL_SetWindowSize(osdl_live(window), osdl_positive_int(w), osdl_positive_int(h)),
               "SDL_SetWindowSize");
    return Val_unit;
}

CAMLprim value osdl_window_set_fullscreen(value window, value fullscreen) {
    osdl_check(SDL_SetWindowFullscreen(osdl_live(window), Bool_val(fullscreen)),
               "SDL_SetWindowFullscreen");
    return Val_unit;
}

OSDL_ACTION(osdl_window_show, SDL_ShowWindow)
OSDL_ACTION(osdl_window_hide, SDL_HideWindow)

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

static SDL_BlendMode osdl_blend_mode(value mode) {
    static const SDL_BlendMode modes[] = {SDL_BLENDMODE_NONE, SDL_BLENDMODE_BLEND,
                                          SDL_BLENDMODE_ADD, SDL_BLENDMODE_MOD, SDL_BLENDMODE_MUL};
    return modes[Int_val(mode)];
}

/* Surfaces. */

CAMLprim value osdl_surface_create(value format, value context, value w, value h) {
    CAMLparam4(format, context, w, h);
    CAMLlocal1(handle);

    static const SDL_PixelFormat formats[] = {SDL_PIXELFORMAT_RGBA32, SDL_PIXELFORMAT_BGRA32,
                                              SDL_PIXELFORMAT_RGB24};

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_PixelFormat pixel_format =
        Is_long(format) ? SDL_PIXELFORMAT_RGBA32 : formats[Int_val(Some_val(format))];
    SDL_Surface* surface =
        SDL_CreateSurface(osdl_positive_int(w), osdl_positive_int(h), pixel_format);
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
    osdl_check(SDL_SaveBMP(osdl_live(surface), osdl_cstring(path)), "SDL_SaveBMP");
    return Val_unit;
}

OSDL_DESTROY(osdl_surface_destroy, SDL_Surface, SDL_DestroySurface)

CAMLprim value osdl_surface_size(value surface) {
    SDL_Surface* s = osdl_live(surface);
    return osdl_int_pair(s->w, s->h);
}

CAMLprim value osdl_surface_fill(value rect, value surface, value color) {
    SDL_Surface*    s = osdl_live(surface);
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

CAMLprim value osdl_surface_read_pixel(value surface, value x, value y) {
    SDL_Color c;
    osdl_check(
        SDL_ReadSurfacePixel(osdl_live(surface), osdl_int(x), osdl_int(y), &c.r, &c.g, &c.b, &c.a),
        "SDL_ReadSurfacePixel");
    return caml_alloc_4(0, Val_int(c.r), Val_int(c.g), Val_int(c.b), Val_int(c.a));
}

/* Renderers. */

static SDL_Texture* osdl_texture_for_renderer(value texture, value renderer) {
    SDL_Texture* t = osdl_live(texture);
    if (osdl_parent(texture) != renderer)
        caml_invalid_argument("Use the renderer that owns the texture");
    return t;
}

CAMLprim value osdl_renderer_create(value driver, value window) {
    CAMLparam2(driver, window);
    CAMLlocal1(handle);

    handle = osdl_new_handle(window);

    const char*   name     = Is_long(driver) ? NULL : osdl_cstring(Some_val(driver));
    SDL_Renderer* renderer = SDL_CreateRenderer(osdl_live(window), name);
    CAMLreturn(osdl_publish(handle, renderer, "SDL_CreateRenderer"));
}

CAMLprim value osdl_renderer_create_software(value surface) {
    CAMLparam1(surface);
    CAMLlocal1(handle);

    handle = osdl_new_handle(surface);

    SDL_Renderer* renderer = SDL_CreateSoftwareRenderer(osdl_live(surface));
    CAMLreturn(osdl_publish(handle, renderer, "SDL_CreateSoftwareRenderer"));
}

OSDL_DESTROY(osdl_renderer_destroy, SDL_Renderer, SDL_DestroyRenderer)

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

CAMLprim value osdl_renderer_set_target(value renderer, value target) {
    SDL_Renderer* r = osdl_live(renderer);
    SDL_Texture* t = Is_long(target) ? NULL : osdl_texture_for_renderer(Some_val(target), renderer);

    osdl_check(SDL_SetRenderTarget(r, t), "SDL_SetRenderTarget");
    return Val_unit;
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

    osdl_check(SDL_SetRenderLogicalPresentation(osdl_live(renderer), w, h, mode),
               "SDL_SetRenderLogicalPresentation");
    return Val_unit;
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

    SDL_Texture* texture = SDL_CreateTextureFromSurface(osdl_live(renderer), osdl_live(surface));
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

CAMLprim value osdl_texture_update(value rect, value texture, value buffer, value pitch) {
    SDL_Texture* t       = osdl_live(texture);
    bool         partial = Is_block(rect);
    SDL_Rect     area    = partial ? osdl_rect(Some_val(rect)) : (SDL_Rect){0, 0, t->w, t->h};
    if (partial && (area.x < 0 || area.y < 0 || area.w <= 0 || area.h <= 0 ||
                    area.x > t->w - area.w || area.y > t->h - area.h))
        caml_invalid_argument("SDL update rectangle must be inside the texture");

    int stride = osdl_positive_int(pitch);
    if (stride % 4 || stride / 4 < area.w)
        caml_invalid_argument("SDL RGBA pitch must be a multiple of four and cover a row");
    if (area.h > INT_MAX / stride) caml_invalid_argument("SDL texture upload is too large");
    if (Caml_ba_array_val(buffer)->dim[0] < stride * area.h)
        caml_invalid_argument("SDL texture upload buffer is too small");

    osdl_check(SDL_UpdateTexture(t, partial ? &area : NULL, Caml_ba_data_val(buffer), stride),
               "SDL_UpdateTexture");
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
    static const SDL_ScaleMode modes[] = {SDL_SCALEMODE_NEAREST, SDL_SCALEMODE_LINEAR};
    osdl_check(SDL_SetTextureScaleMode(osdl_live(texture), modes[Int_val(mode)]),
               "SDL_SetTextureScaleMode");
    return Val_unit;
}

CAMLprim value osdl_texture_set_blend_mode(value texture, value mode) {
    osdl_check(SDL_SetTextureBlendMode(osdl_live(texture), osdl_blend_mode(mode)),
               "SDL_SetTextureBlendMode");
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

CAMLprim value osdl_texture_draw_rotated(value src, value dst, value flip, value renderer,
                                         value texture, value angle) {
    static const SDL_FlipMode modes[] = {SDL_FLIP_NONE, SDL_FLIP_HORIZONTAL, SDL_FLIP_VERTICAL,
                                         SDL_FLIP_HORIZONTAL | SDL_FLIP_VERTICAL};

    SDL_Renderer*    r = osdl_live(renderer);
    SDL_Texture*     t = osdl_texture_source(texture, renderer, r);
    SDL_FRect        s, d;
    const SDL_FRect* source  = osdl_frect_option(src, &s);
    const SDL_FRect* dest    = osdl_frect_option(dst, &d);
    SDL_FlipMode     mode    = Is_long(flip) ? SDL_FLIP_NONE : modes[Int_val(Some_val(flip))];
    double           degrees = Double_val(angle);
    if (!isfinite(degrees)) caml_invalid_argument("SDL rotation must be finite");

    osdl_check(SDL_RenderTextureRotated(r, t, source, dest, degrees, NULL, mode),
               "SDL_RenderTextureRotated");
    return Val_unit;
}

CAMLprim value osdl_texture_draw_rotated_byte(value* argv, int argc) {
    (void)argc;
    return osdl_texture_draw_rotated(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/* Keyboard and mouse. */

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

CAMLprim value osdl_mouse_set_relative_mode(value window, value enabled) {
    osdl_check(SDL_SetWindowRelativeMouseMode(osdl_live(window), Bool_val(enabled)),
               "SDL_SetWindowRelativeMouseMode");
    return Val_unit;
}

/* Gamepads. */

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

CAMLprim value osdl_gamepad_axis(value gamepad, value axis) {
    static const SDL_GamepadAxis axes[] = {
        SDL_GAMEPAD_AXIS_LEFTX,  SDL_GAMEPAD_AXIS_LEFTY,        SDL_GAMEPAD_AXIS_RIGHTX,
        SDL_GAMEPAD_AXIS_RIGHTY, SDL_GAMEPAD_AXIS_LEFT_TRIGGER, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER};
    return Val_int(SDL_GetGamepadAxis(osdl_live(gamepad), axes[Int_val(axis)]));
}

CAMLprim value osdl_gamepad_button(value gamepad, value button) {
    static const SDL_GamepadButton buttons[] = {
        SDL_GAMEPAD_BUTTON_SOUTH,          SDL_GAMEPAD_BUTTON_EAST,
        SDL_GAMEPAD_BUTTON_WEST,           SDL_GAMEPAD_BUTTON_NORTH,
        SDL_GAMEPAD_BUTTON_BACK,           SDL_GAMEPAD_BUTTON_GUIDE,
        SDL_GAMEPAD_BUTTON_START,          SDL_GAMEPAD_BUTTON_LEFT_STICK,
        SDL_GAMEPAD_BUTTON_RIGHT_STICK,    SDL_GAMEPAD_BUTTON_LEFT_SHOULDER,
        SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER, SDL_GAMEPAD_BUTTON_DPAD_UP,
        SDL_GAMEPAD_BUTTON_DPAD_DOWN,      SDL_GAMEPAD_BUTTON_DPAD_LEFT,
        SDL_GAMEPAD_BUTTON_DPAD_RIGHT};
    return Val_bool(SDL_GetGamepadButton(osdl_live(gamepad), buttons[Int_val(button)]));
}

/* Queued audio. */

CAMLprim value osdl_audio_open_playback(value context, value spec) {
    CAMLparam2(context, spec);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_AudioSpec    format = osdl_audio_spec(spec);
    SDL_AudioStream* stream =
        SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &format, NULL, NULL);
    CAMLreturn(osdl_publish(handle, stream, "SDL_OpenAudioDeviceStream"));
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
