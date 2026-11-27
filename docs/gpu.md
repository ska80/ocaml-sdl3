# GPU drawing

Use [`Sdl3.Gpu`](../src/core/sdl3.mli) to draw to a window or a texture. Start SDL with
`[Sdl3.Video]`. A shader is a program that runs on the GPU. Pass the shader formats your program can
supply to `Gpu.create_device`. To draw to a window, give the device control of it with
`Gpu.claim_window`.

## Submit a frame

`Gpu.clear_and_present` clears a window image to one color and submits it for display. If it returns
`false`, SDL had no image available. Do not attach a `Renderer` to a claimed window. Call
`Gpu.release_window` before destroying the device or window.

A command buffer holds GPU work before submission. Open one with `Gpu.acquire_command_buffer`.  Use
`Gpu.begin_swapchain_render_pass` to acquire and clear a window image. If it returns `None`, no
image is available and you can call `Gpu.cancel_command_buffer`. If it returns a pass, call
`Gpu.end_render_pass` and then `Gpu.submit_command_buffer`. You cannot cancel after acquiring an
image.

A fence signals when submitted GPU work finishes. Use `Gpu.submit_and_acquire_fence` to get a fence
at submission. Call `Gpu.wait_fence` to wait for completion. Release the fence with
`Gpu.release_fence` when you no longer need it.

## Create shaders and a pipeline

A uniform block holds values that stay constant for a draw. A sampler tells the shader how to read
pixels from an image.

Use `Gpu.create_shader` to load vertex and fragment code. Declare how many uniform blocks and
texture-sampler pairs each shader uses. Both counts default to zero. The bindings do not support
storage buffers or storage textures.

A graphics pipeline pairs the shaders with the drawing state. Use `Gpu.create_graphics_pipeline` to
select a target format without a window claim. `Gpu.create_swapchain_pipeline` selects the claim's
current format instead. Use either pipeline with targets on the same device that have that
format. Release the shader handles after you create the pipeline.

## Blend colors in a pipeline

Blending combines the pixel from the fragment shader with the pixel already in the target. If you
omit `~blend`, each draw replaces the target values. These settings do not control window
transparency.

Use `Gpu.Blend.straight_alpha` when the shader outputs RGB without scaling it by alpha. If the
shader already scales RGB by alpha, use `Gpu.Blend.premultiplied_alpha` instead. For other effects,
use `Gpu.Blend.additive`, `Gpu.Blend.modulate`, or `Gpu.Blend.multiply`. Those three presets keep
the target alpha unchanged.

A write mask selects the channels a draw can change. This pipeline blends RGB and keeps the alpha
already in the target:

```ocaml
let pipeline =
  let open Sdl3.Gpu in
  create_swapchain_pipeline ~blend:Blend.straight_alpha
    ~color_write_mask:[ Red; Green; Blue ] claim ~vertex ~fragment
    ~primitive:Triangle_list
```

If you omit `~color_write_mask`, draws can write all four channels. An empty list prevents all color
writes. The mask works with or without blending. The mask does not affect clears.

For custom blending, pass a `Gpu.Blend.t` record with two `Blend_mode.equation` values. In each
channel, the equation scales the source and destination by their factors and then applies the
operation. `Minimum` and `Maximum` compare the unscaled values. In the alpha equation, a color
factor uses the corresponding alpha. For example, this blend adds RGB without scaling by alpha and
keeps the destination alpha:

```ocaml
let blend : Sdl3.Gpu.Blend.t =
  { color = { src = One; dst = One; op = Sum };
    alpha = { src = Zero; dst = One; op = Sum } }
```

## Upload and draw geometry

A vertex buffer holds the points and other data for a shape. An index buffer holds the order in
which to draw those points. Use `Gpu.write_upload_buffer` to copy a bigarray into a reusable upload
buffer. Buffer sizes, copy offsets, and copy lengths must be multiples of four bytes.

Call `Gpu.begin_copy_pass` to group transfers in the command buffer. Record each transfer with
`Gpu.upload_to_buffer`. Call `Gpu.end_copy_pass` before you start a render pass.

If the vertex shader reads vertex data, pass `~vertex_layout` when you create the pipeline. In each
pass, call `Gpu.bind_graphics_pipeline` before drawing. Bind the vertex buffer after you bind the
pipeline. Call `Gpu.draw_primitives` to draw without an index buffer. For indexed drawing, bind the
index buffer and call `Gpu.draw_indexed_primitives`.

## Set uniforms and bind textures

Use `Gpu.push_uniform_data` to copy a uniform block to a vertex or fragment slot. Pack the bytes in
the `std140` layout that SDL requires. You can push the data before or during a render pass. The
command buffer keeps it until you replace it in the same slot and stage. After a blit, push fragment
slot zero again if the next pipeline uses it.

