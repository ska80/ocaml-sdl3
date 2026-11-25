#include "sdl3_stubs.h"

#include <caml/signals.h>

/* GPU device selection. */

/* Sdl3.Gpu.shader_format constructor order. */
static const SDL_GPUShaderFormat osdl_gpu_format_bits[] = {
    SDL_GPU_SHADERFORMAT_SPIRV, SDL_GPU_SHADERFORMAT_DXBC,     SDL_GPU_SHADERFORMAT_DXIL,
    SDL_GPU_SHADERFORMAT_MSL,   SDL_GPU_SHADERFORMAT_METALLIB,
};

static SDL_GPUShaderFormat osdl_gpu_format_flags(value formats) {
    if (formats == Val_emptylist) caml_invalid_argument("Pass at least one GPU shader format");

    SDL_GPUShaderFormat flags = 0;
    for (value v = formats; v != Val_emptylist; v = Field(v, 1))
        flags |= osdl_gpu_format_bits[Int_val(Field(v, 0))];
    return flags;
}

static const char* osdl_gpu_driver_option(value driver) {
    return Is_long(driver) ? NULL : osdl_cstring(Some_val(driver));
}

static void osdl_gpu_require_video(value context) {
    osdl_live(context);
    if (!SDL_WasInit(SDL_INIT_VIDEO))
        caml_invalid_argument("Start the SDL video subsystem before using the GPU");
}

CAMLprim value osdl_gpu_drivers(value unit) {
    CAMLparam0();
    CAMLlocal2(drivers, name);
    (void)unit;

    drivers = Val_emptylist;
    for (int i = SDL_GetNumGPUDrivers(); i > 0; --i) {
        const char* driver = SDL_GetGPUDriver(i - 1);
        if (!driver) osdl_fail("SDL_GetGPUDriver");
        name    = caml_copy_string(driver);
        drivers = caml_alloc_2(0, name, drivers);
    }
    CAMLreturn(drivers);
}

CAMLprim value osdl_gpu_supports_shader_formats(value driver, value context, value formats) {
    osdl_gpu_require_video(context);
    SDL_GPUShaderFormat flags = osdl_gpu_format_flags(formats);
    const char*         name  = osdl_gpu_driver_option(driver);

    return Val_bool(SDL_GPUSupportsShaderFormats(flags, name));
}

CAMLprim value osdl_gpu_create_device(value driver, value debug, value context, value formats) {
    CAMLparam4(driver, debug, context, formats);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);

    osdl_gpu_require_video(context);
    SDL_GPUShaderFormat flags      = osdl_gpu_format_flags(formats);
    const char*         name       = osdl_gpu_driver_option(driver);
    bool                debug_mode = Is_block(debug) && Bool_val(Some_val(debug));

    SDL_GPUDevice* device = SDL_CreateGPUDevice(flags, debug_mode, name);
    CAMLreturn(osdl_publish(handle, device, "SDL_CreateGPUDevice"));
}

OSDL_DESTROY(osdl_gpu_destroy_device, SDL_GPUDevice, SDL_DestroyGPUDevice)

CAMLprim value osdl_gpu_driver(value device) {
    const char* name = SDL_GetGPUDeviceDriver(osdl_live(device));
    if (!name) osdl_fail("SDL_GetGPUDeviceDriver");
    return caml_copy_string(name);
}

CAMLprim value osdl_gpu_shader_formats(value device) {
    CAMLparam1(device);
    CAMLlocal1(formats);

    SDL_GPUShaderFormat flags = SDL_GetGPUShaderFormats(osdl_live(device));
    formats                   = Val_emptylist;
    for (int i = SDL_arraysize(osdl_gpu_format_bits); i > 0; --i)
        if (flags & osdl_gpu_format_bits[i - 1]) formats = caml_alloc_2(0, Val_int(i - 1), formats);
    CAMLreturn(formats);
}

