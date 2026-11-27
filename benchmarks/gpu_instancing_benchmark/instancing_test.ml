open Sdl3
open Benchmark_support
open Run
module Scene = Gpu_instancing_scene.Sprite_scene

let check condition message = if not condition then failwith message

let () =
  let open Gpu in
  with_init [ Video ] (fun sdl ->
      let@ device =
        using destroy_device (create_device ~debug:true sdl [ Spirv ])
      in
      let width = 32 and height = 24 in
      let@ target =
        using release_texture
          (create_texture device ~format:Rgba8_unorm ~usage:Color_target
             ~w:width ~h:height)
      in
      let position = function
        | 0 -> (1., 1.)
        | _ -> (23., 10.)
      in
      let@ scene = Scene.with_scene device ~count:2 ~position in
      let@ pipeline =
        using release_graphics_pipeline
          (Scene.offscreen_pipeline device ~format:Rgba8_unorm)
      in
      let download_size = width * height * 4 in
      let@ download =
        using release_download_buffer
          (create_download_buffer device ~size:download_size)
      in
      let actual = Scene.bytes download_size in
      let expected_atlas = Atlas.pixels scene.atlas in
      let render frame =
        let@ commands =
          using cancel_command_buffer (acquire_command_buffer device)
        in
        using end_render_pass
          (begin_render_pass commands ~target ~load:(Clear Scene.clear))
          (fun pass -> Scene.draw scene commands pass pipeline ~frame);
        using end_copy_pass (begin_copy_pass commands) (fun pass ->
            download_from_texture pass ~src:(texture_region target)
              ~dst:download);
        using release_fence (submit_and_acquire_fence commands) wait_fence;
        read_download_buffer download actual
      in
      let pixel x y =
        let i = ((y * width) + x) * 4 in
        Color.rgba actual.{i} actual.{i + 1} actual.{i + 2} actual.{i + 3}
      in
      let atlas_color id =
        let rect = Atlas.region scene.atlas id in
        let i = ((rect.y * scene.atlas.width) + rect.x + 1) * 4 in
        Color.rgba expected_atlas.{i}
          expected_atlas.{i + 1}
          expected_atlas.{i + 2}
          expected_atlas.{i + 3}
      in
      render 0;
      check
        (pixel 2 1 = atlas_color 0)
        "The first instance draws its own region";
      check
        (pixel 24 10 = atlas_color 1)
        "The second instance draws a different region";
      render 2;
      check (pixel 4 2 = atlas_color 0) "The shader moves a sprite in both axes";
      check
        (pixel 2 11 = atlas_color 1)
        "The shader wraps a sprite across the right edge";
      check (pixel 24 10 = Scene.clear) "The old position is clear")
