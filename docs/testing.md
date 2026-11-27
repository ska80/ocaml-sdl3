# Run the tests

Use the library versions listed under [Install from source](../README.md#install-from-source) or
later. The tests passed on Linux with OCaml 5.5.2 and Dune 3.25.0.

## Run the main suite

From the repository root, build the packages and run the native and bytecode tests:

```sh
dune build @install
dune runtest
```

The tests use SDL's dummy video and audio drivers. They need no display, speakers, or microphone.
The core tests need SDL's virtual joystick support, not a physical gamepad. The image tests need
GIF, PNG, and JPEG support in SDL3_image. The mixer tests need WAV support in SDL3_mixer.

Run `dune runtest --force test/core` to test viewport, clip, and scale changes with the software
renderer. These tests read captures from a window, surface, and texture target. They compare the
size and colors, test clipping and ownership, and convert points and events. The tests send all
three renderer reset and loss events through the queue with known timestamps and IDs. They do not
force a real device failure.

The core tests also cover mouse state, focus events, and cursor cleanup. They check failure paths
for capture and system cursors on the dummy driver. Test actual capture and desktop coordinates with
a windowing driver.

The core tests check base and preference paths. On Linux they create save directories in a private
temporary directory. They check that a timed wait returns on timeout and wakes for an event from
another OCaml thread. They also check window size limits and rumble on a virtual gamepad. They read
startup audio device events and send removal events through the queue. These cases do not need
physical devices. The dummy driver cannot show window icons or change the user-resizable setting.
The tests expect an error for both calls. Use a driver with desktop support to test these actions
and exclusive fullscreen.

Run `dune runtest --force test/surface` to test image copies, transforms, and palette swaps. The
native and bytecode tests also check pixel row copies, lock cleanup, and upload of an atlas made
from indexed sprites. They need no window or add-on.

Run `dune runtest --force test/image_data` to test BMP loads on worker domains. The tests compare
pixels from files and memory buffers. They test a shutdown attempt during a load, cleanup after a
failed load, and texture upload on the main thread. They need no window or add-on.

Run `dune runtest --force test/ttf` to test reusable text in native and bytecode. The tests check
style changes in drawn pixels, kerning, fallback font lifetimes, edits, and bounds across wrapped
lines. If SDL_ttf uses HarfBuzz, they also check a ligature and right-to-left layout. Without
HarfBuzz, they check that unsupported directions and scripts return errors. The core tests cover
text input area changes and clipboard text on the dummy driver, not a system input method.

Run `dune runtest --force test/mixer` to test stereo panning and distance with known WAV samples.
The tests also cover tag gain, pause and resume, fades at two input rates, and group assignment.
They move a middle track out of a group and destroy its neighbor. They also read stop notices from
memory mixes and from SDL's dummy audio thread.

## Run the resource lifecycle tests

QCheck generates sequences of operations on a context, a memory stream, and a software rendering
chain. The test tracks which handles must be open. It checks that closing a parent too early and
using a closed handle raise `Invalid_argument`. It also tests repeated cleanup, failed BMP loads,
and texture locks whose callbacks raise exceptions.

The main suite includes this test if QCheck is installed. QCheck is an opam test dependency of
`sdl3`, not a dependency of the installed bindings. From the repository root, run:

```sh
opam install qcheck-core
dune runtest --force test/lifecycle
```

If the test fails, QCheck prints the random seed and tries to shorten the failing sequence.  To
replay a run, use the same QCheck version and replace `31415` with the printed seed:

```sh
SDL_VIDEO_DRIVER=dummy dune exec ./test/lifecycle/lifecycle_test.exe -- --seed 31415
```

Add `--long` after the seed to run 3,000 cases instead of 300.

## Run the C stub tests with sanitizers

AddressSanitizer (ASan) detects invalid memory access. UndefinedBehaviorSanitizer (UBSan) detects
operations that C does not define, such as an invalid bit shift. The `sanitize` profile adds both
checks to the C stubs without changing the normal build.

Use an OCaml switch whose C compiler supports both sanitizers. This profile passed on Linux x86-64
with GCC 14 and Clang 19. From the repository root, run:

```sh
ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=print_stacktrace=1 \
  dune runtest --profile sanitize --build-dir "$PWD/_build/sanitize" --force
```

If you only have SDL3, add `--only-packages=sdl3`. The shorter flag `-p sdl3` selects the release
profile instead.

The profile links both sanitizer libraries into native and bytecode tests. It does not add checks to
the installed SDL libraries or the OCaml runtime. The command disables leak detection because the
stock OCaml runtime leaves some allocations at exit. Invalid memory access still fails the test. Use
the normal build to install the bindings.

## Test sprite batches on another renderer

The main suite tests sprite batches with the software renderer. To test another SDL renderer, set
`SDL_RENDER_DRIVER` and run `dune build --force @runtest-sprite-batch`. The tests read pixels from a
texture to check regions, transforms, and draw order. If your Linux system supports offscreen
OpenGL, run:

```sh
SDL_VIDEO_DRIVER=offscreen SDL_RENDER_DRIVER=opengl dune build --force @runtest-sprite-batch
```

## Test 2D geometry on another renderer

The main suite tests 2D geometry with the software renderer. The tests read pixels to check color
gradients, texture coordinates, blending, and draw order. If your Linux system supports offscreen
OpenGL, run:

```sh
SDL_VIDEO_DRIVER=offscreen SDL_RENDER_DRIVER=opengl dune build --force @runtest-geometry
```

Set `SDL_RENDER_DRIVER` to another supported renderer to test it instead. The command runs both
native and bytecode tests.

## Test texture operations on another renderer

Run `dune runtest --force test/texture` to test the software renderer. These tests use
`Renderer.read_pixels` to read a texture target. They cover tint, rotation pivots, affine copies,
partial tiles, and nine-slice panels. They also check that software rejects unsupported blend
modes. On OpenGL, OpenGL ES 2, and the `gpu` and `vulkan` renderers, they test the reported texture
limit on both axes.

To test drawing and custom blending with offscreen OpenGL on Linux, run:

```sh
SDL_VIDEO_DRIVER=offscreen SDL_RENDER_DRIVER=opengl dune build --force @runtest-texture
```

Both commands run native and bytecode tests.

## Run GPU tests

Run `dune build --force @runtest-gpu` from the repository root on a system with a working SDL GPU
driver. On Linux with offscreen Vulkan support, set `SDL_VIDEO_DRIVER=offscreen` to run without a
display.

The drawing tests use SPIR-V, a shader format that Vulkan accepts. They skip drawing on devices that
do not accept SPIR-V. The repository includes compiled shaders, so the tests do not need a shader
compiler. If you edit the [test shaders](../test/gpu/shaders), rebuild the compiled files from the
repository root:

```sh
for shader in test/gpu/shaders/*.vert test/gpu/shaders/*.frag; do
  glslangValidator -V --target-env vulkan1.0 -g0 "$shader" -o "$shader.spv"
done
```

The Aurora Tunnel example has a [separate short test](../examples/aurora_tunnel/README.md#run-a-short-test).
The [Music Player tests](../examples/music_player/README.md#run-the-tests) also include a GPU test.
