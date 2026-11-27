open Sdl3
open Benchmark_support.Run
module Scene = Lighting_scene.Light_scene

let check condition message = if not condition then failwith message
let near a b = abs (a - b) <= 1

let check_scene renderer =
  let w, h = Renderer.output_size renderer in
  let@ scene = Scene.with_textures renderer ~w ~h in
  let batch = Sprite_batch.create ~capacity:2 in
  let add tint =
    Sprite_batch.add ~tint batch ~src:Scene.halo_region ~x:0. ~y:0. ~w:8. ~h:8.
  in
  let draw () =
    check (Scene.draw renderer scene batch = 3) "Count the three binding draws";
    let@ capture = using Surface.destroy (Renderer.read_pixels renderer) in
    (Surface.read_pixel capture ~x:4 ~y:4, Surface.read_pixel capture ~x:12 ~y:4)
  in
  let ambient, outside = draw () in
  add (Color.rgb 255 0 0);
  let red, _ = draw () in
  check
    (red.r > ambient.r && near red.g ambient.g && near red.b ambient.b)
    "A red light affects only the red channel of the ground";
  add (Color.rgb 0 255 0);
  let both, far = draw () in
  check
    (near both.r red.r && both.g > red.g && near both.b red.b)
    "Overlapping lights add their colors";
  check (far = outside) "Pixels outside both lights stay at ambient light";
  Sprite_batch.clear batch;
  check
    (draw () = (ambient, outside))
    "Clear the light map before the next frame"

let () =
  match Array.to_list Sys.argv with
  | [ _ ] ->
      with_init [] (fun sdl ->
          let@ surface =
            using Surface.destroy (Surface.create sdl ~w:16 ~h:16)
          in
          using Renderer.destroy (Renderer.create_software surface) check_scene)
  | [ _; "--driver"; driver ] ->
      with_init [ Video ] (fun sdl ->
          let@ window =
            using Window.destroy
              (Window.create sdl ~title:"Lighting test" ~w:16 ~h:16)
          in
          using Renderer.destroy (Renderer.create ~driver window) check_scene)
  | _ -> invalid_arg "Use lighting_test [--driver NAME]"
