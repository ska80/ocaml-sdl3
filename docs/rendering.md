# 2D rendering

A surface is a pixel buffer in memory. A texture is an image that a renderer can draw. Use
`Sdl3.Renderer` and `Sdl3.Texture` from the [core API](../src/core/sdl3.mli).

## Update textures

A streaming texture accepts repeated pixel uploads. Create one with `Texture.create_streaming`.  Use
`Texture.update` to upload red, green, blue, and alpha bytes from a reusable bigarray. Alpha
controls opacity. Pass `~rect` to update only part of the texture. Pass `~pitch` for the byte
distance between rows, including padding. The binding passes the buffer directly to SDL.

Use `Texture.with_lock` to write to a streaming texture during a function call. Use
`Texture.Locked.fill` for a solid color or `Texture.Locked.copy_from` to copy pixels from a
bigarray. Use `Texture.Locked.set_pixel` to write one pixel at a time. Coordinates start at zero in
the locked rectangle. Unwritten pixels in that rectangle become transparent black.

The binding unlocks the texture even if the function raises an exception. The writes stay in the
texture. You cannot use the locked view after the function exits.

## Draw to a texture

A render target is where the renderer draws. Use `Texture.create_target` to create a texture you can
draw to. Select it with `Renderer.set_target renderer (Some target)`. Clear it before you draw into
it. Before you draw the texture to the window or present the frame, restore the default render
target with `Renderer.set_target renderer None`.

## Draw in batches

A batch draws several items in one call. Use `Renderer.fill_rects` or `Renderer.draw_rects` to
submit an array of rectangles in one SDL call. Use `Texture.draw_sprites` to draw many copies of one
texture. Pass pairs of coordinates in a flat float array and one tint color per copy. The binding
groups the copies into batches for SDL.

## Draw from a texture atlas

A texture atlas is one texture that holds several images. Use `Sprite_batch` to draw regions of
one texture at different sizes, angles, and positions. A batch draws sprites in the order you add
them. Add background objects first and foreground objects later. The batch does not sort them.
If you change textures, draw the current batch before you add sprites for the next texture.

Create the batch once. Clear it before you add a new frame of sprites. Keep source rectangles and
tint colors to reuse them without making a record for each sprite in each frame. The batch stores
the sprite data in packed buffers.

```ocaml
open Sdl3

let batch = Sprite_batch.create ~capacity:256
let floor_tile = Rect.make ~x:0 ~y:0 ~w:32 ~h:16
let actor_tile = Rect.make ~x:32 ~y:0 ~w:32 ~h:48

let draw_tiles renderer atlas =
  Sprite_batch.clear batch;
  Sprite_batch.add batch ~src:floor_tile ~x:32. ~y:64. ~w:64. ~h:32.;
  Sprite_batch.add batch ~src:actor_tile ~x:48. ~y:24. ~w:32. ~h:48.
    ~angle:12. ~pivot_x:16. ~pivot_y:48. ~flip:Texture.Horizontal ~opacity:192;
  Sprite_batch.draw renderer atlas batch
```

The pivot is the point that the sprite turns around. Its coordinates start at the unrotated
destination's top-left, not at the source rectangle. The default pivot is the destination's
center. Flip mirrors the image without changing the pivot. If you only move sprites, edit the
pairs in `Sprite_batch.positions batch` with `Float.Array.set` and draw the same batch again.
Do not change a batch while a draw uses it.

Set the texture's blend mode to `Blend` for transparency. Sprite opacity multiplies the tint's
alpha. The draw does not change the texture's modulation settings. Use `Nearest` for pixel art.
If you use `Linear`, pad each region with copies of its edge pixels to avoid sampling a neighbor.

Accelerated renderers receive batches of quads, or four-corner shapes. The software renderer uses
ordered texture copies instead to keep rotated regions oriented correctly. Use `Texture.draw_sprites`
if you only need copies of the whole texture at its original size.

## Bunnymark

The [Bunnymark example](../examples/bunnymark/README.md) moves many bunnies and draws them with
`Texture.draw_sprites`. It displays the frame rate.