CAMLprim value osdl_gpu_wait_idle(value device) {
    CAMLparam1(device);

    SDL_GPUDevice* ptr = osdl_live(device);

    /* Do not run an OCaml signal handler between borrowing the device and waiting. */
    caml_enter_blocking_section_no_pending();
    bool ok = SDL_WaitForGPUIdle(ptr);
    caml_leave_blocking_section();

    osdl_check(ok, "SDL_WaitForGPUIdle");
    CAMLreturn(Val_unit);
}

/* Window claims and swapchain configuration. */

CAMLprim value osdl_gpu_claim_window(value device, value window) {
    CAMLparam2(device, window);
    CAMLlocal2(cell, claim);

    /* Store both parents in the claim. The cell's native pointer is the window. */
    cell  = osdl_new_cell(device, &osdl_handle_ops);
    claim = caml_alloc_3(0, cell, device, window);

    SDL_GPUDevice* d = osdl_live(device);
    SDL_Window*    w = osdl_unattached_window(window);

    osdl_check(SDL_ClaimWindowForGPUDevice(d, w), "SDL_ClaimWindowForGPUDevice");
    ++osdl_cell_val(window)->children;
    CAMLreturn(osdl_publish(claim, w, "SDL_ClaimWindowForGPUDevice"));
}

/* A live child keeps its device open. Use only after checking the child. */
static SDL_GPUDevice* osdl_gpu_parent_device(value child) {
    return osdl_cell_val(osdl_parent(child))->ptr;
}

static SDL_Window* osdl_gpu_available_window(value claim) {
    SDL_Window* w = osdl_live(claim);
    if (osdl_cell_val(claim)->children)
        caml_invalid_argument("Submit the GPU command buffer before reusing the swapchain");
    return w;
}

CAMLprim value osdl_gpu_release_window(value claim) {
    SDL_Window* w = osdl_take(claim);
    if (w) {
        SDL_ReleaseWindowFromGPUDevice(osdl_gpu_parent_device(claim), w);
        --osdl_cell_val(Field(claim, 2))->children;
    }
    return Val_unit;
}

static SDL_GPUPresentMode osdl_gpu_present_mode(value mode) {
    static const SDL_GPUPresentMode modes[] = {
        SDL_GPU_PRESENTMODE_VSYNC,
        SDL_GPU_PRESENTMODE_IMMEDIATE,
        SDL_GPU_PRESENTMODE_MAILBOX,
    };
    return modes[Int_val(mode)];
}

static SDL_GPUSwapchainComposition osdl_gpu_composition(value composition) {
    static const SDL_GPUSwapchainComposition compositions[] = {
        SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        SDL_GPU_SWAPCHAINCOMPOSITION_SDR_LINEAR,
        SDL_GPU_SWAPCHAINCOMPOSITION_HDR_EXTENDED_LINEAR,
        SDL_GPU_SWAPCHAINCOMPOSITION_HDR10_ST2084,
    };
    return compositions[Int_val(composition)];
}

CAMLprim value osdl_gpu_supports_present_mode(value claim, value mode) {
    SDL_Window* w = osdl_live(claim);
    return Val_bool(SDL_WindowSupportsGPUPresentMode(osdl_gpu_parent_device(claim), w,
                                                     osdl_gpu_present_mode(mode)));
}

CAMLprim value osdl_gpu_supports_composition(value claim, value composition) {
    SDL_Window* w = osdl_live(claim);
    return Val_bool(SDL_WindowSupportsGPUSwapchainComposition(osdl_gpu_parent_device(claim), w,
                                                              osdl_gpu_composition(composition)));
}

CAMLprim value osdl_gpu_set_swapchain_parameters(value claim, value composition, value mode) {
    SDL_Window* w = osdl_gpu_available_window(claim);
    osdl_check(SDL_SetGPUSwapchainParameters(osdl_gpu_parent_device(claim), w,
                                             osdl_gpu_composition(composition),
                                             osdl_gpu_present_mode(mode)),
               "SDL_SetGPUSwapchainParameters");
    return Val_unit;
}

