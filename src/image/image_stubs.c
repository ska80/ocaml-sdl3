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

CAMLprim value osdl_image_load_io(value stream) {
    CAMLparam1(stream);
    CAMLlocal1(handle);

    SDL_IOStream* io = osdl_unborrowed_io(stream);
    handle           = osdl_new_handle(osdl_parent(stream));

    CAMLreturn(osdl_publish(handle, IMG_Load_IO(io, false), "IMG_Load_IO"));
}

CAMLprim value osdl_image_load_texture(value renderer, value path) {
    CAMLparam2(renderer, path);
    CAMLlocal1(handle);

    handle = osdl_new_handle(renderer);

    SDL_Texture* texture = IMG_LoadTexture(osdl_live(renderer), osdl_cstring(path));
    CAMLreturn(osdl_publish(handle, texture, "IMG_LoadTexture"));
}

CAMLprim value osdl_image_load_texture_io(value renderer, value stream) {
    CAMLparam2(renderer, stream);
    CAMLlocal1(handle);

    SDL_Renderer* r  = osdl_live(renderer);
    SDL_IOStream* io = osdl_unborrowed_io(stream);
    handle           = osdl_new_handle(renderer);

    CAMLreturn(osdl_publish(handle, IMG_LoadTexture_IO(r, io, false), "IMG_LoadTexture_IO"));
}

CAMLprim value osdl_image_save_png(value surface, value path) {
    osdl_check(IMG_SavePNG(osdl_live(surface), osdl_cstring(path)), "IMG_SavePNG");
    return Val_unit;
}

static int jpg_quality(value quality) {
    int q = Is_long(quality) ? 90 : osdl_nonnegative_int(Some_val(quality));
    if (q > 100) caml_invalid_argument("JPEG quality must be in [0, 100]");
    return q;
}

CAMLprim value osdl_image_save_jpg(value quality, value surface, value path) {
    int q = jpg_quality(quality);

    osdl_check(IMG_SaveJPG(osdl_live(surface), osdl_cstring(path), q), "IMG_SaveJPG");
    return Val_unit;
}

/* Some versions of the PNG and JPEG encoders ignore short writes. Keep the
 * first write error, even if the encoder reports success. */
typedef struct {
    SDL_IOStream* dst;
    const char*   function;
    char          error[1024];
} image_writer;

static size_t SDLCALL image_write(void* userdata, const void* ptr, size_t size,
                                  SDL_IOStatus* status) {
    image_writer* writer = userdata;
    if (*writer->error) {
        *status = SDL_IO_STATUS_ERROR;
        return 0;
    }

    size_t count = SDL_WriteIO(writer->dst, ptr, size);
    if (count != size) {
        const char* error = SDL_GetError();
        SDL_snprintf(writer->error, sizeof(writer->error), "%s: %s", writer->function,
                     *error ? error : "Cannot write all image bytes");
        *status = SDL_IO_STATUS_ERROR;
    }
    return count;
}

static value image_save_io(value surface, value stream, bool png, int quality) {
    SDL_Surface* s      = osdl_live(surface);
    image_writer writer = {.dst      = osdl_unborrowed_io(stream),
                           .function = png ? "IMG_SavePNG_IO" : "IMG_SaveJPG_IO"};

    SDL_IOStreamInterface iface;
    SDL_INIT_INTERFACE(&iface);
    iface.write         = image_write;
    SDL_IOStream* proxy = SDL_OpenIO(&iface, &writer);
    if (!proxy) osdl_fail("SDL_OpenIO");

    bool ok = png ? IMG_SavePNG_IO(s, proxy, false) : IMG_SaveJPG_IO(s, proxy, false, quality);
    if (!ok && !*writer.error)
        osdl_error_message(writer.error, sizeof(writer.error), writer.function);
    SDL_CloseIO(proxy);

    if (*writer.error) osdl_raise_error(writer.error);
    return Val_unit;
}

CAMLprim value osdl_image_save_png_io(value surface, value stream) {
    return image_save_io(surface, stream, true, 0);
}

CAMLprim value osdl_image_save_jpg_io(value quality, value surface, value stream) {
    return image_save_io(surface, stream, false, jpg_quality(quality));
}

/* Animations own their SDL surfaces. Export only copies or uploaded textures. */

CAMLprim value osdl_image_animation_load(value context, value path) {
    CAMLparam2(context, path);
    CAMLlocal1(handle);

    handle = osdl_new_handle(context);
    osdl_live(context);

    IMG_Animation* anim = IMG_LoadAnimation(osdl_cstring(path));
    CAMLreturn(osdl_publish(handle, anim, "IMG_LoadAnimation"));
}

CAMLprim value osdl_image_animation_load_io(value stream) {
    CAMLparam1(stream);
    CAMLlocal1(handle);

    handle           = osdl_new_handle(osdl_parent(stream));
    SDL_IOStream* io = osdl_unborrowed_io(stream);

    IMG_Animation* anim = IMG_LoadAnimation_IO(io, false);
    CAMLreturn(osdl_publish(handle, anim, "IMG_LoadAnimation_IO"));
}

OSDL_DESTROY(osdl_image_animation_destroy, IMG_Animation, IMG_FreeAnimation)

CAMLprim value osdl_image_animation_size(value animation) {
    IMG_Animation* anim = osdl_live(animation);
    return osdl_int_pair(anim->w, anim->h);
}

CAMLprim value osdl_image_animation_frame_count(value animation) {
    IMG_Animation* anim = osdl_live(animation);
    return osdl_val_int(anim->count);
}

static int image_frame_index(const IMG_Animation* anim, value index) {
    intnat i = Long_val(index);
    if (i < 0 || i >= anim->count) caml_invalid_argument("SDL_image frame index is out of range");
    return (int)i;
}

CAMLprim value osdl_image_animation_frame_delay_ms(value animation, value index) {
    IMG_Animation* anim = osdl_live(animation);
    return osdl_val_int(anim->delays[image_frame_index(anim, index)]);
}

CAMLprim value osdl_image_animation_copy_frame(value animation, value index) {
    CAMLparam2(animation, index);
    CAMLlocal1(handle);

    handle              = osdl_new_handle(osdl_parent(animation));
    IMG_Animation* anim = osdl_live(animation);
    int            i    = image_frame_index(anim, index);

    SDL_Surface* surface = SDL_DuplicateSurface(anim->frames[i]);
    CAMLreturn(osdl_publish(handle, surface, "SDL_DuplicateSurface"));
}

CAMLprim value osdl_image_animation_frame_texture(value renderer, value animation, value index) {
    CAMLparam3(renderer, animation, index);
    CAMLlocal1(handle);

    handle              = osdl_new_handle(renderer);
    SDL_Renderer*  r    = osdl_live(renderer);
    IMG_Animation* anim = osdl_live(animation);
    int            i    = image_frame_index(anim, index);

    SDL_Texture* texture = SDL_CreateTextureFromSurface(r, anim->frames[i]);
    CAMLreturn(osdl_publish(handle, texture, "SDL_CreateTextureFromSurface"));
}
