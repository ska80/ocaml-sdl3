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

static value osdl_display_rect(value context, value id, bool usable) {
    osdl_require_display_context(context);

    SDL_DisplayID display = (SDL_DisplayID)Int32_val(id);
    SDL_Rect      rect;
    if (usable)
        osdl_check(SDL_GetDisplayUsableBounds(display, &rect), "SDL_GetDisplayUsableBounds");
    else
        osdl_check(SDL_GetDisplayBounds(display, &rect), "SDL_GetDisplayBounds");
    return caml_alloc_4(0, osdl_val_int(rect.x), osdl_val_int(rect.y), osdl_val_int(rect.w),
                        osdl_val_int(rect.h));
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
