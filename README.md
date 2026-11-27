# OCaml SDL3 bindings

These OCaml 5 bindings provide access to SDL3 and its image, mixer, and font add-ons. Use them for
games and multimedia. See [TODO.md](TODO.md) for the remaining work.

| Dune library and opam package | OCaml API | What it covers |
| --- | --- | --- |
| `sdl3` | [`Sdl3`](src/core/sdl3.mli) | Windows, input, 2D and GPU drawing, audio streams, and timers |
| `sdl3-image` | [`Sdl3_image`](src/image/sdl3_image.mli) | Images, textures, animations, and PNG and JPEG output |
| `sdl3-mixer` | [`Sdl3_mixer`](src/mixer/sdl3_mixer.mli) | Sound files, playback tracks, and mixing to a device or memory |
| `sdl3-ttf` | [`Sdl3_ttf`](src/ttf/sdl3_ttf.mli) | Font loading, text measurement, and reusable text drawing |

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

Try [Bunnymark](examples/bunnymark/README.md) for sprite batches,
[Aurora Tunnel](examples/aurora_tunnel/README.md) for GPU drawing, or the
[Music Player](examples/music_player/README.md) for playlists and a live spectrum.

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

## Usage guides

- [Displays and input](docs/input.md): Query displays, touch devices, and gamepads.
- [2D rendering](docs/rendering.md): Update textures, draw to textures, and batch sprites.
- [GPU drawing](docs/gpu.md): Submit frames, upload data, and bind shaders and textures.
- [Audio](docs/audio.md): Select devices, play or record samples, and control mixer tracks.
- [Streams, images, and text](docs/assets.md): Read files and buffers, load animations, and draw
  text.
- [Testing](docs/testing.md): Run the test suite and the separate GPU tests.

## License

This project uses the [MIT License](LICENSE). The [Bunnymark port](examples/bunnymark/bunnymark.LICENSE)
and the [bunny image](examples/bunnymark/assets/LICENSE.md) keep their existing licenses.
The Music Player font comes with its [own license](examples/music_player/assets/LICENSE.md).
