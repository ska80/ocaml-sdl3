#include "sdl3_stubs.h"

#include <SDL3_ttf/SDL_ttf.h>

/* SDL_ttf context. */

static char ttf_initialized;

CAMLprim value osdl_ttf_version(value unit) {
    (void)unit;
    return osdl_version_value(TTF_Version());
}

CAMLprim value osdl_ttf_init(value sdl) {
    CAMLparam1(sdl);
    CAMLlocal1(context);

    context = osdl_new_handle(sdl);
    osdl_live(sdl);

    osdl_check(TTF_Init(), "TTF_Init");
    CAMLreturn(osdl_publish(context, &ttf_initialized, "TTF_Init"));
}

CAMLprim value osdl_ttf_quit(value context) {
    if (osdl_take(context)) TTF_Quit();
    return Val_unit;
}

/* Fonts and metrics. */

static float font_size(value ptsize) {
    float size = osdl_float(Double_val(ptsize));
    if (size <= 0) caml_invalid_argument("Font size must be positive");
    return size;
}

CAMLprim value osdl_ttf_font_open(value context, value path, value ptsize) {
    CAMLparam3(context, path, ptsize);
    CAMLlocal1(handle);

    handle = osdl_new_attached_handle(context, Val_unit);
    osdl_live(context);

    TTF_Font* font = TTF_OpenFont(osdl_cstring(path), font_size(ptsize));
    CAMLreturn(osdl_publish(handle, font, "TTF_OpenFont"));
}

CAMLprim value osdl_ttf_font_open_io(value context, value stream, value ptsize) {
    CAMLparam3(context, stream, ptsize);
    CAMLlocal1(handle);

    osdl_live(context);
    SDL_IOStream* io   = osdl_unborrowed_io(stream);
    float         size = font_size(ptsize);
    handle             = osdl_new_attached_handle(context, stream);

    TTF_Font* font = TTF_OpenFontIO(io, false, size);
    osdl_publish(handle, font, "TTF_OpenFontIO");
    ++osdl_cell_val(stream)->children;
    CAMLreturn(handle);
}

