# Implementation progress

## Done

- [x] Separate Dune packages for `sdl3`, `sdl3-image`, `sdl3-mixer`, and `sdl3-ttf`.
- [x] SDL discovery through `pkg-config` and checks for minimum library versions.
- [x] Abstract handles, explicit cleanup, main thread guards, and shared error reporting.
- [x] Core windows, 2D rendering, textures from surfaces, BMP files, keyboard and mouse input,
      gamepads, queued audio, and timers.
- [x] Window placement and state changes, display queries, touch input, and gamepad discovery
      and events.
- [x] Mouse state, mouse focus events, custom and system cursors, capture, window grabs, and pointer
      movement.
- [x] Streaming texture uploads, render targets, and batches of rectangles.
- [x] Scoped write access to streaming textures.
- [x] Surface blits, conversion, scaling, flips, color keys, and blend modes. Scoped surface pixel
      access and palette swaps for indexed sprites.
- [x] Texture sprite batches and an OCaml Bunnymark example.
- [x] Ordered sprite batches with atlas regions, scaling, rotation, pivots, flips, tint, and
      opacity.
- [x] In-place tint and opacity updates for sprite batches.
- [x] 2D triangle lists with per-vertex colors, optional textures, and optional indices.
- [x] Viewports, clip rectangles, drawing scales, and conversion of window points and events to
      drawing coordinates.
- [x] RGB texture tint, rotation pivots, affine copies, tiling, nine-slice drawing, and custom blend
      modes.
- [x] Renderer queries, including texture size limits, pixel readback, and renderer reset and loss
      events.
- [x] GPU device setup, window claims, and solid-color frames.
- [x] GPU command buffers, swapchain render passes, and fences that signal completion.
- [x] Typed GPU shaders and pipelines for window drawing.
- [x] GPU vertex and index buffers, upload commands, and indexed drawing.
- [x] GPU uniform data, sampled 2D textures, and samplers.
- [x] Aurora Tunnel example with GPU mesh copies, a color texture, and interactive animation.
- [x] Music Player example with file drops, mixer titles, GPU text, and an FFTW spectrum.
- [x] Image loading from a file or memory, texture loading, and PNG and JPEG output.
- [x] Mixer and track playback, looping, gain, and mixing to a device or memory.
- [x] Font loading, metrics, UTF-8 text measurement, and solid or blended text rendering.
- [x] Typed file and memory streams, with stream input for BMP, images, audio, and fonts.  Stream
      output for BMP, PNG, and JPEG.
- [x] Audio device discovery and selection, queued recording, and mixer track seeking, fades, loop
      control, and playback speed.
- [x] SDL3_image animation loading and SDL3_ttf text engines for surfaces and renderers.
- [x] [Plan for audio and event dispatch](docs/callback-dispatch.md) on the main thread.
- [x] Stereo panning, 3D sound positions, tagged track controls, and mixer groups. Stop watches
      report playback stops on the main thread. Group creation needs SDL3_mixer 3.2.4 or later.
- [x] Native and bytecode tests on Linux with OCaml 5.4.1 and 5.5.2 (Dune 3.25.0).
- [x] Runtime tests on Linux with the oldest supported add-on releases.
- [x] QCheck tests for core resource lifetimes and an optional ASan and UBSan test build on Linux.
- [x] [MIT license](LICENSE) for the bindings.
- [x] Release metadata for all four opam packages.

The full suite uses SDL 3.4.16, SDL3_image 3.4.6, SDL3_mixer 3.2.4, and SDL3_ttf 3.2.2. The core
also builds and passes its tests with SDL 3.2.0 and no add-ons. The GPU tests passed on both SDL
versions with offscreen Vulkan. The image tests passed with SDL3_image 3.2.0 on SDL 3.2.0. The mixer
and font tests passed with SDL3_mixer and SDL3_ttf 3.2.0 on SDL 3.4.16. Separate installation of
each add-on also passed.

## Next

- [ ] Add macOS and Windows builds.

## Mixer compatibility follow-ups

The checks below are in [`src/mixer/mixer_stubs.c`](src/mixer/mixer_stubs.c). Keep each check for
SDL_mixer versions that still need it. The package minimum is 3.2.0.

- [ ] Recheck forced stereo when SDL_mixer releases a fix. In
      [3.2.4](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c#L506-L525),
      `MixForcedStereoFloat32Audio` writes two channels into a mono output buffer.
      [`MixerCallback`](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c#L551-L608)
      also gives the temporary input buffer room for only one channel.  `Track.set_stereo` therefore
      requires a memory mixer with at least two channels.  When a fix ships, limit this check to
      affected versions. Test mixing to a mono memory buffer. Before allowing device mixers, test a
      switch to mono during playback.
- [ ] Remove the `Group.create` version check when the minimum reaches SDL_mixer 3.2.4.
      `MIX_SetTrackGroup` in [3.2.0](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.0/src/SDL_mixer.c#L2974-L2984)
      and [3.2.2](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.2/src/SDL_mixer.c#L3001-L3010)
      can break the track list when a track moves from the middle of a group.
      [3.2.4](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c#L3013-L3023)
      fixes the link. Keep the test that moves a middle track and destroys its neighbor.
