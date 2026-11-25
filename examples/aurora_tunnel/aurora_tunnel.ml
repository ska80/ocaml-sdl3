open Sdl3

let using release resource f =
  Fun.protect ~finally:(fun () -> release resource) (fun () -> f resource)

(* Keep a resource alive for the rest of a [let@] block. *)
let ( let@ ) scope body = scope body

let byte_buffer size =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size

let copy_bytes bytes buffer =
  for i = 0 to Bytes.length bytes - 1 do
    buffer.{i} <- Bytes.get_uint8 bytes i
  done

let set_float32 bytes offset value =
  Bytes.set_int32_ne bytes offset (Int32.bits_of_float value)

module Tunnel = struct
  let sides = 72
  let rings = 96
  let index_count = sides * 6
  let stride = 8

  (* Two rows of (turn, edge) pairs. The last column repeats the first
     position so each triangle has continuous texture coordinates. *)
  let mesh () =
    let row = sides + 1 in
    let vertices = Bytes.create (2 * row * stride) in
    let indices = Bytes.create (index_count * 2) in
    for edge = 0 to 1 do
      for side = 0 to sides do
        let offset = ((edge * row) + side) * stride in
        set_float32 vertices offset (float_of_int side /. float_of_int sides);
        set_float32 vertices (offset + 4) (float_of_int edge)
      done
    done;
    for side = 0 to sides - 1 do
      let far = side and near = side + row in
      let offset = side * 12 in
      Bytes.set_uint16_ne indices offset far;
      Bytes.set_uint16_ne indices (offset + 2) near;
      Bytes.set_uint16_ne indices (offset + 4) (far + 1);
      Bytes.set_uint16_ne indices (offset + 6) (far + 1);
      Bytes.set_uint16_ne indices (offset + 8) near;
      Bytes.set_uint16_ne indices (offset + 10) (near + 1)
    done;
    (vertices, indices)

  let vertex_layout : Gpu.vertex_layout =
    {
      stride;
      attributes = [ { location = 0; format = Float32x2; offset = 0 } ];
    }
end

module Gradient = struct
  let width = 256

  let pixels () =
    let stops =
      [|
        (104, 93, 255);
        (31, 180, 255);
        (36, 255, 193);
        (255, 202, 104);
        (255, 63, 154);
        (163, 83, 255);
        (104, 93, 255);
      |]
    in
    let pixels = Bytes.make (4 * width) '\255' in
    let segments = Array.length stops - 1 in
    for i = 0 to width - 1 do
      let position = float_of_int (i * segments) /. float_of_int (width - 1) in
      let segment = min (segments - 1) (int_of_float position) in
      let u = position -. float_of_int segment in
      let r0, g0, b0 = stops.(segment) in
      let r1, g1, b1 = stops.(segment + 1) in
      let lerp a b =
        int_of_float (float_of_int a +. (u *. float_of_int (b - a)) +. 0.5)
      in
      Bytes.set_uint8 pixels (4 * i) (lerp r0 r1);
      Bytes.set_uint8 pixels ((4 * i) + 1) (lerp g0 g1);
      Bytes.set_uint8 pixels ((4 * i) + 2) (lerp b0 b1)
    done;
    pixels
end

let shader_code name =
  let directory = Filename.dirname Sys.executable_name in
  let path = Filename.concat directory (Filename.concat "shaders" name) in
  In_channel.with_open_bin path In_channel.input_all

let create_pipeline device swapchain =
  let open Gpu in
  let@ vertex =
    using release_shader
      (create_shader device ~stage:Vertex ~format:Spirv ~uniform_buffers:1
         (shader_code "tunnel.vert.spv"))
  in
  let@ fragment =
    using release_shader
      (create_shader device ~stage:Fragment ~format:Spirv ~samplers:1
         ~uniform_buffers:1
         (shader_code "tunnel.frag.spv"))
  in
  create_swapchain_pipeline swapchain ~vertex ~fragment
    ~vertex_layout:Tunnel.vertex_layout ~primitive:Triangle_list

let upload device ~vertex ~index ~gradient vertices indices pixels =
  let open Gpu in
  let vertex_size = Bytes.length vertices
  and index_size = Bytes.length indices in
  let data = Bytes.concat Bytes.empty [ vertices; indices; pixels ] in
  let bytes = byte_buffer (Bytes.length data) in
  copy_bytes data bytes;
  let@ src =
    using release_upload_buffer
      (create_upload_buffer device ~size:(Bytes.length data))
  in
  write_upload_buffer src bytes;
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  using end_copy_pass (begin_copy_pass commands) (fun pass ->
      upload_to_buffer pass ~src ~dst:vertex ~size:vertex_size;
      upload_to_buffer ~src_offset:vertex_size pass ~src ~dst:index
        ~size:index_size;
      upload_to_texture ~src_offset:(vertex_size + index_size) pass ~src
        ~dst:gradient);
  using release_fence (submit_and_acquire_fence commands) wait_fence

type scene = {
  pipeline : Gpu.graphics_pipeline;
  vertex : Gpu.vertex Gpu.buffer;
  index : Gpu.index Gpu.buffer;
  material : (Gpu.texture * Gpu.sampler) array;
}

let with_scene device swapchain f =
  let open Gpu in
  let vertices, indices = Tunnel.mesh () in
  let@ pipeline =
    using release_graphics_pipeline (create_pipeline device swapchain)
  in
  let@ vertex =
    using release_buffer
      (create_vertex_buffer device ~size:(Bytes.length vertices))
  in
  let@ index =
    using release_buffer
      (create_index_buffer device ~format:Uint16 ~size:(Bytes.length indices))
  in
  let@ gradient =
    using release_texture (create_sampled_texture device ~w:Gradient.width ~h:1)
  in
  upload device ~vertex ~index ~gradient vertices indices (Gradient.pixels ());
  let@ sampler = using release_sampler (create_sampler device ~filter:Linear) in
  f { pipeline; vertex; index; material = [| (gradient, sampler) |] }