Use `Gpu.create_sampled_texture` to allocate a 2D image that a shader can read. Write four bytes per
pixel in red, green, blue, alpha order. Use `Gpu.upload_to_texture` in a copy pass to copy the
packed pixels from an upload buffer. Use `Gpu.create_sampler` to choose nearest or linear filtering.

After you bind the pipeline, use `Gpu.bind_samplers` to set the texture and sampler for each slot.
Before you draw, set all slots that the shaders declare. Release textures with `Gpu.release_texture`
and samplers with `Gpu.release_sampler` before you destroy the device. For examples of uniforms,
texture uploads, and indexed drawing, see the [GPU test](../test/gpu/gpu_test.ml).

## Draw to a texture

A color target is an image that the GPU draws into. Use `Gpu.create_texture` with `Color_target` for
drawing only. If a later pass needs to read the image in a shader, use `Sampled_color_target`.  Use
`Gpu.supports_texture_format` to test whether your device supports a format for that use.

This example records a render pass with a pipeline for the texture's format. Pass a `draw` function
that binds the resources your shaders need and issues the draw calls.

```ocaml
let make_target device ~w ~h =
  Sdl3.Gpu.(create_texture device ~format:Rgba8_unorm ~usage:Sampled_color_target ~w ~h)

let make_pipeline device target ~vertex ~fragment =
  let open Sdl3.Gpu in
  create_graphics_pipeline device ~format:(texture_format target)
    ~vertex ~fragment ~primitive:Triangle_list

let record_offscreen commands ~target ~pipeline draw =
  let open Sdl3.Gpu in
  let pass = begin_render_pass commands ~target ~load:(Clear (Sdl3.Color.rgb 0 0 0)) in
  Fun.protect ~finally:(fun () -> end_render_pass pass) (fun () ->
      bind_graphics_pipeline pass pipeline;
      draw pass)
```

Use `Clear` to set all pixels in the target before drawing. Use `Load` to keep pixels from earlier
GPU work. Use `Dont_care` if the old pixels do not matter. Pass `~store:Discard` if no later work
reads the result. Do not read from an uninitialized or discarded image.

A viewport maps drawing coordinates to a rectangle. A scissor clips drawing to a rectangle.
`Gpu.set_viewport` and `Gpu.set_scissor` use target pixels. They each start at the full target and
reset to it with `None`. Neither affects the pass's clear. Use `Gpu.render_pass_size` to get the
actual target size, including for a window image.

End the pass before you use its target in a later pass or release it. Do not bind the same texture
as both target and sampler in one pass. To display the result, sample the texture during a window
pass. You can record both passes in one command buffer and submit them together. The binding allows
one open render pass per device.

## Use smaller texture levels

A mip level is a smaller image in the same texture. Use `~mip_levels` when you create the texture.
Level zero has the original size. Each next level halves each dimension, down to one pixel per
axis. Use `Gpu.texture_size ~mip_level` to get its size. Initialize each level that you use with an
upload, a copy, or a render pass. SDL does not generate them in this API.

`Gpu.upload_to_texture ~mip_level` uploads the whole level. Pack rows in the selected format with no
padding. Align the upload offset to both four bytes and the pixel size. Use `Gpu.create_sampler
~max_mip_level` to let a shader read smaller levels. If you omit the limit, the sampler reads only
level zero. SDL 3.4.20 cannot render or blit a level when halving the base size to that level would
give zero on either axis. Uploads, copies, and sampling still work.

## Copy or scale a texture region

Use `Gpu.texture_region` to select a rectangle and a level on each texture. If you omit both, it
selects all of level zero. For a copy or blit, use two distinct textures from the same device.

Call `Gpu.copy_texture` in a copy pass. The rectangles must have equal sizes and use the same pixel
format. A copy does not scale or convert pixels.

For scaling or format conversion, call `Gpu.blit_texture` outside a pass. This call needs a sampled
source and a color target as the destination. Choose `~filter:Linear` to blend nearby pixels as you
resize. Use `~load:Load` to keep the pixels outside the destination rectangle. A blit cannot write
directly to a window image through this API.

Cycling lets SDL use separate storage when recorded work still uses a texture. Enable it only for a
whole one-level destination. For a render pass, use `Clear` or `Dont_care` with cycling. For a blit,
use `Dont_care` and cover the whole destination. If you cancel cycling work, initialize the texture
again before reading it.

## Aurora Tunnel

The [Aurora Tunnel example](../examples/aurora_tunnel/README.md) draws a twisting tunnel of light
with one indexed draw per frame.
