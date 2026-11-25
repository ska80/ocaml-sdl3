# Streams, images, and text

## Use file and memory streams

A stream reads or writes bytes. Use `Io.seek` to change the byte position in a seekable stream.
Open a binary file with `Io.open_file`. The file mode determines whether you can call `Io.read`,
`Io.write`, or both. Use `Io.with_file` to close the file when a function exits.

A bigarray is a buffer outside the OCaml heap. Use `Io.of_memory` to read an existing bigarray.  Use
`Io.of_memory_rw` to read or change it. Neither call copies the bigarray. The stream keeps the
buffer alive until you call `Io.close`. A memory stream has a fixed size.

Load BMP images, SDL3_image images and textures, or SDL3_mixer audio from a readable stream. Save
BMP, PNG, or JPEG data to a writable stream. These calls leave the stream open and do not retain
it. `Sdl3_ttf.Font.open_io` keeps using the stream. Close the font before you use or close that
stream again. Keep the buffer of a memory stream unchanged until you close the font.

```ocaml
let load_bmp context path =
  Sdl3.Io.with_file context ~mode:Read path Sdl3.Surface.load_bmp_io
```

## Load animated images

A surface is a pixel buffer in memory. A texture is an image that a renderer can draw. Use
[`Sdl3_image.Animation.load`](../src/image/sdl3_image.mli) for a file. For a readable, seekable
stream, use `Animation.load_io`. SDL_image decodes all frames during the call. You can close the
stream after the call. The available formats depend on the SDL_image build.

Read the image size with `Animation.size` and the number of frames with `Animation.frame_count`.
Frame indices start at zero. Use `Animation.frame_delay_ms` to get the display time for a frame in
milliseconds. Your program chooses when to advance to the next frame.

Use `Animation.copy_frame` if you need a surface or `Animation.frame_texture` if you need a
texture. Both results can outlive the animation. For repeated drawing, upload each frame once and
reuse the textures. Call `Animation.destroy` to free the decoded frames. Destroy the copies and
textures separately.

## Draw reusable text

A text engine prepares character images for drawing. Use
[`Sdl3_ttf.Text_engine.create_surface`](../src/ttf/sdl3_ttf.mli) to draw to surfaces. Use
`Text_engine.create_renderer` to draw with one renderer. Call `Text.create` with the engine, a font,
and a UTF-8 string. The engine determines which draw function you can call.

Keep the text object across frames. Change its contents with `Text.set_string`. Use `Text.set_color`
to change its color. Use `Text.set_wrap_width` to set the line width in pixels.  `Text.size`
measures the text.

Use `Text.draw_surface` to draw to a surface. Use `Text.draw_renderer` to draw to the current target
of the renderer. The draw and size calls prepare the text after a change. If you need to prepare the
text earlier, call `Text.update`.

Use `Text.destroy` before closing the font or destroying the engine. If an engine uses a renderer,
destroy the engine first. Close all fonts and engines before quitting SDL_ttf.

For GPU drawing, use `Font.render` to draw text to a surface. Use `Surface.read_rgba` to copy the
surface into a buffer for upload. Each pixel has four bytes: red, green, blue, and alpha.
