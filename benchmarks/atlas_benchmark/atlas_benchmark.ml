open Sdl3
open Benchmark_support
open Run

let tile_size = 8
let step_x = 1.
let step_y = 0.5
let seed = 42

let create_batch count atlas ~right ~bottom =
  let rng = Random.State.make [| seed |] in
  let batch = Sprite_batch.create ~capacity:count in
  let size = float tile_size in
  for i = 0 to count - 1 do
    let src = Atlas.region atlas i in
    let x = Random.State.float rng right
    and y = Random.State.float rng bottom in
    Sprite_batch.add batch ~src ~x ~y ~w:size ~h:size
  done;
  batch

let[@inline always] shift positions i step limit =
  let next = Float.Array.unsafe_get positions i +. step in
  Float.Array.unsafe_set positions i
    (if next >= limit then next -. limit else next)

let move positions count ~right ~bottom =
  for i = 0 to count - 1 do
    shift positions (2 * i) step_x right;
    shift positions ((2 * i) + 1) step_y bottom
  done

let benchmark config sdl renderer sprites =
  let width, height = Renderer.output_size renderer in
  if width <= tile_size || height <= tile_size then
    invalid_arg "Use an output that is larger than one sprite";
  let atlas = Atlas.layout ~tiles:sprites ~tile_size in
  let@ texture = Atlas.with_texture renderer atlas in
  Renderer.set_vsync renderer false;
  Renderer.set_draw_color renderer (Color.rgb 18 24 32);
  let right = float (width - tile_size)
  and bottom = float (height - tile_size) in
  let batch = create_batch sprites atlas ~right ~bottom in
  let positions = Sprite_batch.positions batch in
  let record () =
    move positions sprites ~right ~bottom;
    Renderer.clear renderer;
    Sprite_batch.draw renderer texture batch;
    1
  in
  Printf.printf
    "atlas_benchmark\n\
     Sprites: %d\n\
     Atlas: %d x %d pixels, %d unique regions (%d x %d pixels each)\n"
    sprites atlas.width atlas.height sprites tile_size tile_size;
  print_setup config renderer ~width ~height;
  Printf.printf "Position seed: %d\n" seed;
  measure config sdl renderer ~record

let () =
  let name = "atlas_benchmark" and sprites = ref 100_000 in
  let config =
    parse ~name ~min_axis:(tile_size + 1)
      [
        ( "--sprites",
          count "a sprite count" 1 1_000_000 sprites,
          "Number of sprites (default 100000)" );
      ]
  in
  with_window config ~name ~title:"Atlas benchmark" (fun sdl renderer ->
      benchmark config sdl renderer !sprites)
