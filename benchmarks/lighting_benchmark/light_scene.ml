open Sdl3
open Benchmark_support.Run

let halo_size = 64
let halo_region = Rect.make ~x:0 ~y:0 ~w:halo_size ~h:halo_size
let ambient = Color.rgb 34 34 34

let with_image renderer ~size ~scale ~blend ~pixel f =
  let@ texture =
    using Texture.destroy (Texture.create_streaming renderer ~w:size ~h:size)
  in
  let pitch = 4 * size in
  let pixels =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (pitch * size)
  in
  for y = 0 to size - 1 do
    for x = 0 to size - 1 do
      let { Color.r; g; b; a } = pixel x y in
      let i = (y * pitch) + (4 * x) in
      pixels.{i} <- r;
      pixels.{i + 1} <- g;
      pixels.{i + 2} <- b;
      pixels.{i + 3} <- a
    done
  done;
  Texture.update texture pixels ~pitch;
  Texture.set_scale_mode texture scale;
  Texture.set_blend_mode texture blend;
  f texture

let ground_pixel x y =
  let shade =
    if x mod 16 = 0 || y mod 16 = 0 then 104
    else if ((x / 16) + (y / 16)) mod 2 = 0 then 164
    else 188
  in
  Color.rgb shade (shade + 6) (shade + 12)

let halo_pixel x y =
  let radius = float halo_size *. 0.5 in
  let dx = (float x +. 0.5 -. radius) /. radius in
  let dy = (float y +. 0.5 -. radius) /. radius in
  let falloff = max 0. (1. -. (dx *. dx) -. (dy *. dy)) in
  (* Add uses source alpha to scale RGB. Keep the source color white. *)
  Color.rgba 255 255 255 (int_of_float ((255. *. falloff *. falloff) +. 0.5))

type t = {
  ground : Texture.streaming;
  halo : Texture.streaming;
  light_map : Texture.target;
  target : Texture.target option;
}

let with_textures renderer ~w ~h f =
  let@ ground =
    with_image renderer ~size:256 ~scale:Nearest ~blend:Blend_mode.None
      ~pixel:ground_pixel
  in
  let@ halo =
    with_image renderer ~size:halo_size ~scale:Linear ~blend:Add
      ~pixel:halo_pixel
  in
  let@ light_map =
    using Texture.destroy (Texture.create_target renderer ~w ~h)
  in
  Texture.set_scale_mode light_map Nearest;
  Texture.set_blend_mode light_map Mod;
  Renderer.set_draw_color renderer ambient;
  f { ground; halo; light_map; target = Some light_map }

let draw renderer scene batch =
  Renderer.set_target renderer scene.target;
  Fun.protect
    ~finally:(fun () -> Renderer.set_target renderer None)
    (fun () ->
      Renderer.clear renderer;
      Sprite_batch.draw renderer scene.halo batch);
  Texture.draw renderer scene.ground;
  Texture.draw renderer scene.light_map;
  3