/* Shaders and graphics pipelines. */

CAMLprim value osdl_gpu_create_shader(value device, value stage, value format, value entrypoint,
                                      value code) {
    CAMLparam5(device, stage, format, entrypoint, code);
    CAMLlocal1(handle);

    handle = osdl_new_handle(device);

    /* Sdl3.Gpu.shader_stage constructor order. */
    static const SDL_GPUShaderStage stages[] = {
        SDL_GPU_SHADERSTAGE_VERTEX,
        SDL_GPU_SHADERSTAGE_FRAGMENT,
    };
    SDL_GPUDevice*      d     = osdl_live(device);
    SDL_GPUShaderFormat flags = osdl_gpu_format_bits[Int_val(format)];
    const char*         name  = Is_long(entrypoint) ? "main" : osdl_cstring(Some_val(entrypoint));
    size_t              size  = caml_string_length(code);
    if (!(flags & SDL_GetGPUShaderFormats(d)))
        caml_invalid_argument("The GPU device does not support this shader format");
    if (!*name) caml_invalid_argument("The shader entry point must not be empty");
    if (!size) caml_invalid_argument("The shader code must not be empty");
    if (flags == SDL_GPU_SHADERFORMAT_SPIRV && (size < 5 * sizeof(Uint32) || size % sizeof(Uint32)))
        caml_invalid_argument("SPIR-V code must include a header and whole 32-bit words");

    SDL_GPUShaderCreateInfo info = {
        .code_size  = size,
        .code       = (const Uint8*)String_val(code),
        .entrypoint = name,
        .format     = flags,
        .stage      = stages[Int_val(stage)],
    };
    SDL_GPUShader* shader = SDL_CreateGPUShader(d, &info);
    CAMLreturn(osdl_publish(handle, shader, "SDL_CreateGPUShader"));
}

CAMLprim value osdl_gpu_release_shader(value shader) {
    SDL_GPUShader* ptr = osdl_take(shader);
    if (ptr) SDL_ReleaseGPUShader(osdl_gpu_parent_device(shader), ptr);
    return Val_unit;
}

CAMLprim value osdl_gpu_create_swapchain_pipeline(value claim, value vertex, value fragment,
                                                  value primitive) {
    CAMLparam4(claim, vertex, fragment, primitive);
    CAMLlocal2(cell, pipeline);

    /* The third field holds the pixel format, not a reference to the claim. */
    cell     = osdl_new_cell(osdl_parent(claim), &osdl_handle_ops);
    pipeline = caml_alloc_3(0, cell, osdl_parent(claim), Val_unit);

    /* Sdl3.Gpu.primitive constructor order. */
    static const SDL_GPUPrimitiveType primitives[] = {
        SDL_GPU_PRIMITIVETYPE_TRIANGLELIST, SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
        SDL_GPU_PRIMITIVETYPE_LINELIST,     SDL_GPU_PRIMITIVETYPE_LINESTRIP,
        SDL_GPU_PRIMITIVETYPE_POINTLIST,
    };
    SDL_Window*    w  = osdl_live(claim);
    SDL_GPUShader* vs = osdl_live(vertex);
    SDL_GPUShader* fs = osdl_live(fragment);
    if (osdl_parent(claim) != osdl_parent(vertex) || osdl_parent(claim) != osdl_parent(fragment))
        caml_invalid_argument("Use shaders from the GPU device that claimed the window");

    SDL_GPUDevice*       d      = osdl_gpu_parent_device(claim);
    SDL_GPUTextureFormat format = SDL_GetGPUSwapchainTextureFormat(d, w);
    if (format == SDL_GPU_TEXTUREFORMAT_INVALID) osdl_fail("SDL_GetGPUSwapchainTextureFormat");
    Store_field(pipeline, 2, Val_int(format));

    SDL_GPUColorTargetDescription target = {.format = format};

    SDL_GPUGraphicsPipelineCreateInfo info = {
        .vertex_shader     = vs,
        .fragment_shader   = fs,
        .primitive_type    = primitives[Int_val(primitive)],
        .rasterizer_state  = {.fill_mode         = SDL_GPU_FILLMODE_FILL,
                              .cull_mode         = SDL_GPU_CULLMODE_NONE,
                              .enable_depth_clip = true},
        .multisample_state = {.sample_count = SDL_GPU_SAMPLECOUNT_1},
        .target_info       = {.color_target_descriptions = &target, .num_color_targets = 1},
    };
    SDL_GPUGraphicsPipeline* ptr = SDL_CreateGPUGraphicsPipeline(d, &info);
    CAMLreturn(osdl_publish(pipeline, ptr, "SDL_CreateGPUGraphicsPipeline"));
}

