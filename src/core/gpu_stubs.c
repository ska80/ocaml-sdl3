#include "gpu_render_pass.h"

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

/* GPU sizes and offsets. */

static Uint32 osdl_gpu_uint32(value v, const char* error) {
    intnat n = Long_val(v);
    if (n < 0 || (uintnat)(Uint32)n != (uintnat)n) caml_invalid_argument(error);
    return (Uint32)n;
}

static Uint32 osdl_gpu_offset(value offset) {
    return Is_long(offset) ? 0 : osdl_gpu_uint32(Some_val(offset), "GPU offset is out of range");
}

/* macOS Metal requires four-byte copy offsets and lengths. */
static Uint32 osdl_gpu_aligned_size(value size) {
    const char* error = "GPU byte sizes must be positive multiples of four and fit in 32 bits";
    Uint32      bytes = osdl_gpu_uint32(size, error);
    if (!bytes || bytes % 4) caml_invalid_argument(error);
    return bytes;
}

static bool osdl_gpu_range_fits(Uint32 offset, Uint32 size, Uint32 limit) {
    return offset <= limit && size <= limit - offset;
}

/* Vertex, index, and upload buffers. */

enum {
    GPU_BUFFER_CAPACITY = 2,
    GPU_INDEX_WIDTH     = 3,
    GPU_UPLOAD_WRITTEN  = 3,
};

static Uint32 osdl_gpu_capacity(value buffer) {
    return Long_val(Field(buffer, GPU_BUFFER_CAPACITY));
}

static value osdl_gpu_create_buffer(value device, value size, SDL_GPUBufferUsageFlags usage,
                                    Uint32 index_width) {
    CAMLparam2(device, size);
    CAMLlocal2(cell, handle);

    cell   = osdl_new_cell(device, &osdl_handle_ops);
    handle = caml_alloc_4(0, cell, device, size, Val_int(index_width));

    SDL_GPUDevice*          d    = osdl_live(device);
    SDL_GPUBufferCreateInfo info = {.usage = usage, .size = osdl_gpu_aligned_size(size)};

    SDL_GPUBuffer* buffer = SDL_CreateGPUBuffer(d, &info);
    CAMLreturn(osdl_publish(handle, buffer, "SDL_CreateGPUBuffer"));
}

CAMLprim value osdl_gpu_create_vertex_buffer(value device, value size) {
    return osdl_gpu_create_buffer(device, size, SDL_GPU_BUFFERUSAGE_VERTEX, 0);
}

CAMLprim value osdl_gpu_create_index_buffer(value device, value format, value size) {
    /* Sdl3.Gpu.index_format: Uint16 | Uint32. */
    Uint32 width = Int_val(format) == 0 ? 2 : 4;
    return osdl_gpu_create_buffer(device, size, SDL_GPU_BUFFERUSAGE_INDEX, width);
}

CAMLprim value osdl_gpu_release_buffer(value buffer) {
    SDL_GPUBuffer* ptr = osdl_take(buffer);
    if (ptr) SDL_ReleaseGPUBuffer(osdl_gpu_parent_device(buffer), ptr);
    return Val_unit;
}

CAMLprim value osdl_gpu_create_upload_buffer(value device, value size) {
    CAMLparam2(device, size);
    CAMLlocal2(cell, handle);

    cell   = osdl_new_cell(device, &osdl_handle_ops);
    handle = caml_alloc_4(0, cell, device, size, Val_int(0));

    SDL_GPUDevice*                  d    = osdl_live(device);
    SDL_GPUTransferBufferCreateInfo info = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                                            .size  = osdl_gpu_aligned_size(size)};

    SDL_GPUTransferBuffer* buffer = SDL_CreateGPUTransferBuffer(d, &info);
    CAMLreturn(osdl_publish(handle, buffer, "SDL_CreateGPUTransferBuffer"));
}

CAMLprim value osdl_gpu_write_upload_buffer(value upload, value data) {
    SDL_GPUTransferBuffer* ptr  = osdl_live(upload);
    SDL_GPUDevice*         d    = osdl_gpu_parent_device(upload);
    intnat                 size = Caml_ba_array_val(data)->dim[0];
    if (size <= 0 || (uintnat)size > osdl_gpu_capacity(upload))
        caml_invalid_argument("GPU upload data must be nonempty and fit in the upload buffer");

    /* Do not change storage that an earlier recorded copy still reads. */
    Store_field(upload, GPU_UPLOAD_WRITTEN, Val_int(0));
    void* mapped = SDL_MapGPUTransferBuffer(d, ptr, true);
    if (!mapped) osdl_fail("SDL_MapGPUTransferBuffer");
    memcpy(mapped, Caml_ba_data_val(data), (size_t)size);
    SDL_UnmapGPUTransferBuffer(d, ptr);
    Store_field(upload, GPU_UPLOAD_WRITTEN, Val_long(size));
    return Val_unit;
}

