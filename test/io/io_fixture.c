#include "sdl3_stubs.h"

static size_t SDLCALL fail_read(void* userdata, void* ptr, size_t size, SDL_IOStatus* status) {
    (void)userdata;
    (void)size;
    *(Uint8*)ptr = 42;
    *status      = SDL_IO_STATUS_ERROR;
    SDL_SetError("Test error after one byte");
    return 1;
}

static bool SDLCALL fail_close(void* userdata) {
    (void)userdata;
    return SDL_SetError("Test close failure");
}

CAMLprim value test_io_open_failing_stream(value context) {
    CAMLparam1(context);
    CAMLlocal1(handle);

    osdl_live(context);
    handle = osdl_new_attached_handle(context, Val_unit);

    SDL_IOStreamInterface iface;
    SDL_INIT_INTERFACE(&iface);
    iface.read  = fail_read;
    iface.close = fail_close;
    CAMLreturn(osdl_publish(handle, SDL_OpenIO(&iface, NULL), "SDL_OpenIO"));
}
