# Implementation progress

## Done

- [x] Separate Dune packages for `sdl3`, `sdl3-image`, `sdl3-mixer`, and `sdl3-ttf`.
- [x] SDL discovery through `pkg-config`.
- [x] Minimum versions for SDL and its add-ons, checked at build time and run time.
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
- [x] GPU pipeline blending with separate RGB and alpha equations, and RGBA write masks.
- [x] GPU vertex and index buffers, upload commands, and indexed drawing.
- [x] GPU uniform data, sampled 2D textures, and samplers.
- [x] GPU offscreen render passes, pipelines for a selected format, mip levels, viewports, scissors,
      and texture copies and blits.
- [x] GPU buffer and texture readback into bigarrays, with region, pitch, and offset selection.
- [x] Separate GPU vertex and instance buffers, per-axis sampler addressing, and mip filtering.
- [x] GPU 2D renderers, borrowed devices, and custom fragment states with extra textures.
- [x] Aurora Tunnel example with GPU mesh copies, a color texture, and interactive animation.
- [x] Music Player example with file drops, mixer titles, GPU text, and an FFTW spectrum.
- [x] Image loading from a file or memory, texture loading, and PNG and JPEG output.
- [x] BMP decoding on worker domains, with pixel buffers for upload on the main thread.
- [x] Mixer and track playback, looping, gain, and mixing to a device or memory.
- [x] Font loading, metrics, UTF-8 text measurement, and solid or blended text rendering.
- [x] Typed file and memory streams, with stream input for BMP, images, audio, and fonts.  Stream
      output for BMP, PNG, and JPEG.
- [x] Audio device discovery and selection, queued recording, and mixer track seeking, fades, loop
      control, and playback speed.
- [x] SDL3_image animation loading and SDL3_ttf text engines for surfaces and renderers.
- [x] Font styles, outlines, hinting, kerning, alignment, fallback fonts, and glyph metrics.
- [x] Text direction and script settings, UTF-8 edits, substring bounds, and hit testing.
- [x] GPU text engines, borrowed glyph atlases, copied triangle data, and SDF glyphs.
- [x] Native text input areas and clipboard text.
- [x] Platform directories for assets and saves, and a timed wait for events.
- [x] Window icons, minimum size, and fullscreen mode selection. Gamepad vibration and audio device
      connection and disconnection events.
- [x] [Plan for audio and event dispatch](docs/callback-dispatch.md) on the main thread.
- [x] Stereo panning, 3D sound positions, tagged track controls, and mixer groups. Stop watches
      report playback stops on the main thread.
- [x] Native and bytecode tests on Linux with OCaml 5.4.1 and 5.5.2 (Dune 3.25.0).
- [x] QCheck tests for core resource lifetimes and an optional ASan and UBSan test build on Linux.
- [x] [MIT license](LICENSE) for the bindings.
- [x] Release metadata for all four opam packages.

The Linux suite passed with the libraries installed in `/usr/local`: SDL 3.4.20, SDL3_image 3.4.8,
SDL3_mixer 3.2.4, and SDL3_ttf 3.2.2.

## Next

- [ ] Add macOS and Windows builds.

## SDL core compatibility follow-ups

- [ ] Recheck worker PNG loads after SDL fixes shared decoder state. SDL 3.4.20 disables
      thread-local error storage in [`SDL_stb.c`](https://github.com/libsdl-org/SDL/blob/release-3.4.20/src/video/SDL_stb.c).
      SDL_image can use the same decoder. Review other SDL_image codecs separately before allowing
      calls from workers. Do not change the thread rules for existing handles.
- [ ] Recheck render passes and blits on the smallest levels of rectangular GPU textures after an
      SDL update. SDL 3.4.20 can calculate a zero width or height instead of one. The binding
      rejects those levels for rendering and blitting but still allows uploads and copies.
- [ ] Recheck vertex buffer binding on Direct3D 12 after an SDL update. SDL 3.4.20 keeps unused
      slots and does not rebuild buffer views when only the stride changes. The binding replaces
      unused slots and forces a new view when it binds vertex data for another pipeline.
- [ ] Recheck custom render state uniform allocation after an SDL update. SDL 3.4.20 can invalidate
      the uniform array if allocation of a new slot fails. The binding closes a state that fails
      this way without calling SDL's destructor. The native allocation can leak on that path.

## SDL_mixer compatibility follow-ups

Keep the workarounds in [`src/mixer/mixer_stubs.c`](src/mixer/mixer_stubs.c) for supported versions
that need them.

- [ ] Recheck forced stereo when SDL_mixer releases a fix. In
      [3.2.4](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c#L506-L525),
      `MixForcedStereoFloat32Audio` writes two channels into a mono output buffer.
      [`MixerCallback`](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c#L551-L608)
      also gives the temporary input buffer room for only one channel.  `Track.set_stereo` therefore
      requires a memory mixer with at least two channels.  When a fix ships, limit this check to
      affected versions. Test mixing to a mono memory buffer. Before allowing device mixers, test a
      switch to mono during playback.
- [x] Remove the version check from `Group.create`. SDL_mixer
      [3.2.4](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c#L3013-L3023)
      fixes the track list when a track moves from the middle of a group.
      Keep the test that moves a middle track and destroys its neighbor.

## SDL_ttf compatibility follow-ups

Keep the workarounds in [`src/ttf/ttf_stubs.c`](src/ttf/ttf_stubs.c) for supported versions that
need them.

- [ ] Recheck cache clearing after fallback and kerning changes. SDL_ttf 3.2.2 keeps cached glyph
      positions after these changes. The binding resets the caches through hinting
      without changing the hinting setting. Before removing this workaround, test changes with
      live text and close a removed fallback before drawing again.
- [ ] Recheck overlapping deletes. `TTF_DeleteTextString` uses `SDL_memcpy` to shift the tail
      in SDL_ttf 3.2.2. The binding copies through a temporary string if the ranges overlap.
      Keep the middle-delete test and run it with an instrumented SDL_ttf before removing the copy.
- [ ] Recheck subpixel hinting before exposing it. `TTF_SetFontHinting` does not store the subpixel
      flag in SDL_ttf 3.2.2. The binding exposes the four working hinting modes.
- [ ] Recheck GPU glyph packing after an SDL_ttf update. The
      [3.2.2 packer](https://github.com/libsdl-org/SDL_ttf/blob/release-3.2.2/src/SDL_gpu_textengine.c#L532-L548)
      checks glyph dimensions before adding padding. The binding checks the padded size before
      building the atlas. The convenience constructor also leaves its SDL properties open. The
      binding uses the properties constructor and closes them after the call.
- [ ] Recheck [glyph image types](https://github.com/libsdl-org/SDL_ttf/blob/release-3.2.2/src/SDL_ttf.c#L3208-L3213)
      after an SDL_ttf update. SDL_ttf 3.2.2 labels grayscale SDF as alpha and can label color as
      SDF. The binding corrects the types for that version. It rejects mixed alpha and SDF glyphs
      in one text because SDL can group them in one batch.
