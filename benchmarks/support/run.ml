open Sdl3
module Metrics = Benchmark_metrics

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) use f = use f

type config = {
  frames : int;
  warmup : int;
  width : int;
  height : int;
  driver : string option;
  trace_gc : bool;
}

let count name low high target =
  Arg.Int
    (fun value ->
      if value < low || value > high then
        raise (Arg.Bad (Printf.sprintf "Use %s from %d to %d" name low high));
      target := value)

let parse ~name ~min_axis extra =
  let frames = ref 300 and warmup = ref 60 in
  let width = ref 1280 and height = ref 720 in
  let driver = ref None and trace_gc = ref true in
  let common =
    [
      ( "--frames",
        count "a frame count" 1 1_000_000 frames,
        "Frames to measure (default 300)" );
      ( "--warmup",
        count "a warm-up frame count" 0 1_000_000 warmup,
        "Frames before measurement (default 60)" );
      ( "--width",
        count "a window width" min_axis 8192 width,
        "Window width (default 1280)" );
      ( "--height",
        count "a window height" min_axis 8192 height,
        "Window height (default 720)" );
      ( "--driver",
        Arg.String (fun name -> driver := Some name),
        "SDL renderer name" );
      ("--no-gc-events", Arg.Clear trace_gc, "Do not trace OCaml GC pauses");
    ]
  in
  Arg.parse (extra @ common)
    (fun arg -> raise (Arg.Bad ("Unexpected argument: " ^ arg)))
    (name ^ " [options]");
  {
    frames = !frames;
    warmup = !warmup;
    width = !width;
    height = !height;
    driver = !driver;
    trace_gc = !trace_gc;
  }

let with_window config ~name ~title f =
  try
    with_init [ Video ] (fun sdl ->
        let@ window =
          using Window.destroy
            (Window.create sdl ~title ~w:config.width ~h:config.height)
        in
        let@ renderer =
          using Renderer.destroy (Renderer.create ?driver:config.driver window)
        in
        f sdl renderer)
  with Error message | Invalid_argument message ->
    Printf.eprintf "%s: %s\n%!" name message;
    exit 1

let rec poll_events sdl remaining =
  remaining = 0
  ||
  match Event.poll sdl with
  | None -> true
  | Some { kind = Quit | Window { change = Close_requested; _ }; _ } -> false
  | Some { kind = Key { scancode; down = true; _ }; _ }
    when scancode = Scancode.escape ->
      false
  | Some _ -> poll_events sdl (remaining - 1)

let print_setup config renderer ~width ~height =
  let { major; minor; patch } = version () in
  let video_hint =
    Option.value (Sys.getenv_opt "SDL_VIDEO_DRIVER") ~default:"SDL default"
  in
  Printf.printf
    "Output: %d x %d pixels\n\
     Renderer: %s\n\
     Video driver request: %s\n\
     VSync interval reported by SDL: %d\n"
    width height (Renderer.name renderer) video_hint (Renderer.vsync renderer);
  Option.iter
    (fun device -> Printf.printf "GPU driver: %s\n" (Gpu.driver device))
    (Renderer.gpu_device renderer);
  Printf.printf "SDL: %d.%d.%d\nOCaml: %s\nBuild profile: %s\nOS: %s\nCPU: %s\n"
    major minor patch Sys.ocaml_version Build_profile.name
    (Metrics.system_name ())
    (Option.value (Metrics.cpu_model ()) ~default:"unavailable");
  Printf.printf "Warm-up frames: %d\nRequested measured frames: %d\n"
    config.warmup config.frames

let measure config sdl renderer ~record =
  flush stdout;
  let poll () = poll_events sdl 256 in
  let present () = Renderer.present renderer in
  let rec warm frames =
    if frames = 0 then true
    else if not (poll ()) then false
    else (
      ignore (record ());
      present ();
      warm (frames - 1))
  in
  if warm config.warmup then (
    let result =
      Metrics.measure ~frames:config.frames ~trace_gc:config.trace_gc ~poll
        ~record ~present
    in
    Printf.printf "Measured frames: %d\n" result.frames;
    if result.frames > 0 then Metrics.print result)
  else print_endline "Stopped during warm-up. No frames were measured."
