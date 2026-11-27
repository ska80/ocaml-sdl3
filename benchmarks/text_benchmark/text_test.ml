open Sdl3
open Sdl3_ttf
open Benchmark_support.Run
module Scene = Text_bench_scene.Text_scene

let check condition message = if not condition then failwith message

let check_scene sdl renderer =
  Sdl3_ttf.with_init sdl (fun ttf ->
      let@ font =
        using Font.close (Font.open_ ttf (Scene.font_path ()) ~ptsize:10.)
      in
      let w, h = Renderer.output_size renderer in
      let@ scene = Scene.with_scene ttf renderer font ~count:2 ~w ~h in
      let first = scene.labels.(0).text and second = scene.labels.(1).text in
      check
        (Text.string first = "000" && Text.string second = "001")
        "Initial label values";
      let draw expected_first expected_second =
        check (Scene.draw renderer scene = 2) "Count one draw per label";
        check
          (Text.string first = expected_first
          && Text.string second = expected_second)
          "Update the same text objects";
        let rect =
          Rect.make ~x:0 ~y:0 ~w:scene.cell_width ~h:scene.cell_height
        in
        let@ capture =
          using Surface.destroy (Renderer.read_pixels ~rect renderer)
        in
        let length = 4 * rect.w * rect.h in
        let bytes =
          Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout length
        in
        Surface.read_rgba capture bytes;
        bytes
      in
      let first_frame = draw "001" "002" in
      let next_frame = draw "002" "003" in
      let drawn = ref false and changed = ref false in
      for i = 0 to (Bigarray.Array1.dim first_frame / 4) - 1 do
        let x = first_frame.{4 * i} and y = next_frame.{4 * i} in
        if x > 18 then drawn := true;
        if x <> y then changed := true
      done;
      check !drawn "Draw the counter glyphs";
      check !changed "Glyph pixels change when a counter advances")

let () =
  match Array.to_list Sys.argv with
  | [ _ ] ->
      Sdl3.with_init [] (fun sdl ->
          let@ surface =
            using Surface.destroy (Surface.create sdl ~w:96 ~h:48)
          in
          using Renderer.destroy
            (Renderer.create_software surface)
            (check_scene sdl))
  | [ _; "--driver"; driver ] ->
      Sdl3.with_init [ Video ] (fun sdl ->
          let@ window =
            using Window.destroy
              (Window.create sdl ~title:"Text benchmark test" ~w:96 ~h:48)
          in
          using Renderer.destroy
            (Renderer.create ~driver window)
            (check_scene sdl))
  | _ -> invalid_arg "Use text_test [--driver NAME]"
