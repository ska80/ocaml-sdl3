open Sdl3
open Benchmark_support
open Run
module Scene = Gpu_instancing_scene.Sprite_scene

let seed = 42

let prefer_present_mode claim =
  let open Gpu in
  if supports_present_mode claim Immediate then Immediate
  else if supports_present_mode claim Mailbox then Mailbox
  else Vsync

let present_name : Gpu.present_mode -> string = function
  | Immediate -> "immediate"
  | Mailbox -> "mailbox"
  | Vsync -> "vsync"

let benchmark config sdl window count =
  let open Gpu in
  let width, height = Window.size_in_pixels window in
  if width <= Scene.sprite_size || height <= Scene.sprite_size then
    invalid_arg "Use a window image larger than one sprite";
  let@ device =
    using destroy_device (create_device ?driver:config.driver sdl [ Spirv ])
  in
  let@ claim = using release_window (claim_window device window) in
  let mode = prefer_present_mode claim in
  set_swapchain_parameters claim ~composition:Sdr ~present_mode:mode;
  let rng = Random.State.make [| seed |] in
  let right = float (width - Scene.sprite_size)
  and bottom = float (height - Scene.sprite_size) in
  let position _ =
    let x = Random.State.float rng right in
    let y = Random.State.float rng bottom in
    (x, y)
  in
  let@ scene = Scene.with_scene device ~count ~position in
  let@ pipeline =
    using release_graphics_pipeline (Scene.swapchain_pipeline device claim)
  in
  let frame = ref 0 and pending = ref None in
  let present () =
    match !pending with
    | None -> ()
    | Some commands ->
        pending := None;
        submit_command_buffer commands
  in
  let cancel_unrecorded commands =
    if Option.is_none !pending then cancel_command_buffer commands
  in
  let record () =
    let@ commands = using cancel_unrecorded (acquire_command_buffer device) in
    let handoff = Some commands in
    match begin_swapchain_render_pass commands claim ~clear:Scene.clear with
    | None ->
        raise
          (Error
             "No window image is available. Keep the window visible during the \
              run.")
    | Some pass ->
        (* Once a window image is acquired, end the pass and submit even if a
           later draw fails. The outer cleanup handles a pending submission. *)
        pending := handoff;
        using end_render_pass pass (fun pass ->
            incr frame;
            Scene.draw scene commands pass pipeline ~frame:!frame);
        1
  in
  Printf.printf
    "gpu_instancing_benchmark\n\
     Sprites: %d\n\
     Atlas: %d x %d pixels, %d unique regions (%d x %d pixels each)\n"
    count scene.atlas.width scene.atlas.height count Scene.sprite_size
    Scene.sprite_size;
  Printf.printf
    "Output: %d x %d pixels\n\
     GPU driver: %s\n\
     Video driver request: %s\n\
     Present mode: %s\n"
    width height (driver device) (video_hint ()) (present_name mode);
  print_runtime config;
  Printf.printf "Position seed: %d\n" seed;
  Fun.protect ~finally:present (fun () -> measure config sdl ~record ~present)

let () =
  let name = "gpu_instancing_benchmark" and sprites = ref 100_000 in
  let config =
    parse ~name ~min_axis:(Scene.sprite_size + 1)
      ~driver_help:"SDL GPU driver name"
      [
        ( "--sprites",
          count "a sprite count" 1 1_000_000 sprites,
          "Number of sprites (default 100000)" );
      ]
  in
  with_window config ~name ~title:"GPU instancing benchmark" (fun sdl window ->
      benchmark config sdl window !sprites)
