open Sdl3
open Benchmark_support

let tile_size = 8
let atlas_tiles = 16_384
let page_size = 128
let pitch = 4 * page_size
let page_bytes = pitch * page_size
let atlas = Atlas.layout ~tiles:atlas_tiles ~tile_size

let pages =
  let columns = atlas.width / page_size in
  let rows = atlas.height / page_size in
  Array.init (columns * rows) (fun i ->
      Rect.make
        ~x:(i mod columns * page_size)
        ~y:(i / columns * page_size)
        ~w:page_size ~h:page_size)

let page_count = Array.length pages

type t = {
  payloads : byte_buffer array;
  mutable slot : int;
  mutable sweep : int;
}

let create () =
  let tiles_per_side = page_size / tile_size in
  let page_atlas =
    Atlas.layout ~tiles:(tiles_per_side * tiles_per_side) ~tile_size
  in
  let reference = Atlas.pixels page_atlas in
  let payloads =
    Array.init 8 (fun variant ->
        let shift = 19 * (variant + 1) in
        Bigarray.Array1.init Bigarray.int8_unsigned Bigarray.c_layout page_bytes
          (fun i ->
            if i mod 4 = 3 then 255 else (reference.{i} + shift) land 255))
  in
  { payloads; slot = 0; sweep = 0 }

let upload stream texture ~count =
  let variants = Array.length stream.payloads in
  for _ = 1 to count do
    let slot = stream.slot in
    let variant = (slot + stream.sweep) mod variants in
    Texture.update texture ~rect:pages.(slot) stream.payloads.(variant) ~pitch;
    if slot + 1 = page_count then (
      stream.slot <- 0;
      (* Use different pixels when this page comes around again. *)
      stream.sweep <- (stream.sweep + 1) mod variants)
    else stream.slot <- slot + 1
  done