CAMLprim value osdl_ttf_font_close(value font) {
    TTF_Font* f = osdl_take(font);
    if (f) {
        TTF_CloseFont(f);
        value stream = osdl_attachment(font);
        if (Is_block(stream)) {
            --osdl_cell_val(stream)->children;
            osdl_forget_attachment(font);
        }
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_font_set_size(value font, value ptsize) {
    osdl_check(TTF_SetFontSize(osdl_live(font), font_size(ptsize)), "TTF_SetFontSize");
    return Val_unit;
}

CAMLprim value osdl_ttf_font_height(value font) {
    return osdl_val_int(TTF_GetFontHeight(osdl_live(font)));
}

CAMLprim value osdl_ttf_font_ascent(value font) {
    return osdl_val_int(TTF_GetFontAscent(osdl_live(font)));
}

CAMLprim value osdl_ttf_font_descent(value font) {
    return osdl_val_int(TTF_GetFontDescent(osdl_live(font)));
}

CAMLprim value osdl_ttf_font_line_skip(value font) {
    return osdl_val_int(TTF_GetFontLineSkip(osdl_live(font)));
}

CAMLprim value osdl_ttf_font_has_glyph(value font, value ch) {
    return Val_bool(TTF_FontHasGlyph(osdl_live(font), (Uint32)Int_val(ch)));
}

/* Text measurement and rendering. */

CAMLprim value osdl_ttf_font_measure(value wrap_width, value font, value text) {
    TTF_Font*   f      = osdl_live(font);
    const char* s      = osdl_cstring(text);
    size_t      length = caml_string_length(text);

    int w, h;
    if (Is_long(wrap_width))
        osdl_check(TTF_GetStringSize(f, s, length, &w, &h), "TTF_GetStringSize");
    else
        osdl_check(TTF_GetStringSizeWrapped(f, s, length,
                                            osdl_nonnegative_int(Some_val(wrap_width)), &w, &h),
                   "TTF_GetStringSizeWrapped");
    return osdl_int_pair(w, h);
}

CAMLprim value osdl_ttf_font_render(value mode, value wrap_width, value font, value text,
                                    value color) {
    CAMLparam5(mode, wrap_width, font, text, color);
    CAMLlocal1(handle);

    /* A rendered surface depends on SDL, not on SDL_ttf or the font. */
    handle = osdl_new_handle(osdl_parent(osdl_parent(font)));

    TTF_Font*   f      = osdl_live(font);
    bool        solid  = Is_block(mode) && Int_val(Some_val(mode)) == 0;
    const char* s      = osdl_cstring(text);
    size_t      length = caml_string_length(text);
    SDL_Color   rgba   = osdl_color(color);

    if (Is_long(wrap_width)) {
        if (solid)
            CAMLreturn(osdl_publish(handle, TTF_RenderText_Solid(f, s, length, rgba),
                                    "TTF_RenderText_Solid"));
        CAMLreturn(osdl_publish(handle, TTF_RenderText_Blended(f, s, length, rgba),
                                "TTF_RenderText_Blended"));
    }

    int width = osdl_nonnegative_int(Some_val(wrap_width));
    if (solid)
        CAMLreturn(osdl_publish(handle, TTF_RenderText_Solid_Wrapped(f, s, length, rgba, width),
                                "TTF_RenderText_Solid_Wrapped"));
    CAMLreturn(osdl_publish(handle, TTF_RenderText_Blended_Wrapped(f, s, length, rgba, width),
                            "TTF_RenderText_Blended_Wrapped"));
}

/* Text engines are children of the TTF context. A renderer engine also
 * keeps its renderer open until the engine releases its textures. */

CAMLprim value osdl_ttf_engine_create_surface(value context) {
    CAMLparam1(context);
    CAMLlocal1(handle);

    handle = osdl_new_attached_handle(context, Val_unit);
    osdl_live(context);

    TTF_TextEngine* engine = TTF_CreateSurfaceTextEngine();
    CAMLreturn(osdl_publish(handle, engine, "TTF_CreateSurfaceTextEngine"));
}

CAMLprim value osdl_ttf_engine_create_renderer(value context, value renderer) {
    CAMLparam2(context, renderer);
    CAMLlocal1(handle);

    handle = osdl_new_attached_handle(context, renderer);
    osdl_live(context);
    SDL_Renderer* r = osdl_live(renderer);

    TTF_TextEngine* engine = TTF_CreateRendererTextEngine(r);
    osdl_publish(handle, engine, "TTF_CreateRendererTextEngine");
    ++osdl_cell_val(renderer)->children;
    CAMLreturn(handle);
}

CAMLprim value osdl_ttf_engine_destroy(value engine) {
    TTF_TextEngine* ptr = osdl_take(engine);
    if (!ptr) return Val_unit;

    value renderer = osdl_attachment(engine);
    if (renderer == Val_unit) {
        TTF_DestroySurfaceTextEngine(ptr);
    } else {
        TTF_DestroyRendererTextEngine(ptr);
        --osdl_cell_val(renderer)->children;
        osdl_forget_attachment(engine);
    }
    return Val_unit;
}

/* Text belongs to its engine and retains the font as a second dependency. */

static size_t ttf_text_length(value string) {
    size_t length = caml_string_length(string);
    if (length > INT_MAX) caml_invalid_argument("SDL_ttf text has too many bytes");
    return length;
}

CAMLprim value osdl_ttf_text_create(value engine, value font, value string) {
    CAMLparam3(engine, font, string);
    CAMLlocal1(handle);

    handle                 = osdl_new_attached_handle(engine, font);
    TTF_TextEngine* e      = osdl_live(engine);
    TTF_Font*       f      = osdl_live(font);
    size_t          length = ttf_text_length(string);
    const char*     s      = osdl_cstring(string);

    TTF_Text* text = TTF_CreateText(e, f, s, length);
    osdl_publish(handle, text, "TTF_CreateText");
    ++osdl_cell_val(font)->children;
    CAMLreturn(handle);
}

CAMLprim value osdl_ttf_text_destroy(value text) {
    TTF_Text* ptr = osdl_take(text);
    if (ptr) {
        TTF_DestroyText(ptr);
        --osdl_cell_val(osdl_attachment(text))->children;
        osdl_forget_attachment(text);
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_text_set_string(value text, value string) {
    TTF_Text*   ptr    = osdl_live(text);
    size_t      length = ttf_text_length(string);
    const char* s      = osdl_cstring(string);

    osdl_check(TTF_SetTextString(ptr, s, length), "TTF_SetTextString");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_set_color(value text, value color) {
    TTF_Text* ptr  = osdl_live(text);
    SDL_Color rgba = osdl_color(color);

    osdl_check(TTF_SetTextColor(ptr, rgba.r, rgba.g, rgba.b, rgba.a), "TTF_SetTextColor");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_set_wrap_width(value text, value width) {
    TTF_Text* ptr = osdl_live(text);
    int       w   = osdl_nonnegative_int(width);

    osdl_check(TTF_SetTextWrapWidth(ptr, w), "TTF_SetTextWrapWidth");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_size(value text) {
    int w, h;
    osdl_check(TTF_GetTextSize(osdl_live(text), &w, &h), "TTF_GetTextSize");
    return osdl_int_pair(w, h);
}

OSDL_ACTION(osdl_ttf_text_update, TTF_UpdateText)

CAMLprim value osdl_ttf_text_draw_surface(value text, value surface, value x, value y) {
    TTF_Text*    ptr = osdl_live(text);
    SDL_Surface* s   = osdl_unlocked_surface(surface);
    int          dx  = osdl_int(x);
    int          dy  = osdl_int(y);
    if (dx >= s->w || dy >= s->h) return Val_unit;

    /* The surface engine adds the origin to the glyph rectangles in C ints. */
    int w, h;
    osdl_check(TTF_GetTextSize(ptr, &w, &h), "TTF_GetTextSize");
    Sint64 right  = (Sint64)dx + w;
    Sint64 bottom = (Sint64)dy + h;
    if (right <= 0 || bottom <= 0) return Val_unit;
    if (right > INT_MAX || bottom > INT_MAX)
        caml_invalid_argument("SDL text bounds are outside the C int range");

    osdl_check(TTF_DrawSurfaceText(ptr, dx, dy, s), "TTF_DrawSurfaceText");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_draw_renderer(value text, value x, value y) {
    TTF_Text* ptr = osdl_live(text);
    float     dx  = osdl_float(Double_val(x));
    float     dy  = osdl_float(Double_val(y));

    osdl_check(TTF_DrawRendererText(ptr, dx, dy), "TTF_DrawRendererText");
    return Val_unit;
}
