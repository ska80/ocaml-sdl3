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

    handle = osdl_new_handle(context);
    osdl_live(context);

    TTF_Font* font = TTF_OpenFont(osdl_cstring(path), font_size(ptsize));
    CAMLreturn(osdl_publish(handle, font, "TTF_OpenFont"));
}

OSDL_DESTROY(osdl_ttf_font_close, TTF_Font, TTF_CloseFont)

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
