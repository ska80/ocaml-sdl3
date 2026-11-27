# Benchmark plan

The atlas and tilemap benchmarks are ready to run. The other workloads are planned.

## Workloads

| Benchmark | Workload |
| --- | --- |
| [`atlas_benchmark`](#atlas-benchmark) | 100,000 sprites with different atlas regions |
| [`tilemap_benchmark`](#tilemap-benchmark) | Large scrolling maps |
| `isometric_benchmark` | Sorted, overlapping transparent sprites |
| `gpu_instancing_benchmark` | 100,000 instanced sprites |
| `lighting_benchmark` | Multiple dynamic light sources |
| `text_benchmark` | Thousands of dynamic text objects |
| `asset_streaming_benchmark` | Texture uploads during gameplay |
| `resource_churn_benchmark` | Repeated resource creation and destruction |

## Atlas benchmark

From the repository root, run the native release build:

```sh
dune exec --profile release ./benchmarks/atlas_benchmark/atlas_benchmark.exe
```

The benchmark generates one texture atlas, a texture that holds many images. Each sprite uses its
own 8 × 8 pixel region. The benchmark uploads the atlas once and moves the sprites by a fixed step
each frame. It reuses one `Sprite_batch` without allocating an OCaml object for each sprite on every
frame. The default draws 100,000 sprites in a 1280 × 720 window. It measures 300 frames after 60
warm-up frames.

Use `--sprites`, `--width`, `--height`, `--warmup`, or `--frames` to change the workload. Use
`--driver` to select a renderer. If SDL supports offscreen Vulkan on your system, run a short check
without a display:

```sh
SDL_VIDEO_DRIVER=offscreen SDL_GPU_DRIVER=vulkan \
  dune exec --profile release ./benchmarks/atlas_benchmark/atlas_benchmark.exe -- \
  --driver gpu --warmup 5 --frames 30
```

The program asks SDL to disable VSync. It reports the interval SDL returns. The CPU frame time
covers the scene update, draw recording, and `Renderer.present`. The report separates the present
call, which can include a driver wait. It excludes event polling from frame timing. `Esc` or a
window close ends the run and reports any frames it measured.

The allocation count includes the measurement loop. GC tracing counts stop-the-world pauses, when
the runtime stops running application code. The benchmark reads these events after the measured
frames. If the runtime overwrites events before they are read, it reports the pause measurements as
unavailable. Use `--no-gc-events` to skip tracing. If the working directory is read-only, set
`OCAML_RUNTIME_EVENTS_DIR` to a writable directory for the trace.

On Linux, peak resident process memory includes setup and warm-up. The report counts one binding
draw per frame. SDL can split or combine draws before they reach the GPU. GPU frame time, GPU
memory, and backend draw counts require a separate profiler and are not in this report.

Run `dune runtest benchmarks` for short software-renderer runs and tests of the measurement code.
These tests do not enforce any timing limits.

### Current results

Both offscreen runs drew 100,000 sprites at 1280 × 720. Each run measured 30 frames after five
warm-up frames. The host ran Linux on an Intel i7-1165G7 with SDL 3.4.20 and OCaml 5.5.2. Both runs
used a native release build, and SDL reported VSync off.

| Measurement | SDL `gpu` (Vulkan, llvmpipe) | SDL `opengl` |
| --- | ---: | ---: |
| CPU frame time, p50 / p95 / p99 | 74.067 / 89.201 / 120.623 ms | 21.046 / 46.444 / 51.424 ms |
| Scene update and draw recording, p50 / p95 / p99 | 4.787 / 6.644 / 7.475 ms | 4.857 / 6.516 / 7.276 ms |
| `Renderer.present` call, p50 / p95 / p99 | 69.373 / 83.549 / 114.377 ms | 16.479 / 40.738 / 46.092 ms |
| OCaml allocations | 3.2 bytes/frame | 3.2 bytes/frame |
| Garbage collection pauses | 0 | 0 |
| Peak resident process memory | 321.0 MiB | 130.3 MiB |
| Binding draw calls | 1/frame | 1/frame |
| GPU frame time, GPU memory, backend draw count | Unavailable | Unavailable |

Scene update and draw recording took about the same time in both runs. Most of the difference was in
`Renderer.present`, which includes driver work and waits. It does not measure GPU time.  The Vulkan
run used a software driver. These short runs do not rank the two backends in general.

## Tilemap benchmark

From the repository root, run the native release build:

```sh
dune exec --profile release ./benchmarks/tilemap_benchmark/tilemap_benchmark.exe
```

The benchmark generates a map with 4,096 × 4,096 tiles by default. Each tile is 16 × 16 pixels and
stores one byte that selects an image from a shared atlas. The map data takes 16 MiB. The camera
moves by a fixed step of seven pixels horizontally and five pixels vertically per frame. It reverses
direction at the map edges.

Each frame, the benchmark finds the tiles that intersect the viewport, including partial tiles at
the edges. It puts them into one reusable batch in row order. It does not scan the whole map or
upload the atlas again. At the default output size of 1280 × 720, the batch holds at most 3,726
visible tiles.

Use `--map-width` and `--map-height` to change the number of tiles. Use `--tile-size` to change both
pixel dimensions of a tile. The benchmark also accepts `--width`, `--height`, `--driver`,
`--warmup`, `--frames`, and `--no-gc-events`, like the atlas benchmark.

### Tilemap results

Both offscreen runs used the default map, tile size, and output size. Each run measured 30 frames
after five warm-up frames. The host ran Linux on an Intel i7-1165G7 with SDL 3.4.20 and OCaml 5.5.2.
Both runs used a native release build, and SDL reported VSync off.

| Measurement | SDL `gpu` (Vulkan, llvmpipe) | SDL `opengl` |
| --- | ---: | ---: |
| CPU frame time, p50 / p95 / p99 | 5.496 / 6.173 / 6.583 ms | 0.813 / 1.151 / 1.212 ms |
| Scene update and draw recording, p50 / p95 / p99 | 0.306 / 0.324 / 0.333 ms | 0.251 / 0.415 / 0.439 ms |
| `Renderer.present` call, p50 / p95 / p99 | 5.187 / 5.849 / 6.278 ms | 0.563 / 0.804 / 0.816 ms |
| OCaml allocations | 51.2 bytes/frame | 51.2 bytes/frame |
| Garbage collection pauses | 0 | 0 |
| Peak resident process memory | 128.1 MiB | 101.2 MiB |
| Binding draw calls | 1/frame | 1/frame |
| GPU frame time, GPU memory, backend draw count | Unavailable | Unavailable |

The allocation rate stayed the same in a smaller release run with a batch capacity of 70 tiles.
Most of the frame time difference was in `Renderer.present`. The runs do not measure GPU time, and
the Vulkan run used a software driver.

## Measurements

- CPU frame time: Measure the time to update the scene, record draws, and submit a frame. Separate
  waits for the GPU or display if the backend reports them.
- GPU frame time: Use GPU timestamps or a profiler when available. If neither provides GPU time,
  report it as unavailable. Waiting for a fence does not measure GPU frame time.
- Frame-time percentiles: Report the median (p50), p95, and p99 in milliseconds. A p95 of 10 ms
  means that 95% of measured frames took 10 ms or less.
- OCaml allocations: Report bytes allocated per frame.
- Garbage collection pauses: Report how often collection pauses the program and how long the pauses
  last.
- Memory consumption: Report peak process memory and GPU memory when the tools report it.
- Draw call count: Report draws per frame. Count binding calls and backend draws separately when
  both counts are available. One binding call can turn into several draws.

## Compare runs

Keep the workload fixed between runs. If the camera moves, use the same path. Exclude warm-up frames
from the results. Record the workload size, output size, and number of measured frames.  Record the
CPU and GPU models, operating system, and driver version. Record the SDL version, OCaml version, and
build profile. State whether presentation waits for the display to refresh (VSync).
