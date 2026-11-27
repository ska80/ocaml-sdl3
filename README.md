# OCaml SDL3

Build games, graphics tools, and multimedia apps in OCaml 5. Start with SDL's 2D renderer or use its
GPU API directly. The packages wrap SDL3 and its image, mixer, and font add-ons. Your code controls
the event loop and decides when to release resources.

## What you can do

- [Draw 2D scenes](docs/rendering.md): Draw many sprites in order with one batch. Render into
  textures. Use the `gpu` driver to apply [custom shaders](docs/rendering.md#apply-a-fragment-effect).
- [Build GPU effects](docs/gpu.md): Draw many copies of the same geometry in one call. Use the
  output of one pass in the next. Copy rendered pixels back to OCaml buffers.
- [Load assets and draw text](docs/assets.md): Load animations, swap sprite palettes, and decode
  BMPs off the main thread. Edit reusable text and draw it to a surface or with a renderer. For GPU
  drawing, use a [glyph atlas](docs/gpu.md#draw-text-from-a-glyph-atlas), a texture that stores
  character shapes.
- [Play, record, and mix audio](docs/audio.md): Choose audio devices, position sounds in 3D, and
  control groups of tracks. Read track stop notices on the main thread.
- [Handle input](docs/input.md): Use a keyboard, mouse, touch screen, or gamepad. Accept file drops,
  native text input, and clipboard text.

## Packages

Use the core by itself or add the packages you need. The core does not link to the add-ons.

| Dune library and opam package | OCaml API | What it covers |
| --- | --- | --- |
| `sdl3` | [`Sdl3`](src/core/sdl3.mli) | Windows, input, 2D and GPU drawing, audio streams, and timers |
| `sdl3-image` | [`Sdl3_image`](src/image/sdl3_image.mli) | Image and animation loading, and PNG and JPEG output |
| `sdl3-mixer` | [`Sdl3_mixer`](src/mixer/sdl3_mixer.mli) | Playback tracks and mixing to a device or memory |
| `sdl3-ttf` | [`Sdl3_ttf`](src/ttf/sdl3_ttf.mli) | Fonts, text layout, and drawing to surfaces, renderers, or the GPU |

## Install from source

Use OCaml 5.4 or later and Dune 3.25 or later. Install a C compiler and `pkg-config`, which finds
the SDL headers and libraries.

Use these versions or later at build time and run time. Install only the add-ons you need.

| SDL library | Minimum version |
| --- | --- |
| SDL3 | 3.4.20 |
| SDL3_image | 3.4.8 |
| SDL3_mixer | 3.2.4 |
| SDL3_ttf | 3.2.2 |

If you use `opam`, install the build tools in the active switch, which is your selected OCaml
installation:

```sh
opam install 'dune>=3.25' dune-configurator conf-pkg-config
```

If `pkg-config` cannot find SDL under `/usr/local`, add that search path. Before a full build, make
sure that `pkg-config` reports supported versions of all four libraries.

```sh
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
pkg-config --modversion sdl3 sdl3-image sdl3-mixer sdl3-ttf
```

From the repository root, build and install all four packages:

```sh
dune build @install
dune install --prefix "$(opam var prefix)"
```

If you only need the core, build and install `sdl3` alone. It does not need any of the add-on
libraries.

```sh
dune build -p sdl3 @install
dune install --prefix "$(opam var prefix)" sdl3
```

If you install outside opam, give `dune install --prefix` an absolute path. Add its `lib` directory
to `OCAMLPATH`. For dynamically linked bytecode, add `lib/stublibs` to `CAML_LD_LIBRARY_PATH`. Your
system must also be able to load the SDL shared libraries at run time.

## Get started

List `sdl3` and any add-ons you use in your `dune` file. For a program that uses only the core:

```lisp
(executable
 (name main)
 (libraries sdl3))
```

Run the [Basic example](examples/basic/basic.ml) from the repository root. Press `Esc` or close the
window to exit.

```sh
dune exec ./examples/basic/basic.exe
```

Use `Sdl3.with_init` to start and stop SDL. Pass `[Sdl3.Video]` for a window or `[Sdl3.Audio]` for a
core audio stream. Pass `[]` if you do not need a subsystem. SDL3_image needs no separate setup.
Use `Sdl3_mixer.with_init` and `Sdl3_ttf.with_init` inside the SDL context.

## Examples

Each example page has run instructions and a preview:

- [Bunnymark](examples/bunnymark/README.md) moves and draws thousands of sprites in one reusable
  batch.
- [Aurora Tunnel](examples/aurora_tunnel/README.md) draws an interactive tunnel from copies of one
  ring.
- [Music Player](examples/music_player/README.md) plays dropped files and shows the strength of
  the sound from bass to treble.

## Resource rules

A handle is a typed reference to an SDL resource. Load the bindings and use handles on the main
thread. Close every handle explicitly. Use `Fun.protect` so cleanup runs even if an exception
occurs. The OCaml garbage collector does not destroy SDL resources.

Close children before their parents. For example, destroy textures before their renderer. Close all
resources before `Sdl3.quit`. Keep only one SDL context open at a time. Do not shut down SDL through
another binding.

Timer and version calls can run on other threads. You can also [decode BMP assets on worker
domains](docs/assets.md#decode-bmp-assets-on-a-worker-domain) and pass the pixels to the main
thread. Do not change a buffer from another domain while SDL uses it.

Using a closed handle or closing a parent with live children raises `Invalid_argument`. When an SDL
call reports a failure, the binding raises `Sdl3.Error` with the function name and message.

See [Testing](docs/testing.md) for test commands and [TODO.md](TODO.md) for remaining work.

## License

This project uses the [MIT License](LICENSE). The [Bunnymark port](examples/bunnymark/bunnymark.LICENSE)
and the [bunny image](examples/bunnymark/assets/LICENSE.md) keep their existing licenses.
The Music Player font comes with its [own license](examples/music_player/assets/LICENSE.md).
