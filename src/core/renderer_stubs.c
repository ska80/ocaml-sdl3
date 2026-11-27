#include "gpu_handles.h"

/* A renderer keeps its window, surface, or offscreen context open. */
static value osdl_new_renderer(value parent, int kind) {
    CAMLparam1(parent);
    CAMLlocal1(cell);

    cell = osdl_new_cell(parent, &osdl_handle_ops);
    CAMLreturn(caml_alloc_6(0, cell, parent, Val_unit, Val_int(kind), Val_unit, Val_emptylist));
}

CAMLprim value osdl_renderer_create(value driver, value window) {
    CAMLparam2(driver, window);
    CAMLlocal1(handle);

    handle = osdl_new_renderer(window, OSDL_RENDERER_WINDOW);

    const char*   name     = Is_long(driver) ? NULL : osdl_cstring(Some_val(driver));
    SDL_Renderer* renderer = SDL_CreateRenderer(osdl_unattached_window(window), name);
    CAMLreturn(osdl_publish(handle, renderer, "SDL_CreateRenderer"));
}

CAMLprim value osdl_renderer_create_software(value surface) {
    CAMLparam1(surface);
    CAMLlocal1(handle);

    handle = osdl_new_renderer(surface, OSDL_RENDERER_SURFACE);

    SDL_Renderer* renderer = SDL_CreateSoftwareRenderer(osdl_unlocked_surface(surface));
    CAMLreturn(osdl_publish(handle, renderer, "SDL_CreateSoftwareRenderer"));
}

static value osdl_create_gpu_renderer(value device, value parent, bool offscreen) {
    CAMLparam2(device, parent);
    CAMLlocal1(handle);

    handle = osdl_new_renderer(parent, offscreen ? OSDL_RENDERER_OFFSCREEN : OSDL_RENDERER_WINDOW);
    SDL_Window* window = NULL;
    if (offscreen)
        osdl_require_subsystem(parent, SDL_INIT_VIDEO,
                               "Start SDL with Video before creating a GPU renderer");
    else
        window = osdl_unattached_window(parent);

    device             = Is_long(device) ? Val_unit : Some_val(device);
    SDL_GPUDevice* ptr = NULL;
    if (device != Val_unit) {
        ptr = osdl_live(device);
        osdl_gpu_require_no_render_pass(device);
    }

    SDL_Renderer* renderer = SDL_CreateGPURenderer(ptr, window);
    osdl_publish(handle, renderer, "SDL_CreateGPURenderer");
    if (device != Val_unit) {
        ++osdl_cell_val(device)->children;
        Store_field(handle, OSDL_RENDERER_DEVICE, device);
    }
    CAMLreturn(handle);
}

CAMLprim value osdl_renderer_create_gpu(value device, value window) {
    return osdl_create_gpu_renderer(device, window, false);
}

CAMLprim value osdl_renderer_create_gpu_offscreen(value device, value context) {
    return osdl_create_gpu_renderer(device, context, true);
}

CAMLprim value osdl_renderer_gpu_device(value renderer) {
    CAMLparam1(renderer);
    CAMLlocal2(device, borrowed);

    SDL_Renderer* r = osdl_live(renderer);
    device          = Field(renderer, OSDL_RENDERER_DEVICE);
    if (device == Val_unit) {
        const char* name = SDL_GetRendererName(r);
        if (!name) osdl_fail("SDL_GetRendererName");
        if (strcmp(name, SDL_GPU_RENDERER) != 0) CAMLreturn(Val_none);

        borrowed = osdl_new_gpu_device(renderer, false);
        r        = osdl_live(renderer);
        device   = Field(renderer, OSDL_RENDERER_DEVICE);
        if (device == Val_unit) {
            SDL_GPUDevice* ptr = SDL_GetGPURendererDevice(r);
            if (!ptr) osdl_fail("SDL_GetGPURendererDevice");
            /* Only the borrowed device's resources, not the handle itself,
             * prevent the renderer from closing. */
            osdl_cell_val(borrowed)->ptr = ptr;
            Store_field(renderer, OSDL_RENDERER_DEVICE, borrowed);
            device = borrowed;
        }
    }
    CAMLreturn(caml_alloc_some(device));
}

static void osdl_renderer_release_shader_pins(value renderer, SDL_GPUDevice* device) {
    for (value list = Field(renderer, OSDL_RENDERER_SHADERS); list != Val_emptylist;
         list       = Field(list, 1)) {
        osdl_gpu_shader_cell* cell = (osdl_gpu_shader_cell*)osdl_cell_val(Field(list, 0));
        if (--cell->renderer_count == 0 && cell->deferred_release) {
            SDL_ReleaseGPUShader(device, cell->deferred_release);
            cell->deferred_release = NULL;
        }
    }
    Store_field(renderer, OSDL_RENDERER_SHADERS, Val_emptylist);
}

