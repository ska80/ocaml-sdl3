# Run the tests

The tests passed on Linux with OCaml 5.5.2 and Dune 3.25.0. See [TODO.md](../TODO.md#done) for the
SDL versions.

## Run the main suite

From the repository root, build the packages and run the native and bytecode tests:

```sh
dune build @install
dune runtest
```

The tests use SDL's dummy video and audio drivers. They need no display, speakers, or microphone.
The core tests need SDL's virtual joystick support, not a physical gamepad. The image tests need
GIF, PNG, and JPEG support in SDL3_image. The mixer tests need WAV support in SDL3_mixer.

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
