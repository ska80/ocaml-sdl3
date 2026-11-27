#include "gpu_handles.h"

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

    handle = osdl_new_gpu_device(context, true);
    osdl_gpu_require_video(context);
    SDL_GPUShaderFormat flags      = osdl_gpu_format_flags(formats);
    const char*         name       = osdl_gpu_driver_option(driver);
    bool                debug_mode = Is_block(debug) && Bool_val(Some_val(debug));

    SDL_GPUDevice* device = SDL_CreateGPUDevice(flags, debug_mode, name);
    CAMLreturn(osdl_publish(handle, device, "SDL_CreateGPUDevice"));
}

CAMLprim value osdl_gpu_destroy_device(value device) {
    if (!Bool_val(Field(device, GPU_DEVICE_OWNED)))
        caml_invalid_argument("Destroy the renderer that owns this GPU device instead");
    SDL_GPUDevice* ptr = osdl_take(device);
    if (ptr) SDL_DestroyGPUDevice(ptr);
    return Val_unit;
}

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
    CAMLlocal1(mark);

    /* A fresh identity proves completion of earlier submissions without a
     * device-wide list of download buffers or a counter that can wrap. */
    mark = caml_alloc_1(0, Val_unit);

    SDL_GPUDevice* ptr = osdl_live(device);

    /* Do not run an OCaml signal handler between borrowing the device and waiting. */
    caml_enter_blocking_section_no_pending();
    bool ok = SDL_WaitForGPUIdle(ptr);
    caml_leave_blocking_section();

    osdl_check(ok, "SDL_WaitForGPUIdle");
    Store_field(device, GPU_DEVICE_IDLE_MARK, mark);
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

static SDL_GPUTextureFormat osdl_gpu_swapchain_native_format(value claim) {
    SDL_Window*          w = osdl_live(claim);
    SDL_GPUTextureFormat format =
        SDL_GetGPUSwapchainTextureFormat(osdl_gpu_parent_device(claim), w);
    if (format == SDL_GPU_TEXTUREFORMAT_INVALID) osdl_fail("SDL_GetGPUSwapchainTextureFormat");
    return format;
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

static SDL_Rect osdl_gpu_rect(value rect, Uint32 width, Uint32 height, const char* error) {
    Uint32 x = osdl_gpu_uint32(Field(rect, 0), error);
    Uint32 y = osdl_gpu_uint32(Field(rect, 1), error);
    Uint32 w = osdl_gpu_uint32(Field(rect, 2), error);
    Uint32 h = osdl_gpu_uint32(Field(rect, 3), error);
    if (!w || !h || !osdl_gpu_range_fits(x, w, width) || !osdl_gpu_range_fits(y, h, height))
        caml_invalid_argument(error);
    return (SDL_Rect){(int)x, (int)y, (int)w, (int)h};
}

static bool osdl_gpu_cycle(value cycle) {
    return Is_block(cycle) && Bool_val(Some_val(cycle));
}

/* Vertex, index, and transfer buffers. */

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
    uintnat                size = caml_ba_byte_size(Caml_ba_array_val(data));
    if (!size || size > osdl_gpu_capacity(upload))
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

/* A command buffer and its downloads share one batch. A fence can complete
 * that batch but does not own the downloads. No SDL pointer lives in a batch. */
typedef enum {
    GPU_DOWNLOAD_RECORDING,
    GPU_DOWNLOAD_SUBMITTED,
    GPU_DOWNLOAD_READY,
    GPU_DOWNLOAD_CANCELED,
    GPU_DOWNLOAD_FAILED,
} osdl_gpu_download_state;

enum { GPU_DOWNLOAD_STATE, GPU_DOWNLOAD_IDLE_MARK };

enum {
    GPU_DOWNLOAD_BATCH = 3,
    GPU_DOWNLOAD_OFFSET,
    GPU_DOWNLOAD_ROW_BYTES,
    GPU_DOWNLOAD_PITCH,
    GPU_DOWNLOAD_ROWS,
};

static bool osdl_gpu_waited_since_submit(value batch, value device) {
    return Field(batch, GPU_DOWNLOAD_IDLE_MARK) != Field(device, GPU_DEVICE_IDLE_MARK);
}

static osdl_gpu_download_state osdl_gpu_download_status(value download) {
    value batch = Field(download, GPU_DOWNLOAD_BATCH);
    if (batch == Val_unit) return GPU_DOWNLOAD_CANCELED;

    osdl_gpu_download_state state = Int_val(Field(batch, GPU_DOWNLOAD_STATE));
    if ((state == GPU_DOWNLOAD_SUBMITTED || state == GPU_DOWNLOAD_FAILED) &&
        osdl_gpu_waited_since_submit(batch, osdl_parent(download)))
        return state == GPU_DOWNLOAD_SUBMITTED ? GPU_DOWNLOAD_READY : GPU_DOWNLOAD_CANCELED;
    return state;
}

CAMLprim value osdl_gpu_create_download_buffer(value device, value size) {
    CAMLparam2(device, size);
    CAMLlocal2(cell, handle);

    cell   = osdl_new_cell(device, &osdl_handle_ops);
    handle = caml_alloc_8(0, cell, device, size, Val_unit, Val_int(0), Val_int(0), Val_int(0),
                          Val_int(0));

    SDL_GPUDevice*                  d    = osdl_live(device);
    SDL_GPUTransferBufferCreateInfo info = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
                                            .size  = osdl_gpu_aligned_size(size)};

    SDL_GPUTransferBuffer* buffer = SDL_CreateGPUTransferBuffer(d, &info);
    CAMLreturn(osdl_publish(handle, buffer, "SDL_CreateGPUTransferBuffer"));
}

CAMLprim value osdl_gpu_release_download_buffer(value download) {
    SDL_GPUTransferBuffer* ptr = osdl_take(download);
    if (ptr) {
        SDL_ReleaseGPUTransferBuffer(osdl_gpu_parent_device(download), ptr);
        Store_field(download, GPU_DOWNLOAD_BATCH, Val_unit);
    }
    return Val_unit;
}

CAMLprim value osdl_gpu_read_download_buffer(value dst_offset, value pitch, value download,
                                             value data) {
    SDL_GPUTransferBuffer* ptr = osdl_live(download);
    SDL_GPUDevice*         d   = osdl_gpu_parent_device(download);
    if (osdl_gpu_download_status(download) != GPU_DOWNLOAD_READY)
        caml_invalid_argument("Complete a GPU download before reading the buffer");

    size_t row_bytes = Long_val(Field(download, GPU_DOWNLOAD_ROW_BYTES));
    size_t rows      = Long_val(Field(download, GPU_DOWNLOAD_ROWS));
    size_t src_pitch = Long_val(Field(download, GPU_DOWNLOAD_PITCH));
    intnat offset    = Is_long(dst_offset) ? 0 : Long_val(Some_val(dst_offset));
    intnat stride    = Is_long(pitch) ? (intnat)row_bytes : Long_val(Some_val(pitch));
    size_t length    = Caml_ba_array_val(data)->dim[0];
    if (stride < 0 || (size_t)stride < row_bytes)
        caml_invalid_argument("The bigarray pitch must cover a row of downloaded bytes");
    if (offset < 0 || (size_t)offset > length || length - offset < row_bytes ||
        rows - 1 > (length - offset - row_bytes) / (size_t)stride)
        caml_invalid_argument("The GPU download must fit in the destination bigarray");

    /* Nothing can allocate or raise between mapping and unmapping. */
    const Uint8* mapped = SDL_MapGPUTransferBuffer(d, ptr, false);
    if (!mapped) osdl_fail("SDL_MapGPUTransferBuffer");
    const Uint8* src = mapped + Long_val(Field(download, GPU_DOWNLOAD_OFFSET));
    Uint8*       dst = (Uint8*)Caml_ba_data_val(data) + offset;
    if (src_pitch == row_bytes && (size_t)stride == row_bytes)
        memcpy(dst, src, rows * row_bytes);
    else
        for (size_t y = 0; y < rows; ++y)
            memcpy(dst + y * (size_t)stride, src + y * src_pitch, row_bytes);
    SDL_UnmapGPUTransferBuffer(d, ptr);
    return Val_unit;
}

/* Textures and samplers. */

/* Gpu.texture_format constructor order. These uncompressed color formats
 * support linear blits on Vulkan, as required by mipmap generation. */
static const SDL_GPUTextureFormat osdl_gpu_texture_formats[] = {
    SDL_GPU_TEXTUREFORMAT_R8_UNORM,
    SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
    SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
    SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
    SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
    SDL_GPU_TEXTUREFORMAT_R10G10B10A2_UNORM,
};

static value osdl_gpu_texture_format_value(SDL_GPUTextureFormat format) {
    for (size_t i = 0; i < SDL_arraysize(osdl_gpu_texture_formats); ++i)
        if (osdl_gpu_texture_formats[i] == format) return Val_int(i);
    osdl_raise_error("Unsupported SDL GPU texture format");
}

CAMLprim value osdl_gpu_swapchain_format(value claim) {
    return osdl_gpu_texture_format_value(osdl_gpu_swapchain_native_format(claim));
}

static SDL_GPUTextureUsageFlags osdl_gpu_texture_usage(value usage) {
    /* Gpu.texture_usage constructor order. */
    static const SDL_GPUTextureUsageFlags flags[] = {
        SDL_GPU_TEXTUREUSAGE_SAMPLER,
        SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
    };
    return flags[Int_val(usage)];
}

CAMLprim value osdl_gpu_supports_texture_format(value device, value format, value usage) {
    SDL_GPUDevice* d = osdl_live(device);
    return Val_bool(SDL_GPUTextureSupportsFormat(d, osdl_gpu_texture_formats[Int_val(format)],
                                                 SDL_GPU_TEXTURETYPE_2D,
                                                 osdl_gpu_texture_usage(usage)));
}