CAMLprim value osdl_renderer_destroy(value renderer) {
    osdl_cell* cell = osdl_cell_val(renderer);
    osdl_require_thread(osdl_cell_thread(cell));
    if (!cell->ptr) return Val_unit;

    value device      = Field(renderer, OSDL_RENDERER_DEVICE);
    bool  owns_device = device != Val_unit && osdl_parent(device) == renderer;
    if (device != Val_unit) {
        osdl_gpu_require_no_render_pass(device);
        if (owns_device && osdl_cell_val(device)->children)
            caml_invalid_argument("Close the resources of the renderer's GPU device first");
    }
    SDL_Renderer* ptr = osdl_take(renderer);

    if (device != Val_unit) {
        /* All states are closed. SDL only frees cache entries during teardown.
         * Release shaders now, before SDL destroys an internally owned device. */
        osdl_renderer_release_shader_pins(renderer, osdl_cell_val(device)->ptr);
        if (owns_device) osdl_cell_val(device)->ptr = NULL;
    }
    SDL_DestroyRenderer(ptr);
    if (device != Val_unit && !owns_device) --osdl_cell_val(device)->children;
    Store_field(renderer, OSDL_RENDERER_DEVICE, Val_unit);
    return Val_unit;
}

/* Custom render states borrow the fragment shader and additional sampler pairs. */
static void osdl_renderer_pin_shader(value renderer, value shader, value node) {
    value shaders = Field(renderer, OSDL_RENDERER_SHADERS);
    for (value list = shaders; list != Val_emptylist; list = Field(list, 1))
        if (Field(list, 0) == shader) return;

    osdl_gpu_shader_cell* cell = (osdl_gpu_shader_cell*)osdl_cell_val(shader);
    ++cell->renderer_count;
    Store_field(node, 1, shaders);
    Store_field(renderer, OSDL_RENDERER_SHADERS, node);
}

static void osdl_gpu_state_ref_pairs(value pairs, bool retain) {
    for (mlsize_t i = 0; i < Wosize_val(pairs); ++i) {
        value      pair    = Field(pairs, i);
        osdl_cell* texture = osdl_cell_val(Field(pair, 0));
        osdl_cell* sampler = osdl_cell_val(Field(pair, 1));
        if (retain) {
            ++texture->children;
            ++sampler->children;
        } else {
            --texture->children;
            --sampler->children;
        }
    }
}

CAMLprim value osdl_renderer_create_gpu_render_state(value samplers, value renderer, value draw,
                                                     value fragment) {
    CAMLparam4(samplers, renderer, draw, fragment);
    CAMLlocal4(cell, state, pairs, pin);

    mlsize_t count = Is_long(samplers) ? 0 : Wosize_val(Some_val(samplers));
    if (count + (Int_val(draw) == OSDL_STATE_TEXTURED) !=
        (mlsize_t)Int_val(Field(fragment, GPU_SHADER_SAMPLERS)))
        caml_invalid_argument(
            "Match the sampler count to the GPU render state's draw type and pairs");

    pairs = caml_alloc_tuple(count);
    cell  = osdl_new_cell(renderer, &osdl_handle_ops);
    state = caml_alloc_6(0, cell, renderer, draw, fragment, pairs, Val_int(0));
    pin   = caml_alloc_2(0, fragment, Val_emptylist);

    SDL_Renderer*  r      = osdl_renderer_ready(renderer);
    value          device = Field(renderer, OSDL_RENDERER_DEVICE);
    SDL_GPUShader* shader = osdl_live(fragment);
    if (device == Val_unit || device != osdl_parent(fragment))
        caml_invalid_argument("Use a fragment shader from the GPU renderer's device");

    SDL_GPUTextureSamplerBinding native[GPU_MAX_SAMPLERS];
    for (mlsize_t i = 0; i < count; ++i) {
        value           pair    = Field(Some_val(samplers), i);
        value           texture = Field(pair, 0), sampler = Field(pair, 1);
        SDL_GPUTexture* t = osdl_live(texture);
        SDL_GPUSampler* s = osdl_live(sampler);
        if (osdl_parent(texture) != device || osdl_parent(sampler) != device)
            caml_invalid_argument("Use textures and samplers from the GPU renderer's device");
        if (!(osdl_gpu_image_usage(texture) & SDL_GPU_TEXTUREUSAGE_SAMPLER))
            caml_invalid_argument("The GPU texture must support sampling");
        native[i] = (SDL_GPUTextureSamplerBinding){.texture = t, .sampler = s};
        Store_field(pairs, i, pair);
    }

    SDL_GPURenderStateCreateInfo info = {
        .fragment_shader      = shader,
        .num_sampler_bindings = (Sint32)count,
        .sampler_bindings     = count ? native : NULL,
    };
    SDL_GPURenderState* ptr = SDL_CreateGPURenderState(r, &info);
    osdl_publish(state, ptr, "SDL_CreateGPURenderState");
    ++osdl_cell_val(fragment)->children;
    osdl_gpu_state_ref_pairs(pairs, true);
    osdl_renderer_pin_shader(renderer, fragment, pin);
    CAMLreturn(state);
}

