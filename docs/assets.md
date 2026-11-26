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

## Compose images in memory

A surface is a pixel buffer in memory. A blit copies pixels between surfaces. Use `Surface.blit
source target` to copy at the original size. Pass `~src` to select a rectangle.  Pass `~dst` to
place the copy. An unscaled blit uses only the destination rectangle's `x` and `y`.

Use `Surface.blit_scaled` to copy into a destination rectangle of a different size. Keep the source
rectangle inside the source. The default, `Nearest`, keeps hard pixel edges. For smooth edges, use
`~scale_mode:Linear` with true-color surfaces, which store colors instead of indices.

A color key marks one pixel value as transparent. Use `Surface.set_color_key` to set it. For a
surface with an alpha channel, set the blend mode to `Blend_mode.None` to blit with the key instead
of alpha. If you scale a keyed sprite with linear filtering or clip a scaled copy, convert the
source to `Rgba32` first. The conversion puts transparency in the alpha channel.

`Surface.scale` and `Surface.convert` make new surfaces. Destroy each result separately.
`Surface.flip` changes the original surface.

A texture is an image that a renderer can draw. A texture atlas holds several images in one
texture. Copy the images into one surface, then upload it with `Texture.of_surface`. The texture
keeps its own copy, so destroy the surface after the upload. See [Draw from a texture
atlas](rendering.md#draw-from-a-texture-atlas) to draw its regions.

## Edit pixels during a lock

Use `Surface.with_lock` to read or change pixels during a function call. Use `Surface.Locked` to
access the pixels. A surface lock keeps the old pixels, unlike a streaming texture lock. The binding
ends the lock even if the function raises an exception. Writes before the exception stay in the
surface. Do not use the locked view after the function exits.

For a generated image, fill a reusable bigarray, then call `Surface.Locked.copy_from`. Use the
surface's byte order. For `Rgba32`, put red, green, blue, and alpha in that order. Pass `~pitch` for
the byte distance between rows. The last row does not need padding. Use `copy_to` to read back rows
without changing their format. Use `Surface.read_rgba` outside the lock to convert to RGBA.

## Swap palettes on indexed sprites

A palette is a table of colors. An `Index8` surface stores one byte per pixel. That byte selects an
entry in the palette. When you change the palette, the same pixel indices select new colors.  For
example, two factions can use the same sprite shape with different uniform colors.

Set the pixel indices with `Surface.Locked.set_index`, or copy a buffer of indices with
`Surface.Locked.copy_from`. Call `Surface.set_color_key sprite (Some (Index 0))` to make index zero
transparent in a blit. The key still selects index zero after a palette swap.

This function takes an `Index8` sprite with a key already set. It copies the sprite to an atlas
using the colors for one faction. The surface keeps a reference to the palette until it changes
palettes or is destroyed.

```ocaml
open Sdl3

let add_faction sdl sprite atlas ~x ~y colors =
  let palette = Surface.Palette.create sdl colors in
  Fun.protect
    ~finally:(fun () -> Surface.Palette.destroy palette)
    (fun () -> Surface.set_palette sprite palette);
  let dst = Rect.make ~x ~y ~w:0 ~h:0 in
  Surface.blit ~dst sprite atlas
```

Call `add_faction` with a different palette and position for each faction. The atlas keeps the
colors from each copy. To change entries on all surfaces that share an open palette, use
`Surface.Palette.set_colors`. Textures that you already uploaded do not change.

## Load animated images

Use [`Sdl3_image.Animation.load`](../src/image/sdl3_image.mli) for a file. For a readable, seekable
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