static void osdl_gpu_require_texture_format(SDL_GPUDevice* device, SDL_GPUTextureFormat format,
                                            SDL_GPUTextureUsageFlags usage) {
    if (!SDL_GPUTextureSupportsFormat(device, format, SDL_GPU_TEXTURETYPE_2D, usage))
        osdl_raise_error("SDL_GPUTextureSupportsFormat: Unsupported format for this texture use");
}

CAMLprim value osdl_gpu_create_texture(value mip_levels, value device, value format, value usage,
                                       value width, value height) {
    CAMLparam5(mip_levels, device, format, usage, width);
    CAMLxparam1(height);
    CAMLlocal1(handle);

    SDL_GPUTextureFormat     native = osdl_gpu_texture_formats[Int_val(format)];
    SDL_GPUTextureUsageFlags flags  = osdl_gpu_texture_usage(usage);
    intnat                   levels = Is_long(mip_levels) ? 1 : Long_val(Some_val(mip_levels));
    handle = osdl_new_gpu_texture(device, Val_unit, width, height, Val_long(levels), native, flags);

    SDL_GPUDevice* d = osdl_live(device);
    intnat         w = Long_val(width), h = Long_val(height);
    if (w < 1 || h < 1 || w > 16384 || h > 16384)
        caml_invalid_argument("GPU texture width and height must be in [1, 16384]");
    int max_levels = 1;
    for (intnat size = SDL_max(w, h); size > 1; size >>= 1)
        ++max_levels;
    if (levels < 1 || levels > max_levels)
        caml_invalid_argument("The GPU mip level count must fit the texture dimensions");

    osdl_gpu_require_texture_format(d, native, flags);
    SDL_GPUTextureCreateInfo info = {
        .type                 = SDL_GPU_TEXTURETYPE_2D,
        .format               = native,
        .usage                = flags,
        .width                = (Uint32)w,
        .height               = (Uint32)h,
        .layer_count_or_depth = 1,
        .num_levels           = (Uint32)levels,
        .sample_count         = SDL_GPU_SAMPLECOUNT_1,
    };
    SDL_GPUTexture* texture = SDL_CreateGPUTexture(d, &info);
    CAMLreturn(osdl_publish(handle, texture, "SDL_CreateGPUTexture"));
}