CAMLprim value osdl_gpu_release_graphics_pipeline(value pipeline) {
    SDL_GPUGraphicsPipeline* ptr = osdl_take(pipeline);
    if (ptr) SDL_ReleaseGPUGraphicsPipeline(osdl_gpu_parent_device(pipeline), ptr);
    return Val_unit;
}

/* Command buffers and fences. */

CAMLprim value osdl_gpu_acquire_command_buffer(value device) {
    CAMLparam1(device);
    CAMLlocal2(cell, buffer);

    /* The third field keeps the window claim live after image acquisition. */
    cell   = osdl_new_cell(device, &osdl_handle_ops);
    buffer = caml_alloc_3(0, cell, device, Val_unit);

    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(osdl_live(device));
    CAMLreturn(osdl_publish(buffer, commands, "SDL_AcquireGPUCommandBuffer"));
}

static value osdl_gpu_command_claim(value buffer) {
    return Field(buffer, 2);
}

/* SDL consumes a command buffer on submission, even if the call fails. */
static SDL_GPUCommandBuffer* osdl_gpu_take_live_commands(value buffer) {
    SDL_GPUCommandBuffer* commands = osdl_take(buffer);
    if (!commands) caml_invalid_argument("SDL handle is closed");

    value claim = osdl_gpu_command_claim(buffer);
    if (claim != Val_unit) {
        --osdl_cell_val(claim)->children;
        Store_field(buffer, 2, Val_unit);
    }
    return commands;
}

CAMLprim value osdl_gpu_submit_command_buffer(value buffer) {
    SDL_GPUCommandBuffer* commands = osdl_gpu_take_live_commands(buffer);
    osdl_check(SDL_SubmitGPUCommandBuffer(commands), "SDL_SubmitGPUCommandBuffer");
    return Val_unit;
}

CAMLprim value osdl_gpu_submit_and_acquire_fence(value buffer) {
    CAMLparam1(buffer);
    CAMLlocal1(fence);

    fence = osdl_new_handle(osdl_parent(buffer));

    SDL_GPUCommandBuffer* commands = osdl_gpu_take_live_commands(buffer);
    SDL_GPUFence*         ptr      = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    CAMLreturn(osdl_publish(fence, ptr, "SDL_SubmitGPUCommandBufferAndAcquireFence"));
}

CAMLprim value osdl_gpu_cancel_command_buffer(value buffer) {
    osdl_require_thread(osdl_cell_thread(osdl_cell_val(buffer)));
    if (osdl_gpu_command_claim(buffer) != Val_unit)
        caml_invalid_argument("Submit the GPU command buffer after acquiring a window image");

    SDL_GPUCommandBuffer* commands = osdl_take(buffer);
    if (commands) osdl_check(SDL_CancelGPUCommandBuffer(commands), "SDL_CancelGPUCommandBuffer");
    return Val_unit;
}

CAMLprim value osdl_gpu_fence_signaled(value fence) {
    SDL_GPUFence* ptr = osdl_live(fence);
    return Val_bool(SDL_QueryGPUFence(osdl_gpu_parent_device(fence), ptr));
}

