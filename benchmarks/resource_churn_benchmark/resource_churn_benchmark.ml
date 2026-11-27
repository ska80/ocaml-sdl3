open Sdl3
open Benchmark_support.Run
module Scene = Resource_churn_scene.Churn_scene

let benchmark config sdl renderer ~pairs ~size =
  let width, height = Renderer.output_size renderer in
  let@ scene = using Scene.release (Scene.create ~pairs ~size ~width ~height) in
  Renderer.set_vsync renderer false;
  Renderer.set_draw_color renderer Scene.background;
  Printf.printf
    "resource_churn_benchmark\nSurface and texture pairs per frame: %d\n" pairs;
  Printf.printf
    "Texture size: %d x %d pixels\nSource pixel bytes per frame: %d\n" size size
    (pairs * size * size * 4);
  print_setup config renderer ~width ~height;
  measure_renderer config sdl renderer ~record:(fun () ->
      Scene.record sdl renderer scene)

let () =
  let name = "resource_churn_benchmark" in
  let pairs = ref 64 and size = ref 64 in
  let config =
    parse ~name ~min_axis:1
      [
        ( "--pairs",
          count "a resource pair count" 1 1000 pairs,
          "Surface and texture pairs per frame (default 64)" );
        ( "--size",
          count "a texture size in pixels" 1 512 size,
          "Surface and texture width and height (default 64)" );
      ]
  in
  with_renderer config ~name ~title:"Resource churn benchmark"
    (fun sdl renderer ->
      benchmark config sdl renderer ~pairs:!pairs ~size:!size)