CAMLprim value osdl_gpu_create_texture_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_create_texture(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

static value osdl_gpu_mip_index(value level) {
    return Is_long(level) ? Val_int(0) : Some_val(level);
}

CAMLprim value osdl_gpu_texture_format(value texture) {
    osdl_gpu_live_texture(texture);
    return osdl_gpu_texture_format_value(osdl_gpu_image_format(texture));
}

CAMLprim value osdl_gpu_texture_mip_levels(value texture) {
    osdl_gpu_live_texture(texture);
    return Field(texture, GPU_TEXTURE_LEVELS);
}

CAMLprim value osdl_gpu_texture_size(value level, value texture) {
    osdl_gpu_live_texture(texture);
    osdl_gpu_texture_mip mip = osdl_gpu_mip(texture, osdl_gpu_mip_index(level), false);
    return osdl_int_pair((int)mip.w, (int)mip.h);
}

CAMLprim value osdl_gpu_release_texture(value texture) {
    osdl_gpu_require_owned_texture(texture);
    SDL_GPUTexture* ptr = osdl_take(texture);
    if (ptr) SDL_ReleaseGPUTexture(osdl_gpu_parent_device(texture), ptr);
    return Val_unit;
}

static SDL_GPUFilter osdl_gpu_filter(value filter) {
    /* Gpu.sampler_filter: Nearest | Linear. */
    return Int_val(filter) == 0 ? SDL_GPU_FILTER_NEAREST : SDL_GPU_FILTER_LINEAR;
}

static SDL_GPUSamplerAddressMode osdl_gpu_sampler_address(value mode) {
    /* Gpu.sampler_address: Clamp_to_edge | Repeat | Mirrored_repeat. */
    static const SDL_GPUSamplerAddressMode modes[] = {
        SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        SDL_GPU_SAMPLERADDRESSMODE_MIRRORED_REPEAT,
    };
    return modes[Is_long(mode) ? 0 : Int_val(Some_val(mode))];
}

CAMLprim value osdl_gpu_create_sampler(value max_mip_level, value mipmap_filter, value address_u,
                                       value address_v, value address_w, value device,
                                       value filter) {
    CAMLparam5(max_mip_level, mipmap_filter, address_u, address_v, address_w);
    CAMLxparam2(device, filter);
    CAMLlocal1(handle);

    handle = osdl_new_handle(device);

    SDL_GPUDevice* d   = osdl_live(device);
    intnat         lod = Long_val(osdl_gpu_mip_index(max_mip_level));
    if (lod < 0 || lod > GPU_MAX_MIP_LEVEL)
        caml_invalid_argument("The sampler's maximum mip level must be in [0, 14]");
    SDL_GPUFilter mode = osdl_gpu_filter(filter);

    SDL_GPUSamplerCreateInfo info = {
        .min_filter     = mode,
        .mag_filter     = mode,
        .mipmap_mode    = Is_block(mipmap_filter) && Int_val(Some_val(mipmap_filter)) == 1
                            ? SDL_GPU_SAMPLERMIPMAPMODE_LINEAR
                            : SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = osdl_gpu_sampler_address(address_u),
        .address_mode_v = osdl_gpu_sampler_address(address_v),
        .address_mode_w = osdl_gpu_sampler_address(address_w),
        .max_anisotropy = 1.0f,
        .compare_op     = SDL_GPU_COMPAREOP_NEVER,
        .max_lod        = (float)lod,
    };
    SDL_GPUSampler* sampler = SDL_CreateGPUSampler(d, &info);
    CAMLreturn(osdl_publish(handle, sampler, "SDL_CreateGPUSampler"));
}

CAMLprim value osdl_gpu_create_sampler_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_create_sampler(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

CAMLprim value osdl_gpu_release_sampler(value sampler) {
    SDL_GPUSampler* ptr = osdl_take(sampler);
    if (ptr) SDL_ReleaseGPUSampler(osdl_gpu_parent_device(sampler), ptr);
    return Val_unit;
}

/* Shaders and graphics pipelines. */

/* Sdl3.Gpu.shader_stage constructor order. */
enum { GPU_VERTEX, GPU_FRAGMENT };

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
    cell              = osdl_new_cell_sized(device, &osdl_handle_ops, sizeof(osdl_gpu_shader_cell));
    osdl_gpu_shader_cell* native = Data_custom_val(cell);
    native->renderer_count       = 0;
    native->deferred_release     = NULL;
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
    if (ptr) {
        osdl_gpu_shader_cell* cell = (osdl_gpu_shader_cell*)osdl_cell_val(shader);
        if (cell->renderer_count)
            cell->deferred_release = ptr;
        else
            SDL_ReleaseGPUShader(osdl_gpu_parent_device(shader), ptr);
    }
    return Val_unit;
}

enum {
    GPU_PIPELINE_FORMAT = 2,
    GPU_PIPELINE_LAYOUTS,
    GPU_PIPELINE_VERTEX_SAMPLERS,
    GPU_PIPELINE_FRAGMENT_SAMPLERS,
    GPU_PIPELINE_UNIFORM_MASK,
    GPU_MAX_VERTEX_ATTRIBUTES = 16,
    GPU_MAX_VERTEX_BUFFERS    = 16,
};

static void osdl_gpu_vertex_layout(value layout, Uint32 slot, SDL_GPUVertexInputRate rate,
                                   SDL_GPUVertexBufferDescription* buffer,
                                   SDL_GPUVertexAttribute* attributes, Uint32* count,
                                   Uint32* used) {
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
    Uint32 stride = osdl_gpu_aligned_size(Field(layout, 0));
    if (stride > 2048) caml_invalid_argument("GPU vertex stride must be at most 2048 bytes");
    if (Field(layout, 1) == Val_emptylist)
        caml_invalid_argument("Supply at least one GPU vertex attribute per buffer");

    for (value list = Field(layout, 1); list != Val_emptylist; list = Field(list, 1)) {
        /* Sdl3.Gpu.vertex_attribute: location, format, offset. */
        value  attr     = Field(list, 0);
        intnat location = Long_val(Field(attr, 0));
        int    format   = Int_val(Field(attr, 1));
        Uint32 offset   = osdl_gpu_uint32(Field(attr, 2), "GPU attribute offset is out of range");
        if (location < 0 || location >= GPU_MAX_VERTEX_ATTRIBUTES)
            caml_invalid_argument("GPU attribute location must be in [0, 15]");
        Uint32 bit = 1u << location;
        if (*used & bit) caml_invalid_argument("GPU attribute locations must be unique");
        if (offset % 4 || !osdl_gpu_range_fits(offset, formats[format].bytes, stride))
            caml_invalid_argument("Align the GPU attribute to four bytes and fit it in the stride");
        *used |= bit;
        attributes[(*count)++] = (SDL_GPUVertexAttribute){.location    = (Uint32)location,
                                                          .buffer_slot = slot,
                                                          .format      = formats[format].format,
                                                          .offset      = offset};
    }
    *buffer = (SDL_GPUVertexBufferDescription){.slot = slot, .pitch = stride, .input_rate = rate};
}

static SDL_GPUVertexInputState osdl_gpu_vertex_input(value layout, value layouts,
                                                     SDL_GPUVertexBufferDescription* buffers,
                                                     SDL_GPUVertexAttribute*         attrs) {
    Uint32 slots = 0, count = 0, used = 0;
    if (Is_block(layout)) {
        if (Is_block(layouts))
            caml_invalid_argument("Pass either vertex_layout or vertex_layouts, not both");
        osdl_gpu_vertex_layout(Some_val(layout), 0, SDL_GPU_VERTEXINPUTRATE_VERTEX, buffers, attrs,
                               &count, &used);
        slots = 1;
    } else if (Is_block(layouts)) {
        for (value list = Some_val(layouts); list != Val_emptylist; list = Field(list, 1)) {
            if (slots == GPU_MAX_VERTEX_BUFFERS)
                caml_invalid_argument("Use at most 16 GPU vertex buffer slots");
            /* Gpu.vertex_buffer_layout: layout, input_rate. */
            value                  spec = Field(list, 0);
            SDL_GPUVertexInputRate rate = Int_val(Field(spec, 1)) == 0
                                            ? SDL_GPU_VERTEXINPUTRATE_VERTEX
                                            : SDL_GPU_VERTEXINPUTRATE_INSTANCE;
            osdl_gpu_vertex_layout(Field(spec, 0), slots, rate, &buffers[slots], attrs, &count,
                                   &used);
            ++slots;
        }
    }
    return (SDL_GPUVertexInputState){
        .vertex_buffer_descriptions = slots ? buffers : NULL,
        .num_vertex_buffers         = slots,
        .vertex_attributes          = count ? attrs : NULL,
        .num_vertex_attributes      = count,
    };
}

static SDL_GPUBlendFactor osdl_gpu_blend_factor(value factor, bool alpha) {
    /* Blend_mode.factor order, not the order of the SDL GPU or renderer enum. */
    static const SDL_GPUBlendFactor factors[] = {
        SDL_GPU_BLENDFACTOR_ZERO,      SDL_GPU_BLENDFACTOR_ONE,
        SDL_GPU_BLENDFACTOR_SRC_COLOR, SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
        SDL_GPU_BLENDFACTOR_SRC_ALPHA, SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
        SDL_GPU_BLENDFACTOR_DST_COLOR, SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR,
        SDL_GPU_BLENDFACTOR_DST_ALPHA, SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
    };
    SDL_GPUBlendFactor native = factors[Int_val(factor)];
    if (!alpha) return native;

    /* Use the alpha component of color factors on every backend. */
    switch (native) {
    case SDL_GPU_BLENDFACTOR_SRC_COLOR:
        return SDL_GPU_BLENDFACTOR_SRC_ALPHA;
    case SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR:
        return SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
    case SDL_GPU_BLENDFACTOR_DST_COLOR:
        return SDL_GPU_BLENDFACTOR_DST_ALPHA;
    case SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR:
        return SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA;
    default:
        return native;
    }
}

static SDL_GPUBlendOp osdl_gpu_blend_channel(value equation, bool alpha, SDL_GPUBlendFactor* src,
                                             SDL_GPUBlendFactor* dst) {
    static const SDL_GPUBlendOp operations[] = {
        SDL_GPU_BLENDOP_ADD, SDL_GPU_BLENDOP_SUBTRACT, SDL_GPU_BLENDOP_REVERSE_SUBTRACT,
        SDL_GPU_BLENDOP_MIN, SDL_GPU_BLENDOP_MAX,
    };
    /* Blend_mode.equation: src, dst, op. GPU min/max compare unscaled values. */
    SDL_GPUBlendOp op = operations[Int_val(Field(equation, 2))];
    if (op == SDL_GPU_BLENDOP_MIN || op == SDL_GPU_BLENDOP_MAX) {
        *src = *dst = SDL_GPU_BLENDFACTOR_ONE;
    } else {
        *src = osdl_gpu_blend_factor(Field(equation, 0), alpha);
        *dst = osdl_gpu_blend_factor(Field(equation, 1), alpha);
    }
    return op;
}

static SDL_GPUColorTargetBlendState osdl_gpu_blend_state(value blend, value write_mask) {
    SDL_GPUColorTargetBlendState state = {0};
    if (Is_block(blend)) {
        /* Gpu.Blend.t: color, alpha. */
        value equations      = Some_val(blend);
        state.enable_blend   = true;
        state.color_blend_op = osdl_gpu_blend_channel(
            Field(equations, 0), false, &state.src_color_blendfactor, &state.dst_color_blendfactor);
        state.alpha_blend_op = osdl_gpu_blend_channel(
            Field(equations, 1), true, &state.src_alpha_blendfactor, &state.dst_alpha_blendfactor);
    }
    if (Is_block(write_mask)) {
        /* Gpu.color_component constructor order. Some [] writes nothing. */
        static const SDL_GPUColorComponentFlags bits[] = {
            SDL_GPU_COLORCOMPONENT_R,
            SDL_GPU_COLORCOMPONENT_G,
            SDL_GPU_COLORCOMPONENT_B,
            SDL_GPU_COLORCOMPONENT_A,
        };
        state.enable_color_write_mask = true;
        for (value list = Some_val(write_mask); list != Val_emptylist; list = Field(list, 1))
            state.color_write_mask |= bits[Int_val(Field(list, 0))];
    }
    return state;
}

/* An unspecified native format means that owner is a window claim. */
static value osdl_gpu_create_pipeline(value layout, value layouts, value blend, value write_mask,
                                      value owner, value vertex, value fragment, value primitive,
                                      SDL_GPUTextureFormat format) {
    CAMLparam5(layout, layouts, blend, write_mask, owner);
    CAMLxparam3(vertex, fragment, primitive);
    CAMLlocal4(device, cell, pipeline, strides);

    SDL_GPUVertexBufferDescription buffers[GPU_MAX_VERTEX_BUFFERS];
    SDL_GPUVertexAttribute         attrs[GPU_MAX_VERTEX_ATTRIBUTES];
    SDL_GPUVertexInputState        input = osdl_gpu_vertex_input(layout, layouts, buffers, attrs);

    /* Negative strides mark per-instance slots. Keep only the draw metadata. */
    strides = caml_alloc_tuple(input.num_vertex_buffers);
    for (Uint32 i = 0; i < input.num_vertex_buffers; ++i) {
        int stride = (int)buffers[i].pitch;
        Store_field(
            strides, i,
            Val_int(buffers[i].input_rate == SDL_GPU_VERTEXINPUTRATE_INSTANCE ? -stride : stride));
    }

    bool swapchain             = format == SDL_GPU_TEXTUREFORMAT_INVALID;
    device                     = swapchain ? osdl_parent(owner) : owner;
    cell                       = osdl_new_cell(device, &osdl_handle_ops);
    /* Keep the resource counts after the shader handles are released. */
    unsigned vertex_uniforms   = (1u << Int_val(Field(vertex, GPU_SHADER_UNIFORMS))) - 1;
    unsigned fragment_uniforms = (1u << Int_val(Field(fragment, GPU_SHADER_UNIFORMS))) - 1;
    unsigned mask              = vertex_uniforms | (fragment_uniforms << GPU_MAX_UNIFORMS);
    pipeline = caml_alloc_7(0, cell, device, Val_unit, strides, Field(vertex, GPU_SHADER_SAMPLERS),
                            Field(fragment, GPU_SHADER_SAMPLERS), Val_int(mask));

    /* Sdl3.Gpu.primitive constructor order. */
    static const SDL_GPUPrimitiveType primitives[] = {
        SDL_GPU_PRIMITIVETYPE_TRIANGLELIST, SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
        SDL_GPU_PRIMITIVETYPE_LINELIST,     SDL_GPU_PRIMITIVETYPE_LINESTRIP,
        SDL_GPU_PRIMITIVETYPE_POINTLIST,
    };
    SDL_GPUDevice* d  = osdl_live(device);
    SDL_GPUShader* vs = osdl_live(vertex);
    SDL_GPUShader* fs = osdl_live(fragment);
    if (device != osdl_parent(vertex) || device != osdl_parent(fragment))
        caml_invalid_argument("Use shaders from the pipeline's GPU device");

    if (swapchain)
        format = osdl_gpu_swapchain_native_format(owner);
    else
        osdl_gpu_require_texture_format(d, format, SDL_GPU_TEXTUREUSAGE_COLOR_TARGET);
    Store_field(pipeline, GPU_PIPELINE_FORMAT, Val_int(format));

    SDL_GPUColorTargetDescription target = {.format      = format,
                                            .blend_state = osdl_gpu_blend_state(blend, write_mask)};

    SDL_GPUGraphicsPipelineCreateInfo info = {
        .vertex_shader      = vs,
        .fragment_shader    = fs,
        .vertex_input_state = input,
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

CAMLprim value osdl_gpu_create_graphics_pipeline(value layout, value layouts, value blend,
                                                 value write_mask, value device, value format,
                                                 value vertex, value fragment, value primitive) {
    return osdl_gpu_create_pipeline(layout, layouts, blend, write_mask, device, vertex, fragment,
                                    primitive, osdl_gpu_texture_formats[Int_val(format)]);
}

CAMLprim value osdl_gpu_create_graphics_pipeline_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_create_graphics_pipeline(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5],
                                             argv[6], argv[7], argv[8]);
}

CAMLprim value osdl_gpu_create_swapchain_pipeline(value layout, value layouts, value blend,
                                                  value write_mask, value claim, value vertex,
                                                  value fragment, value primitive) {
    return osdl_gpu_create_pipeline(layout, layouts, blend, write_mask, claim, vertex, fragment,
                                    primitive, SDL_GPU_TEXTUREFORMAT_INVALID);
}

CAMLprim value osdl_gpu_create_swapchain_pipeline_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_create_swapchain_pipeline(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5],
                                              argv[6], argv[7]);
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
    GPU_COMMAND_DOWNLOADS,
    GPU_COMMAND_READS_ATLAS,
};

