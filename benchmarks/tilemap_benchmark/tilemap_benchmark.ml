open Sdl3
open Benchmark_support
open Run

let atlas_tiles = 256
let scroll_x = 7
let scroll_y = 5

type tilemap = {
  columns : int;
  rows : int;
  tile_size : int;
  cells : byte_buffer;
}

let make_map ~columns ~rows ~tile_size =
  let cells =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (columns * rows)
  in
  for y = 0 to rows - 1 do
    let row = y * columns in
    for x = 0 to columns - 1 do
      let tile = ((x * 0x52f) + (y * 0x1f3)) lxor (x / 8 * (y / 8)) land 255 in
      Bigarray.Array1.unsafe_set cells (row + x) tile
    done
  done;
  { columns; rows; tile_size; cells }

let batch_capacity map ~width ~height =
  let tile_size = map.tile_size in
  let columns = Tile_grid.capacity ~tiles:map.columns ~tile_size ~span:width
  and rows = Tile_grid.capacity ~tiles:map.rows ~tile_size ~span:height in
  columns * rows

let fill_visible batch regions map ~width ~height ~offset_x ~offset_y =
  let tile_size = map.tile_size in
  let first_x, stop_x =
    Tile_grid.visible ~tiles:map.columns ~tile_size ~offset:offset_x ~span:width
  and first_y, stop_y =
    Tile_grid.visible ~tiles:map.rows ~tile_size ~offset:offset_y ~span:height
  in
  let size = float tile_size in
  Sprite_batch.clear batch;
  for row = first_y to stop_y - 1 do
    let row_start = row * map.columns in
    let y = float ((row * tile_size) - offset_y) in
    for column = first_x to stop_x - 1 do
      (* The visible interval fits the map, and every tile ID is one byte. *)
      let id = Bigarray.Array1.unsafe_get map.cells (row_start + column) in
      let src = regions.(id) in
      let x = float ((column * tile_size) - offset_x) in
      Sprite_batch.add batch ~src ~x ~y ~w:size ~h:size
    done
  done

let benchmark config sdl renderer ~map_width ~map_height ~tile_size =
  let width, height = Renderer.output_size renderer in
  if width <= 0 || height <= 0 then invalid_arg "Use a nonempty renderer output";
  let map = make_map ~columns:map_width ~rows:map_height ~tile_size in
  let atlas = Atlas.layout ~tiles:atlas_tiles ~tile_size in
  let regions = Array.init atlas_tiles (Atlas.region atlas) in
  let@ texture = Atlas.with_texture renderer atlas in
  Renderer.set_vsync renderer false;
  Renderer.set_draw_color renderer (Color.rgb 18 24 32);
  let world_width = map.columns * tile_size
  and world_height = map.rows * tile_size in
  let x = Tile_grid.axis ~extent:world_width ~view:width ~delta:scroll_x
  and y = Tile_grid.axis ~extent:world_height ~view:height ~delta:scroll_y in
  let capacity = batch_capacity map ~width ~height in
  let batch = Sprite_batch.create ~capacity in
  let record () =
    Tile_grid.advance x;
    Tile_grid.advance y;
    fill_visible batch regions map ~width ~height ~offset_x:x.position
      ~offset_y:y.position;
    Renderer.clear renderer;
    Sprite_batch.draw renderer texture batch;
    1
  in
  Printf.printf
    "tilemap_benchmark\n\
     Map: %d x %d tiles (%d x %d pixels)\n\
     Tile size: %d x %d pixels\n"
    map.columns map.rows world_width world_height tile_size tile_size;
  Printf.printf
    "Atlas: %d x %d pixels, %d regions\nBatch capacity: %d visible tiles\n"
    atlas.width atlas.height atlas_tiles capacity;
  Printf.printf
    "Camera start: %d, %d pixels\nCamera step: %d, %d pixels/frame\n" x.position
    y.position x.step y.step;
  print_setup config renderer ~width ~height;
  measure_renderer config sdl renderer ~record

let () =
  let name = "tilemap_benchmark" in
  let map_width = ref 4096 and map_height = ref 4096 and tile_size = ref 16 in
  let config =
    parse ~name ~min_axis:1
      [
        ( "--map-width",
          count "a map width in tiles" 1 16_384 map_width,
          "Map width in tiles (default 4096)" );
        ( "--map-height",
          count "a map height in tiles" 1 16_384 map_height,
          "Map height in tiles (default 4096)" );
        ( "--tile-size",
          count "a tile size in pixels" 4 64 tile_size,
          "Tile width and height in pixels (default 16)" );
      ]
  in
  with_renderer config ~name ~title:"Tilemap benchmark" (fun sdl renderer ->
      benchmark config sdl renderer ~map_width:!map_width
        ~map_height:!map_height ~tile_size:!tile_size)
