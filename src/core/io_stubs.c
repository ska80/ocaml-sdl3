#include "sdl3_stubs.h"

/* Stream handles own the SDL stream and keep borrowed bigarray storage alive. */

CAMLprim value osdl_io_open_file(value context, value path, value mode) {
    CAMLparam3(context, path, mode);
    CAMLlocal1(handle);

    osdl_live(context);
    handle = osdl_new_attached_handle(context, Val_bool(String_val(mode)[0] == 'a'));

    SDL_IOStream* io = SDL_IOFromFile(osdl_cstring(path), String_val(mode));
    CAMLreturn(osdl_publish(handle, io, "SDL_IOFromFile"));
}

static value io_of_memory(value context, value buffer, bool writable) {
    CAMLparam2(context, buffer);
    CAMLlocal1(handle);

    osdl_live(context);
    size_t size = (size_t)Caml_ba_array_val(buffer)->dim[0];
    if (!size) caml_invalid_argument("A memory stream needs a nonempty buffer");
    handle = osdl_new_attached_handle(context, buffer);

    void* data = Caml_ba_data_val(buffer);
    if (writable) CAMLreturn(osdl_publish(handle, SDL_IOFromMem(data, size), "SDL_IOFromMem"));
    CAMLreturn(osdl_publish(handle, SDL_IOFromConstMem(data, size), "SDL_IOFromConstMem"));
}

CAMLprim value osdl_io_of_memory(value context, value buffer) {
    return io_of_memory(context, buffer, false);
}

CAMLprim value osdl_io_of_memory_rw(value context, value buffer) {
    return io_of_memory(context, buffer, true);
}

CAMLprim value osdl_io_close(value stream) {
    SDL_IOStream* io = osdl_take(stream);
    if (io) {
        bool ok = SDL_CloseIO(io);
        osdl_forget_attachment(stream);
        osdl_check(ok, "SDL_CloseIO");
    }
    return Val_unit;
}

/* Size and position are measured in bytes. */

CAMLprim value osdl_io_size(value stream) {
    Sint64 size = SDL_GetIOSize(osdl_unborrowed_io(stream));
    if (size < 0) osdl_fail("SDL_GetIOSize");
    return caml_copy_int64(size);
}

static Sint64 io_position(SDL_IOStream* io) {
    Sint64 pos = SDL_TellIO(io);
    if (pos < 0) osdl_fail("SDL_TellIO");
    return pos;
}

CAMLprim value osdl_io_tell(value stream) {
    return caml_copy_int64(io_position(osdl_unborrowed_io(stream)));
}

CAMLprim value osdl_io_seek(value stream, value origin, value offset) {
    static const SDL_IOWhence origins[] = {SDL_IO_SEEK_SET, SDL_IO_SEEK_CUR, SDL_IO_SEEK_END};

    SDL_IOStream* io      = osdl_unborrowed_io(stream);
    SDL_IOWhence  from    = origins[Int_val(origin)];
    Sint64        n       = Int64_val(offset);
    value         backing = osdl_attachment(stream);

    if (Is_block(backing)) {
        /* Limit the byte position before SDL adds it to a memory pointer. */
        Sint64 size = Caml_ba_array_val(backing)->dim[0];
        Sint64 base = from == SDL_IO_SEEK_CUR ? io_position(io)
                    : from == SDL_IO_SEEK_END ? size
                                              : 0;
        n           = n < -base ? 0 : n > size - base ? size : base + n;
        from        = SDL_IO_SEEK_SET;
    }

    Sint64 pos = SDL_SeekIO(io, n, from);
    if (pos < 0) osdl_fail("SDL_SeekIO");
    return caml_copy_int64(pos);
}

/* Direct transfers into or out of a region of a bigarray. */

typedef struct {
    Uint8* data;
    size_t size;
} io_slice;

static io_slice io_buffer_slice(value stream, value buffer, value offset, value length) {
    intnat size = Caml_ba_array_val(buffer)->dim[0];
    intnat off = Long_val(offset), len = Long_val(length);
    if (off < 0 || off > size || len < 0 || len > size - off)
        caml_invalid_argument("Stream transfer is outside the byte buffer");
    if (!len) return (io_slice){NULL, 0};

    Uint8* data    = (Uint8*)Caml_ba_data_val(buffer) + off;
    value  backing = osdl_attachment(stream);
    if (Is_block(backing)) {
        /* SDL copies with memcpy, including when two bigarrays share storage. */
        uintptr_t a        = (uintptr_t)data;
        uintptr_t b        = (uintptr_t)Caml_ba_data_val(backing);
        size_t    capacity = (size_t)Caml_ba_array_val(backing)->dim[0];
        if (a <= b ? b - a < (size_t)len : a - b < capacity)
            caml_invalid_argument("Transfer buffer overlaps the stream's memory");
    }
    return (io_slice){data, (size_t)len};
}

CAMLprim value osdl_io_read(value stream, value buffer, value offset, value length) {
    SDL_IOStream* io    = osdl_unborrowed_io(stream);
    io_slice      slice = io_buffer_slice(stream, buffer, offset, length);
    if (!slice.size) return Val_int(0);

    size_t count = SDL_ReadIO(io, slice.data, slice.size);
    if (count < slice.size) {
        SDL_IOStatus status = SDL_GetIOStatus(io);
        if (status != SDL_IO_STATUS_READY && status != SDL_IO_STATUS_EOF) osdl_fail("SDL_ReadIO");
    }
    return Val_long(count);
}

CAMLprim value osdl_io_write(value stream, value buffer, value offset, value length) {
    SDL_IOStream* io    = osdl_unborrowed_io(stream);
    io_slice      slice = io_buffer_slice(stream, buffer, offset, length);
    if (!slice.size) return Val_unit;

    if (SDL_WriteIO(io, slice.data, slice.size) != slice.size) {
        if (Is_block(osdl_attachment(stream)))
            osdl_raise_error("SDL_WriteIO: memory stream is full");
        osdl_fail("SDL_WriteIO");
    }
    return Val_unit;
}

CAMLprim value osdl_io_flush(value stream) {
    osdl_check(SDL_FlushIO(osdl_unborrowed_io(stream)), "SDL_FlushIO");
    return Val_unit;
}