CAMLprim value osdl_gpu_acquire_command_buffer(value device) {
    CAMLparam1(device);
    CAMLlocal2(cell, buffer);

    /* The third field keeps the window claim live after image acquisition. */
    cell   = osdl_new_cell(device, &osdl_handle_ops);
    buffer = caml_alloc_6(0, cell, device, Val_unit, Val_int(0), Val_unit, Val_false);

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
    intnat                index    = Long_val(slot);
    if (index < 0 || index >= GPU_MAX_UNIFORMS)
        caml_invalid_argument("GPU uniform slot must be in [0, 3]");
    intnat size = osdl_gpu_uniform_size(data);

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

/* SDL_ttf can reuse atlas pixels as soon as a text is rebuilt. Do not let it
 * upload to an atlas before the commands that read it reach the queue. */
static void osdl_gpu_record_texture_read(value buffer, value texture) {
    if (osdl_gpu_texture_borrowed(texture) && !Bool_val(Field(buffer, GPU_COMMAND_READS_ATLAS))) {
        value  device  = osdl_parent(buffer);
        intnat readers = Long_val(Field(device, GPU_DEVICE_ATLAS_READERS));
        Store_field(device, GPU_DEVICE_ATLAS_READERS, Val_long(readers + 1));
        Store_field(buffer, GPU_COMMAND_READS_ATLAS, Val_true);
    }
}

static void osdl_gpu_finish_recording(value buffer, osdl_gpu_download_state state) {
    if (Bool_val(Field(buffer, GPU_COMMAND_READS_ATLAS))) {
        value  device  = osdl_parent(buffer);
        intnat readers = Long_val(Field(device, GPU_DEVICE_ATLAS_READERS));
        Store_field(device, GPU_DEVICE_ATLAS_READERS, Val_long(readers - 1));
        Store_field(buffer, GPU_COMMAND_READS_ATLAS, Val_false);
    }
    value batch = Field(buffer, GPU_COMMAND_DOWNLOADS);
    if (batch != Val_unit) {
        Store_field(batch, GPU_DOWNLOAD_STATE, Val_int(state));
        Store_field(batch, GPU_DOWNLOAD_IDLE_MARK,
                    Field(osdl_parent(buffer), GPU_DEVICE_IDLE_MARK));
        Store_field(buffer, GPU_COMMAND_DOWNLOADS, Val_unit);
    }
}

CAMLprim value osdl_gpu_submit_command_buffer(value buffer) {
    SDL_GPUCommandBuffer* commands = osdl_gpu_take_live_commands(buffer);
    bool                  ok       = SDL_SubmitGPUCommandBuffer(commands);
    osdl_gpu_finish_recording(buffer, ok ? GPU_DOWNLOAD_SUBMITTED : GPU_DOWNLOAD_FAILED);
    osdl_check(ok, "SDL_SubmitGPUCommandBuffer");
    return Val_unit;
}

CAMLprim value osdl_gpu_submit_and_acquire_fence(value buffer) {
    CAMLparam1(buffer);
    CAMLlocal1(fence);

    fence = osdl_new_attached_handle(osdl_parent(buffer), Val_unit);

    SDL_GPUCommandBuffer* commands = osdl_gpu_take_live_commands(buffer);
    SDL_GPUFence*         ptr      = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    Store_field(fence, 2, Field(buffer, GPU_COMMAND_DOWNLOADS));
    osdl_gpu_finish_recording(buffer, ptr ? GPU_DOWNLOAD_SUBMITTED : GPU_DOWNLOAD_FAILED);
    CAMLreturn(osdl_publish(fence, ptr, "SDL_SubmitGPUCommandBufferAndAcquireFence"));
}

CAMLprim value osdl_gpu_cancel_command_buffer(value buffer) {
    osdl_require_thread(osdl_cell_thread(osdl_cell_val(buffer)));
    if (osdl_gpu_command_claim(buffer) != Val_unit)
        caml_invalid_argument("Submit the GPU command buffer after acquiring a window image");

    SDL_GPUCommandBuffer* commands = osdl_take(buffer);
    if (commands) {
        bool ok = SDL_CancelGPUCommandBuffer(commands);
        osdl_gpu_finish_recording(buffer, ok ? GPU_DOWNLOAD_CANCELED : GPU_DOWNLOAD_FAILED);
        osdl_check(ok, "SDL_CancelGPUCommandBuffer");
    }
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

    /* A fence query alone does not run D3D12's deferred texture copies. */
    value batch = osdl_attachment(fence);
    if (batch != Val_unit && Int_val(Field(batch, GPU_DOWNLOAD_STATE)) == GPU_DOWNLOAD_SUBMITTED &&
        !osdl_gpu_waited_since_submit(batch, osdl_parent(fence)))
        Store_field(batch, GPU_DOWNLOAD_STATE,
                    Val_int(ok ? GPU_DOWNLOAD_READY : GPU_DOWNLOAD_FAILED));
    osdl_check(ok, "SDL_WaitForGPUFences");
    CAMLreturn(Val_unit);
}

CAMLprim value osdl_gpu_release_fence(value fence) {
    SDL_GPUFence* ptr = osdl_take(fence);
    if (ptr) {
        SDL_ReleaseGPUFence(osdl_gpu_parent_device(fence), ptr);
        osdl_forget_attachment(fence);
    }
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

static SDL_GPUCopyPass* osdl_gpu_prepare_download(value pass, value* batch) {
    CAMLparam1(pass);

    SDL_GPUCopyPass* ptr = osdl_live(pass);
    *batch               = Field(osdl_parent(pass), GPU_COMMAND_DOWNLOADS);
    if (*batch == Val_unit) {
        /* The caller roots the candidate batch. Recheck liveness after allocation. */
        *batch = caml_alloc_2(0, Val_int(GPU_DOWNLOAD_RECORDING), Val_unit);
        ptr    = osdl_live(pass);
    }
    CAMLreturnT(SDL_GPUCopyPass*, ptr);
}

static SDL_GPUTransferBuffer* osdl_gpu_download_destination(value pass, value src, value dst) {
    SDL_GPUTransferBuffer* ptr    = osdl_live(dst);
    value                  device = osdl_gpu_pass_device(pass);
    if (osdl_parent(src) != device || osdl_parent(dst) != device)
        caml_invalid_argument("Use download resources from the copy pass's GPU device");
    osdl_gpu_download_state state = osdl_gpu_download_status(dst);
    if (state != GPU_DOWNLOAD_READY && state != GPU_DOWNLOAD_CANCELED)
        caml_invalid_argument("Finish the pending GPU download before reusing the buffer");
    return ptr;
}

static void osdl_gpu_record_download(value pass, value dst, value batch, Uint32 offset,
                                     Uint32 row_bytes, Uint32 pitch, Uint32 rows) {
    value commands = osdl_parent(pass);
    value attached = Field(commands, GPU_COMMAND_DOWNLOADS);
    if (attached == Val_unit)
        Store_field(commands, GPU_COMMAND_DOWNLOADS, batch);
    else
        batch = attached;

    Store_field(dst, GPU_DOWNLOAD_BATCH, batch);
    Store_field(dst, GPU_DOWNLOAD_OFFSET, Val_long(offset));
    Store_field(dst, GPU_DOWNLOAD_ROW_BYTES, Val_long(row_bytes));
    Store_field(dst, GPU_DOWNLOAD_PITCH, Val_long(pitch));
    Store_field(dst, GPU_DOWNLOAD_ROWS, Val_long(rows));
}

CAMLprim value osdl_gpu_download_from_buffer(value src_offset, value dst_offset, value pass,
                                             value src, value dst, value size) {
    CAMLparam5(src_offset, dst_offset, pass, src, dst);
    CAMLxparam1(size);
    CAMLlocal1(batch);

    SDL_GPUCopyPass*       p           = osdl_gpu_prepare_download(pass, &batch);
    SDL_GPUBuffer*         source      = osdl_live(src);
    SDL_GPUTransferBuffer* destination = osdl_gpu_download_destination(pass, src, dst);
    Uint32                 start       = osdl_gpu_offset(src_offset);
    Uint32                 offset      = osdl_gpu_offset(dst_offset);
    Uint32                 length      = osdl_gpu_aligned_size(size);
    if (start % 4 || offset % 4)
        caml_invalid_argument("GPU buffer download offsets must be multiples of four bytes");
    if (!osdl_gpu_range_fits(start, length, osdl_gpu_capacity(src)))
        caml_invalid_argument("The download must fit in the source GPU buffer");
    if (!osdl_gpu_range_fits(offset, length, osdl_gpu_capacity(dst)))
        caml_invalid_argument("The download must fit in the GPU download buffer");

    SDL_GPUBufferRegion           from = {.buffer = source, .offset = start, .size = length};
    SDL_GPUTransferBufferLocation to   = {.transfer_buffer = destination, .offset = offset};
    SDL_DownloadFromGPUBuffer(p, &from, &to);
    osdl_gpu_record_download(pass, dst, batch, offset, length, length, 1);
    CAMLreturn(Val_unit);
}

CAMLprim value osdl_gpu_download_from_buffer_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_download_from_buffer(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
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

static void osdl_gpu_upload_repacked(SDL_GPUDevice* device, SDL_GPUCopyPass* pass,
                                     const SDL_GPUTextureTransferInfo* from,
                                     const SDL_GPUTextureRegion* to, Uint32 pixel, Uint32 src_pitch,
                                     Uint32 dst_pitch, bool cycle) {
    /* The region is at most 16384 by 16384, with at most eight bytes per pixel.
     * Rounding a row to 256 bytes still fits the 32-bit transfer size. */
    Uint32                          size    = (dst_pitch * to->h + 3u) & ~3u;
    SDL_GPUTransferBufferCreateInfo info    = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                                               .size  = size};
    SDL_GPUTransferBuffer*          scratch = SDL_CreateGPUTransferBuffer(device, &info);
    if (!scratch) osdl_fail("SDL_CreateGPUTransferBuffer");

    /* Read the existing upload storage without cycling or changing it. */
    const Uint8* input  = SDL_MapGPUTransferBuffer(device, from->transfer_buffer, false);
    Uint8*       output = input ? SDL_MapGPUTransferBuffer(device, scratch, false) : NULL;
    if (!output) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "SDL_MapGPUTransferBuffer");
        if (input) SDL_UnmapGPUTransferBuffer(device, from->transfer_buffer);
        SDL_ReleaseGPUTransferBuffer(device, scratch);
        osdl_raise_error(message);
    }

    size_t row_bytes = (size_t)to->w * pixel;
    for (Uint32 y = 0; y < to->h; ++y)
        memcpy(output + (size_t)y * dst_pitch, input + from->offset + (size_t)y * src_pitch,
               row_bytes);
    SDL_UnmapGPUTransferBuffer(device, scratch);
    SDL_UnmapGPUTransferBuffer(device, from->transfer_buffer);

    SDL_GPUTextureTransferInfo packed = {.transfer_buffer = scratch,
                                         .pixels_per_row  = dst_pitch / pixel};
    SDL_UploadToGPUTexture(pass, &packed, to, cycle);
    SDL_ReleaseGPUTransferBuffer(device, scratch);
}

