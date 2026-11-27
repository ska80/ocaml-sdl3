open Sdl3

type t = { columns : int; width : int; height : int; tile_size : int }

let layout ~tiles ~tile_size =
  let columns = int_of_float (ceil (sqrt (float tiles))) in
  let rows = (tiles + columns - 1) / columns in
  { columns; width = columns * tile_size; height = rows * tile_size; tile_size }

let region atlas index =
  let size = atlas.tile_size in
  Rect.make
    ~x:(index mod atlas.columns * size)
    ~y:(index / atlas.columns * size)
    ~w:size ~h:size

let fill ?alpha atlas texture =
  let pitch = 4 * atlas.width in
  let pixels =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (pitch * atlas.height)
  in
  for y = 0 to atlas.height - 1 do
    for x = 0 to atlas.width - 1 do
      let tile =
        (y / atlas.tile_size * atlas.columns) + (x / atlas.tile_size)
      in
      (* Multiplication by an odd number gives distinct 24-bit colors here. *)
      let rgb = ((tile * 0x34567) + 0x346cdf) land 0xff_ffff in
      let u = x mod atlas.tile_size and v = y mod atlas.tile_size in
      let rgb = if u = v then rgb lxor 0xff_ffff else rgb in
      let i = (y * pitch) + (4 * x) in
      pixels.{i} <- rgb lsr 16;
      pixels.{i + 1} <- (rgb lsr 8) land 255;
      pixels.{i + 2} <- rgb land 255;
      pixels.{i + 3} <-
        (match alpha with
        | None -> 255
        | Some f -> f u v)
    done
  done;
  Texture.update texture pixels ~pitch

let with_texture ?alpha ?(blend = Blend_mode.None) renderer atlas f =
  (match Renderer.max_texture_size renderer with
  | Some limit when max atlas.width atlas.height > limit ->
      invalid_arg
        (Printf.sprintf
           "Use a smaller atlas. The renderer limits textures to %d pixels per \
            axis"
           limit)
  | _ -> ());
  Run.using Texture.destroy
    (Texture.create_streaming renderer ~w:atlas.width ~h:atlas.height)
    (fun texture ->
      fill ?alpha atlas texture;
      Texture.set_scale_mode texture Nearest;
      Texture.set_blend_mode texture blend;
      f texture)