CAMLprim value osdl_gpu_wait_fence(value fence) {
    CAMLparam1(fence);

    SDL_GPUFence*  ptr = osdl_live(fence);
    SDL_GPUDevice* d   = osdl_gpu_parent_device(fence);

    caml_enter_blocking_section_no_pending();
    bool ok = SDL_WaitForGPUFences(d, true, &ptr, 1);
    caml_leave_blocking_section();

    osdl_check(ok, "SDL_WaitForGPUFences");
    CAMLreturn(Val_unit);
}

CAMLprim value osdl_gpu_release_fence(value fence) {
    SDL_GPUFence* ptr = osdl_take(fence);
    if (ptr) SDL_ReleaseGPUFence(osdl_gpu_parent_device(fence), ptr);
    return Val_unit;
}

/* Swapchain render passes. */

static bool osdl_gpu_wait_for_image(SDL_GPUCommandBuffer* commands, SDL_Window* window,
                                    SDL_GPUTexture** image) {
    caml_enter_blocking_section_no_pending();
    bool ok = SDL_WaitAndAcquireGPUSwapchainTexture(commands, window, image, NULL, NULL);
    caml_leave_blocking_section();
    return ok;
}

static SDL_GPURenderPass* osdl_gpu_begin_clear_pass(SDL_GPUCommandBuffer* commands,
                                                    SDL_GPUTexture* image, SDL_Color color) {
    SDL_GPUColorTargetInfo target = {
        .texture     = image,
        .clear_color = {color.r / 255.0f, color.g / 255.0f, color.b / 255.0f, color.a / 255.0f},
        .load_op     = SDL_GPU_LOADOP_CLEAR,
        .store_op    = SDL_GPU_STOREOP_STORE,
    };
    return SDL_BeginGPURenderPass(commands, &target, 1, NULL);
}

CAMLnoret static void osdl_gpu_fail_frame(SDL_GPUCommandBuffer* commands, bool has_image,
                                          const char* fn) {
    char message[1024];
    osdl_error_message(message, sizeof(message), fn);

    /* SDL forbids cancellation once a swapchain image is acquired. */
    if (has_image)
        SDL_SubmitGPUCommandBuffer(commands);
    else
        SDL_CancelGPUCommandBuffer(commands);
    osdl_raise_error(message);
}

CAMLprim value osdl_gpu_begin_swapchain_render_pass(value buffer, value claim, value color) {
    CAMLparam3(buffer, claim, color);
    CAMLlocal3(cell, pass, result);

    /* Fields 2 and 3 hold the target format and the bound pipeline. */
    cell   = osdl_new_cell(buffer, &osdl_handle_ops);
    pass   = caml_alloc_4(0, cell, buffer, Val_unit, Val_unit);
    result = caml_alloc_some(pass);

    SDL_GPUCommandBuffer* commands = osdl_live(buffer);
    if (osdl_cell_val(buffer)->children) caml_invalid_argument("End the active GPU pass first");
    if (osdl_gpu_command_claim(buffer) != Val_unit)
        caml_invalid_argument("The GPU command buffer already holds a window image");

    SDL_Window* w = osdl_gpu_available_window(claim);
    if (osdl_parent(buffer) != osdl_parent(claim))
        caml_invalid_argument("Use the GPU device that claimed the window");

    SDL_GPUTexture* image = NULL;
    if (!osdl_gpu_wait_for_image(commands, w, &image))
        osdl_gpu_fail_frame(osdl_gpu_take_live_commands(buffer), image != NULL,
                            "SDL_WaitAndAcquireGPUSwapchainTexture");
    if (!image) CAMLreturn(Val_none);

    SDL_GPUTextureFormat format =
        SDL_GetGPUSwapchainTextureFormat(osdl_gpu_parent_device(claim), w);
    if (format == SDL_GPU_TEXTUREFORMAT_INVALID)
        osdl_gpu_fail_frame(osdl_gpu_take_live_commands(buffer), true,
                            "SDL_GetGPUSwapchainTextureFormat");
    Store_field(pass, 2, Val_int(format));

    SDL_GPURenderPass* ptr = osdl_gpu_begin_clear_pass(commands, image, osdl_color(color));
    if (!ptr)
        osdl_gpu_fail_frame(osdl_gpu_take_live_commands(buffer), true, "SDL_BeginGPURenderPass");

    Store_field(buffer, 2, claim);
    ++osdl_cell_val(claim)->children;
    osdl_publish(pass, ptr, "SDL_BeginGPURenderPass");
    CAMLreturn(result);
}