CAMLprim value osdl_gpu_upload_to_texture(value src_offset, value pitch, value cycle, value level,
                                          value rect, value pass, value src, value dst) {
    SDL_GPUCopyPass*       p           = osdl_live(pass);
    SDL_GPUTransferBuffer* source      = osdl_live(src);
    SDL_GPUTexture*        destination = osdl_gpu_live_texture(dst);
    osdl_gpu_require_owned_texture(dst);
    value device = osdl_gpu_pass_device(pass);
    if (osdl_parent(src) != device || osdl_parent(dst) != device)
        caml_invalid_argument("Use an upload buffer and texture from the copy pass's GPU device");

    osdl_gpu_texture_mip mip  = osdl_gpu_mip(dst, osdl_gpu_mip_index(level), false);
    SDL_Rect             area = {0, 0, (int)mip.w, (int)mip.h};
    if (Is_block(rect))
        area =
            osdl_gpu_rect(Some_val(rect), mip.w, mip.h,
                          "The GPU upload rectangle must have positive size and fit the mip level");
    Uint32 start     = osdl_gpu_offset(src_offset);
    Uint32 pixel     = SDL_GPUTextureFormatTexelBlockSize(osdl_gpu_image_format(dst));
    Uint32 row_bytes = (Uint32)area.w * pixel;
    Uint32 stride    = Is_long(pitch)
                         ? row_bytes
                         : osdl_gpu_uint32(Some_val(pitch), "The GPU upload pitch is out of range");
    if (start % SDL_max(4u, pixel))
        caml_invalid_argument("Align the GPU texture upload offset to four bytes and to a pixel");
    if (stride < row_bytes || stride % pixel)
        caml_invalid_argument(
            "Use a GPU upload pitch that covers a row and is a multiple of the pixel size");
    if (stride > SDL_MAX_SINT32) caml_invalid_argument("The GPU upload pitch is too large");

    Uint64 written = Long_val(Field(src, GPU_UPLOAD_WRITTEN));
    if ((Uint64)start + (Uint64)(area.h - 1) * stride + row_bytes > written)
        caml_invalid_argument(
            "The texture copy must fit in the written bytes of the upload buffer");
    bool rotate = osdl_gpu_cycle(cycle);
    if (rotate && (Int_val(Field(dst, GPU_TEXTURE_LEVELS)) != 1 || area.x || area.y ||
                   (Uint32)area.w != mip.w || (Uint32)area.h != mip.h))
        caml_invalid_argument("A cycling GPU upload must replace the whole one-level texture");

    if (area.h == 1) stride = row_bytes;
    SDL_GPUTextureTransferInfo from = {.transfer_buffer = source,
                                       .offset          = start,
                                       .pixels_per_row  = stride == row_bytes ? 0 : stride / pixel};
    SDL_GPUTextureRegion       to   = {.texture   = destination,
                                       .mip_level = mip.level,
                                       .x         = (Uint32)area.x,
                                       .y         = (Uint32)area.y,
                                       .w         = (Uint32)area.w,
                                       .h         = (Uint32)area.h,
                                       .d         = 1};
    if (stride != row_bytes) {
        SDL_GPUDevice* d        = osdl_cell_val(device)->ptr;
        const char*    driver   = SDL_GetGPUDeviceDriver(d);
        Uint32         repacked = 0;
        /* Metal ignores pixels_per_row in SDL 3.4.20. The older D3D12 path
         * copies each full source stride into a row aligned from the width
         * of the region. It also reads the last row's padding. */
        if (driver && strcmp(driver, "metal") == 0) {
            repacked = row_bytes;
        } else if (driver && strcmp(driver, "direct3d12") == 0) {
            Uint32 aligned = (row_bytes + 255u) & ~255u;
            if (stride > aligned || (Uint64)start + (Uint64)stride * to.h > written)
                repacked = aligned;
        }
        if (repacked) {
            osdl_gpu_upload_repacked(d, p, &from, &to, pixel, stride, repacked, rotate);
            return Val_unit;
        }
    }
    SDL_UploadToGPUTexture(p, &from, &to, rotate);
    return Val_unit;
}

CAMLprim value osdl_gpu_upload_to_texture_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_upload_to_texture(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6],
                                      argv[7]);
}

static SDL_GPUBlitRegion osdl_gpu_region(value region, bool render) {
    /* Gpu.texture_region: texture, mip_level, rect. */
    value                texture = Field(region, 0);
    SDL_GPUTexture*      ptr     = osdl_gpu_live_texture(texture);
    osdl_gpu_texture_mip mip     = osdl_gpu_mip(texture, Field(region, 1), render);
    SDL_Rect             rect    = osdl_gpu_rect(Field(region, 2), mip.w, mip.h,
                                                 "The GPU region must have positive size and fit the mip level");
    return (SDL_GPUBlitRegion){.texture   = ptr,
                               .mip_level = mip.level,
                               .x         = (Uint32)rect.x,
                               .y         = (Uint32)rect.y,
                               .w         = (Uint32)rect.w,
                               .h         = (Uint32)rect.h};
}

CAMLprim value osdl_gpu_download_from_texture(value dst_offset, value pitch, value pass, value src,
                                              value dst) {
    CAMLparam5(dst_offset, pitch, pass, src, dst);
    CAMLlocal1(batch);

    SDL_GPUCopyPass*       p           = osdl_gpu_prepare_download(pass, &batch);
    value                  texture     = Field(src, 0);
    SDL_GPUBlitRegion      region      = osdl_gpu_region(src, false);
    SDL_GPUTransferBuffer* destination = osdl_gpu_download_destination(pass, texture, dst);
    Uint32 pixel     = SDL_GPUTextureFormatTexelBlockSize(osdl_gpu_image_format(texture));
    Uint32 offset    = osdl_gpu_offset(dst_offset);
    Uint32 row_bytes = region.w * pixel;
    Uint32 stride    = Is_long(pitch)
                         ? row_bytes
                         : osdl_gpu_uint32(Some_val(pitch), "The GPU download pitch is out of range");
    if (offset % SDL_max(4u, pixel))
        caml_invalid_argument("Align the GPU texture download offset to four bytes and to a pixel");
    if (stride < row_bytes || stride % pixel)
        caml_invalid_argument(
            "Use a GPU download pitch that covers a row and is a multiple of the pixel size");

    /* Vulkan limits row bytes to INT32_MAX. D3D12 can round the pitch up to
     * 256 bytes in a temporary buffer, and it can copy the last row's padding. */
    Uint64 aligned = ((Uint64)stride + 255) & ~(Uint64)255;
    if (stride > SDL_MAX_SINT32 || aligned * region.h > SDL_MAX_UINT32)
        caml_invalid_argument("The GPU download pitch is too large for this texture region");
    if ((Uint64)offset + (Uint64)stride * region.h > osdl_gpu_capacity(dst))
        caml_invalid_argument("The texture download must fit in the GPU download buffer");

    SDL_GPUTextureRegion       from = {.texture   = region.texture,
                                       .mip_level = region.mip_level,
                                       .x         = region.x,
                                       .y         = region.y,
                                       .w         = region.w,
                                       .h         = region.h,
                                       .d         = 1};
    SDL_GPUTextureTransferInfo to   = {.transfer_buffer = destination,
                                       .offset          = offset,
                                       .pixels_per_row  = stride / pixel,
                                       .rows_per_layer  = region.h};
    SDL_DownloadFromGPUTexture(p, &from, &to);
    osdl_gpu_record_texture_read(osdl_parent(pass), texture);
    osdl_gpu_record_download(pass, dst, batch, offset, row_bytes, stride, region.h);
    CAMLreturn(Val_unit);
}

static void osdl_gpu_require_region_devices(value device, value src, value dst) {
    if (osdl_parent(src) != device || osdl_parent(dst) != device)
        caml_invalid_argument("Use textures from the command buffer's GPU device");
    if (src == dst) caml_invalid_argument("Copy or blit between distinct GPU textures");
}

