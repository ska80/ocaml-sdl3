# GPU drawing

Use [`Sdl3.Gpu`](../src/core/sdl3.mli) to draw to a window. Start SDL with `[Sdl3.Video]`. A shader
is a program that runs on the GPU. Pass the shader formats your program can supply to
`Gpu.create_device`. Use `Gpu.claim_window` to give the device control of a window.

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

A graphics pipeline pairs the shaders with the drawing state. Create one with
`Gpu.create_swapchain_pipeline`. You can release the shader handles after you create the pipeline.
If the window image changes to a different pixel format, create a pipeline for the new format.

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
the `std140` layout that SDL requires. You can push the data before or during a render pass.  The
command buffer keeps it until you replace it in the same slot and stage.

Use `Gpu.create_sampled_texture` to allocate a 2D image that a shader can read. Write four bytes per
pixel in red, green, blue, alpha order. Use `Gpu.upload_to_texture` in a copy pass to copy the
packed pixels from an upload buffer. Use `Gpu.create_sampler` to choose nearest or linear filtering.

After you bind the pipeline, use `Gpu.bind_samplers` to set the texture and sampler for each slot.
Before you draw, set all slots that the shaders declare. Release textures with `Gpu.release_texture`
and samplers with `Gpu.release_sampler` before you destroy the device. For examples of uniforms,
texture uploads, and indexed drawing, see the [GPU test](../test/gpu/gpu_test.ml).

## Aurora Tunnel

[Aurora Tunnel](../examples/aurora_tunnel/aurora_tunnel.ml) draws a twisting tunnel of light. Move
the mouse to steer. Click to send a pulse through the tunnel. Press Space to pause or resume. Press
Escape or close the window to exit.

The example needs Vulkan support in SDL3 and a Vulkan driver. It includes compiled shaders, so you
do not need a shader compiler to run it. Run it from the repository root:

```sh
dune exec --profile release ./examples/aurora_tunnel/aurora_tunnel.exe
```

See the [example notes](../examples/aurora_tunnel/README.md) for a preview, the draw sequence, and
test and build commands.
