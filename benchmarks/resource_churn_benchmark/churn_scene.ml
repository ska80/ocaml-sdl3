open Sdl3
open Benchmark_support.Run

let background = Color.rgb 18 24 32

let colors =
  [|
    Color.rgb 200 88 64;
    Color.rgb 76 180 220;
    Color.rgb 116 192 84;
    Color.rgb 224 182 72;
  |]

type slot = { dst : Frect.t option; mutable texture : Texture.t option }
type t = { size : int; slots : slot array; mutable phase : int }

let create ~pairs ~size ~width ~height =
  let columns = width / size and rows = height / size in
  let capacity = columns * rows in
  if pairs > capacity then
    invalid_arg
      (Printf.sprintf
         "At this texture and output size, the grid fits %d pairs. Use fewer \
          pairs or smaller textures."
         capacity);
  let edge = float size in
  let slots =
    Array.init pairs (fun i ->
        {
          dst =
            Some
              (Frect.make
                 ~x:(float (i mod columns * size))
                 ~y:(float (i / columns * size))
                 ~w:edge ~h:edge);
          texture = None;
        })
  in
  { size; slots; phase = 0 }

let release scene =
  Array.iter
    (fun slot ->
      match slot.texture with
      | None -> ()
      | Some texture ->
          Texture.destroy texture;
          slot.texture <- None)
    scene.slots

let make_texture sdl renderer ~size color =
  let@ surface = using Surface.destroy (Surface.create sdl ~w:size ~h:size) in
  Surface.fill surface color;
  Texture.of_surface renderer surface

let keep slot texture =
  match Some texture with
  | value -> slot.texture <- value
  | exception exn ->
      Texture.destroy texture;
      raise exn

let record sdl renderer scene =
  (* The previous frame has already presented. Destroy its textures before
     creating the next set, so destruction does not flush each draw. *)
  release scene;
  Renderer.clear renderer;
  for i = 0 to Array.length scene.slots - 1 do
    let slot = scene.slots.(i) in
    let color = colors.((scene.phase + i) mod Array.length colors) in
    let texture = make_texture sdl renderer ~size:scene.size color in
    keep slot texture;
    Texture.set_blend_mode texture Blend_mode.None;
    Texture.draw ?dst:slot.dst renderer texture
  done;
  scene.phase <- (scene.phase + 1) mod Array.length colors;
  Array.length scene.slots
