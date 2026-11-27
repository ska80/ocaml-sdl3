# Remaining work

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
      Recheck the same sizes during mipmap generation on Vulkan and Direct3D 12.
- [ ] Recheck texture upload pitches on Metal and Direct3D 12 after an SDL update. SDL 3.4.20
      ignores the source pitch on Metal. The Direct3D 12 realignment path can copy a source row into
      a smaller temporary row or read padding after the last pixel. The binding repacks those
      layouts.
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

Keep the test that moves a middle track to another group and destroys its neighbor.

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
