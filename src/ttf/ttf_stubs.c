#include "sdl3_stubs.h"

#include <SDL3_ttf/SDL_ttf.h>

/* SDL_ttf context. */

static char ttf_initialized;

CAMLprim value osdl_ttf_version(value unit) {
    (void)unit;
    return osdl_version_value(TTF_Version());
}

CAMLprim value osdl_ttf_has_harfbuzz(value unit) {
    (void)unit;
    int major;
    TTF_GetHarfBuzzVersion(&major, NULL, NULL);
    return Val_bool(major > 0);
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

/* Shaping settings shared by fonts and text objects. */

static const TTF_Direction ttf_directions[] = {TTF_DIRECTION_LTR, TTF_DIRECTION_RTL,
                                               TTF_DIRECTION_TTB, TTF_DIRECTION_BTT};

static TTF_Direction ttf_direction(value direction) {
    return Is_long(direction) ? TTF_DIRECTION_INVALID
                              : ttf_directions[Int_val(Some_val(direction))];
}

static value ttf_direction_value(TTF_Direction direction) {
    for (int i = 0; i < (int)SDL_arraysize(ttf_directions); ++i) {
        if (direction == ttf_directions[i]) return caml_alloc_some(Val_int(i));
    }
    return Val_none;
}

static Uint32 ttf_script(value script) {
    if (Is_long(script)) return 0;
    value       v   = Some_val(script);
    const char* tag = String_val(v);
    if (caml_string_length(v) != 4)
        caml_invalid_argument("A script tag must have four ASCII letters");
    for (int i = 0; i < 4; ++i) {
        if (!SDL_isalpha((unsigned char)tag[i]))
            caml_invalid_argument("A script tag must have four ASCII letters");
    }
    return TTF_StringToTag(tag);
}

static value ttf_script_value(Uint32 script) {
    if (!script) return Val_none;

    char tag[4];
    TTF_TagToString(script, tag, sizeof(tag));
    return caml_alloc_some(caml_alloc_initialized_string(sizeof(tag), tag));
}

/* Fonts and metrics. The attachment retains the optional stream and both
 * lists of links. Each link is shared by the two fonts and keeps them rooted. */

enum { FONT_STREAM, FONT_FALLBACKS, FONT_BASES };
enum { LINK_BASE, LINK_FALLBACK, LINK_NEXT_FALLBACK, LINK_NEXT_BASE };

static value ttf_new_font_handle(value context, value stream) {
    CAMLparam2(context, stream);
    CAMLlocal1(attachment);

    attachment = caml_alloc_3(0, stream, Val_unit, Val_unit);
    CAMLreturn(osdl_new_attached_handle(context, attachment));
}

static value ttf_find_fallback(value font, value fallback) {
    for (value link = Field(osdl_attachment(font), FONT_FALLBACKS); link != Val_unit;
         link       = Field(link, LINK_NEXT_FALLBACK)) {
        if (Field(link, LINK_FALLBACK) == fallback) return link;
    }
    return Val_unit;
}

static void ttf_unlink_fallback(value link) {
    value           base = Field(link, LINK_BASE), fallback = Field(link, LINK_FALLBACK);
    volatile value* outgoing = &Field(osdl_attachment(base), FONT_FALLBACKS);
    volatile value* incoming = &Field(osdl_attachment(fallback), FONT_BASES);
    while (*outgoing != link)
        outgoing = &Field(*outgoing, LINK_NEXT_FALLBACK);
    while (*incoming != link)
        incoming = &Field(*incoming, LINK_NEXT_BASE);
    caml_modify(outgoing, Field(link, LINK_NEXT_FALLBACK));
    caml_modify(incoming, Field(link, LINK_NEXT_BASE));
    --osdl_cell_val(fallback)->children;
}

/* SDL_ttf 3.2.0 and 3.2.2 mark texts dirty on fallback or kerning changes but
 * keep cached positions and glyphs. Toggle hinting to clear the positions and
 * bump the font generation so the engines rebuild glyphs on the next update. */
static void ttf_invalidate_font(TTF_Font* font) {
    TTF_HintingFlags hinting = TTF_GetFontHinting(font);
    TTF_SetFontHinting(font,
                       hinting == TTF_HINTING_NORMAL ? TTF_HINTING_LIGHT : TTF_HINTING_NORMAL);
    TTF_SetFontHinting(font, hinting);
}

static void ttf_invalidate_fallback_users(value font) {
    for (value link = Field(osdl_attachment(font), FONT_BASES); link != Val_unit;
         link       = Field(link, LINK_NEXT_BASE))
        ttf_invalidate_font(osdl_live(Field(link, LINK_BASE)));
}

static float font_size(value ptsize) {
    float size = osdl_float(Double_val(ptsize));
    if (size <= 0) caml_invalid_argument("Font size must be positive");
    return size;
}

CAMLprim value osdl_ttf_font_open(value context, value path, value ptsize) {
    CAMLparam3(context, path, ptsize);
    CAMLlocal1(handle);

    osdl_live(context);
    handle = ttf_new_font_handle(context, Val_unit);

    TTF_Font* font = TTF_OpenFont(osdl_cstring(path), font_size(ptsize));
    CAMLreturn(osdl_publish(handle, font, "TTF_OpenFont"));
}

CAMLprim value osdl_ttf_font_open_io(value context, value stream, value ptsize) {
    CAMLparam3(context, stream, ptsize);
    CAMLlocal1(handle);

    osdl_live(context);
    SDL_IOStream* io   = osdl_unborrowed_io(stream);
    float         size = font_size(ptsize);
    handle             = ttf_new_font_handle(context, stream);

    TTF_Font* font = TTF_OpenFontIO(io, false, size);
    osdl_publish(handle, font, "TTF_OpenFontIO");
    ++osdl_cell_val(stream)->children;
    CAMLreturn(handle);
}

CAMLprim value osdl_ttf_font_close(value font) {
    TTF_Font* f = osdl_take(font);
    if (f) {
        TTF_CloseFont(f);
        value attachment = osdl_attachment(font);
        while (Field(attachment, FONT_FALLBACKS) != Val_unit)
            ttf_unlink_fallback(Field(attachment, FONT_FALLBACKS));
        value stream = Field(attachment, FONT_STREAM);
        if (Is_block(stream)) --osdl_cell_val(stream)->children;
        osdl_forget_attachment(font);
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_font_set_size(value font, value ptsize) {
    TTF_Font* f    = osdl_live(font);
    float     size = font_size(ptsize);

    if (size != TTF_GetFontSize(f)) {
        osdl_check(TTF_SetFontSize(f, size), "TTF_SetFontSize");
        ttf_invalidate_fallback_users(font);
    }
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

CAMLprim value osdl_ttf_font_glyph_metrics(value font, value ch) {
    int min_x, max_x, min_y, max_y, advance;
    osdl_check(TTF_GetGlyphMetrics(osdl_live(font), (Uint32)Int_val(ch), &min_x, &max_x, &min_y,
                                   &max_y, &advance),
               "TTF_GetGlyphMetrics");
    return caml_alloc_5(0, osdl_val_int(min_x), osdl_val_int(max_x), osdl_val_int(min_y),
                        osdl_val_int(max_y), osdl_val_int(advance));
}

CAMLprim value osdl_ttf_font_glyph_kerning(value font, value previous, value current) {
    int kerning;
    osdl_check(TTF_GetGlyphKerning(osdl_live(font), (Uint32)Int_val(previous),
                                   (Uint32)Int_val(current), &kerning),
               "TTF_GetGlyphKerning");
    return osdl_val_int(kerning);
}

/* Font appearance and layout. */

static const TTF_FontStyleFlags ttf_styles[] = {TTF_STYLE_BOLD, TTF_STYLE_ITALIC,
                                                TTF_STYLE_UNDERLINE, TTF_STYLE_STRIKETHROUGH};

CAMLprim value osdl_ttf_font_set_style(value font, value styles) {
    TTF_Font*          f     = osdl_live(font);
    TTF_FontStyleFlags flags = TTF_STYLE_NORMAL;
    for (; styles != Val_emptylist; styles = Field(styles, 1))
        flags |= ttf_styles[Int_val(Field(styles, 0))];

    TTF_FontStyleFlags old = TTF_GetFontStyle(f);
    TTF_SetFontStyle(f, flags);
    if (old != TTF_GetFontStyle(f)) ttf_invalidate_fallback_users(font);
    return Val_unit;
}

CAMLprim value osdl_ttf_font_style(value font) {
    CAMLparam1(font);
    CAMLlocal1(styles);

    TTF_FontStyleFlags flags = TTF_GetFontStyle(osdl_live(font));
    styles                   = Val_emptylist;
    for (int i = (int)SDL_arraysize(ttf_styles) - 1; i >= 0; --i) {
        if (flags & ttf_styles[i]) styles = caml_alloc_2(0, Val_int(i), styles);
    }
    CAMLreturn(styles);
}

CAMLprim value osdl_ttf_font_set_outline(value font, value outline) {
    TTF_Font* f     = osdl_live(font);
    int       width = osdl_int(outline);
    if (width < 0 || width > 32767)
        caml_invalid_argument("Font outline thickness must be between 0 and 32767 pixels");

    if (width != TTF_GetFontOutline(f)) {
        osdl_check(TTF_SetFontOutline(f, width), "TTF_SetFontOutline");
        ttf_invalidate_fallback_users(font);
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_font_outline(value font) {
    return osdl_val_int(TTF_GetFontOutline(osdl_live(font)));
}

static const TTF_HintingFlags ttf_hinting_modes[] = {TTF_HINTING_NORMAL, TTF_HINTING_LIGHT,
                                                     TTF_HINTING_MONO, TTF_HINTING_NONE};

CAMLprim value osdl_ttf_font_set_hinting(value font, value hinting) {
    TTF_Font*        f    = osdl_live(font);
    TTF_HintingFlags mode = ttf_hinting_modes[Int_val(hinting)];

    if (mode != TTF_GetFontHinting(f)) {
        TTF_SetFontHinting(f, mode);
        ttf_invalidate_fallback_users(font);
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_font_hinting(value font) {
    TTF_HintingFlags mode = TTF_GetFontHinting(osdl_live(font));
    for (int i = 0; i < (int)SDL_arraysize(ttf_hinting_modes); ++i) {
        if (mode == ttf_hinting_modes[i]) return Val_int(i);
    }
    osdl_raise_error("TTF_GetFontHinting: Unsupported hinting mode");
}

CAMLprim value osdl_ttf_font_set_kerning(value font, value enabled) {
    TTF_Font* f = osdl_live(font);
    if (TTF_GetFontKerning(f) != Bool_val(enabled)) {
        TTF_SetFontKerning(f, Bool_val(enabled));
        ttf_invalidate_font(f);
        ttf_invalidate_fallback_users(font);
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_font_kerning(value font) {
    return Val_bool(TTF_GetFontKerning(osdl_live(font)));
}

static const TTF_HorizontalAlignment ttf_alignments[] = {
    TTF_HORIZONTAL_ALIGN_LEFT, TTF_HORIZONTAL_ALIGN_CENTER, TTF_HORIZONTAL_ALIGN_RIGHT};

CAMLprim value osdl_ttf_font_set_wrap_alignment(value font, value alignment) {
    TTF_SetFontWrapAlignment(osdl_live(font), ttf_alignments[Int_val(alignment)]);
    return Val_unit;
}

CAMLprim value osdl_ttf_font_wrap_alignment(value font) {
    TTF_HorizontalAlignment alignment = TTF_GetFontWrapAlignment(osdl_live(font));
    for (int i = 0; i < (int)SDL_arraysize(ttf_alignments); ++i) {
        if (alignment == ttf_alignments[i]) return Val_int(i);
    }
    osdl_raise_error("TTF_GetFontWrapAlignment: Unsupported alignment");
}

CAMLprim value osdl_ttf_font_set_direction(value font, value direction) {
    osdl_check(TTF_SetFontDirection(osdl_live(font), ttf_direction(direction)),
               "TTF_SetFontDirection");
    return Val_unit;
}

CAMLprim value osdl_ttf_font_direction(value font) {
    return ttf_direction_value(TTF_GetFontDirection(osdl_live(font)));
}

CAMLprim value osdl_ttf_font_set_script(value font, value script) {
    osdl_check(TTF_SetFontScript(osdl_live(font), ttf_script(script)), "TTF_SetFontScript");
    return Val_unit;
}

CAMLprim value osdl_ttf_font_script(value font) {
    return ttf_script_value(TTF_GetFontScript(osdl_live(font)));
}

/* Fallback fonts. The native list determines glyph search order. The binding
 * retains links to keep each fallback open and invalidate dependent caches. */

CAMLprim value osdl_ttf_font_add_fallback(value font, value fallback) {
    CAMLparam2(font, fallback);
    CAMLlocal1(link);

    TTF_Font* base  = osdl_live(font);
    TTF_Font* extra = osdl_live(fallback);
    if (font == fallback) caml_invalid_argument("A font cannot be its own fallback");
    if (ttf_find_fallback(font, fallback) != Val_unit) CAMLreturn(Val_unit);
    if (Field(osdl_attachment(font), FONT_BASES) != Val_unit ||
        Field(osdl_attachment(fallback), FONT_FALLBACKS) != Val_unit)
        caml_invalid_argument("A fallback font cannot have its own fallbacks");
    link = caml_alloc_4(0, font, fallback, Field(osdl_attachment(font), FONT_FALLBACKS),
                        Field(osdl_attachment(fallback), FONT_BASES));

    osdl_check(TTF_AddFallbackFont(base, extra), "TTF_AddFallbackFont");
    ttf_invalidate_font(base);
    caml_modify(&Field(osdl_attachment(font), FONT_FALLBACKS), link);
    caml_modify(&Field(osdl_attachment(fallback), FONT_BASES), link);
    ++osdl_cell_val(fallback)->children;
    CAMLreturn(Val_unit);
}

CAMLprim value osdl_ttf_font_remove_fallback(value font, value fallback) {
    TTF_Font* base  = osdl_live(font);
    TTF_Font* extra = osdl_live(fallback);
    value     link  = ttf_find_fallback(font, fallback);

    if (link != Val_unit) {
        TTF_RemoveFallbackFont(base, extra);
        ttf_invalidate_font(base);
        ttf_unlink_fallback(link);
    }
    return Val_unit;
}

CAMLprim value osdl_ttf_font_clear_fallbacks(value font) {
    TTF_Font* f          = osdl_live(font);
    value     attachment = osdl_attachment(font);
    if (Field(attachment, FONT_FALLBACKS) == Val_unit) return Val_unit;

    TTF_ClearFallbackFonts(f);
    ttf_invalidate_font(f);
    while (Field(attachment, FONT_FALLBACKS) != Val_unit)
        ttf_unlink_fallback(Field(attachment, FONT_FALLBACKS));
    return Val_unit;
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

CAMLprim value osdl_ttf_text_string(value text) {
    TTF_Text* ptr = osdl_live(text);
    return caml_copy_string(ptr->text ? ptr->text : "");
}

CAMLprim value osdl_ttf_text_set_string(value text, value string) {
    TTF_Text*   ptr    = osdl_live(text);
    size_t      length = ttf_text_length(string);
    const char* s      = osdl_cstring(string);

    osdl_check(TTF_SetTextString(ptr, s, length), "TTF_SetTextString");
    return Val_unit;
}

static int ttf_text_bytes(TTF_Text* text) {
    return text->text ? (int)SDL_strlen(text->text) : 0;
}

static void ttf_check_byte_range(int bytes, int offset, int length) {
    if (offset > bytes || length > bytes - offset)
        caml_invalid_argument("The byte range is outside the text");
}

static void ttf_check_edit_boundary(TTF_Text* text, int bytes, int offset) {
    if (offset < bytes && ((Uint8)text->text[offset] & 0xc0) == 0x80)
        caml_invalid_argument("Text edits must start and end at UTF-8 code point boundaries");
}

CAMLprim value osdl_ttf_text_insert(value text, value offset, value string) {
    TTF_Text*   ptr    = osdl_live(text);
    int         bytes  = ttf_text_bytes(ptr);
    int         start  = osdl_nonnegative_int(offset);
    size_t      length = ttf_text_length(string);
    const char* s      = osdl_cstring(string);
    ttf_check_byte_range(bytes, start, 0);
    ttf_check_edit_boundary(ptr, bytes, start);
    if (length > (size_t)(INT_MAX - bytes))
        caml_invalid_argument("SDL_ttf text has too many bytes");

    osdl_check(TTF_InsertTextString(ptr, start, s, length), "TTF_InsertTextString");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_delete(value text, value offset, value length) {
    TTF_Text* ptr   = osdl_live(text);
    int       bytes = ttf_text_bytes(ptr);
    int       start = osdl_nonnegative_int(offset), count = osdl_nonnegative_int(length);
    ttf_check_byte_range(bytes, start, count);
    ttf_check_edit_boundary(ptr, bytes, start);
    ttf_check_edit_boundary(ptr, bytes, start + count);
    if (!count) return Val_unit;

    int tail = bytes - start - count;
    if (tail <= count) {
        osdl_check(TTF_DeleteTextString(ptr, start, count), "TTF_DeleteTextString");
    } else {
        /* SDL_ttf 3.2.0 and 3.2.2 use memcpy for the shift. Copy the retained
         * bytes separately when the source and destination would overlap. */
        char* kept = SDL_malloc((size_t)(bytes - count) + 1);
        if (!kept) osdl_fail("SDL_malloc");
        SDL_memcpy(kept, ptr->text, (size_t)start);
        SDL_memcpy(kept + start, ptr->text + start + count, (size_t)tail + 1);
        bool ok = TTF_SetTextString(ptr, kept, (size_t)(bytes - count));
        SDL_free(kept);
        osdl_check(ok, "TTF_SetTextString");
    }
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

CAMLprim value osdl_ttf_text_set_direction(value text, value direction) {
    osdl_check(TTF_SetTextDirection(osdl_live(text), ttf_direction(direction)),
               "TTF_SetTextDirection");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_direction(value text) {
    return ttf_direction_value(TTF_GetTextDirection(osdl_live(text)));
}

CAMLprim value osdl_ttf_text_set_script(value text, value script) {
    osdl_check(TTF_SetTextScript(osdl_live(text), ttf_script(script)), "TTF_SetTextScript");
    return Val_unit;
}

CAMLprim value osdl_ttf_text_script(value text) {
    return ttf_script_value(TTF_GetTextScript(osdl_live(text)));
}

CAMLprim value osdl_ttf_text_size(value text) {
    int w, h;
    osdl_check(TTF_GetTextSize(osdl_live(text), &w, &h), "TTF_GetTextSize");
    return osdl_int_pair(w, h);
}

OSDL_ACTION(osdl_ttf_text_update, TTF_UpdateText)

/* Text layout queries return copies, never references into SDL_ttf. */

static TTF_SubString ttf_substring_at(TTF_Text* text, int offset, int bytes) {
    TTF_SubString sub;
    osdl_check(TTF_GetTextSubString(text, offset, &sub), "TTF_GetTextSubString");
    /* The search can return a zero-length wrap marker instead of the group
     * starting on the next line, especially for multibyte text. */
    if (offset < bytes && !sub.length && (sub.flags & TTF_SUBSTRING_LINE_END))
        osdl_check(TTF_GetNextTextSubString(text, &sub, &sub), "TTF_GetNextTextSubString");
    return sub;
}

static value ttf_substring_value(TTF_SubString sub) {
    CAMLparam0();
    CAMLlocal2(rect, direction);

    rect      = osdl_rect_value(sub.rect);
    direction = ttf_direction_value(sub.flags & TTF_SUBSTRING_DIRECTION_MASK);
    CAMLreturn(caml_alloc_5(0, osdl_val_int(sub.offset), osdl_val_int(sub.length),
                            osdl_val_int(sub.line_index), rect, direction));
}

CAMLprim value osdl_ttf_text_substring_at(value text, value offset) {
    TTF_Text* ptr   = osdl_live(text);
    int       bytes = ttf_text_bytes(ptr), start = osdl_nonnegative_int(offset);
    ttf_check_byte_range(bytes, start, 0);

    TTF_SubString sub = ttf_substring_at(ptr, start, bytes);
    /* Use the font height if SDL did not lay out this byte. */
    if (!sub.flags && !sub.length) {
        sub.offset = start;
        sub.rect.h = TTF_GetFontHeight(TTF_GetTextFont(ptr));
    }
    return ttf_substring_value(sub);
}

CAMLprim value osdl_ttf_text_substring_bounds(value text, value offset, value length) {
    CAMLparam3(text, offset, length);
    CAMLlocal2(rect, results);

    TTF_Text* ptr   = osdl_live(text);
    int       bytes = ttf_text_bytes(ptr);
    int       start = osdl_nonnegative_int(offset), count = osdl_nonnegative_int(length);
    ttf_check_byte_range(bytes, start, count);
    if (!count) CAMLreturn(Val_emptylist);

    /* SDL's range query can lose the last group if the end falls inside it.
     * Start at the final byte instead and merge groups on each covered line. */
    TTF_SubString sub    = ttf_substring_at(ptr, start + count - 1, bytes);
    SDL_Rect      bounds = {0};
    int           line   = -1;
    results              = Val_emptylist;
    while (sub.offset + sub.length > start) {
        if (sub.length) {
            if (sub.line_index == line) {
                osdl_check(SDL_GetRectUnion(&bounds, &sub.rect, &bounds), "SDL_GetRectUnion");
            } else {
                if (line >= 0) {
                    rect    = osdl_rect_value(bounds);
                    results = caml_alloc_2(0, rect, results);
                }
                bounds = sub.rect;
                line   = sub.line_index;
            }
        }
        if (!sub.cluster_index) break;
        osdl_check(TTF_GetPreviousTextSubString(ptr, &sub, &sub), "TTF_GetPreviousTextSubString");
    }
    if (line >= 0) {
        rect    = osdl_rect_value(bounds);
        results = caml_alloc_2(0, rect, results);
    }
    CAMLreturn(results);
}

CAMLprim value osdl_ttf_text_hit_test(value text, value x, value y) {
    TTF_Text* ptr = osdl_live(text);
    int       px = osdl_int(x), py = osdl_int(y);
    /* SDL weights one axis by 100 and adds both distances in an int. Leave
     * room for line ends and glyph bearings beyond the reported text size. */
    const int limit = INT_MAX / 512;
    if (px < -limit || px > limit || py < -limit || py > limit)
        caml_invalid_argument("The hit test point is outside the SDL_ttf range");

    int w, h;
    osdl_check(TTF_GetTextSize(ptr, &w, &h), "TTF_GetTextSize");
    if (w < 0 || h < 0 || w > limit || h > limit)
        caml_invalid_argument("The text is too large for hit testing");

    TTF_SubString sub;
    osdl_check(TTF_GetTextSubStringForPoint(ptr, px, py, &sub), "TTF_GetTextSubStringForPoint");
    if (!sub.flags && !sub.length) sub.rect.h = TTF_GetFontHeight(TTF_GetTextFont(ptr));
    return ttf_substring_value(sub);
}

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
