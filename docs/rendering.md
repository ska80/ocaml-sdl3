# 2D rendering

A surface is a pixel buffer in memory. A texture is an image that a renderer can draw. Use
`Sdl3.Renderer` and `Sdl3.Texture` from the [core API](../src/core/sdl3.mli).

## Check the renderer

Use `Renderer.drivers ()` to list the driver names built into SDL. Use `Renderer.name renderer` to
find which driver the renderer uses. A listed driver can still fail to start on a given system.

Use `Renderer.max_texture_size renderer` before you [build an atlas](#draw-from-a-texture-atlas).
SDL reports one limit in pixels for both width and height. `None` means the driver reports no
limit. It does not mean that any size will work. If allocation fails, try a smaller texture.

`Renderer.texture_formats` lists the native texture formats that the driver reports. SDL can convert
other formats when it uploads a surface. VSync aligns frame presentation with the display
refresh. Use `Renderer.vsync` to get the current setting.

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

## Draw in part of a target

A viewport is the rectangle where SDL draws. Use `Renderer.set_viewport` to draw a panel, a minimap,
or one side of a split screen. Draw at `(0, 0)` to start at the viewport's top-left corner.  Pass
`None` to restore the automatic viewport, which covers the whole drawing area.

A clip rectangle limits drawing without moving the origin. Pass it to `Renderer.set_clip_rect` in
coordinates relative to the viewport. Pass `None` to remove the extra clip. To clear only a panel,
fill a rectangle. `Renderer.clear` clears the whole target, even with a viewport and clip.

Use `Renderer.set_scale renderer ~x:2. ~y:2.` to draw twice as large on both axes. The scale also
affects the viewport and clip rectangles. Pass `1.` for both axes to reset the scale.

Logical presentation maps a fixed drawing size to an output of a different size. For example,
`Renderer.set_logical_presentation renderer (Some (640, 360, Letterbox))` keeps the aspect ratio and
adds bars as needed. Use `Renderer.logical_presentation_rect` to find where the picture appears in
output pixels, before the viewport and drawing scale.

The window or surface and each texture target keep their own viewport, clip, scale, and logical
presentation. Use `Renderer.viewport_is_set` if you need to restore the viewport later.
`Renderer.viewport` returns a rectangle even when you did not set one. If the previous viewport was
automatic, restore `None` so it still follows changes in size or scale.

See [Convert input to drawing coordinates](input.md#convert-input-to-drawing-coordinates) to map
clicks to a viewport.

## Capture an image

`Renderer.read_pixels` copies the current target into a new surface. For a window capture, call it
after drawing and before `Renderer.present`. Readback can wait for drawing to finish, so use it only
when you need a copy.

Pass `~rect` in actual target pixels, relative to the target's top-left corner. SDL clips the region
to the viewport and the binding clips it to the target bounds. The drawing clip does not limit the
capture. If you omit `~rect`, the capture covers the part of the viewport inside the target. When
logical presentation is on, the result can differ from the logical drawing size.

```ocaml
open Sdl3

let save_frame renderer path =
  let pixels = Renderer.read_pixels renderer in
  Fun.protect
    ~finally:(fun () -> Surface.destroy pixels)
    (fun () -> Surface.save_bmp pixels path)
```

You can destroy the target and renderer before the capture. Destroy the capture before you quit
SDL. Use `Surface.scale` to make a thumbnail. To compare pixels in a test, use `Surface.read_rgba`
for the same byte order across renderers.

With SDL's `vulkan` renderer, read from a texture target. Not all Vulkan window buffers support
pixel copies. The binding raises `Sdl3.Error` if you read directly from the window on this renderer.

## Handle renderer resets

`Event.poll` reports 2D renderer failures as `Event.Render { window; change }`. Use the window ID to
find the affected renderer. If SDL reports no window ID, `window` is `None`. Keep the source images
and drawing data you need to rebuild textures. The binding reports the event without changing your
handles.

- `Targets_reset`: Draw the contents of the texture targets again.
- `Device_reset`: Destroy and recreate all textures for the renderer.
- `Device_lost`: Stop drawing with this renderer. SDL cannot recover the device. Release the
  renderer's children before you release the renderer.

## Tint and transform texture copies

Color modulation multiplies the red, green, and blue channels of a texture. Use
`Texture.set_color_mod texture (Color.rgb 128 255 255)` to cut red in half. White leaves all three
channels unchanged. Set opacity separately with `Texture.set_alpha_mod`. These changes affect future
copies. They do not change the texture's pixels.

Use `Texture.draw_rotated` to turn a copy clockwise. Set `~pivot:(0., 0.)` to turn it about the
top-left corner of its destination. Omit the pivot to turn it about the center. The pivot can be
outside the destination.

An affine transform maps a rectangle to a parallelogram. It can turn, stretch, or slant a copy.  Use
`Texture.draw_affine` with the destination positions of three source corners. SDL calculates the
fourth corner from those positions.

```ocaml
open Sdl3

let draw_sign renderer texture =
  Texture.draw_affine renderer texture ~origin:(32., 64.) ~right:(96., 48.)
    ~down:(40., 104.)
```

## Repeat textures and resize panels

Use `Texture.draw_tiled` for a repeating pattern. Pass `~src` to select part of the texture. Use
`~scale:2.` to double the width and height of each tile. SDL fits partial tiles at the right and
bottom edges. With software rendering, use tile edges that line up with pixels for best results.

Nine-slice drawing splits a texture into four corners, four edges, and a center. Use
`Texture.draw_nine_slice` to resize a button or panel. The edges and center stretch to fill the
space between the corners. By default, the corners keep their size.

```ocaml
open Sdl3

let panel_src = Frect.make ~x:0. ~y:0. ~w:32. ~h:32.
let panel_dst = Frect.make ~x:12. ~y:16. ~w:240. ~h:96.
let panel_borders = Texture.{ left = 6.; right = 6.; top = 6.; bottom = 6. }

let draw_panel renderer theme =
  Texture.draw_nine_slice ~src:panel_src ~dst:panel_dst renderer theme
    ~borders:panel_borders
```

Measure the borders in source pixels. The source must have a center. The destination must fit the
corners. If you pass a corner scale, allow for SDL to round each scaled border up.

## Choose a blend mode

A blend mode controls how a new pixel combines with the pixel already in the target. Use
`Blend_mode.Add` to add light. Use `Blend_mode.Mod` to multiply the target by a texture of
brightness values. Many 2D lighting effects need only these standard modes.

For a different rule, use `Blend_mode.compose`. Give it one equation for color and one for alpha.
Each equation multiplies the source and destination by factors, then combines the products. This
example adds source color and reduces the contribution from the destination as the source gets
brighter. It leaves the destination alpha unchanged.

```ocaml
open Sdl3

let screen =
  Blend_mode.compose
    ~color:Blend_mode.{ src = One; dst = One_minus_src_color; op = Sum }
    ~alpha:Blend_mode.{ src = Zero; dst = One; op = Sum }

let set_screen_blending texture = Texture.set_blend_mode texture screen
```

Use the same mode with `Renderer.set_draw_blend_mode` for shapes. If the renderer does not support
the mode, the setter raises `Sdl3.Error`. The software renderer only accepts SDL's standard modes.

## Draw in batches

A batch draws several items in one call. Use `Renderer.fill_rects` or `Renderer.draw_rects` to
submit an array of rectangles in one SDL call. Use `Texture.draw_sprites` to draw many copies of one
texture. Pass pairs of coordinates in a flat float array and one tint color per copy. The binding
groups the copies into batches for SDL.

## Draw from a texture atlas

A texture atlas is one texture that holds several images. To build an atlas at run time, see
[Compose images in memory](assets.md#compose-images-in-memory). Use `Sprite_batch` to draw its
regions at different sizes, angles, and positions. A batch draws sprites in the order you add
them. Add background objects first and foreground objects later. The batch does not sort them.  If
you change textures, draw the current batch before you add sprites for the next texture.

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
center. Flip mirrors the image without changing the pivot. If you only move sprites, edit the pairs
in `Sprite_batch.positions batch` with `Float.Array.set` and draw the same batch again.

To recolor a sprite, call `Sprite_batch.set_tint batch ~index color`. To fade it, call
`Sprite_batch.set_opacity batch ~index opacity` with a value from 0 to 255. Indices start at zero.
Both functions keep the draw order and do not rebuild the batch. Do not edit a batch during a draw.

Set the texture's blend mode to `Blend` for transparency. Sprite opacity multiplies the tint's
alpha. The draw does not change the texture's modulation settings. Use `Nearest` for pixel art.  If
you use `Linear`, pad each region with copies of its edge pixels to avoid sampling a neighbor.

Accelerated renderers receive batches of quads, or four-corner shapes. The software renderer uses
ordered texture copies instead to keep rotated regions oriented correctly. Use
`Texture.draw_sprites` if you only need copies of the whole texture at its original size.

## Draw custom triangles

Use `Renderer.draw_geometry` when a sprite or rectangle does not fit the shape. SDL draws triangles,
not whole polygons. Split each polygon into triangles before you pass it to SDL.

A vertex is one corner of a triangle. Store its position as an `x, y` pair and its color as a red,
green, blue, alpha group. Use flat bigarrays of 32-bit floats. Each color component ranges from 0
to 1. SDL mixes the vertex colors across each triangle to make a gradient.

Without indices, each group of three vertices forms a triangle. To share vertices, pass a 32-bit
integer bigarray and an index count. An index is a vertex number that starts at zero.  The following
example draws two triangles that share two vertices:

```ocaml
open Sdl3
open Bigarray

let positions = Array1.of_array float32 c_layout [| 16.; 16.; 144.; 16.; 144.; 80.; 16.; 80. |]

let colors =
  Array1.of_array float32 c_layout
    [| 1.; 0.; 0.; 1.; 0.; 1.; 0.; 1.; 0.; 0.; 1.; 1.; 1.; 1.; 0.; 1. |]

let indices = Array1.of_array int32 c_layout [| 0l; 1l; 2l; 0l; 2l; 3l |]

let draw_gradient renderer =
  Renderer.draw_geometry ~indices:(indices, 6) renderer ~positions ~colors ~vertex_count:4
```

For a textured draw, add `~texture:(image, uv)`. Store one `u, v` pair per vertex in `uv`.  These
coordinates range from 0 to 1 across the texture. The top-left is `0, 0`. The bottom-right is `1,
1`. The vertex colors tint the texture for this draw. SDL ignores the texture's usual color and
alpha settings. For transparency, set the texture's blend mode to `Blend`. Without a texture, set
the renderer's draw blend mode instead.

Create the buffers once and reuse them. The counts select how much of each buffer to use. You can
change the buffers after the call returns. SDL draws in the order you supply. Accelerated renderers
receive the buffers in one call to SDL. The software renderer draws one triangle at a time to keep
the texture mapping and blend mode. It uses nearest filtering and can reject large positions or
large textured triangles. If it rejects a large textured triangle, split it into smaller ones.

## Bunnymark

The [Bunnymark example](../examples/bunnymark/README.md) adds each bunny to one `Sprite_batch`.  It
updates their positions in place and displays the frame rate.
