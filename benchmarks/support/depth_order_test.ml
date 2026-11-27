open Sdl3
open Benchmark_support
open Run

let check condition message = if not condition then failwith message

let sort_keys () =
  let order = Depth_order.create ~levels:10 5 in
  Array.iteri (Depth_order.set order) [| 9; 8; 3; 8; 0 |];
  let ids = Depth_order.sort order in
  check (ids = [| 4; 2; 1; 3; 0 |]) "Sort by depth, then by ID";
  Array.iteri (Depth_order.set order) [| 1; 1; 2; 0; 0 |];
  let updated = Depth_order.sort order in
  check (updated == ids) "Sort in the same storage";
  check (updated = [| 3; 4; 0; 1; 2 |]) "Sort again after changes to depth"

let blend_in_order () =
  with_init [] (fun sdl ->
      let@ surface = using Surface.destroy (Surface.create sdl ~w:2 ~h:2) in
      let@ renderer =
        using Renderer.destroy (Renderer.create_software surface)
      in
      let@ texture =
        using Texture.destroy (Texture.create_streaming renderer ~w:2 ~h:1)
      in
      let rgba = [| 255; 0; 0; 128; 0; 0; 255; 128 |] in
      let buffer =
        Bigarray.Array1.init Bigarray.int8_unsigned Bigarray.c_layout 8
          (Array.get rgba)
      in
      Texture.update texture buffer ~pitch:8;
      Texture.set_blend_mode texture Blend;
      let order = Depth_order.create ~levels:8 2 in
      let batch = Sprite_batch.create ~capacity:2 in
      let draw red_depth blue_depth =
        Depth_order.set order 0 red_depth;
        Depth_order.set order 1 blue_depth;
        Sprite_batch.clear batch;
        Array.iter
          (fun id ->
            let src = Rect.make ~x:id ~y:0 ~w:1 ~h:1 in
            Sprite_batch.add batch ~src ~x:0. ~y:0. ~w:2. ~h:2.)
          (Depth_order.sort order);
        Renderer.set_draw_color renderer (Color.rgb 0 0 0);
        Renderer.clear renderer;
        Sprite_batch.draw renderer texture batch;
        Renderer.present renderer;
        Surface.read_pixel surface ~x:0 ~y:0
      in
      let red_front = draw 7 3 in
      check
        (red_front.r > red_front.b && red_front.b > 0)
        "Blend red in front of blue";
      let blue_front = draw 3 3 in
      check
        (blue_front.b > blue_front.r && blue_front.r > 0)
        "Use ID order for equal depths")

let () =
  sort_keys ();
  blend_in_order ()