CAMLprim value osdl_renderer_set_gpu_render_state(value renderer, value state) {
    SDL_Renderer*       r      = osdl_renderer_ready(renderer);
    value               handle = Is_long(state) ? Val_unit : Some_val(state);
    SDL_GPURenderState* ptr    = NULL;
    if (handle != Val_unit) {
        ptr = osdl_live(handle);
        if (osdl_parent(handle) != renderer)
            caml_invalid_argument("Use a GPU render state from this renderer");
        value shader   = Field(handle, OSDL_STATE_SHADER);
        int   required = (1 << Int_val(Field(shader, GPU_SHADER_UNIFORMS))) - 1;
        if (Int_val(Field(handle, OSDL_STATE_UNIFORMS)) != required)
            caml_invalid_argument(
                "Set every declared fragment uniform slot before using the state");
    } else if (Field(renderer, OSDL_RENDERER_STATE) == Val_unit) {
        return Val_unit;
    }

    osdl_check(SDL_SetGPURenderState(r, ptr), "SDL_SetGPURenderState");
    Store_field(renderer, OSDL_RENDERER_STATE, handle);
    return Val_unit;
}

static void osdl_gpu_state_drop_resources(value state) {
    --osdl_cell_val(Field(state, OSDL_STATE_SHADER))->children;
    osdl_gpu_state_ref_pairs(Field(state, OSDL_STATE_SAMPLERS), false);
    Store_field(state, OSDL_STATE_SHADER, Val_unit);
    Store_field(state, OSDL_STATE_SAMPLERS, Val_unit);
}

CAMLprim value osdl_renderer_set_gpu_render_state_fragment_uniforms(value state, value slot,
                                                                    value data) {
    SDL_GPURenderState* ptr = osdl_live(state);
    osdl_renderer_ready(osdl_parent(state));
    value  shader = Field(state, OSDL_STATE_SHADER);
    intnat index  = Long_val(slot);
    if (index < 0 || index >= Int_val(Field(shader, GPU_SHADER_UNIFORMS)))
        caml_invalid_argument("The uniform slot is outside the state shader's declared slots");
    intnat size = osdl_gpu_uniform_size(data);
    int    mask = Int_val(Field(state, OSDL_STATE_UNIFORMS)), bit = 1 << index;

    bool ok = SDL_SetGPURenderStateFragmentUniforms(ptr, (Uint32)index, Caml_ba_data_val(data),
                                                    (Uint32)size);
    if (!ok && mask && !(mask & bit)) {
        /* SDL 3.4.20 can invalidate the old uniform array if allocation of a
         * new slot fails. The state was never active. Retire the handle rather
         * than pass a possibly corrupt state back to SDL. */
        osdl_take(state);
        osdl_gpu_state_drop_resources(state);
    }
    osdl_check(ok, "SDL_SetGPURenderStateFragmentUniforms");
    Store_field(state, OSDL_STATE_UNIFORMS, Val_int(mask | bit));
    return Val_unit;
}

CAMLprim value osdl_renderer_destroy_gpu_render_state(value state) {
    osdl_cell* cell = osdl_cell_val(state);
    osdl_require_thread(osdl_cell_thread(cell));
    if (!cell->ptr) return Val_unit;

    value         renderer = osdl_parent(state);
    SDL_Renderer* r        = osdl_renderer_ready(renderer);
    if (Field(renderer, OSDL_RENDERER_STATE) == state) {
        osdl_check(SDL_SetGPURenderState(r, NULL), "SDL_SetGPURenderState");
        Store_field(renderer, OSDL_RENDERER_STATE, Val_unit);
    }

    /* SDL flushes any queued draws that reference the state before freeing it. */
    SDL_DestroyGPURenderState(osdl_take(state));
    osdl_gpu_state_drop_resources(state);
    return Val_unit;
}
