# OCaml SDL3 bindings

These bindings let OCaml 5.4 programs call SDL3 for 2D games and multimedia. They cover a first set
of SDL3 functions, not the full C API. See [TODO.md](TODO.md) for the remaining work.

| Dune library and opam package | OCaml module | What it covers |
| --- | --- | --- |
| `sdl3` | [`Sdl3`](src/core/sdl3.mli) | Windows, 2D drawing, GPU setup, textures, surfaces, input events, gamepads, queued audio, and timers |
| `sdl3-image` | [`Sdl3_image`](src/image/sdl3_image.mli) | Load images from files or memory, load textures, and save PNG and JPEG files |
| `sdl3-mixer` | [`Sdl3_mixer`](src/mixer/sdl3_mixer.mli) | Load sounds, play audio tracks, and mix to a device or a memory buffer |
| `sdl3-ttf` | [`Sdl3_ttf`](src/ttf/sdl3_ttf.mli) | Open fonts, measure UTF-8 text, and render text to surfaces |

A surface is a pixel buffer in memory. A texture is an image that a renderer can draw. Image loading
and text rendering return core SDL types.

## Install from source

Use OCaml 5.4 or later and Dune 3.25 or later. Install a C compiler and `pkg-config`, which finds
the SDL headers and libraries. Install SDL3 3.2.0 or later and version 3.2.0 or later of each add-on
you want to use.

If you use `opam`, install the build tools in the active switch, which is the selected OCaml
installation:

```sh
opam install 'dune>=3.25' dune-configurator conf-pkg-config
```

If you installed SDL under `/usr/local` and `pkg-config` cannot find it, add its search path. To
build all four packages, make sure that `pkg-config` prints all four versions.

```sh
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
pkg-config --modversion sdl3 sdl3-image sdl3-mixer sdl3-ttf
```

From this repository, build the packages. Install them into your active opam switch:

```sh
dune build @install
dune install --prefix "$(opam var prefix)"
```

If you only need SDL3, build and install `sdl3` alone. This does not need the other three C
libraries.

```sh
dune build -p sdl3 @install
dune install --prefix "$(opam var prefix)" sdl3
```

If you install outside opam, give `dune install --prefix` an absolute path. Add that path's `lib`
directory to `OCAMLPATH`. For dynamically linked OCaml bytecode, add its `lib/stublibs` directory to
`CAML_LD_LIBRARY_PATH`. Your system must also be able to load the SDL shared libraries at run time.

## Use the bindings

Add `sdl3` and the add-ons that you use to the `libraries` field in your `dune` file:

```lisp
(executable
 (name main)
 (libraries sdl3 sdl3-image sdl3-mixer sdl3-ttf))
```

Run the [window and event loop example](examples/hello.ml) from this repository. Press Escape or
close the window to exit.

```sh
dune exec ./examples/hello.exe
```

Use `Sdl3.with_init` to start and stop SDL. Pass `[Sdl3.Video]` for a window or `[Sdl3.Audio]` for a
core audio stream. Pass `[]` for work that does not use a subsystem, such as loading an image into
memory. SDL3_image needs no separate setup. Use `Sdl3_mixer.with_init` and `Sdl3_ttf.with_init`
inside the SDL context.

## Resource and thread rules

A handle is a typed reference to an SDL resource. Close every handle explicitly. The OCaml garbage
collector does not destroy SDL resources. Use `Fun.protect` to close handles even if an exception
occurs.

Close each child before its parent. For example, destroy textures before their renderer, then
destroy the renderer before its window. Close all resources before `Sdl3.quit`. The bindings raise
`Invalid_argument` if you use a closed handle or close a parent that still has children. An SDL call
that reports failure raises `Sdl3.Error` with the function name and error message.

Only one SDL context can be open at a time. Do not shut down SDL or its subsystems through another
binding.

Load and use the bindings on the main thread, including for cleanup. Other OCaml domains can do work
that does not use SDL resources. Timer and version calls can run on other threads. Do not change a
buffer from another domain while SDL reads or writes it.

Drawing calls pass small values directly to C. Audio and in-memory image calls take bigarrays, which
hold data outside the OCaml heap. `Audio.queue` copies the samples into SDL, but the binding adds no
copy.

## Update textures and draw to them

A streaming texture accepts repeated pixel uploads. Create one with `Texture.create_streaming` and
upload RGBA bytes from a reusable bigarray with `Texture.update`. Pass `~rect` to update only part
of the texture. Pass `~pitch` for the byte distance between rows, including any padding. The binding
passes the buffer directly to SDL.

A render target is where the renderer draws. Use `Texture.create_target` to create a texture you can
draw to. Select it with `Renderer.set_target renderer (Some target)`. Clear it before you draw to
it. Use `Renderer.set_target renderer None` before you draw the texture to the window and present
the frame.

Use `Renderer.fill_rects` or `Renderer.draw_rects` to submit an array of rectangles in one SDL call.

## Set up GPU presentation

`Sdl3.Gpu` opens devices and presents solid-color frames. It does not yet expose shaders or drawing
commands. Start SDL with `Video`. Pass the shader formats your program can supply to
`Gpu.create_device`. Use `Gpu.claim_window` to give the device control of a window.

`Gpu.clear_and_present` clears a window image to one color and submits it for display. If it returns
`false`, SDL had no image available. Release the claim before destroying the device or window. Do
not attach a `Renderer` to a claimed window.

## Run the tests

Run `dune runtest` for native and bytecode tests. These tests use SDL's dummy video and audio
drivers, so they need no display or speakers. The image tests need PNG and JPEG support in
SDL3_image.

Run `dune build --force @runtest-gpu` on a system with a working SDL GPU driver. On Linux with
offscreen Vulkan support, set `SDL_VIDEO_DRIVER=offscreen` to run without a display.
