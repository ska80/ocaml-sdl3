open Sdl3
open Benchmark_support.Run
module Scene = Resource_churn_scene.Churn_scene

let check condition message = if not condition then failwith message

let closed texture =
  match Texture.size texture with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "An old texture is still open"

let check_scene sdl renderer =
  let width, height = Renderer.output_size renderer in
  let final = ref None in
  (match
     let@ scene =
       using Scene.release (Scene.create ~pairs:2 ~size:4 ~width ~height)
     in
     Renderer.set_draw_color renderer Scene.background;
     let draw () =
       check (Scene.record sdl renderer scene = 2) "Count one draw per texture";
       let@ capture = using Surface.destroy (Renderer.read_pixels renderer) in
       let color = Surface.read_pixel capture ~x:1 ~y:1 in
       Renderer.present renderer;
       color
     in
     let first = draw () in
     check
       (first = Scene.colors.(0))
       "Draw the first texture after releasing its source surface";
     let old =
       Array.map
         (fun (slot : Scene.slot) -> Option.get slot.texture)
         scene.slots
     in
     let second = draw () in
     check
       (second = Scene.colors.(1))
       "The next frame draws a new set of textures";
     Array.iter closed old;
     final := scene.slots.(0).texture;
     raise Exit
   with
  | exception Exit -> ()
  | _ -> failwith "Expected the scene to raise");
  closed (Option.get !final)

let () =
  match Array.to_list Sys.argv with
  | [ _ ] ->
      with_init [] (fun sdl ->
          let@ surface =
            using Surface.destroy (Surface.create sdl ~w:16 ~h:16)
          in
          using Renderer.destroy
            (Renderer.create_software surface)
            (check_scene sdl))
  | [ _; "--driver"; driver ] ->
      with_init [ Video ] (fun sdl ->
          let@ window =
            using Window.destroy
              (Window.create sdl ~title:"Resource churn test" ~w:16 ~h:16)
          in
          using Renderer.destroy
            (Renderer.create ~driver window)
            (check_scene sdl))
  | _ -> invalid_arg "Use resource_churn_test [--driver NAME]"
