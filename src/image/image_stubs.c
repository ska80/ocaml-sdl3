#include "sdl3_stubs.h"

#include <SDL3_image/SDL_image.h>

CAMLprim value osdl_image_version(value unit) {
    (void)unit;
    return osdl_version_value(IMG_Version());
}

CAMLprim value osdl_image_load(value context, value path) {
    CAMLparam2(context, path);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    CAMLreturn(osdl_publish(handle, IMG_Load(osdl_cstring(path)), "IMG_Load"));
}

CAMLprim value osdl_image_load_memory(value context, value buffer) {
    CAMLparam2(context, buffer);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    SDL_IOStream* io =
        SDL_IOFromConstMem(Caml_ba_data_val(buffer), (size_t)Caml_ba_array_val(buffer)->dim[0]);
    if (!io) osdl_fail("SDL_IOFromConstMem");

    CAMLreturn(osdl_publish(handle, IMG_Load_IO(io, true), "IMG_Load_IO"));
}

CAMLprim value osdl_image_load_texture(value renderer, value path) {
    CAMLparam2(renderer, path);
    CAMLlocal1(handle);

    handle = osdl_new_handle(renderer);

    SDL_Texture* texture = IMG_LoadTexture(osdl_live(renderer), osdl_cstring(path));
    CAMLreturn(osdl_publish(handle, texture, "IMG_LoadTexture"));
}

CAMLprim value osdl_image_save_png(value surface, value path) {
    osdl_check(IMG_SavePNG(osdl_live(surface), osdl_cstring(path)), "IMG_SavePNG");
    return Val_unit;
}

CAMLprim value osdl_image_save_jpg(value quality, value surface, value path) {
    int q = Is_long(quality) ? 90 : osdl_nonnegative_int(Some_val(quality));
    if (q > 100) caml_invalid_argument("JPEG quality must be in [0, 100]");

    osdl_check(IMG_SaveJPG(osdl_live(surface), osdl_cstring(path), q), "IMG_SaveJPG");
    return Val_unit;
}
