#include "sdl3_stubs.h"

/* Test bytes on the GPU. The caller supplies the expected buffer contents. */
CAMLprim value test_gpu_buffer_matches(value buffer, value expected) {
    SDL_GPUBuffer* src = osdl_live(buffer);
    SDL_GPUDevice* d   = osdl_live(osdl_parent(buffer));
    size_t         len = caml_string_length(expected);
    if (!len || len % 4 || (size_t)(Uint32)len != len)
        caml_invalid_argument("Invalid GPU buffer readback size");

    SDL_GPUTransferBufferCreateInfo info     = {.usage = SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
                                                .size  = (Uint32)len};
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

    SDL_GPUBufferRegion           from = {.buffer = src, .size = (Uint32)len};
    SDL_GPUTransferBufferLocation to   = {.transfer_buffer = download};
    SDL_DownloadFromGPUBuffer(pass, &from, &to);
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
    same = memcmp(mapped, String_val(expected), len) == 0;
    SDL_UnmapGPUTransferBuffer(d, download);
    error = NULL;

cleanup:
    if (error) osdl_error_message(message, sizeof(message), error);
    if (commands) SDL_CancelGPUCommandBuffer(commands);
    if (fence) SDL_ReleaseGPUFence(d, fence);
    SDL_ReleaseGPUTransferBuffer(d, download);
    if (error) osdl_raise_error(message);
    return Val_bool(same);
}
