open Sdl3
open Sdl3_ttf
open Benchmark_support.Run

let background = Color.rgb 18 24 32

let font_path () =
  Filename.concat (Filename.dirname Sys.executable_name) "DejaVuSans.ttf"

let values () = Array.init 1000 (Printf.sprintf "%03d")

let cell_size font values =
  let w, h =
    Array.fold_left
      (fun (max_w, max_h) text ->
        let w, h = Font.measure font text in
        (max w max_w, max h max_h))
      (1, Font.height font)
      values
  in
  (w + 2, h + 2)

let with_texts engine font values count f =
  let@ first = using Text.destroy (Text.create engine font values.(0)) in
  let texts = Array.make count first in
  let live = ref 1 in
  Fun.protect
    ~finally:(fun () ->
      for i = 1 to !live - 1 do
        Text.destroy texts.(i)
      done)
    (fun () ->
      for i = 1 to count - 1 do
        texts.(i) <- Text.create engine font values.(i mod Array.length values);
        incr live
      done;
      f texts)

type label = { text : Text_engine.renderer Text.t; x : float; y : float }

type t = {
  labels : label array;
  values : string array;
  cell_width : int;
  cell_height : int;
  mutable phase : int;
}

let with_scene ttf renderer font ~count ~w ~h f =
  let values = values () in
  let cell_width, cell_height = cell_size font values in
  let columns = w / cell_width and rows = h / cell_height in
  let capacity = columns * rows in
  if count > capacity then
    invalid_arg
      (Printf.sprintf
         "At this font and output size, use at most %d labels. Enlarge the \
          output or reduce the font size."
         capacity);
  let@ engine =
    using Text_engine.destroy (Text_engine.create_renderer ttf renderer)
  in
  let@ texts = with_texts engine font values count in
  (* Store the boxed coordinates once. The renderer API takes float values. *)
  let labels =
    Array.mapi
      (fun i text ->
        {
          text;
          x = float (1 + (i mod columns * cell_width));
          y = float (1 + (i / columns * cell_height));
        })
      texts
  in
  Renderer.set_draw_color renderer background;
  f { labels; values; cell_width; cell_height; phase = 0 }

let draw renderer scene =
  let period = Array.length scene.values in
  let phase = (scene.phase + 1) mod period in
  scene.phase <- phase;
  Renderer.clear renderer;
  for i = 0 to Array.length scene.labels - 1 do
    let label = scene.labels.(i) in
    Text.set_string label.text scene.values.((i + phase) mod period);
    Text.draw_renderer label.text ~x:label.x ~y:label.y
  done;
  Array.length scene.labels
