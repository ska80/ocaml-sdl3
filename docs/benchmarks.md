# Benchmark plan

These benchmarks are planned. They do not have runnable targets or results yet.

## Workloads

| Benchmark | Workload |
| --- | --- |
| `atlas_benchmark` | 100,000 sprites with different atlas regions |
| `tilemap_benchmark` | Large scrolling maps |
| `isometric_benchmark` | Sorted, overlapping transparent sprites |
| `gpu_instancing_benchmark` | 100,000 instanced sprites |
| `lighting_benchmark` | Multiple dynamic light sources |
| `text_benchmark` | Thousands of dynamic text objects |
| `asset_streaming_benchmark` | Texture uploads during gameplay |
| `resource_churn_benchmark` | Repeated resource creation and destruction |

## Measurements

- CPU frame time: Measure the time to update the scene, record draws, and submit a frame. Report
  time spent waiting for the GPU or display separately.
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

Keep the workload and camera path fixed between runs. Exclude warm-up frames from the results.
Record the workload size, output size, and number of measured frames. Record the hardware, operating
system, driver, SDL version, OCaml version, and build profile. State whether presentation waits for
the display to refresh (VSync).