(* Match the fog color in tunnel.frag. *)
let clear = Color.rgb 4 7 18

let draw_frame device swapchain scene uniforms =
  let open Gpu in
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  match begin_swapchain_render_pass commands swapchain ~clear with
  | None -> false
  | Some pass ->
      (* Once SDL hands us a window image, submit even if recording fails.
         The outer cancel does nothing on a submitted command buffer. *)
      Fun.protect
        ~finally:(fun () ->
          end_render_pass pass;
          submit_command_buffer commands)
        (fun () ->
          push_uniform_data commands ~stage:Vertex ~slot:0 uniforms;
          push_uniform_data commands ~stage:Fragment ~slot:0 uniforms;
          bind_graphics_pipeline pass scene.pipeline;
          bind_vertex_buffer pass scene.vertex;
          bind_index_buffer pass scene.index;
          bind_samplers pass ~stage:Fragment scene.material;
          draw_indexed_primitives pass ~instances:Tunnel.rings
            ~indices:Tunnel.index_count;
          true)

type controls = {
  mutable mouse_x : float;
  mutable mouse_y : float;
  mutable paused : bool;
  mutable pulse : bool;
}

let aim window controls x y =
  let width, height = Window.size window in
  let ndc p span = max (-1.) (min 1. ((2. *. p /. float_of_int span) -. 1.)) in
  if width > 0 && height > 0 then (
    controls.mouse_x <- ndc x width;
    controls.mouse_y <- -.ndc y height)

let rec poll sdl window space controls =
  match Event.poll sdl with
  | None -> true
  | Some { kind = Quit | Window { change = Close_requested; _ }; _ } -> false
  | Some { kind = Key { scancode; down = true; _ }; _ }
    when scancode = Scancode.escape ->
      false
  | Some { kind; _ } ->
      (match kind with
      | Mouse_motion { x; y; _ } -> aim window controls x y
      | Mouse_button { button = Left; down = true; x; y; _ } ->
          aim window controls x y;
          controls.pulse <- true
      | Key { scancode; down = true; repeat = false; _ } ->
          if scancode = space then controls.paused <- not controls.paused
      | Window { change = Focus_lost; _ } ->
          controls.mouse_x <- 0.;
          controls.mouse_y <- 0.
      | _ -> ());
      poll sdl window space controls

let seconds () = Int64.to_float (Timer.ticks_ns ()) *. 1e-9

let play sdl window device swapchain scene ~frame_limit =
  let space = Option.get (Scancode.of_name "Space") in
  let controls =
    { mouse_x = 0.; mouse_y = 0.; paused = false; pulse = false }
  in
  (* Both shaders read the same std140 block of two vec4s. *)
  let packed = Bytes.make 32 '\000' in
  let uniforms = byte_buffer (Bytes.length packed) in
  set_float32 packed 20 (float_of_int Tunnel.rings);
  let rec loop frame previous time pulse_start x y =
    if frame < frame_limit && poll sdl window space controls then (
      let now = seconds () in
      let dt = min 0.1 (now -. previous) in
      let time = if controls.paused then time else time +. dt in
      let pulse_start =
        if controls.pulse || time -. pulse_start >= 4.0 then time
        else pulse_start
      in
      controls.pulse <- false;
      let ease = 1. -. exp (-7. *. dt) in
      let x = x +. (ease *. (controls.mouse_x -. x)) in
      let y = y +. (ease *. (controls.mouse_y -. y)) in
      let width, height = Window.size_in_pixels window in
      let drawn =
        if width <= 0 || height <= 0 then false
        else
          let aspect = float_of_int width /. float_of_int height in
          set_float32 packed 0 time;
          set_float32 packed 4 aspect;
          set_float32 packed 8 x;
          set_float32 packed 12 y;
          set_float32 packed 16 (1. +. (20. *. (time -. pulse_start)));
          copy_bytes packed uniforms;
          draw_frame device swapchain scene uniforms
      in
      if not drawn then Timer.delay_ns 16_000_000L;
      loop (if drawn then frame + 1 else frame) now time pulse_start x y)
  in
  (* Start with a pulse already in view. *)
  loop 0 (seconds ()) 0. (-0.45) 0. 0.

let run ~frame_limit =
  let@ sdl = with_init [ Video ] in
  let@ device = using Gpu.destroy_device (Gpu.create_device sdl [ Spirv ]) in
  let title =
    "Aurora Tunnel  |  Mouse: steer  |  Click: pulse  |  Space: pause"
  in
  let@ window =
    using Window.destroy
      (Window.create
         ~flags:[ Resizable; High_pixel_density ]
         sdl ~title ~w:960 ~h:600)
  in
  let@ swapchain = using Gpu.release_window (Gpu.claim_window device window) in
  let@ scene = with_scene device swapchain in
  play sdl window device swapchain scene ~frame_limit;
  Gpu.wait_idle device

let () =
  let frame_limit = ref max_int in
  let set_frames n =
    if n < 1 then raise (Arg.Bad "Use a positive frame count");
    frame_limit := n
  in
  Arg.parse
    [ ("--frames", Arg.Int set_frames, "Stop after this many drawn frames") ]
    (fun arg -> raise (Arg.Bad ("Unexpected argument: " ^ arg)))
    "aurora_tunnel [--frames COUNT]";
  try run ~frame_limit:!frame_limit
  with
  | Error message | Fun.Finally_raised (Error message) | Sys_error message ->
    Printf.eprintf "Aurora Tunnel: %s\n%!" message;
    exit 1
