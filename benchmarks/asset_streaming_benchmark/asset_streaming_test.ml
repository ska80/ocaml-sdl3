open Sdl3
open Benchmark_support
open Run
module Stream = Asset_streaming_scene.Page_stream

let check condition message = if not condition then failwith message

let check_uploads renderer =
  let@ texture = Atlas.with_texture renderer Stream.atlas in
  let stream = Stream.create () in
  let expected variant =
    let page = stream.payloads.(variant) in
    let i = Stream.pitch + 4 in
    Color.rgba page.{i} page.{i + 1} page.{i + 2} page.{i + 3}
  in
  let read () =
    let sample x dst =
      let src = Frect.make ~x ~y:1. ~w:1. ~h:1. in
      let dst = Frect.make ~x:dst ~y:0. ~w:1. ~h:1. in
      Texture.draw ~src ~dst renderer texture
    in
    sample 1. 0.;
    sample (float (Stream.page_size + 1)) 1.;
    let rect = Rect.make ~x:0 ~y:0 ~w:2 ~h:1 in
    let@ pixels = using Surface.destroy (Renderer.read_pixels ~rect renderer) in
    (Surface.read_pixel pixels ~x:0 ~y:0, Surface.read_pixel pixels ~x:1 ~y:0)
  in
  let first, second = read () in
  Stream.upload stream texture ~count:0;
  check
    (read () = (first, second))
    "The no-upload workload leaves the atlas unchanged";
  Stream.upload stream texture ~count:1;
  let updated, untouched = read () in
  check
    (updated = expected 0 && updated <> first)
    "The uploaded page contains the first payload";
  check (untouched = second) "The next atlas page is unchanged";
  Stream.upload stream texture ~count:Stream.page_count;
  let next_sweep, updated_second = read () in
  check
    (next_sweep = expected 1 && next_sweep <> updated)
    "The next sweep replaces the first page again";
  check
    (updated_second = expected 1 && updated_second <> second)
    "The sweep reaches the other pages"

let () =
  match Array.to_list Sys.argv with
  | [ _ ] ->
      with_init [] (fun sdl ->
          let@ surface = using Surface.destroy (Surface.create sdl ~w:2 ~h:1) in
          using Renderer.destroy
            (Renderer.create_software surface)
            check_uploads)
  | [ _; "--driver"; driver ] ->
      with_init [ Video ] (fun sdl ->
          let@ window =
            using Window.destroy
              (Window.create sdl ~title:"Asset streaming test" ~w:16 ~h:16)
          in
          using Renderer.destroy (Renderer.create ~driver window) check_uploads)
  | _ -> invalid_arg "Use asset_streaming_test [--driver NAME]"
