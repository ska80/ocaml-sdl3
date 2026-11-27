open Sdl3
open Benchmark_support
open Run

let sprite_size = 8
let clear = Color.rgb 18 24 32
let quad_bytes = 4 * 2 * 4
let index_count = 6
let index_bytes = index_count * 2
let instance_stride = 16
let bytes n = Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout n
let floats n = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout n

let mesh () =
  let edge = float sprite_size in
  let corners =
    Bigarray.Array1.of_array Bigarray.float32 Bigarray.c_layout
      [| 0.; 0.; edge; 0.; edge; edge; 0.; edge |]
  in
  let indices =
    Bigarray.Array1.of_array Bigarray.int16_unsigned Bigarray.c_layout
      [| 0; 1; 2; 0; 2; 3 |]
  in
  (corners, indices)

let instance_data (atlas : Atlas.t) count position =
  let data = floats (count * 4) in
  for i = 0 to count - 1 do
    let x, y = position i in
    let j = 4 * i in
    data.{j} <- x;
    data.{j + 1} <- y;
    data.{j + 2} <- float (i mod atlas.columns * sprite_size);
    data.{j + 3} <- float (i / atlas.columns * sprite_size)
  done;
  data

let shader_code file =
  let directory = Filename.dirname Sys.executable_name in
  let path = Filename.concat (Filename.concat directory "shaders") file in
  In_channel.with_open_bin path In_channel.input_all

let vertex_layouts : Gpu.vertex_buffer_layout list =
  Gpu.
    [
      {
        input_rate = Per_vertex;
        layout =
          {
            stride = 8;
            attributes = [ { location = 0; format = Float32x2; offset = 0 } ];
          };
      };
      {
        input_rate = Per_instance;
        layout =
          {
            stride = instance_stride;
            attributes =
              [
                { location = 1; format = Float32x2; offset = 0 };
                { location = 2; format = Float32x2; offset = 8 };
              ];
          };
      };
    ]

let with_shaders device f =
  let open Gpu in
  let@ vertex =
    using release_shader
      (create_shader device ~stage:Vertex ~format:Spirv ~uniform_buffers:1
         (shader_code "sprites.vert.spv"))
  in
  let@ fragment =
    using release_shader
      (create_shader device ~stage:Fragment ~format:Spirv ~samplers:1
         (shader_code "sprites.frag.spv"))
  in
  f ~vertex ~fragment

let swapchain_pipeline device claim =
  with_shaders device (fun ~vertex ~fragment ->
      Gpu.create_swapchain_pipeline ~vertex_layouts claim ~vertex ~fragment
        ~primitive:Triangle_list)

let offscreen_pipeline device ~format =
  with_shaders device (fun ~vertex ~fragment ->
      Gpu.create_graphics_pipeline ~vertex_layouts device ~format ~vertex
        ~fragment ~primitive:Triangle_list)

let with_upload device ~size data f =
  let open Gpu in
  let@ upload =
    using release_upload_buffer (create_upload_buffer device ~size)
  in
  write_upload_buffer upload data;
  f upload

let upload device atlas ~image ~quad ~indices ~instances count position =
  let open Gpu in
  let vertex_data, index_data = mesh () in
  let instance_data = instance_data atlas count position in
  let pixels = Atlas.pixels atlas in
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  using end_copy_pass (begin_copy_pass commands) (fun pass ->
      let transfer data size dst =
        with_upload device ~size data (fun src ->
            upload_to_buffer pass ~src ~dst ~size)
      in
      transfer vertex_data quad_bytes quad;
      transfer index_data index_bytes indices;
      transfer instance_data (instance_stride * count) instances;
      with_upload device ~size:(Bigarray.Array1.dim pixels) pixels (fun src ->
          upload_to_texture pass ~src ~dst:image));
  using release_fence (submit_and_acquire_fence commands) wait_fence

type t = {
  atlas : Atlas.t;
  count : int;
  bindings : (Gpu.vertex Gpu.buffer * int) array;
  indices : Gpu.index Gpu.buffer;
  material : (Gpu.texture * Gpu.sampler) array;
  uniform : byte_buffer;
  uniform_bytes : Bytes.t;
}

let with_scene device ~count ~position f =
  let open Gpu in
  let atlas = Atlas.layout ~tiles:count ~tile_size:sprite_size in
  let@ image =
    using release_texture
      (create_sampled_texture device ~w:atlas.width ~h:atlas.height)
  in
  let@ quad =
    using release_buffer (create_vertex_buffer device ~size:quad_bytes)
  in
  let@ indices =
    using release_buffer
      (create_index_buffer device ~format:Uint16 ~size:index_bytes)
  in
  let@ instances =
    using release_buffer
      (create_vertex_buffer device ~size:(count * instance_stride))
  in
  let@ sampler =
    using release_sampler (create_sampler device ~filter:Nearest)
  in
  upload device atlas ~image ~quad ~indices ~instances count position;
  f
    {
      atlas;
      count;
      bindings = [| (quad, 0); (instances, 0) |];
      indices;
      material = [| (image, sampler) |];
      uniform = bytes 32;
      uniform_bytes = Bytes.create 32;
    }

let set_float scene offset value =
  Bytes.set_int32_ne scene.uniform_bytes offset (Int32.bits_of_float value)

let draw scene commands pass pipeline ~frame =
  let open Gpu in
  let width, height = render_pass_size pass in
  let right = width - sprite_size and bottom = height - sprite_size in
  if right <= 0 || bottom <= 0 then
    invalid_arg "Use a window image larger than one sprite";
  set_float scene 0 (2. /. float width);
  set_float scene 4 (-2. /. float height);
  set_float scene 8 (1. /. float scene.atlas.width);
  set_float scene 12 (1. /. float scene.atlas.height);
  set_float scene 16 (float (frame mod right));
  set_float scene 20 (0.5 *. float (frame mod (2 * bottom)));
  set_float scene 24 (float right);
  set_float scene 28 (float bottom);
  for i = 0 to Bytes.length scene.uniform_bytes - 1 do
    scene.uniform.{i} <- Bytes.get_uint8 scene.uniform_bytes i
  done;
  push_uniform_data commands ~stage:Vertex ~slot:0 scene.uniform;
  bind_graphics_pipeline pass pipeline;
  bind_vertex_buffers pass scene.bindings;
  bind_index_buffer pass scene.indices;
  bind_samplers pass ~stage:Fragment scene.material;
  draw_indexed_primitives ~instances:scene.count pass ~indices:index_count
