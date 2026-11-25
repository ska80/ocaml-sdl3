#ifndef OCAML_SDL3_GPU_RENDER_PASS_H
#define OCAML_SDL3_GPU_RENDER_PASS_H

#include "sdl3_stubs.h"

/* Internal layout shared with the GPU render test. */
enum {
    GPU_PASS_FORMAT = 2,
    GPU_PASS_PIPELINE,
    GPU_PASS_VERTEX_BUFFER,
    GPU_PASS_VERTEX_COUNT,
    GPU_PASS_INDEX_BUFFER,
    GPU_PASS_INDEX_COUNT,
    GPU_PASS_SAMPLERS,
};

static inline value osdl_gpu_new_render_pass(value commands) {
    CAMLparam1(commands);
    CAMLlocal1(cell);

    cell = osdl_new_cell(commands, &osdl_handle_ops);
    CAMLreturn(caml_alloc_9(0, cell, commands, Val_unit, Val_unit, Val_unit, Val_int(0), Val_unit,
                            Val_int(0), Val_unit));
}

#endif
