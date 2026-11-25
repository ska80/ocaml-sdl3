#include "gpu_render_pass.h"

/* Read back a buffer or a texture and compare the bytes. */
static bool test_gpu_matches(SDL_GPUDevice* d, const SDL_GPUBufferRegion* buffer,
                             const SDL_GPUTextureRegion* texture, Uint32 len,
                             const void* expected) {
    SDL_GPUTransferBufferCreateInfo info     = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
                                                .size  = len};
    SDL_GPUTransferBuffer*          download = SDL_CreateGPUTransferBuffer(d, &info);
    if (!download) osdl_fail("SDL_CreateGPUTransferBuffer");

    char                  message[1024];
    SDL_GPUFence*         fence    = NULL;
    const char*           error    = "SDL_AcquireGPUCommandBuffer";
    bool                  same     = false;
    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(d);
    if (!commands) goto cleanup;

    error                 = "SDL_BeginGPUCopyPass";
    SDL_GPUCopyPass* pass = SDL_BeginGPUCopyPass(commands);
    if (!pass) goto cleanup;

    if (buffer) {
        SDL_GPUTransferBufferLocation to = {.transfer_buffer = download};
        SDL_DownloadFromGPUBuffer(pass, buffer, &to);
    } else {
        SDL_GPUTextureTransferInfo to = {.transfer_buffer = download};
        SDL_DownloadFromGPUTexture(pass, texture, &to);
    }
    SDL_EndGPUCopyPass(pass);

    error    = "SDL_SubmitGPUCommandBufferAndAcquireFence";
    fence    = SDL_SubmitGPUCommandBufferAndAcquireFence(commands);
    commands = NULL;
    if (!fence) goto cleanup;

    error = "SDL_WaitForGPUFences";
    if (!SDL_WaitForGPUFences(d, true, &fence, 1)) goto cleanup;

    error              = "SDL_MapGPUTransferBuffer";
    const void* mapped = SDL_MapGPUTransferBuffer(d, download, false);
    if (!mapped) goto cleanup;
    same = memcmp(mapped, expected, len) == 0;
    if (!same && texture && len == 4) {
        const Uint8* actual = mapped;
        const Uint8* want   = expected;
        SDL_Log("GPU pixel bytes: got [%u, %u, %u, %u], expected [%u, %u, %u, %u]", actual[0],
                actual[1], actual[2], actual[3], want[0], want[1], want[2], want[3]);
    }
    SDL_UnmapGPUTransferBuffer(d, download);
    error = NULL;

cleanup:
    if (error) osdl_error_message(message, sizeof(message), error);
    if (commands) SDL_CancelGPUCommandBuffer(commands);
    if (fence) SDL_ReleaseGPUFence(d, fence);
    SDL_ReleaseGPUTransferBuffer(d, download);
    if (error) osdl_raise_error(message);
    return same;
}

CAMLprim value test_gpu_buffer_matches(value buffer, value expected) {
    SDL_GPUBuffer* src = osdl_live(buffer);
    SDL_GPUDevice* d   = osdl_live(osdl_parent(buffer));
    size_t         len = caml_string_length(expected);
    if (!len || len % 4 || (size_t)(Uint32)len != len)
        caml_invalid_argument("Invalid GPU buffer readback size");

    SDL_GPUBufferRegion from = {.buffer = src, .size = (Uint32)len};
    return Val_bool(test_gpu_matches(d, &from, NULL, (Uint32)len, String_val(expected)));
}

/* A one-pixel render target with the same format as the window. The tests
 * can read it back without trying to copy an image owned by the swapchain. */
CAMLprim value test_gpu_create_color_target(value claim) {
    CAMLparam1(claim);
    CAMLlocal2(cell, target);

    cell   = osdl_new_cell(osdl_parent(claim), &osdl_handle_ops);
    target = caml_alloc_3(0, cell, osdl_parent(claim), Val_unit);

    SDL_Window*          w      = osdl_live(claim);
    SDL_GPUDevice*       d      = osdl_live(osdl_parent(claim));
    SDL_GPUTextureFormat format = SDL_GetGPUSwapchainTextureFormat(d, w);
    if (format != SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM &&
        format != SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM &&
        format != SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB &&
        format != SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB)
        caml_failwith("Unexpected GPU test color target format");
    Store_field(target, 2, Val_int(format));

    SDL_GPUTextureCreateInfo info = {.type                 = SDL_GPU_TEXTURETYPE_2D,
                                     .format               = format,
                                     .usage                = SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
                                     .width                = 1,
                                     .height               = 1,
                                     .layer_count_or_depth = 1,
                                     .num_levels           = 1,
                                     .sample_count         = SDL_GPU_SAMPLECOUNT_1};
    SDL_GPUTexture*          ptr  = SDL_CreateGPUTexture(d, &info);
    CAMLreturn(osdl_publish(target, ptr, "SDL_CreateGPUTexture"));
}

CAMLprim value test_gpu_release_color_target(value target) {
    SDL_GPUTexture* ptr = osdl_take(target);
    if (ptr) SDL_ReleaseGPUTexture(osdl_live(osdl_parent(target)), ptr);
    return Val_unit;
}

CAMLprim value test_gpu_begin_color_pass(value commands, value target) {
    CAMLparam2(commands, target);
    CAMLlocal1(pass);

    pass = osdl_gpu_new_render_pass(commands);

    SDL_GPUCommandBuffer* c = osdl_live(commands);
    SDL_GPUTexture*       t = osdl_live(target);
    if (osdl_cell_val(commands)->children || osdl_parent(commands) != osdl_parent(target))
        caml_invalid_argument("Invalid GPU test render pass");
    Store_field(pass, GPU_PASS_FORMAT, Field(target, 2));

    SDL_GPUColorTargetInfo info = {
        .texture = t, .load_op = SDL_GPU_LOADOP_CLEAR, .store_op = SDL_GPU_STOREOP_STORE};
    SDL_GPURenderPass* ptr = SDL_BeginGPURenderPass(c, &info, 1, NULL);
    CAMLreturn(osdl_publish(pass, ptr, "SDL_BeginGPURenderPass"));
}

CAMLprim value test_gpu_color_target_matches(value target, value color) {
    SDL_GPUTexture*      t      = osdl_live(target);
    SDL_GPUDevice*       d      = osdl_live(osdl_parent(target));
    SDL_GPUTextureFormat format = Int_val(Field(target, 2));
    bool                 bgra   = format == SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM ||
                format == SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB;
    SDL_Color            c          = osdl_color(color);
    const Uint8          expected[] = {bgra ? c.b : c.r, c.g, bgra ? c.r : c.b, c.a};
    SDL_GPUTextureRegion from       = {.texture = t, .w = 1, .h = 1, .d = 1};
    return Val_bool(test_gpu_matches(d, NULL, &from, sizeof(expected), expected));
}
