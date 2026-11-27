#ifndef OCAML_SDL3_GPU_HANDLES_H
#define OCAML_SDL3_GPU_HANDLES_H

#include "sdl3_stubs.h"

/* Internal GPU texture layout. */
enum {
    GPU_TEXTURE_WIDTH = 2,
    GPU_TEXTURE_HEIGHT,
    GPU_TEXTURE_FORMAT,
    GPU_TEXTURE_USAGE,
    GPU_TEXTURE_LEVELS,
    GPU_MAX_MIP_LEVEL = 14,
};

typedef struct {
    Uint32 level, w, h;
} osdl_gpu_texture_mip;

static inline osdl_gpu_texture_mip osdl_gpu_mip(value texture, value level, bool render) {
    intnat index = Long_val(level);
    if (index < 0 || index >= Long_val(Field(texture, GPU_TEXTURE_LEVELS)))
        caml_invalid_argument("The GPU mip level index is outside the texture");
    Uint32 w = Int_val(Field(texture, GPU_TEXTURE_WIDTH)) >> index;
    Uint32 h = Int_val(Field(texture, GPU_TEXTURE_HEIGHT)) >> index;
    /* SDL 3.4.20 shifts dimensions without clamping when it renders or blits. */
    if (render && (!w || !h))
        caml_invalid_argument("SDL cannot render or blit this mip level of a rectangular texture");
    return (osdl_gpu_texture_mip){(Uint32)index, SDL_max(w, 1u), SDL_max(h, 1u)};
}

static inline SDL_GPUTextureFormat osdl_gpu_image_format(value texture) {
    return Int_val(Field(texture, GPU_TEXTURE_FORMAT));
}

/* Internal render pass layout. */
enum {
    GPU_PASS_FORMAT = 2,
    GPU_PASS_PIPELINE,
    GPU_PASS_VERTEX_BUFFER,
    GPU_PASS_VERTEX_COUNT,
    GPU_PASS_INDEX_BUFFER,
    GPU_PASS_INDEX_COUNT,
    GPU_PASS_SAMPLERS,
    GPU_PASS_TARGET,
    GPU_PASS_WIDTH,
    GPU_PASS_HEIGHT,
    GPU_PASS_FIELDS,
};

static inline value osdl_gpu_new_render_pass(value commands) {
    CAMLparam1(commands);
    CAMLlocal2(cell, pass);

    cell           = osdl_new_cell(commands, &osdl_handle_ops);
    pass           = caml_alloc_small(GPU_PASS_FIELDS, 0);
    Field(pass, 0) = cell;
    Field(pass, 1) = commands;
    for (mlsize_t i = 2; i < GPU_PASS_FIELDS; ++i)
        Field(pass, i) = Val_unit;
    CAMLreturn(pass);
}

#endif
