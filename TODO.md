# Implementation progress

## Done

- [x] Separate Dune packages for `sdl3`, `sdl3-image`, `sdl3-mixer`, and `sdl3-ttf`.
- [x] SDL discovery through `pkg-config` and checks for minimum library versions.
- [x] Abstract handles, explicit cleanup, main thread guards, and shared error reporting.
- [x] Core windows, 2D rendering, textures from surfaces, BMP files, keyboard and mouse input, gamepads, queued audio, and timers.
- [x] Image loading from a file or memory, texture loading, and PNG and JPEG output.
- [x] Mixer and track playback, looping, gain, and mixing to a device or memory.
- [x] Font loading, metrics, UTF-8 text measurement, and solid or blended text rendering.
- [x] Native and bytecode tests on Linux with OCaml 5.4.1 and Dune 3.25.0.

The tests use SDL 3.4.16, SDL3_image 3.4.6, SDL3_mixer 3.2.4, and SDL3_ttf 3.2.2. A core-only build and separate installation of each add-on also passed.

## Next

- [ ] Add streaming textures, render targets, and calls that draw many shapes at once.
- [ ] Add the SDL3 GPU API.
- [ ] Add more window, display, touch, and gamepad APIs.
- [ ] Add file and memory streams with clear ownership rules.
- [ ] Add audio device selection, audio capture, and more mixer playback controls.
- [ ] Add SDL3_image animation and SDL3_ttf text engine support.
- [ ] Plan how to dispatch audio and event callbacks before allowing native threads to call OCaml.
- [ ] Test the oldest supported SDL releases. Add macOS and Windows builds.
- [ ] Select release metadata and a license before publishing the opam packages.