static bool osdl_gpu_full_texture(value texture, SDL_GPUBlitRegion region) {
    return Int_val(Field(texture, GPU_TEXTURE_LEVELS)) == 1 && !region.x && !region.y &&
           region.w == (Uint32)Int_val(Field(texture, GPU_TEXTURE_WIDTH)) &&
           region.h == (Uint32)Int_val(Field(texture, GPU_TEXTURE_HEIGHT));
}

CAMLprim value osdl_gpu_copy_texture(value cycle, value pass, value src, value dst) {
    SDL_GPUCopyPass*  p      = osdl_live(pass);
    value             source = Field(src, 0), destination = Field(dst, 0);
    SDL_GPUBlitRegion from = osdl_gpu_region(src, false), to = osdl_gpu_region(dst, false);
    osdl_gpu_require_owned_texture(destination);
    osdl_gpu_require_region_devices(osdl_gpu_pass_device(pass), source, destination);
    if (osdl_gpu_image_format(source) != osdl_gpu_image_format(destination))
        caml_invalid_argument("GPU texture copies need matching pixel formats");
    if (from.w != to.w || from.h != to.h)
        caml_invalid_argument("GPU texture copies need regions of the same size");
    bool rotate = osdl_gpu_cycle(cycle);
    if (rotate && !osdl_gpu_full_texture(destination, to))
        caml_invalid_argument("A cycling GPU copy must replace the whole destination texture");

    SDL_GPUTextureLocation source_location = {
        .texture = from.texture, .mip_level = from.mip_level, .x = from.x, .y = from.y};
    SDL_GPUTextureLocation destination_location = {
        .texture = to.texture, .mip_level = to.mip_level, .x = to.x, .y = to.y};
    SDL_CopyGPUTextureToTexture(p, &source_location, &destination_location, from.w, from.h, 1,
                                rotate);
    osdl_gpu_record_texture_read(osdl_parent(pass), source);
    return Val_unit;
}

OSDL_DESTROY(osdl_gpu_end_copy_pass, SDL_GPUCopyPass, SDL_EndGPUCopyPass)

/* Blitting, mipmap generation, and render passes. */

static void osdl_gpu_forget_fragment_slot_zero(value buffer) {
    /* SDL can use this slot for its internal blit shader. */
    int mask = Int_val(Field(buffer, GPU_COMMAND_UNIFORMS));
    Store_field(buffer, GPU_COMMAND_UNIFORMS, Val_int(mask & ~(1 << GPU_MAX_UNIFORMS)));
}

CAMLprim value osdl_gpu_generate_mipmaps(value buffer, value texture) {
    SDL_GPUCommandBuffer* commands = osdl_gpu_commands_without_pass(buffer);
    value                 device   = osdl_parent(buffer);
    osdl_gpu_require_no_render_pass(device);
    SDL_GPUTexture* ptr = osdl_gpu_live_texture(texture);
    osdl_gpu_require_owned_texture(texture);
    if (osdl_parent(texture) != device)
        caml_invalid_argument("Use a texture from the command buffer's GPU device");

    int levels = Int_val(Field(texture, GPU_TEXTURE_LEVELS));
    if (levels < 2) caml_invalid_argument("Mipmap generation needs at least two texture levels");
    SDL_GPUTextureUsageFlags required =
        SDL_GPU_TEXTUREUSAGE_SAMPLER | SDL_GPU_TEXTUREUSAGE_COLOR_TARGET;
    if ((osdl_gpu_image_usage(texture) & required) != required)
        caml_invalid_argument("Mipmap generation needs a sampled color target");

    /* SDL 3.4.20 can blit or render zero extents on Vulkan and D3D12.
     * Metal generates mips directly and keeps each axis at least one pixel. */
    int shortest = SDL_min(Int_val(Field(texture, GPU_TEXTURE_WIDTH)),
                           Int_val(Field(texture, GPU_TEXTURE_HEIGHT)));
    if (!(shortest >> (levels - 1))) {
        const char* driver = SDL_GetGPUDeviceDriver(osdl_cell_val(device)->ptr);
        if (!driver || strcmp(driver, "metal") != 0)
            caml_invalid_argument(
                "Use fewer mip levels to generate mipmaps for this rectangular texture");
    }

    SDL_GenerateMipmapsForGPUTexture(commands, ptr);
    osdl_gpu_forget_fragment_slot_zero(buffer);
    return Val_unit;
}

static SDL_FColor osdl_gpu_clear_color(value color) {
    SDL_Color rgba = osdl_color(color);
    return (SDL_FColor){rgba.r / 255.0f, rgba.g / 255.0f, rgba.b / 255.0f, rgba.a / 255.0f};
}

static SDL_GPULoadOp osdl_gpu_load_op(value load, SDL_FColor* clear) {
    /* Gpu.load_op: Load | Clear of Color.t | Dont_care. */
    if (Is_block(load)) {
        *clear = osdl_gpu_clear_color(Field(load, 0));
        return SDL_GPU_LOADOP_CLEAR;
    }
    return Int_val(load) == 0 ? SDL_GPU_LOADOP_LOAD : SDL_GPU_LOADOP_DONT_CARE;
}

CAMLprim value osdl_gpu_blit_texture(value filter, value flip, value cycle, value buffer, value src,
                                     value dst, value load) {
    SDL_GPUCommandBuffer* commands = osdl_gpu_commands_without_pass(buffer);
    value                 device   = osdl_parent(buffer);
    osdl_gpu_require_no_render_pass(device);

    value           source = Field(src, 0), destination = Field(dst, 0);
    SDL_GPUBlitInfo info = {
        .source      = osdl_gpu_region(src, true),
        .destination = osdl_gpu_region(dst, true),
        .filter      = Is_long(filter) ? SDL_GPU_FILTER_NEAREST : osdl_gpu_filter(Some_val(filter)),
        .flip_mode   = Is_long(flip) ? SDL_FLIP_NONE : osdl_flip_mode(Some_val(flip)),
        .cycle       = osdl_gpu_cycle(cycle),
    };
    info.load_op = osdl_gpu_load_op(load, &info.clear_color);
    osdl_gpu_require_owned_texture(destination);
    osdl_gpu_require_region_devices(device, source, destination);
    if (!(osdl_gpu_image_usage(source) & SDL_GPU_TEXTUREUSAGE_SAMPLER))
        caml_invalid_argument("The GPU blit source must support sampling");
    if (!(osdl_gpu_image_usage(destination) & SDL_GPU_TEXTUREUSAGE_COLOR_TARGET))
        caml_invalid_argument("The GPU blit destination must support color targets");
    /* SDL's Vulkan backend can cycle twice if the blit clears first. */
    if (info.cycle && (info.load_op != SDL_GPU_LOADOP_DONT_CARE ||
                       !osdl_gpu_full_texture(destination, info.destination)))
        caml_invalid_argument("A cycling GPU blit needs Dont_care and a whole destination texture");

    SDL_BlitGPUTexture(commands, &info);
    osdl_gpu_record_texture_read(buffer, source);
    osdl_gpu_forget_fragment_slot_zero(buffer);
    return Val_unit;
}

CAMLprim value osdl_gpu_blit_texture_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_blit_texture(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]);
}

static value osdl_gpu_publish_render_pass(value pass, SDL_GPURenderPass* ptr, value target,
                                          SDL_GPUTextureFormat format, Uint32 w, Uint32 h) {
    osdl_publish(pass, ptr, "SDL_BeginGPURenderPass");
    Store_field(pass, GPU_PASS_FORMAT, Val_int(format));
    Store_field(pass, GPU_PASS_WIDTH, Val_long(w));
    Store_field(pass, GPU_PASS_HEIGHT, Val_long(h));
    if (target != Val_unit) {
        Store_field(pass, GPU_PASS_TARGET, target);
        ++osdl_cell_val(target)->children;
    }
    value device = osdl_gpu_pass_device(pass);
    Store_field(device, GPU_DEVICE_RENDERING, Val_true);
    return pass;
}

CAMLprim value osdl_gpu_begin_render_pass(value level, value store, value cycle, value buffer,
                                          value target, value load) {
    CAMLparam5(level, store, cycle, buffer, target);
    CAMLxparam1(load);
    CAMLlocal1(pass);

    pass = osdl_gpu_new_render_pass(buffer);

    SDL_GPUCommandBuffer* commands = osdl_gpu_commands_without_pass(buffer);
    SDL_GPUTexture*       texture  = osdl_gpu_live_texture(target);
    osdl_gpu_require_owned_texture(target);
    value device = osdl_parent(buffer);
    if (osdl_parent(target) != device)
        caml_invalid_argument("Use a render target from the command buffer's GPU device");
    if (!(osdl_gpu_image_usage(target) & SDL_GPU_TEXTUREUSAGE_COLOR_TARGET))
        caml_invalid_argument("The GPU texture must support color targets");
    osdl_gpu_require_no_render_pass(device);
    osdl_gpu_texture_mip mip = osdl_gpu_mip(target, osdl_gpu_mip_index(level), true);

    SDL_GPUColorTargetInfo info = {
        .texture   = texture,
        .mip_level = mip.level,
        .store_op  = Is_long(store) || Int_val(Some_val(store)) == 0 ? SDL_GPU_STOREOP_STORE
                                                                     : SDL_GPU_STOREOP_DONT_CARE,
        .cycle     = osdl_gpu_cycle(cycle),
    };
    info.load_op = osdl_gpu_load_op(load, &info.clear_color);
    if (info.cycle &&
        (info.load_op == SDL_GPU_LOADOP_LOAD || Int_val(Field(target, GPU_TEXTURE_LEVELS)) != 1))
        caml_invalid_argument("A cycling GPU render pass needs one mip level and cannot load it");

    SDL_GPURenderPass* ptr = SDL_BeginGPURenderPass(commands, &info, 1, NULL);
    CAMLreturn(osdl_gpu_publish_render_pass(pass, ptr, target, osdl_gpu_image_format(target), mip.w,
                                            mip.h));
}

