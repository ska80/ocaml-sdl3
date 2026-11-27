#ifndef OCAML_SDL3_GPU_HANDLES_H
#define OCAML_SDL3_GPU_HANDLES_H

#include "sdl3_stubs.h"

/* Internal GPU device and shader layouts. */
enum { GPU_DEVICE_IDLE_MARK = GPU_DEVICE_RENDERING + 1, GPU_DEVICE_OWNED };

static inline value osdl_new_gpu_device(value parent, bool owned) {
    CAMLparam1(parent);
    CAMLlocal1(cell);

    cell = osdl_new_cell(parent, &osdl_handle_ops);
    CAMLreturn(caml_alloc_5(0, cell, parent, Val_false, Val_unit, Val_bool(owned)));
}

enum {
    GPU_SHADER_SAMPLERS = 2,
    GPU_SHADER_UNIFORMS,
    GPU_MAX_SAMPLERS      = 16,
    GPU_MAX_UNIFORMS      = 4,
    /* SDL's Vulkan backend uses a 4 KiB descriptor range for each uniform slot. */
    GPU_MAX_UNIFORM_BYTES = 4096,
};

typedef struct {
    osdl_cell      cell;
    /* The GPU renderer's pipeline cache uses the native shader address as a key. */
    size_t         renderer_count;
    SDL_GPUShader* deferred_release;
} osdl_gpu_shader_cell;

static inline intnat osdl_gpu_uniform_size(value data) {
    intnat size = Caml_ba_array_val(data)->dim[0];
    if (size <= 0 || size > GPU_MAX_UNIFORM_BYTES || size % 4)
        caml_invalid_argument("GPU uniform data must be 4 to 4096 bytes and a multiple of four");
    return size;
}

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

static inline SDL_GPUTextureUsageFlags osdl_gpu_image_usage(value texture) {
    return Int_val(Field(texture, GPU_TEXTURE_USAGE));
}

/* Internal render pass layout. */
enum {
    GPU_PASS_FORMAT = 2,
    GPU_PASS_PIPELINE,
    GPU_PASS_VERTEX_BINDINGS,
    GPU_PASS_VERTEX_DIRTY,
    GPU_PASS_VERTEX_PREFIX,
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
