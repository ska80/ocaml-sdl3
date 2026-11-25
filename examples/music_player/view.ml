open Sdl3
open Music_player_support
open Scope

let asset name = Filename.concat (Filename.dirname Sys.executable_name) name
let shader name = In_channel.with_open_bin (asset name) In_channel.input_all
let black = Color.rgb 0 0 0
let white = Color.rgb 255 255 255

let create_pipeline device swapchain =
  let open Gpu in
  let@ vertex =
    using release_shader
      (create_shader device ~stage:Vertex ~format:Spirv ~uniform_buffers:1
         (shader "shaders/player.vert.spv"))
  in
  let@ fragment =
    using release_shader
      (create_shader device ~stage:Fragment ~format:Spirv ~samplers:1
         (shader "shaders/player.frag.spv"))
  in
  create_swapchain_pipeline swapchain ~vertex ~fragment ~primitive:Triangle_list

type label = {
  caption : string;
  width : int;
  height : int;
  texture : Gpu.texture;
  material : (Gpu.texture * Gpu.sampler) array;
}

type t = {
  device : Gpu.device;
  swapchain : Gpu.swapchain;
  pipeline : Gpu.graphics_pipeline;
  font : Sdl3_ttf.Font.t;
  sampler : Gpu.sampler;
  packed : bytes;
  uniforms : byte_buffer;
  heights : Float.Array.t;
  mutable label : label option;
}

let with_view font_context device swapchain f =
  let@ font =
    let open Sdl3_ttf.Font in
    using close (open_ font_context (asset "assets/DejaVuSans.ttf") ~ptsize:44.)
  in
  let@ pipeline =
    using Gpu.release_graphics_pipeline (create_pipeline device swapchain)
  in
  let@ sampler =
    using Gpu.release_sampler (Gpu.create_sampler device ~filter:Linear)
  in
  (* std140: one vec4 for the label and eight vec4s for the band heights. *)
  let size = 4 * (4 + Spectrum.band_count) in
  let view =
    {
      device;
      swapchain;
      pipeline;
      font;
      sampler;
      packed = Bytes.create size;
      uniforms = byte_buffer size;
      heights = Float.Array.make Spectrum.band_count 0.;
      label = None;
    }
  in
  Fun.protect
    ~finally:(fun () ->
      Option.iter (fun label -> Gpu.release_texture label.texture) view.label)
    (fun () -> f view)

let upload device texture pixels =
  let open Gpu in
  let@ transfer =
    using release_upload_buffer
      (create_upload_buffer device ~size:(Bigarray.Array1.dim pixels))
  in
  write_upload_buffer transfer pixels;
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  using end_copy_pass (begin_copy_pass commands) (fun pass ->
      upload_to_texture pass ~src:transfer ~dst:texture);
  submit_command_buffer commands

let make_label view caption =
  let@ surface =
    using Surface.destroy (Sdl3_ttf.Font.render view.font caption white)
  in
  let width, height = Surface.size surface in
  let pixels = byte_buffer (4 * width * height) in
  Surface.read_rgba surface pixels;
  let texture = Gpu.create_sampled_texture view.device ~w:width ~h:height in
  try
    upload view.device texture pixels;
    {
      caption;
      width;
      height;
      texture;
      material = [| (texture, view.sampler) |];
    }
  with exn ->
    let backtrace = Printexc.get_raw_backtrace () in
    Gpu.release_texture texture;
    Printexc.raise_with_backtrace exn backtrace

let set_caption view caption =
  match view.label with
  | Some label when label.caption = caption -> ()
  | old ->
      let label = Some (make_label view caption) in
      Option.iter (fun label -> Gpu.release_texture label.texture) old;
      view.label <- label

let set_float32 bytes offset value =
  Bytes.set_int32_ne bytes offset (Int32.bits_of_float value)

let pack view window label spectrum ~width ~height ~show_bars ~dt =
  let w = float width and h = float height in
  let lw = float label.width and lh = float label.height in
  let scale =
    min (Window.display_scale window) (min (0.84 *. w /. lw) (0.18 *. h /. lh))
  in
  let label_w = lw *. scale /. w and label_h = lh *. scale /. h in
  let center_y = if show_bars then 0.17 else 0.5 in
  let set = set_float32 view.packed in
  set 0 ((1. -. label_w) *. 0.5);
  set 4 (center_y -. (label_h *. 0.5));
  set 8 label_w;
  set 12 label_h;
  let rise = 1. -. exp (-35. *. dt) and fall = 1. -. exp (-12. *. dt) in
  for i = 0 to Spectrum.band_count - 1 do
    let old = Float.Array.get view.heights i in
    let target = if show_bars then Spectrum.level spectrum i else 0. in
    let ease = if target > old then rise else fall in
    let value = old +. (ease *. (target -. old)) in
    Float.Array.set view.heights i value;
    set (16 + (4 * i)) value
  done;
  let packed = view.packed and uniforms = view.uniforms in
  for i = 0 to Bytes.length packed - 1 do
    uniforms.{i} <- Bytes.get_uint8 packed i
  done

let draw view window spectrum ~show_bars ~dt =
  let width, height = Window.size_in_pixels window in
  match view.label with
  | Some label when width > 0 && height > 0 -> (
      let open Gpu in
      pack view window label spectrum ~width ~height ~show_bars ~dt;
      let@ commands =
        using cancel_command_buffer (acquire_command_buffer view.device)
      in
      match
        begin_swapchain_render_pass commands view.swapchain ~clear:black
      with
      | None -> false
      | Some pass ->
          (* Once SDL hands us a window image, submit even if recording fails. *)
          Fun.protect
            ~finally:(fun () ->
              end_render_pass pass;
              submit_command_buffer commands)
            (fun () ->
              push_uniform_data commands ~stage:Vertex ~slot:0 view.uniforms;
              bind_graphics_pipeline pass view.pipeline;
              bind_samplers pass ~stage:Fragment label.material;
              let instances =
                if show_bars then 1 + Spectrum.band_count else 1
              in
              draw_primitives pass ~vertices:6 ~instances;
              true))
  | _ -> false
