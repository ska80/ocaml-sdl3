#include "sdl3_stubs.h"

CAMLprim value test_sprite_batch_read_pixel(value renderer, value x, value y) {
    CAMLparam3(renderer, x, y);

    SDL_Renderer* r    = osdl_live(renderer);
    SDL_Rect      area = {osdl_int(x), osdl_int(y), 1, 1};
    SDL_Surface*  s    = SDL_RenderReadPixels(r, &area);
    if (!s) osdl_fail("SDL_RenderReadPixels");

    SDL_Color color;
    if (!SDL_ReadSurfacePixel(s, 0, 0, &color.r, &color.g, &color.b, &color.a)) {
        char message[1024];
        osdl_error_message(message, sizeof(message), "SDL_ReadSurfacePixel");
        SDL_DestroySurface(s);
        osdl_raise_error(message);
    }
    SDL_DestroySurface(s);
    CAMLreturn(
        caml_alloc_4(0, Val_int(color.r), Val_int(color.g), Val_int(color.b), Val_int(color.a)));
}
