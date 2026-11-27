open Sdl3
open Sdl3_ttf
open Benchmark_support.Run
module Scene = Text_bench_scene.Text_scene

let benchmark config sdl renderer ~labels ~font_size ~font_path =
  let width, height = Renderer.output_size renderer in
  Renderer.set_vsync renderer false;
  Sdl3_ttf.with_init sdl (fun ttf ->
      let@ font =
        using Font.close (Font.open_ ttf font_path ~ptsize:(float font_size))
      in
      let@ scene =
        Scene.with_scene ttf renderer font ~count:labels ~w:width ~h:height
      in
      let { major; minor; patch } = Sdl3_ttf.version () in
      Printf.printf
        "text_benchmark\nText labels: %d\nText updates per frame: %d\n" labels
        labels;
      Printf.printf "Font: %s\nFont size: %d pt\nLabel cell: %d x %d pixels\n"
        (Filename.basename font_path)
        font_size scene.cell_width scene.cell_height;
      Printf.printf "SDL_ttf: %d.%d.%d\nHarfBuzz: %b\n" major minor patch
        (Sdl3_ttf.has_harfbuzz ());
      print_setup config renderer ~width ~height;
      measure_renderer config sdl renderer ~record:(fun () ->
          Scene.draw renderer scene))

let () =
  let name = "text_benchmark" in
  let labels = ref 2048 and font_size = ref 10 and font = ref None in
  let config =
    parse ~name ~min_axis:1
      [
        ( "--labels",
          count "a label count" 1 100_000 labels,
          "Number of text labels (default 2048)" );
        ( "--font-size",
          count "a font size" 6 72 font_size,
          "Font size in points (default 10)" );
        ( "--font",
          Arg.String (fun path -> font := Some path),
          "Font file (default DejaVu Sans)" );
      ]
  in
  let font_path = Option.value !font ~default:(Scene.font_path ()) in
  with_renderer config ~name ~title:"Text benchmark" (fun sdl renderer ->
      benchmark config sdl renderer ~labels:!labels ~font_size:!font_size
        ~font_path)