CAMLprim value osdl_gpu_begin_render_pass_byte(value* argv, int argc) {
    (void)argc;
    return osdl_gpu_begin_render_pass(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
}

/* Swapchain render passes. */

static bool osdl_gpu_wait_for_image(SDL_GPUCommandBuffer* commands, SDL_Window* window,
                                    SDL_GPUTexture** image, Uint32* width, Uint32* height) {
    caml_enter_blocking_section_no_pending();
    bool ok = SDL_WaitAndAcquireGPUSwapchainTexture(commands, window, image, width, height);
    caml_leave_blocking_section();
    return ok;
}

static SDL_GPURenderPass* osdl_gpu_begin_clear_pass(SDL_GPUCommandBuffer* commands,
                                                    SDL_GPUTexture* image, value color) {
    SDL_GPUColorTargetInfo target = {
        .texture     = image,
        .clear_color = osdl_gpu_clear_color(color),
        .load_op     = SDL_GPU_LOADOP_CLEAR,
        .store_op    = SDL_GPU_STOREOP_STORE,
    };
    return SDL_BeginGPURenderPass(commands, &target, 1, NULL);
}

CAMLnoret static void osdl_gpu_fail_frame(value buffer, SDL_GPUCommandBuffer* commands,
                                          bool has_image, const char* fn) {
    char message[1024];
    osdl_error_message(message, sizeof(message), fn);

    if (buffer != Val_unit) commands = osdl_gpu_take_live_commands(buffer);
    /* SDL forbids cancellation once a swapchain image is acquired. Discard
     * any results but do not allow reuse until submitted work finishes. */
    bool canceled = false;
    if (has_image)
        SDL_SubmitGPUCommandBuffer(commands);
    else
        canceled = SDL_CancelGPUCommandBuffer(commands);
    if (buffer != Val_unit)
        osdl_gpu_finish_recording(buffer, canceled ? GPU_DOWNLOAD_CANCELED : GPU_DOWNLOAD_FAILED);
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
    osdl_gpu_require_no_render_pass(osdl_parent(buffer));

    SDL_GPUTexture* image = NULL;
    Uint32          width = 0, height = 0;
    if (!osdl_gpu_wait_for_image(commands, w, &image, &width, &height))
        osdl_gpu_fail_frame(buffer, commands, image != NULL,
                            "SDL_WaitAndAcquireGPUSwapchainTexture");
    if (!image) CAMLreturn(Val_none);

    SDL_GPUTextureFormat format =
        SDL_GetGPUSwapchainTextureFormat(osdl_gpu_parent_device(claim), w);
    if (format == SDL_GPU_TEXTUREFORMAT_INVALID)
        osdl_gpu_fail_frame(buffer, commands, true, "SDL_GetGPUSwapchainTextureFormat");
    if (!width || !height || width > SDL_min(INT_MAX, Max_long) ||
        height > SDL_min(INT_MAX, Max_long)) {
        SDL_SetError("Invalid GPU swapchain image size");
        osdl_gpu_fail_frame(buffer, commands, true, "SDL_WaitAndAcquireGPUSwapchainTexture");
    }

    SDL_GPURenderPass* ptr = osdl_gpu_begin_clear_pass(commands, image, color);
    if (!ptr) osdl_gpu_fail_frame(buffer, commands, true, "SDL_BeginGPURenderPass");

    Store_field(buffer, GPU_COMMAND_CLAIM, claim);
    ++osdl_cell_val(claim)->children;
    osdl_gpu_publish_render_pass(pass, ptr, Val_unit, format, width, height);
    CAMLreturn(result);
}

CAMLprim value osdl_gpu_render_pass_size(value pass) {
    osdl_live(pass);
    return osdl_int_pair(Int_val(Field(pass, GPU_PASS_WIDTH)),
                         Int_val(Field(pass, GPU_PASS_HEIGHT)));
}

CAMLprim value osdl_gpu_set_viewport(value pass, value viewport) {
    SDL_GPURenderPass* ptr   = osdl_live(pass);
    int                width = Int_val(Field(pass, GPU_PASS_WIDTH)),
        height               = Int_val(Field(pass, GPU_PASS_HEIGHT));
    SDL_GPUViewport native   = {.w = (float)width, .h = (float)height, .max_depth = 1.0f};
    if (Is_block(viewport)) {
        value rect = Some_val(viewport);
        native.x   = osdl_float(Double_flat_field(rect, 0));
        native.y   = osdl_float(Double_flat_field(rect, 1));
        native.w   = osdl_float(Double_flat_field(rect, 2));
        native.h   = osdl_float(Double_flat_field(rect, 3));
        if (native.x < 0.0f || native.y < 0.0f || native.w <= 0.0f || native.h <= 0.0f ||
            (double)native.x + native.w > width || (double)native.y + native.h > height)
            caml_invalid_argument("The GPU viewport must have positive size and fit the target");
    }
    SDL_SetGPUViewport(ptr, &native);
    return Val_unit;
}

CAMLprim value osdl_gpu_set_scissor(value pass, value scissor) {
    SDL_GPURenderPass* ptr   = osdl_live(pass);
    int                width = Int_val(Field(pass, GPU_PASS_WIDTH)),
        height               = Int_val(Field(pass, GPU_PASS_HEIGHT));
    SDL_Rect native          = {0, 0, width, height};
    if (Is_block(scissor))
        native = osdl_gpu_rect(Some_val(scissor), (Uint32)width, (Uint32)height,
                               "The GPU scissor must have positive size and fit the target");
    SDL_SetGPUScissor(ptr, &native);
    return Val_unit;
}

enum { GPU_SLOT_BUFFER, GPU_SLOT_OFFSET, GPU_SLOT_AVAILABLE, GPU_SLOT_FIELDS };

CAMLprim value osdl_gpu_bind_graphics_pipeline(value pass, value pipeline) {
    CAMLparam2(pass, pipeline);
    CAMLlocal2(slots, vertices);

    mlsize_t count = Int_val(Field(pipeline, GPU_PIPELINE_VERTEX_SAMPLERS)) +
                     Int_val(Field(pipeline, GPU_PIPELINE_FRAGMENT_SAMPLERS));
    mlsize_t fields = GPU_SLOT_FIELDS * Wosize_val(Field(pipeline, GPU_PIPELINE_LAYOUTS));
    slots           = Field(pass, GPU_PASS_SAMPLERS);
    if (Is_long(slots) || Wosize_val(slots) != count) slots = caml_alloc_tuple(count);
    vertices = Field(pass, GPU_PASS_VERTEX_BINDINGS);
    if (Is_long(vertices) || Wosize_val(vertices) != fields) vertices = caml_alloc_tuple(fields);

    SDL_GPURenderPass*       p   = osdl_live(pass);
    SDL_GPUGraphicsPipeline* ptr = osdl_live(pipeline);
    if (osdl_gpu_pass_device(pass) != osdl_parent(pipeline))
        caml_invalid_argument("Use a pipeline from the render pass's GPU device");
    if (Field(pass, GPU_PASS_FORMAT) != Field(pipeline, GPU_PIPELINE_FORMAT))
        caml_invalid_argument("Use a pipeline that matches the render pass's pixel format");

    SDL_BindGPUGraphicsPipeline(p, ptr);
    Store_field(pass, GPU_PASS_PIPELINE, pipeline);
    /* Rebind vertex data and samplers against the current pipeline. */
    for (mlsize_t i = 0; i < fields; ++i)
        Store_field(vertices, i, Val_unit);
    Store_field(pass, GPU_PASS_VERTEX_BINDINGS, vertices);
    Store_field(pass, GPU_PASS_VERTEX_DIRTY, Val_true);
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
        SDL_GPUTexture* t = osdl_gpu_live_texture(tex);
        SDL_GPUSampler* s = osdl_live(sampler);
        if (osdl_parent(tex) != device || osdl_parent(sampler) != device)
            caml_invalid_argument("Use textures and samplers from the render pass's GPU device");
        if (!(osdl_gpu_image_usage(tex) & SDL_GPU_TEXTUREUSAGE_SAMPLER))
            caml_invalid_argument("The GPU texture must support sampling");
        if (tex == Field(pass, GPU_PASS_TARGET))
            caml_invalid_argument("Do not sample the color target in its own GPU render pass");
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
    for (mlsize_t i = 0; i < count; ++i) {
        Store_field(slots, base + start + i, pairs[i]);
        osdl_gpu_record_texture_read(osdl_parent(pass), Field(pairs[i], 0));
    }
    return Val_unit;
}

static Uint32 osdl_gpu_check_vertex_binding(value device, value buffer, value offset, int stride) {
    osdl_live(buffer);
    if (osdl_parent(buffer) != device)
        caml_invalid_argument("Use a vertex buffer from the render pass's GPU device");
    Uint32 start = osdl_gpu_uint32(offset, "GPU vertex buffer offset is out of range");
    Uint32 size = osdl_gpu_capacity(buffer), pitch = (Uint32)SDL_abs(stride);
    if (start % 4 || !osdl_gpu_range_fits(start, pitch, size))
        caml_invalid_argument(
            "Align the vertex buffer offset to four bytes and leave room for one element");
    return (size - start) / pitch;
}

static void osdl_gpu_store_vertex_binding(value slots, mlsize_t index, value buffer, value offset,
                                          Uint32 available) {
    mlsize_t base = index * GPU_SLOT_FIELDS;
    Store_field(slots, base + GPU_SLOT_BUFFER, buffer);
    Store_field(slots, base + GPU_SLOT_OFFSET, offset);
    Store_field(slots, base + GPU_SLOT_AVAILABLE, Val_long(available));
}

CAMLprim value osdl_gpu_bind_vertex_buffer(value slot, value offset, value pass, value buffer) {
    osdl_live(pass);
    value  layouts = Field(osdl_gpu_bound_pipeline(pass), GPU_PIPELINE_LAYOUTS);
    intnat index   = Is_long(slot) ? 0 : Long_val(Some_val(slot));
    if (index < 0 || (uintnat)index >= Wosize_val(layouts))
        caml_invalid_argument("The vertex buffer slot is outside the GPU pipeline's layout");

    value  start     = Is_long(offset) ? Val_int(0) : Some_val(offset);
    Uint32 available = osdl_gpu_check_vertex_binding(osdl_gpu_pass_device(pass), buffer, start,
                                                     Int_val(Field(layouts, index)));
    osdl_gpu_store_vertex_binding(Field(pass, GPU_PASS_VERTEX_BINDINGS), index, buffer, start,
                                  available);
    Store_field(pass, GPU_PASS_VERTEX_DIRTY, Val_true);
    return Val_unit;
}

CAMLprim value osdl_gpu_bind_vertex_buffers(value first_slot, value pass, value bindings) {
    osdl_live(pass);
    value    layouts = Field(osdl_gpu_bound_pipeline(pass), GPU_PIPELINE_LAYOUTS);
    intnat   start   = Is_long(first_slot) ? 0 : Long_val(Some_val(first_slot));
    mlsize_t limit = Wosize_val(layouts), count = Wosize_val(bindings);
    if (start < 0 || (uintnat)start > limit || count > limit - (uintnat)start)
        caml_invalid_argument("Vertex buffer bindings must fit in the GPU pipeline's layout");
    if (!count) return Val_unit;

    value  device = osdl_gpu_pass_device(pass);
    value  pairs[GPU_MAX_VERTEX_BUFFERS];
    Uint32 available[GPU_MAX_VERTEX_BUFFERS];
    for (mlsize_t i = 0; i < count; ++i) {
        value pair   = Field(bindings, i);
        available[i] = osdl_gpu_check_vertex_binding(device, Field(pair, 0), Field(pair, 1),
                                                     Int_val(Field(layouts, start + i)));
        pairs[i]     = pair;
    }

    value slots = Field(pass, GPU_PASS_VERTEX_BINDINGS);
    for (mlsize_t i = 0; i < count; ++i)
        osdl_gpu_store_vertex_binding(slots, start + i, Field(pairs[i], 0), Field(pairs[i], 1),
                                      available[i]);
    Store_field(pass, GPU_PASS_VERTEX_DIRTY, Val_true);
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

static value osdl_gpu_draw_layouts(value pass) {
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
            if (pair == Val_unit || !osdl_gpu_texture_valid(Field(pair, 0)) ||
                !osdl_cell_val(Field(pair, 1))->ptr)
                caml_invalid_argument(
                    "Bind a live texture and sampler to each slot before drawing");
        }
    }
    return Field(pipeline, GPU_PIPELINE_LAYOUTS);
}

