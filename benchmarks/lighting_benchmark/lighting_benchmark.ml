open Sdl3
open Benchmark_support
open Run
module Scene = Lighting_scene.Light_scene

let seed = 42
let default_diameter = 128

let colors =
  [|
    Color.rgb 255 136 88;
    Color.rgb 90 132 255;
    Color.rgb 110 244 142;
    Color.rgb 249 216 92;
    Color.rgb 210 124 234;
  |]

let make_lights count ~diameter ~right ~bottom =
  let rng = Random.State.make [| seed |] in
  let batch = Sprite_batch.create ~capacity:count in
  let speeds = Float.Array.make (2 * count) 0. in
  let size = float diameter in
  let dx = min 2.5 right and dy = min 2.5 bottom in
  let speed limit = Random.State.float rng (2. *. limit) -. limit in
  for i = 0 to count - 1 do
    let x = Random.State.float rng right in
    let y = Random.State.float rng bottom in
    Float.Array.unsafe_set speeds (2 * i) (speed dx);
    Float.Array.unsafe_set speeds ((2 * i) + 1) (speed dy);
    Sprite_batch.add
      ~tint:colors.(i mod Array.length colors)
      batch ~src:Scene.halo_region ~x ~y ~w:size ~h:size
  done;
  (batch, speeds)

let[@inline always] advance positions speeds i limit =
  let speed = Float.Array.unsafe_get speeds i in
  let next = Float.Array.unsafe_get positions i +. speed in
  if next < 0. then (
    Float.Array.unsafe_set positions i (-.next);
    Float.Array.unsafe_set speeds i (-.speed))
  else if next > limit then (
    Float.Array.unsafe_set positions i ((2. *. limit) -. next);
    Float.Array.unsafe_set speeds i (-.speed))
  else Float.Array.unsafe_set positions i next

let move positions speeds count ~right ~bottom =
  for i = 0 to count - 1 do
    advance positions speeds (2 * i) right;
    advance positions speeds ((2 * i) + 1) bottom
  done

let benchmark config sdl renderer ~lights ~diameter =
  let width, height = Renderer.output_size renderer in
  if width <= diameter || height <= diameter then
    invalid_arg "Use a light diameter smaller than both output dimensions";
  let right = float (width - diameter) and bottom = float (height - diameter) in
  let batch, speeds = make_lights lights ~diameter ~right ~bottom in
  let positions = Sprite_batch.positions batch in
  let@ scene = Scene.with_textures renderer ~w:width ~h:height in
  Renderer.set_vsync renderer false;
  let record () =
    move positions speeds lights ~right ~bottom;
    Scene.draw renderer scene batch
  in
  Printf.printf
    "lighting_benchmark\n\
     Lights: %d\n\
     Light diameter: %d pixels\n\
     Light map: %d x %d pixels\n"
    lights diameter width height;
  print_setup config renderer ~width ~height;
  Printf.printf "Position seed: %d\n" seed;
  measure_renderer config sdl renderer ~record

let () =
  let name = "lighting_benchmark" in
  let lights = ref 256 and diameter = ref default_diameter in
  let config =
    parse ~name ~min_axis:2
      [
        ( "--lights",
          count "a light count" 1 100_000 lights,
          "Number of lights (default 256)" );
        ( "--diameter",
          count "a light diameter in pixels" 1 8191 diameter,
          "Light diameter in output pixels (default 128)" );
      ]
  in
  with_renderer config ~name ~title:"Lighting benchmark" (fun sdl renderer ->
      benchmark config sdl renderer ~lights:!lights ~diameter:!diameter)
