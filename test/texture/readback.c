#include "sdl3_stubs.h"

CAMLprim value test_texture_read_pixel(value renderer, value x, value y) {
    SDL_Rect     area    = {osdl_int(x), osdl_int(y), 1, 1};
    SDL_Surface* surface = SDL_RenderReadPixels(osdl_live(renderer), &area);
    if (!surface) osdl_fail("SDL_RenderReadPixels");

    SDL_Color color;
    if (!SDL_ReadSurfacePixel(surface, 0, 0, &color.r, &color.g, &color.b, &color.a)) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "SDL_ReadSurfacePixel");
        SDL_DestroySurface(surface);
        osdl_raise_error(message);
    }
    SDL_DestroySurface(surface);
    return caml_alloc_4(0, Val_int(color.r), Val_int(color.g), Val_int(color.b), Val_int(color.a));
}