CAMLprim value osdl_gpu_release_upload_buffer(value upload) {
    SDL_GPUTransferBuffer* ptr = osdl_take(upload);
    if (ptr) SDL_ReleaseGPUTransferBuffer(osdl_gpu_parent_device(upload), ptr);
    return Val_unit;
}

/* Sampled textures and samplers. */

enum {
    GPU_TEXTURE_WIDTH = 2,
    GPU_TEXTURE_HEIGHT,
};

CAMLprim value osdl_gpu_create_sampled_texture(value device, value width, value height) {
    CAMLparam3(device, width, height);
    CAMLlocal2(cell, handle);

    cell   = osdl_new_cell(device, &osdl_handle_ops);
    handle = caml_alloc_4(0, cell, device, width, height);

    SDL_GPUDevice* d = osdl_live(device);
    intnat         w = Long_val(width), h = Long_val(height);
    if (w < 1 || h < 1 || w > 16384 || h > 16384)
        caml_invalid_argument("GPU texture width and height must be in [1, 16384]");

    SDL_GPUTextureCreateInfo info = {
        .type                 = SDL_GPU_TEXTURETYPE_2D,
        .format               = SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage                = SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width                = (Uint32)w,
        .height               = (Uint32)h,
        .layer_count_or_depth = 1,
        .num_levels           = 1,
        .sample_count         = SDL_GPU_SAMPLECOUNT_1,
    };
    SDL_GPUTexture* texture = SDL_CreateGPUTexture(d, &info);
    CAMLreturn(osdl_publish(handle, texture, "SDL_CreateGPUTexture"));
}

CAMLprim value osdl_gpu_release_texture(value texture) {
    SDL_GPUTexture* ptr = osdl_take(texture);
    if (ptr) SDL_ReleaseGPUTexture(osdl_gpu_parent_device(texture), ptr);
    return Val_unit;
}

CAMLprim value osdl_gpu_create_sampler(value device, value filter) {
    CAMLparam2(device, filter);
    CAMLlocal1(handle);

    handle = osdl_new_handle(device);

    /* Sdl3.Gpu.sampler_filter: Nearest | Linear. */
    SDL_GPUDevice* d    = osdl_live(device);
    SDL_GPUFilter  mode = Int_val(filter) == 0 ? SDL_GPU_FILTER_NEAREST : SDL_GPU_FILTER_LINEAR;

    SDL_GPUSamplerCreateInfo info = {
        .min_filter     = mode,
        .mag_filter     = mode,
        .mipmap_mode    = SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .max_anisotropy = 1.0f,
        .compare_op     = SDL_GPU_COMPAREOP_NEVER,
    };
    SDL_GPUSampler* sampler = SDL_CreateGPUSampler(d, &info);
    CAMLreturn(osdl_publish(handle, sampler, "SDL_CreateGPUSampler"));
}

CAMLprim value osdl_gpu_release_sampler(value sampler) {
    SDL_GPUSampler* ptr = osdl_take(sampler);
    if (ptr) SDL_ReleaseGPUSampler(osdl_gpu_parent_device(sampler), ptr);
    return Val_unit;
}

/* Shaders and graphics pipelines. */

/* Sdl3.Gpu.shader_stage constructor order. */
enum { GPU_VERTEX, GPU_FRAGMENT };

enum {
    GPU_SHADER_SAMPLERS = 2,
    GPU_SHADER_UNIFORMS,
    GPU_MAX_SAMPLERS      = 16,
    GPU_MAX_UNIFORMS      = 4,
    /* SDL's Vulkan backend uses a 4 KiB descriptor range for each uniform slot. */
    GPU_MAX_UNIFORM_BYTES = 4096,
};

static int osdl_gpu_shader_count(value count, int max, const char* error) {
    intnat n = Is_long(count) ? 0 : Long_val(Some_val(count));
    if (n < 0 || n > max) caml_invalid_argument(error);
    return (int)n;
}

