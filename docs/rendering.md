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

## Bunnymark

[Bunnymark](../examples/bunnymark/bunnymark.ml) measures the frame rate while moving and drawing
copies of one texture. It uses the [bunny image](../examples/bunnymark/assets/LICENSE.md) from
[Raylib's Bunnymark](https://www.raylib.com/examples/textures/loader.html?name=textures_bunnymark).
Install SDL3_image with PNG support. Run the example from the repository root:

```sh
dune exec --profile release ./examples/bunnymark/bunnymark.exe
```

Hold the left mouse button to add 100 bunnies per frame, up to 80,000. Press P to pause or resume
movement. Press Escape or close the window to exit. The window title shows the count and frames per
second. The example disables synchronization with the display refresh rate.

For a fixed workload, set the initial count and the number of frames. The example prints the mean
frames per second when it exits.

```sh
dune exec --profile release ./examples/bunnymark/bunnymark.exe -- --bunnies 10000 --frames 300
```

The example reuses arrays for positions, speeds, and colors. It submits all bunnies in one
`Texture.draw_sprites` call. It does not allocate a rectangle or color per bunny per frame.
