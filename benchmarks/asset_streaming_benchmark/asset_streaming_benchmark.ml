open Sdl3
open Benchmark_support
open Run
module Stream = Asset_streaming_scene.Page_stream

let seed = 42

let create_batch count ~right ~bottom =
  let rng = Random.State.make [| seed |] in
  let batch = Sprite_batch.create ~capacity:count in
  let size = float Stream.tile_size in
  for i = 0 to count - 1 do
    (* An odd stride spreads a smaller sprite count across the atlas. *)
    let src = Atlas.region Stream.atlas (129 * i mod Stream.atlas_tiles) in
    let x = Random.State.float rng right in
    let y = Random.State.float rng bottom in
    Sprite_batch.add batch ~src ~x ~y ~w:size ~h:size
  done;
  batch

let[@inline always] shift positions i step limit =
  let next = Float.Array.unsafe_get positions i +. step in
  Float.Array.unsafe_set positions i
    (if next >= limit then next -. limit else next)

let move positions count ~right ~bottom =
  for i = 0 to count - 1 do
    shift positions (2 * i) 1. right;
    shift positions ((2 * i) + 1) 0.5 bottom
  done

let benchmark config sdl renderer ~sprites ~uploads =
  let width, height = Renderer.output_size renderer in
  if width <= Stream.tile_size || height <= Stream.tile_size then
    invalid_arg "Use an output that is larger than one sprite";
  let@ texture = Atlas.with_texture renderer Stream.atlas in
  let stream = Stream.create () in
  Renderer.set_vsync renderer false;
  Renderer.set_draw_color renderer (Color.rgb 18 24 32);
  let right = float (width - Stream.tile_size)
  and bottom = float (height - Stream.tile_size) in
  let batch = create_batch sprites ~right ~bottom in
  let positions = Sprite_batch.positions batch in
  let record () =
    Stream.upload stream texture ~count:uploads;
    move positions sprites ~right ~bottom;
    Renderer.clear renderer;
    Sprite_batch.draw renderer texture batch;
    1
  in
  Printf.printf
    "asset_streaming_benchmark\nSprites: %d\nAtlas: %d x %d pixels\n" sprites
    Stream.atlas.width Stream.atlas.height;
  Printf.printf
    "Pages: %d (%d x %d pixels each)\n\
     Page uploads per frame: %d\n\
     Upload payload per frame: %d bytes\n"
    Stream.page_count Stream.page_size Stream.page_size uploads
    (uploads * Stream.page_bytes);
  print_setup config renderer ~width ~height;
  Printf.printf "Position seed: %d\n" seed;
  measure_renderer config sdl renderer ~record

let () =
  let name = "asset_streaming_benchmark" in
  let sprites = ref Stream.atlas_tiles and uploads = ref 4 in
  let config =
    parse ~name ~min_axis:(Stream.tile_size + 1)
      [
        ( "--sprites",
          count "a sprite count" 1 Stream.atlas_tiles sprites,
          "Number of sprites (default 16384)" );
        ( "--uploads-per-frame",
          count "a page upload count" 0 Stream.page_count uploads,
          "Page uploads per frame (default 4)" );
      ]
  in
  with_renderer config ~name ~title:"Asset streaming benchmark"
    (fun sdl renderer ->
      benchmark config sdl renderer ~sprites:!sprites ~uploads:!uploads)