CAMLprim value osdl_gpu_create_shader(value device, value stage, value format, value entrypoint,
                                      value samplers, value uniforms, value code) {
    CAMLparam5(device, stage, format, entrypoint, samplers);
    CAMLxparam2(uniforms, code);
    CAMLlocal2(cell, handle);

    int sampler_count = osdl_gpu_shader_count(samplers, GPU_MAX_SAMPLERS,
                                              "GPU shader sampler count must be in [0, 16]");
    int uniform_count = osdl_gpu_shader_count(uniforms, GPU_MAX_UNIFORMS,
                                              "GPU shader uniform buffer count must be in [0, 4]");
    cell              = osdl_new_cell(device, &osdl_handle_ops);
    handle = caml_alloc_4(0, cell, device, Val_int(sampler_count), Val_int(uniform_count));

    static const SDL_GPUShaderStage stages[] = {
        [GPU_VERTEX]   = SDL_GPU_SHADERSTAGE_VERTEX,
        [GPU_FRAGMENT] = SDL_GPU_SHADERSTAGE_FRAGMENT,
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
        .code_size           = size,
        .code                = (const Uint8*)String_val(code),
        .entrypoint          = name,
        .format              = flags,
        .stage               = stages[Int_val(stage)],
        .num_samplers        = (Uint32)sampler_count,
        .num_uniform_buffers = (Uint32)uniform_count,
    };
    SDL_GPUShader* shader = SDL_CreateGPUShader(d, &info);
    CAMLreturn(osdl_publish(handle, shader, "SDL_CreateGPUShader"));
}

