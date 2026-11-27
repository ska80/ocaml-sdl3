#include "gpu_handles.h"

/* Read back a buffer or a texture and compare the bytes. */
static bool test_gpu_matches(SDL_GPUDevice* d, const SDL_GPUBufferRegion* buffer,
                             const SDL_GPUTextureRegion* texture, Uint32 len, const void* expected,
                             int tolerance) {
    SDL_GPUTransferBufferCreateInfo info     = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
                                                .size  = (len + 3u) & ~3u};
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
    if (!same && texture) {
        const Uint8* actual = mapped;
        const Uint8* want   = expected;
        same                = true;
        for (Uint32 i = 0; i < len; ++i) {
            if (SDL_abs(actual[i] - want[i]) <= tolerance) continue;
            SDL_Log("GPU image byte %u: got %u, expected %u", i, actual[i], want[i]);
            same = false;
            break;
        }
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
    return Val_bool(test_gpu_matches(d, &from, NULL, (Uint32)len, String_val(expected), 0));
}

CAMLprim value test_gpu_texture_matches(value region, value expected, value tolerance) {
    value                texture = Field(region, 0), rect = Field(region, 2);
    SDL_GPUTexture*      t   = osdl_live(texture);
    SDL_GPUDevice*       d   = osdl_live(osdl_parent(texture));
    osdl_gpu_texture_mip mip = osdl_gpu_mip(texture, Field(region, 1), false);
    Uint32 x = osdl_nonnegative_int(Field(rect, 0)), y = osdl_nonnegative_int(Field(rect, 1));
    Uint32 w = osdl_positive_int(Field(rect, 2)), h = osdl_positive_int(Field(rect, 3));
    size_t len   = caml_string_length(expected);
    Uint32 pixel = SDL_GPUTextureFormatTexelBlockSize(osdl_gpu_image_format(texture));
    if (x > mip.w || w > mip.w - x || y > mip.h || h > mip.h - y || (Uint64)w * h * pixel != len ||
        len > SDL_MAX_UINT32 - 3u)
        caml_invalid_argument("Invalid GPU texture readback region or byte length");

    SDL_GPUTextureRegion from = {
        .texture = t, .mip_level = mip.level, .x = x, .y = y, .w = w, .h = h, .d = 1};
    return Val_bool(
        test_gpu_matches(d, NULL, &from, (Uint32)len, String_val(expected), Int_val(tolerance)));
}
