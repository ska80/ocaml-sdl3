open Sdl3
open Benchmark_support
open Run

let sprite_size = 24
let atlas_tiles = 64
let opacity = 160
let seed = 42

type scene = {
  u : int array;
  v : int array;
  du : int array;
  dv : int array;
  depth : Depth_order.t;
  span : int;
}

let make_scene count span =
  let rng = Random.State.make [| seed |] in
  let positions () =
    Array.init count (fun _ -> Random.State.int rng (span + 1))
  in
  let speed = min 3 span in
  let speeds () =
    Array.init count (fun _ -> Random.State.int rng ((2 * speed) + 1) - speed)
  in
  let u = positions () in
  let v = positions () in
  let du = speeds () in
  let dv = speeds () in
  for i = 0 to count - 1 do
    if du.(i) = 0 && dv.(i) = 0 then du.(i) <- 1
  done;
  {
    u;
    v;
    du;
    dv;
    depth = Depth_order.create ~levels:((2 * span) + 1) count;
    span;
  }

let[@inline always] advance positions speeds i span =
  let position = positions.(i) and speed = speeds.(i) in
  let next = position + speed in
  let next =
    if next < 0 then (
      speeds.(i) <- -speed;
      -next)
    else if next > span then (
      speeds.(i) <- -speed;
      (2 * span) - next)
    else next
  in
  positions.(i) <- next;
  next

let move scene =
  for i = 0 to Array.length scene.u - 1 do
    let u = advance scene.u scene.du i scene.span in
    let v = advance scene.v scene.dv i scene.span in
    Depth_order.set scene.depth i (u + v)
  done

let fill_batch batch regions scene ~left ~top =
  let ids = Depth_order.sort scene.depth in
  let size = float sprite_size in
  Sprite_batch.clear batch;
  for j = 0 to Array.length ids - 1 do
    let id = ids.(j) in
    let src = regions.(id mod atlas_tiles) in
    let x = float (left + scene.u.(id) - scene.v.(id)) in
    let y = top +. (0.5 *. float (Depth_order.depth scene.depth id)) in
    Sprite_batch.add batch ~src ~x ~y ~w:size ~h:size
  done

let diamond_alpha x y =
  let dx = abs ((2 * x) + 1 - sprite_size) in
  let dy = abs ((2 * y) + 1 - sprite_size) in
  if dx + (2 * dy) <= sprite_size then opacity else 0

let benchmark config sdl renderer count =
  let width, height = Renderer.output_size renderer in
  (* Fit the projected square inside the output. U moves right and down;
     V moves left and down. All sprites have the same size. *)
  let left = (width - sprite_size) / 2 in
  let span = min left (height - sprite_size) in
  if span < 1 then invalid_arg "Use an output that is larger than one sprite";
  let top = 0.5 *. float (height - sprite_size - span) in
  let atlas = Atlas.layout ~tiles:atlas_tiles ~tile_size:sprite_size in
  let regions = Array.init atlas_tiles (Atlas.region atlas) in
  let@ texture =
    Atlas.with_texture ~alpha:diamond_alpha ~blend:Blend renderer atlas
  in
  Renderer.set_vsync renderer false;
  Renderer.set_draw_color renderer (Color.rgb 18 24 32);
  let scene = make_scene count span in
  let batch = Sprite_batch.create ~capacity:count in
  let record () =
    move scene;
    fill_batch batch regions scene ~left ~top;
    Renderer.clear renderer;
    Sprite_batch.draw renderer texture batch;
    1
  in
  Printf.printf
    "isometric_benchmark\nSprites: %d\nSprite size: %d x %d pixels\n" count
    sprite_size sprite_size;
  Printf.printf "Atlas: %d x %d pixels, %d regions\nDiamond opacity: %d/255\n"
    atlas.width atlas.height atlas_tiles opacity;
  Printf.printf
    "Depth order: back to front, then sprite ID\nPosition seed: %d\n" seed;
  print_setup config renderer ~width ~height;
  measure_renderer config sdl renderer ~record

let () =
  let name = "isometric_benchmark" and sprites = ref 20_000 in
  let config =
    parse ~name ~min_axis:(sprite_size + 2)
      [
        ( "--sprites",
          count "a sprite count" 1 250_000 sprites,
          "Number of sprites (default 20000)" );
      ]
  in
  with_renderer config ~name ~title:"Isometric benchmark" (fun sdl renderer ->
      benchmark config sdl renderer !sprites)