CAMLprim value osdl_gpu_create_shader_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_create_shader(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

CAMLprim value osdl_gpu_release_shader(value shader) {
    SDL_GPUShader* ptr = osdl_take(shader);
    if (ptr) SDL_ReleaseGPUShader(osdl_gpu_parent_device(shader), ptr);
    return Val_unit;
}

enum {
    GPU_PIPELINE_FORMAT = 2,
    GPU_PIPELINE_STRIDE,
    GPU_PIPELINE_VERTEX_SAMPLERS,
    GPU_PIPELINE_FRAGMENT_SAMPLERS,
    GPU_PIPELINE_UNIFORM_MASK,
    GPU_MAX_VERTEX_ATTRIBUTES = 16,
};

static Uint32 osdl_gpu_vertex_attributes(value layout, SDL_GPUVertexBufferDescription* buffer,
                                         SDL_GPUVertexAttribute* attributes) {
    if (Is_long(layout)) return 0;

    /* Sdl3.Gpu.vertex_format constructor order. All formats use 4-byte alignment. */
    static const struct {
        SDL_GPUVertexElementFormat format;
        Uint32                     bytes;
    } formats[] = {
        {SDL_GPU_VERTEXELEMENTFORMAT_FLOAT,       4 },
        {SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,      8 },
        {SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,      12},
        {SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,      16},
        {SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM, 4 },
    };

    /* Sdl3.Gpu.vertex_layout: stride, attributes. */
    value  spec   = Some_val(layout);
    Uint32 stride = osdl_gpu_aligned_size(Field(spec, 0));
    if (stride > 2048) caml_invalid_argument("GPU vertex stride must be at most 2048 bytes");

    Uint32 count = 0, used = 0;
    for (value list = Field(spec, 1); list != Val_emptylist; list = Field(list, 1)) {
        /* Sdl3.Gpu.vertex_attribute: location, format, offset. */
        value  attr     = Field(list, 0);
        intnat location = Long_val(Field(attr, 0));
        int    format   = Int_val(Field(attr, 1));
        Uint32 offset   = osdl_gpu_uint32(Field(attr, 2), "GPU attribute offset is out of range");
        if (location < 0 || location >= GPU_MAX_VERTEX_ATTRIBUTES)
            caml_invalid_argument("GPU attribute location must be in [0, 15]");
        Uint32 bit = 1u << location;
        if (used & bit) caml_invalid_argument("GPU attribute locations must be unique");
        if (offset % 4 || !osdl_gpu_range_fits(offset, formats[format].bytes, stride))
            caml_invalid_argument("Align the GPU attribute to four bytes and fit it in the stride");
        used |= bit;
        attributes[count++] = (SDL_GPUVertexAttribute){
            .location = (Uint32)location, .format = formats[format].format, .offset = offset};
    }
    if (!count) caml_invalid_argument("Supply at least one GPU vertex attribute");
    *buffer = (SDL_GPUVertexBufferDescription){.pitch      = stride,
                                               .input_rate = SDL_GPU_VERTEXINPUTRATE_VERTEX};
    return count;
}

CAMLprim value osdl_gpu_create_swapchain_pipeline(value layout, value claim, value vertex,
                                                  value fragment, value primitive) {
    CAMLparam5(layout, claim, vertex, fragment, primitive);
    CAMLlocal2(cell, pipeline);

    /* Keep the resource counts after the shader handles are released. */
    unsigned vertex_uniforms   = (1u << Int_val(Field(vertex, GPU_SHADER_UNIFORMS))) - 1;
    unsigned fragment_uniforms = (1u << Int_val(Field(fragment, GPU_SHADER_UNIFORMS))) - 1;
    unsigned mask              = vertex_uniforms | (fragment_uniforms << GPU_MAX_UNIFORMS);
    cell                       = osdl_new_cell(osdl_parent(claim), &osdl_handle_ops);
    pipeline                   = caml_alloc_7(0, cell, osdl_parent(claim), Val_unit, Val_int(0),
                                              Field(vertex, GPU_SHADER_SAMPLERS),
                                              Field(fragment, GPU_SHADER_SAMPLERS), Val_int(mask));

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

    SDL_GPUVertexBufferDescription vertex_buffer = {0};
    SDL_GPUVertexAttribute         attributes[GPU_MAX_VERTEX_ATTRIBUTES];
    Uint32 count = osdl_gpu_vertex_attributes(layout, &vertex_buffer, attributes);

    SDL_GPUDevice*       d      = osdl_gpu_parent_device(claim);
    SDL_GPUTextureFormat format = SDL_GetGPUSwapchainTextureFormat(d, w);
    if (format == SDL_GPU_TEXTUREFORMAT_INVALID) osdl_fail("SDL_GetGPUSwapchainTextureFormat");
    Store_field(pipeline, GPU_PIPELINE_FORMAT, Val_int(format));
    Store_field(pipeline, GPU_PIPELINE_STRIDE, Val_int(vertex_buffer.pitch));

    SDL_GPUColorTargetDescription target = {.format = format};

    SDL_GPUGraphicsPipelineCreateInfo info = {
        .vertex_shader      = vs,
        .fragment_shader    = fs,
        .vertex_input_state = {.vertex_buffer_descriptions = count ? &vertex_buffer : NULL,
                               .num_vertex_buffers         = count ? 1 : 0,
                               .vertex_attributes          = count ? attributes : NULL,
                               .num_vertex_attributes      = count},
        .primitive_type     = primitives[Int_val(primitive)],
        .rasterizer_state   = {.fill_mode         = SDL_GPU_FILLMODE_FILL,
                               .cull_mode         = SDL_GPU_CULLMODE_NONE,
                               .enable_depth_clip = true},
        .multisample_state  = {.sample_count = SDL_GPU_SAMPLECOUNT_1},
        .target_info        = {.color_target_descriptions = &target, .num_color_targets = 1},
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

enum {
    GPU_COMMAND_CLAIM = 2,
    GPU_COMMAND_UNIFORMS,
};

CAMLprim value osdl_gpu_acquire_command_buffer(value device) {
    CAMLparam1(device);
    CAMLlocal2(cell, buffer);

    /* The third field keeps the window claim live after image acquisition. */
    cell   = osdl_new_cell(device, &osdl_handle_ops);
    buffer = caml_alloc_4(0, cell, device, Val_unit, Val_int(0));

    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(osdl_live(device));
    CAMLreturn(osdl_publish(buffer, commands, "SDL_AcquireGPUCommandBuffer"));
}

static value osdl_gpu_command_claim(value buffer) {
    return Field(buffer, GPU_COMMAND_CLAIM);
}

static SDL_GPUCommandBuffer* osdl_gpu_commands_without_pass(value buffer) {
    SDL_GPUCommandBuffer* ptr = osdl_live(buffer);
    if (osdl_cell_val(buffer)->children) caml_invalid_argument("End the active GPU pass first");
    return ptr;
}

static value osdl_gpu_pass_device(value pass) {
    return osdl_parent(osdl_parent(pass));
}

CAMLprim value osdl_gpu_push_uniform_data(value buffer, value stage, value slot, value data) {
    SDL_GPUCommandBuffer* commands = osdl_live(buffer);
    intnat                index = Long_val(slot), size = Caml_ba_array_val(data)->dim[0];
    if (index < 0 || index >= GPU_MAX_UNIFORMS)
        caml_invalid_argument("GPU uniform slot must be in [0, 3]");
    if (size <= 0 || size > GPU_MAX_UNIFORM_BYTES || size % 4)
        caml_invalid_argument("GPU uniform data must be 4 to 4096 bytes and a multiple of four");

    const void* bytes = Caml_ba_data_val(data);
    if (Int_val(stage) == GPU_VERTEX)
        SDL_PushGPUVertexUniformData(commands, (Uint32)index, bytes, (Uint32)size);
    else
        SDL_PushGPUFragmentUniformData(commands, (Uint32)index, bytes, (Uint32)size);

    unsigned bit = 1u << (index + Int_val(stage) * GPU_MAX_UNIFORMS);
    Store_field(buffer, GPU_COMMAND_UNIFORMS,
                Val_int(Int_val(Field(buffer, GPU_COMMAND_UNIFORMS)) | bit));
    return Val_unit;
}

/* SDL consumes a command buffer on submission, even if the call fails. */
static SDL_GPUCommandBuffer* osdl_gpu_take_live_commands(value buffer) {
    SDL_GPUCommandBuffer* commands = osdl_take(buffer);
    if (!commands) caml_invalid_argument("SDL handle is closed");

    value claim = osdl_gpu_command_claim(buffer);
    if (claim != Val_unit) {
        --osdl_cell_val(claim)->children;
        Store_field(buffer, GPU_COMMAND_CLAIM, Val_unit);
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

/* Copy passes. */

CAMLprim value osdl_gpu_begin_copy_pass(value buffer) {
    CAMLparam1(buffer);
    CAMLlocal1(pass);

    pass = osdl_new_handle(buffer);

    SDL_GPUCommandBuffer* commands = osdl_gpu_commands_without_pass(buffer);

    SDL_GPUCopyPass* ptr = SDL_BeginGPUCopyPass(commands);
    CAMLreturn(osdl_publish(pass, ptr, "SDL_BeginGPUCopyPass"));
}

CAMLprim value osdl_gpu_upload_to_buffer(value src_offset, value dst_offset, value cycle,
                                         value pass, value src, value dst, value size) {
    SDL_GPUCopyPass*       p           = osdl_live(pass);
    SDL_GPUTransferBuffer* source      = osdl_live(src);
    SDL_GPUBuffer*         destination = osdl_live(dst);
    value                  device      = osdl_gpu_pass_device(pass);
    if (osdl_parent(src) != device || osdl_parent(dst) != device)
        caml_invalid_argument("Use upload and destination buffers from the copy pass's GPU device");

    Uint32 start  = osdl_gpu_offset(src_offset);
    Uint32 offset = osdl_gpu_offset(dst_offset);
    Uint32 length = osdl_gpu_aligned_size(size);
    bool   rotate = Is_block(cycle) && Bool_val(Some_val(cycle));
    if (start % 4 || offset % 4)
        caml_invalid_argument("GPU upload offsets must be multiples of four bytes");
    if (!osdl_gpu_range_fits(start, length, Long_val(Field(src, GPU_UPLOAD_WRITTEN))))
        caml_invalid_argument("The copy must fit in the written bytes of the upload buffer");
    if (!osdl_gpu_range_fits(offset, length, osdl_gpu_capacity(dst)))
        caml_invalid_argument("The copy must fit in the destination GPU buffer");
    if (rotate && (offset || length != osdl_gpu_capacity(dst)))
        caml_invalid_argument("A cycling GPU upload must replace the whole destination buffer");

    SDL_GPUTransferBufferLocation from = {.transfer_buffer = source, .offset = start};
    SDL_GPUBufferRegion           to   = {.buffer = destination, .offset = offset, .size = length};
    SDL_UploadToGPUBuffer(p, &from, &to, rotate);
    return Val_unit;
}

CAMLprim value osdl_gpu_upload_to_buffer_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_upload_to_buffer(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

CAMLprim value osdl_gpu_upload_to_texture(value src_offset, value cycle, value pass, value src,
                                          value dst) {
    SDL_GPUCopyPass*       p           = osdl_live(pass);
    SDL_GPUTransferBuffer* source      = osdl_live(src);
    SDL_GPUTexture*        destination = osdl_live(dst);
    value                  device      = osdl_gpu_pass_device(pass);
    if (osdl_parent(src) != device || osdl_parent(dst) != device)
        caml_invalid_argument("Use an upload buffer and texture from the copy pass's GPU device");

    Uint32 start = osdl_gpu_offset(src_offset);
    Uint32 w = Int_val(Field(dst, GPU_TEXTURE_WIDTH)), h = Int_val(Field(dst, GPU_TEXTURE_HEIGHT));
    Uint32 row_bytes = 4 * w;
    bool   rotate    = Is_block(cycle) && Bool_val(Some_val(cycle));
    if (start % 4) caml_invalid_argument("GPU texture upload offsets must be multiples of four");
    if (!osdl_gpu_range_fits(start, row_bytes * h, Long_val(Field(src, GPU_UPLOAD_WRITTEN))))
        caml_invalid_argument(
            "The texture copy must fit in the written bytes of the upload buffer");

    /* Before SDL 3.4.2, D3D12's fallback copies 256 bytes from each narrow row
     * except the last. Make sure the penultimate row has that much storage. */
    if (row_bytes < 128 && h > 1 &&
        !osdl_gpu_range_fits(start, row_bytes * (h - 2) + 256, osdl_gpu_capacity(src)) &&
        SDL_GetVersion() < SDL_VERSIONNUM(3, 4, 2)) {
        const char* driver = SDL_GetGPUDeviceDriver(osdl_cell_val(device)->ptr);
        if (driver && strcmp(driver, "direct3d12") == 0)
            caml_invalid_argument("Leave 256 bytes in the upload buffer from the next-to-last row");
    }

    SDL_GPUTextureTransferInfo from = {.transfer_buffer = source, .offset = start};
    SDL_GPUTextureRegion       to   = {.texture = destination, .w = w, .h = h, .d = 1};
    SDL_UploadToGPUTexture(p, &from, &to, rotate);
    return Val_unit;
}

OSDL_DESTROY(osdl_gpu_end_copy_pass, SDL_GPUCopyPass, SDL_EndGPUCopyPass)

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
    CAMLlocal2(pass, result);

    pass   = osdl_gpu_new_render_pass(buffer);
    result = caml_alloc_some(pass);

    SDL_GPUCommandBuffer* commands = osdl_gpu_commands_without_pass(buffer);
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
    Store_field(pass, GPU_PASS_FORMAT, Val_int(format));

    SDL_GPURenderPass* ptr = osdl_gpu_begin_clear_pass(commands, image, osdl_color(color));
    if (!ptr)
        osdl_gpu_fail_frame(osdl_gpu_take_live_commands(buffer), true, "SDL_BeginGPURenderPass");

    Store_field(buffer, GPU_COMMAND_CLAIM, claim);
    ++osdl_cell_val(claim)->children;
    osdl_publish(pass, ptr, "SDL_BeginGPURenderPass");
    CAMLreturn(result);
}

CAMLprim value osdl_gpu_bind_graphics_pipeline(value pass, value pipeline) {
    CAMLparam2(pass, pipeline);
    CAMLlocal1(slots);

    mlsize_t count = Int_val(Field(pipeline, GPU_PIPELINE_VERTEX_SAMPLERS)) +
                     Int_val(Field(pipeline, GPU_PIPELINE_FRAGMENT_SAMPLERS));
    slots = Field(pass, GPU_PASS_SAMPLERS);
    if (!count)
        slots = Val_unit;
    else if (Is_long(slots) || Wosize_val(slots) != count)
        slots = caml_alloc(count, 0);

    SDL_GPURenderPass*       p   = osdl_live(pass);
    SDL_GPUGraphicsPipeline* ptr = osdl_live(pipeline);
    if (osdl_gpu_pass_device(pass) != osdl_parent(pipeline))
        caml_invalid_argument("Use a pipeline from the render pass's GPU device");
    if (Field(pass, GPU_PASS_FORMAT) != Field(pipeline, GPU_PIPELINE_FORMAT))
        caml_invalid_argument("Use a pipeline that matches the render pass's pixel format");

    SDL_BindGPUGraphicsPipeline(p, ptr);
    Store_field(pass, GPU_PASS_PIPELINE, pipeline);
    /* Rebind vertex data and samplers against the current pipeline. */
    Store_field(pass, GPU_PASS_VERTEX_BUFFER, Val_unit);
    for (mlsize_t i = 0; i < count; ++i)
        Store_field(slots, i, Val_unit);
    Store_field(pass, GPU_PASS_SAMPLERS, slots);
    CAMLreturn(Val_unit);
}

/* Check the pass first. Only its device's resources can be bound. */
static value osdl_gpu_bound(value pass, int field, const char* error) {
    value handle = Field(pass, field);
    if (handle == Val_unit || !osdl_cell_val(handle)->ptr) caml_invalid_argument(error);
    return handle;
}

static value osdl_gpu_bound_pipeline(value pass) {
    return osdl_gpu_bound(pass, GPU_PASS_PIPELINE, "Bind a live GPU graphics pipeline first");
}

CAMLprim value osdl_gpu_bind_samplers(value first_slot, value pass, value stage, value bindings) {
    SDL_GPURenderPass* p        = osdl_live(pass);
    value              pipeline = osdl_gpu_bound_pipeline(pass);
    bool               vertex   = Int_val(stage) == GPU_VERTEX;
    int                limit    = Int_val(
        Field(pipeline, vertex ? GPU_PIPELINE_VERTEX_SAMPLERS : GPU_PIPELINE_FRAGMENT_SAMPLERS));
    intnat   start = Is_long(first_slot) ? 0 : Long_val(Some_val(first_slot));
    mlsize_t count = Wosize_val(bindings);
    if (start < 0 || start > limit || count > (mlsize_t)(limit - start))
        caml_invalid_argument("Sampler bindings must fit in the GPU shader's declared slots");
    if (!count) return Val_unit;

    value                        device = osdl_gpu_pass_device(pass);
    SDL_GPUTextureSamplerBinding native[GPU_MAX_SAMPLERS];
    value                        pairs[GPU_MAX_SAMPLERS];
    for (mlsize_t i = 0; i < count; ++i) {
        value           pair = Field(bindings, i);
        value           tex = Field(pair, 0), sampler = Field(pair, 1);
        SDL_GPUTexture* t = osdl_live(tex);
        SDL_GPUSampler* s = osdl_live(sampler);
        if (osdl_parent(tex) != device || osdl_parent(sampler) != device)
            caml_invalid_argument("Use textures and samplers from the render pass's GPU device");
        native[i] = (SDL_GPUTextureSamplerBinding){.texture = t, .sampler = s};
        pairs[i]  = pair;
    }

    if (vertex)
        SDL_BindGPUVertexSamplers(p, (Uint32)start, native, (Uint32)count);
    else
        SDL_BindGPUFragmentSamplers(p, (Uint32)start, native, (Uint32)count);

    /* Keep the pairs, not the caller's mutable array. */
    value    slots = Field(pass, GPU_PASS_SAMPLERS);
    mlsize_t base  = vertex ? 0 : Int_val(Field(pipeline, GPU_PIPELINE_VERTEX_SAMPLERS));
    for (mlsize_t i = 0; i < count; ++i)
        Store_field(slots, base + start + i, pairs[i]);
    return Val_unit;
}

CAMLprim value osdl_gpu_bind_vertex_buffer(value offset, value pass, value buffer) {
    SDL_GPURenderPass* p      = osdl_live(pass);
    SDL_GPUBuffer*     ptr    = osdl_live(buffer);
    Uint32             stride = Int_val(Field(osdl_gpu_bound_pipeline(pass), GPU_PIPELINE_STRIDE));
    Uint32             start  = osdl_gpu_offset(offset);
    Uint32             size   = osdl_gpu_capacity(buffer);
    if (osdl_gpu_pass_device(pass) != osdl_parent(buffer))
        caml_invalid_argument("Use a vertex buffer from the render pass's GPU device");
    if (!stride) caml_invalid_argument("The GPU pipeline does not use a vertex buffer");
    if (start % 4 || !osdl_gpu_range_fits(start, stride, size))
        caml_invalid_argument(
            "Align the vertex buffer offset to four bytes and leave room for a vertex");

    SDL_GPUBufferBinding binding = {.buffer = ptr, .offset = start};
    SDL_BindGPUVertexBuffers(p, 0, &binding, 1);
    Store_field(pass, GPU_PASS_VERTEX_BUFFER, buffer);
    Store_field(pass, GPU_PASS_VERTEX_COUNT, Val_long((size - start) / stride));
    return Val_unit;
}

CAMLprim value osdl_gpu_bind_index_buffer(value offset, value pass, value buffer) {
    SDL_GPURenderPass* p     = osdl_live(pass);
    SDL_GPUBuffer*     ptr   = osdl_live(buffer);
    Uint32             width = Long_val(Field(buffer, GPU_INDEX_WIDTH));
    Uint32             start = osdl_gpu_offset(offset);
    Uint32             size  = osdl_gpu_capacity(buffer);
    if (osdl_gpu_pass_device(pass) != osdl_parent(buffer))
        caml_invalid_argument("Use an index buffer from the render pass's GPU device");
    if (start % width || !osdl_gpu_range_fits(start, width, size))
        caml_invalid_argument(
            "Align the index buffer offset to the index width and leave room for an index");

    SDL_GPUBufferBinding    binding = {.buffer = ptr, .offset = start};
    SDL_GPUIndexElementSize format =
        width == 2 ? SDL_GPU_INDEXELEMENTSIZE_16BIT : SDL_GPU_INDEXELEMENTSIZE_32BIT;
    SDL_BindGPUIndexBuffer(p, &binding, format);
    Store_field(pass, GPU_PASS_INDEX_BUFFER, buffer);
    Store_field(pass, GPU_PASS_INDEX_COUNT, Val_long((size - start) / width));
    return Val_unit;
}

static Uint32 osdl_gpu_draw_count(value v) {
    const char* error = "GPU draw counts must be in [1, 4294967295]";
    Uint32      n     = osdl_gpu_uint32(v, error);
    if (!n) caml_invalid_argument(error);
    return n;
}

static Uint32 osdl_gpu_draw_stride(value pass) {
    value pipeline = osdl_gpu_bound_pipeline(pass);
    int   required = Int_val(Field(pipeline, GPU_PIPELINE_UNIFORM_MASK));
    if (required) {
        int provided = Int_val(Field(osdl_parent(pass), GPU_COMMAND_UNIFORMS));
        if ((required & provided) != required)
            caml_invalid_argument("Push data for every declared GPU uniform slot before drawing");
    }

    value slots = Field(pass, GPU_PASS_SAMPLERS);
    if (Is_block(slots)) {
        for (mlsize_t i = 0; i < Wosize_val(slots); ++i) {
            value pair = Field(slots, i);
            if (pair == Val_unit || !osdl_cell_val(Field(pair, 0))->ptr ||
                !osdl_cell_val(Field(pair, 1))->ptr)
                caml_invalid_argument(
                    "Bind a live texture and sampler to each slot before drawing");
        }
    }
    return Int_val(Field(pipeline, GPU_PIPELINE_STRIDE));
}

static void osdl_gpu_require_vertices(value pass, Uint32 stride, Uint32 count) {
    if (!stride) return;
    osdl_gpu_bound(pass, GPU_PASS_VERTEX_BUFFER, "Bind a live GPU vertex buffer before drawing");
    Uint32 available = Long_val(Field(pass, GPU_PASS_VERTEX_COUNT));
    if (count > available) caml_invalid_argument("The draw exceeds the GPU vertex buffer");
}

CAMLprim value osdl_gpu_draw_primitives(value instances, value pass, value vertices) {
    SDL_GPURenderPass* p      = osdl_live(pass);
    Uint32             stride = osdl_gpu_draw_stride(pass);
    Uint32             count  = osdl_gpu_draw_count(vertices);
    Uint32             reps   = Is_long(instances) ? 1 : osdl_gpu_draw_count(Some_val(instances));
    osdl_gpu_require_vertices(pass, stride, count);

    SDL_DrawGPUPrimitives(p, count, reps, 0, 0);
    return Val_unit;
}

CAMLprim value osdl_gpu_draw_indexed_primitives(value instances, value first_index, value pass,
                                                value indices) {
    SDL_GPURenderPass* p      = osdl_live(pass);
    Uint32             stride = osdl_gpu_draw_stride(pass);
    Uint32             count  = osdl_gpu_draw_count(indices);
    Uint32             reps   = Is_long(instances) ? 1 : osdl_gpu_draw_count(Some_val(instances));
    Uint32             first  = osdl_gpu_offset(first_index);
    osdl_gpu_require_vertices(pass, stride, 1);
    osdl_gpu_bound(pass, GPU_PASS_INDEX_BUFFER, "Bind a live GPU index buffer before drawing");
    if (!osdl_gpu_range_fits(first, count, Long_val(Field(pass, GPU_PASS_INDEX_COUNT))))
        caml_invalid_argument("The draw exceeds the GPU index buffer");

    SDL_DrawGPUIndexedPrimitives(p, count, reps, first, 0, 0);
    return Val_unit;
}

CAMLprim value osdl_gpu_end_render_pass(value pass) {
    SDL_GPURenderPass* ptr = osdl_take(pass);
    if (ptr) {
        SDL_EndGPURenderPass(ptr);
        Store_field(pass, GPU_PASS_PIPELINE, Val_unit);
        Store_field(pass, GPU_PASS_VERTEX_BUFFER, Val_unit);
        Store_field(pass, GPU_PASS_INDEX_BUFFER, Val_unit);
        Store_field(pass, GPU_PASS_SAMPLERS, Val_unit);
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