CAMLprim value osdl_gpu_bind_graphics_pipeline(value pass, value pipeline) {
    SDL_GPURenderPass*       p   = osdl_live(pass);
    SDL_GPUGraphicsPipeline* ptr = osdl_live(pipeline);
    if (osdl_parent(osdl_parent(pass)) != osdl_parent(pipeline))
        caml_invalid_argument("Use a pipeline from the render pass's GPU device");
    if (Field(pass, 2) != Field(pipeline, 2))
        caml_invalid_argument("Use a pipeline that matches the render pass's pixel format");

    SDL_BindGPUGraphicsPipeline(p, ptr);
    Store_field(pass, 3, pipeline);
    return Val_unit;
}

static Uint32 osdl_gpu_draw_count(value v) {
    intnat n = Long_val(v);
    if (n <= 0 || (uintnat)(Uint32)n != (uintnat)n)
        caml_invalid_argument("GPU draw counts must be in [1, 4294967295]");
    return (Uint32)n;
}

CAMLprim value osdl_gpu_draw_primitives(value instances, value pass, value vertices) {
    SDL_GPURenderPass* p        = osdl_live(pass);
    value              pipeline = Field(pass, 3);
    if (pipeline == Val_unit || !osdl_cell_val(pipeline)->ptr)
        caml_invalid_argument("Bind a live GPU graphics pipeline before drawing");

    Uint32 count = osdl_gpu_draw_count(vertices);
    Uint32 reps  = Is_long(instances) ? 1 : osdl_gpu_draw_count(Some_val(instances));

    SDL_DrawGPUPrimitives(p, count, reps, 0, 0);
    return Val_unit;
}

CAMLprim value osdl_gpu_end_render_pass(value pass) {
    SDL_GPURenderPass* ptr = osdl_take(pass);
    if (ptr) {
        SDL_EndGPURenderPass(ptr);
        Store_field(pass, 3, Val_unit);
    }
    return Val_unit;
}

CAMLprim value osdl_gpu_clear_and_present(value claim, value color) {
    CAMLparam2(claim, color);

    SDL_Window*    w = osdl_gpu_available_window(claim);
    SDL_GPUDevice* d = osdl_gpu_parent_device(claim);

    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(d);
    if (!commands) osdl_fail("SDL_AcquireGPUCommandBuffer");

    SDL_GPUTexture* image = NULL;
    if (!osdl_gpu_wait_for_image(commands, w, &image))
        osdl_gpu_fail_frame(commands, image != NULL, "SDL_WaitAndAcquireGPUSwapchainTexture");
    if (!image) {
        osdl_check(SDL_CancelGPUCommandBuffer(commands), "SDL_CancelGPUCommandBuffer");
        CAMLreturn(Val_false);
    }

    SDL_GPURenderPass* pass = osdl_gpu_begin_clear_pass(commands, image, osdl_color(color));
    if (!pass) osdl_gpu_fail_frame(commands, true, "SDL_BeginGPURenderPass");
    SDL_EndGPURenderPass(pass);
    osdl_check(SDL_SubmitGPUCommandBuffer(commands), "SDL_SubmitGPUCommandBuffer");
    CAMLreturn(Val_true);
}
