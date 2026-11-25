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

/* Use only after validating or taking the claim. It keeps the device live. */
static SDL_GPUDevice* osdl_gpu_claim_device(value claim) {
    return osdl_cell_val(osdl_parent(claim))->ptr;
}

CAMLprim value osdl_gpu_release_window(value claim) {
    SDL_Window* w = osdl_take(claim);
    if (w) {
        SDL_ReleaseWindowFromGPUDevice(osdl_gpu_claim_device(claim), w);
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
    return Val_bool(SDL_WindowSupportsGPUPresentMode(osdl_gpu_claim_device(claim), w,
                                                     osdl_gpu_present_mode(mode)));
}

CAMLprim value osdl_gpu_supports_composition(value claim, value composition) {
    SDL_Window* w = osdl_live(claim);
    return Val_bool(SDL_WindowSupportsGPUSwapchainComposition(osdl_gpu_claim_device(claim), w,
                                                              osdl_gpu_composition(composition)));
}

CAMLprim value osdl_gpu_set_swapchain_parameters(value claim, value composition, value mode) {
    SDL_Window* w = osdl_live(claim);
    osdl_check(SDL_SetGPUSwapchainParameters(osdl_gpu_claim_device(claim), w,
                                             osdl_gpu_composition(composition),
                                             osdl_gpu_present_mode(mode)),
               "SDL_SetGPUSwapchainParameters");
    return Val_unit;
}

/* Clear and present a frame without exposing the borrowed swapchain texture. */

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

CAMLprim value osdl_gpu_clear_and_present(value claim, value color) {
    CAMLparam2(claim, color);

    SDL_Window*    w = osdl_live(claim);
    SDL_GPUDevice* d = osdl_gpu_claim_device(claim);
    SDL_Color      c = osdl_color(color);

    SDL_GPUCommandBuffer* commands = SDL_AcquireGPUCommandBuffer(d);
    if (!commands) osdl_fail("SDL_AcquireGPUCommandBuffer");

    SDL_GPUTexture* image = NULL;
    caml_enter_blocking_section_no_pending();
    bool ok = SDL_WaitAndAcquireGPUSwapchainTexture(commands, w, &image, NULL, NULL);
    caml_leave_blocking_section();

    if (!ok) osdl_gpu_fail_frame(commands, image != NULL, "SDL_WaitAndAcquireGPUSwapchainTexture");
    if (!image) {
        osdl_check(SDL_CancelGPUCommandBuffer(commands), "SDL_CancelGPUCommandBuffer");
        CAMLreturn(Val_false);
    }

    SDL_GPUColorTargetInfo target = {
        .texture     = image,
        .clear_color = {c.r / 255.0f, c.g / 255.0f, c.b / 255.0f, c.a / 255.0f},
        .load_op     = SDL_GPU_LOADOP_CLEAR,
        .store_op    = SDL_GPU_STOREOP_STORE,
    };
    SDL_GPURenderPass* pass = SDL_BeginGPURenderPass(commands, &target, 1, NULL);
    if (!pass) osdl_gpu_fail_frame(commands, true, "SDL_BeginGPURenderPass");
    SDL_EndGPURenderPass(pass);
    osdl_check(SDL_SubmitGPUCommandBuffer(commands), "SDL_SubmitGPUCommandBuffer");
    CAMLreturn(Val_true);
}