static void osdl_gpu_draw_vertices(SDL_GPURenderPass* ptr, value pass, value layouts,
                                   Uint32 vertices, Uint32 instances) {
    Uint32 count = Wosize_val(layouts);
    if (!count) return;

    bool                 dirty = Bool_val(Field(pass, GPU_PASS_VERTEX_DIRTY));
    value                slots = Field(pass, GPU_PASS_VERTEX_BINDINGS);
    SDL_GPUBufferBinding native[GPU_MAX_VERTEX_BUFFERS];
    for (Uint32 i = 0; i < count; ++i) {
        mlsize_t       base   = i * GPU_SLOT_FIELDS;
        value          buffer = Field(slots, base + GPU_SLOT_BUFFER);
        SDL_GPUBuffer* ptr    = buffer == Val_unit ? NULL : osdl_cell_val(buffer)->ptr;
        if (!ptr)
            caml_invalid_argument("Bind a live vertex buffer to each GPU slot before drawing");
        bool   instance  = Int_val(Field(layouts, i)) < 0;
        Uint32 needed    = instance ? instances : vertices;
        Uint32 available = Long_val(Field(slots, base + GPU_SLOT_AVAILABLE));
        if (needed > available)
            caml_invalid_argument(instance ? "The draw exceeds the GPU instance buffer"
                                           : "The draw exceeds the GPU vertex buffer");
        if (dirty)
            native[i] = (SDL_GPUBufferBinding){
                .buffer = ptr, .offset = Long_val(Field(slots, base + GPU_SLOT_OFFSET))};
    }
    if (!dirty) return;

    /* SDL's backends use a dense prefix. Bind only after every slot is present.
     * D3D12 keeps the largest prefix until the pass ends and may rebuild views
     * of slots that this pipeline no longer reads. Replace those stale views.
     * D3D12 also skips the stride update if no buffer or offset has changed. */
    SDL_GPUDevice* device = osdl_cell_val(osdl_gpu_pass_device(pass))->ptr;
    const char*    driver = SDL_GetGPUDeviceDriver(device);
    if (driver && strcmp(driver, "direct3d12") == 0) {
        Uint32 prefix = Int_val(Field(pass, GPU_PASS_VERTEX_PREFIX));
        for (Uint32 i = count; i < prefix; ++i)
            native[i] = native[0];
        count = SDL_max(count, prefix);
        Store_field(pass, GPU_PASS_VERTEX_PREFIX, Val_int(count));

        /* SDL caches this offset. Only the final binding reaches a draw. */
        SDL_GPUBufferBinding changed = {.buffer = native[0].buffer, .offset = native[0].offset + 1};
        SDL_BindGPUVertexBuffers(ptr, 0, &changed, 1);
    }
    SDL_BindGPUVertexBuffers(ptr, 0, native, count);
    Store_field(pass, GPU_PASS_VERTEX_DIRTY, Val_false);
}

CAMLprim value osdl_gpu_draw_primitives(value instances, value pass, value vertices) {
    SDL_GPURenderPass* p       = osdl_live(pass);
    value              layouts = osdl_gpu_draw_layouts(pass);
    Uint32             count   = osdl_gpu_draw_count(vertices);
    Uint32             reps    = Is_long(instances) ? 1 : osdl_gpu_draw_count(Some_val(instances));
    osdl_gpu_draw_vertices(p, pass, layouts, count, reps);

    SDL_DrawGPUPrimitives(p, count, reps, 0, 0);
    return Val_unit;
}

CAMLprim value osdl_gpu_draw_indexed_primitives(value instances, value first_index, value pass,
                                                value indices) {
    SDL_GPURenderPass* p       = osdl_live(pass);
    value              layouts = osdl_gpu_draw_layouts(pass);
    Uint32             count   = osdl_gpu_draw_count(indices);
    Uint32             reps    = Is_long(instances) ? 1 : osdl_gpu_draw_count(Some_val(instances));
    Uint32             first   = osdl_gpu_offset(first_index);
    osdl_gpu_bound(pass, GPU_PASS_INDEX_BUFFER, "Bind a live GPU index buffer before drawing");
    if (!osdl_gpu_range_fits(first, count, Long_val(Field(pass, GPU_PASS_INDEX_COUNT))))
        caml_invalid_argument("The draw exceeds the GPU index buffer");
    osdl_gpu_draw_vertices(p, pass, layouts, 1, reps);

    SDL_DrawGPUIndexedPrimitives(p, count, reps, first, 0, 0);
    return Val_unit;
}

CAMLprim value osdl_gpu_end_render_pass(value pass) {
    SDL_GPURenderPass* ptr = osdl_take(pass);
    if (ptr) {
        SDL_EndGPURenderPass(ptr);
        value device = osdl_gpu_pass_device(pass);
        value target = Field(pass, GPU_PASS_TARGET);
        if (target != Val_unit) {
            --osdl_cell_val(target)->children;
            Store_field(pass, GPU_PASS_TARGET, Val_unit);
        }
        Store_field(device, GPU_DEVICE_RENDERING, Val_false);
        Store_field(pass, GPU_PASS_PIPELINE, Val_unit);
        Store_field(pass, GPU_PASS_VERTEX_BINDINGS, Val_unit);
        Store_field(pass, GPU_PASS_INDEX_BUFFER, Val_unit);
        Store_field(pass, GPU_PASS_SAMPLERS, Val_unit);
    }
    return Val_unit;
}

CAMLprim value osdl_gpu_clear_and_present(value claim, value color) {
    CAMLparam2(claim, color);

    SDL_Window*    w = osdl_gpu_available_window(claim);
    SDL_GPUDevice* d = osdl_gpu_parent_device(claim);
    osdl_gpu_require_no_render_pass(osdl_parent(claim));

    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(d);
    if (!commands) osdl_fail("SDL_AcquireGPUCommandBuffer");

    SDL_GPUTexture* image = NULL;
    if (!osdl_gpu_wait_for_image(commands, w, &image, NULL, NULL))
        osdl_gpu_fail_frame(Val_unit, commands, image != NULL,
                            "SDL_WaitAndAcquireGPUSwapchainTexture");
    if (!image) {
        osdl_check(SDL_CancelGPUCommandBuffer(commands), "SDL_CancelGPUCommandBuffer");
        CAMLreturn(Val_false);
    }

    SDL_GPURenderPass* pass = osdl_gpu_begin_clear_pass(commands, image, color);
    if (!pass) osdl_gpu_fail_frame(Val_unit, commands, true, "SDL_BeginGPURenderPass");
    SDL_EndGPURenderPass(pass);
    osdl_check(SDL_SubmitGPUCommandBuffer(commands), "SDL_SubmitGPUCommandBuffer");
    CAMLreturn(Val_true);
}
