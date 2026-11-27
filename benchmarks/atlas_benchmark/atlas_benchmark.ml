open Sdl3
module Metrics = Benchmark_metrics

let tile_size = 8
let step_x = 1.
let step_y = 0.5
let seed = 42

type config = {
  sprites : int;
  frames : int;
  warmup : int;
  width : int;
  height : int;
  driver : string option;
  trace_gc : bool;
}

let parse_args () =
  let sprites = ref 100_000 and frames = ref 300 and warmup = ref 60 in
  let width = ref 1280 and height = ref 720 in
  let driver = ref None and trace_gc = ref true in
  let count name low high target =
    Arg.Int
      (fun value ->
        if value < low || value > high then
          raise (Arg.Bad (Printf.sprintf "Use %s from %d to %d" name low high));
        target := value)
  in
  Arg.parse
    [
      ( "--sprites",
        count "a sprite count" 1 1_000_000 sprites,
        "Number of sprites (default 100000)" );
      ( "--frames",
        count "a frame count" 1 1_000_000 frames,
        "Frames to measure (default 300)" );
      ( "--warmup",
        count "a warm-up frame count" 0 1_000_000 warmup,
        "Frames before measurement (default 60)" );
      ( "--width",
        count "a window width" (tile_size + 1) 8192 width,
        "Window width (default 1280)" );
      ( "--height",
        count "a window height" (tile_size + 1) 8192 height,
        "Window height (default 720)" );
      ( "--driver",
        Arg.String (fun name -> driver := Some name),
        "SDL renderer name" );
      ("--no-gc-events", Arg.Clear trace_gc, "Do not trace OCaml GC pauses");
    ]
    (fun arg -> raise (Arg.Bad ("Unexpected argument: " ^ arg)))
    "atlas_benchmark [options]";
  {
    sprites = !sprites;
    frames = !frames;
    warmup = !warmup;
    width = !width;
    height = !height;
    driver = !driver;
    trace_gc = !trace_gc;
  }

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) use f = use f

type atlas = { columns : int; width : int; height : int }

let atlas_layout count =
  let columns = int_of_float (ceil (sqrt (float count))) in
  let rows = (count + columns - 1) / columns in
  { columns; width = columns * tile_size; height = rows * tile_size }

let fill_atlas layout texture =
  let pitch = 4 * layout.width in
  let pixels =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (pitch * layout.height)
  in
  for y = 0 to layout.height - 1 do
    for x = 0 to layout.width - 1 do
      let tile = (y / tile_size * layout.columns) + (x / tile_size) in
      (* Multiplication by an odd number gives distinct 24-bit colors here. *)
      let rgb = ((tile * 0x34567) + 0x346cdf) land 0xff_ffff in
      let rgb =
        if x mod tile_size = y mod tile_size then rgb lxor 0xff_ffff else rgb
      in
      let i = (y * pitch) + (4 * x) in
      pixels.{i} <- rgb lsr 16;
      pixels.{i + 1} <- (rgb lsr 8) land 255;
      pixels.{i + 2} <- rgb land 255;
      pixels.{i + 3} <- 255
    done
  done;
  Texture.update texture pixels ~pitch

let create_batch count layout ~right ~bottom =
  let rng = Random.State.make [| seed |] in
  let batch = Sprite_batch.create ~capacity:count in
  let size = float tile_size in
  for i = 0 to count - 1 do
    let src =
      Rect.make
        ~x:(i mod layout.columns * tile_size)
        ~y:(i / layout.columns * tile_size)
        ~w:tile_size ~h:tile_size
    in
    let x = Random.State.float rng right
    and y = Random.State.float rng bottom in
    Sprite_batch.add batch ~src ~x ~y ~w:size ~h:size
  done;
  batch

let[@inline always] shift positions i step limit =
  let next = Float.Array.unsafe_get positions i +. step in
  Float.Array.unsafe_set positions i
    (if next >= limit then next -. limit else next)

let move positions count ~right ~bottom =
  for i = 0 to count - 1 do
    shift positions (2 * i) step_x right;
    shift positions ((2 * i) + 1) step_y bottom
  done

let rec poll sdl remaining =
  remaining = 0
  ||
  match Event.poll sdl with
  | None -> true
  | Some { kind = Quit | Window { change = Close_requested; _ }; _ } -> false
  | Some { kind = Key { scancode; down = true; _ }; _ }
    when scancode = Scancode.escape ->
      false
  | Some _ -> poll sdl (remaining - 1)

let print_setup config renderer layout ~width ~height =
  let { major; minor; patch } = version () in
  let video_hint =
    Option.value (Sys.getenv_opt "SDL_VIDEO_DRIVER") ~default:"SDL default"
  in
  Printf.printf
    "atlas_benchmark\n\
     Sprites: %d\n\
     Atlas: %d x %d pixels, %d unique regions (%d x %d pixels each)\n"
    config.sprites layout.width layout.height config.sprites tile_size tile_size;
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
  Printf.printf
    "Warm-up frames: %d\nRequested measured frames: %d\nPosition seed: %d\n%!"
    config.warmup config.frames seed

let benchmark sdl renderer config =
  let width, height = Renderer.output_size renderer in
  if width <= tile_size || height <= tile_size then
    invalid_arg "Use an output that is larger than one sprite";
  let layout = atlas_layout config.sprites in
  (match Renderer.max_texture_size renderer with
  | Some limit when max layout.width layout.height > limit ->
      invalid_arg
        (Printf.sprintf
           "Use fewer sprites. The renderer limits textures to %d pixels per \
            axis"
           limit)
  | _ -> ());
  let@ texture =
    using Texture.destroy
      (Texture.create_streaming renderer ~w:layout.width ~h:layout.height)
  in
  fill_atlas layout texture;
  Texture.set_scale_mode texture Nearest;
  Texture.set_blend_mode texture Blend_mode.None;
  Renderer.set_vsync renderer false;
  Renderer.set_draw_color renderer (Color.rgb 18 24 32);
  let right = float (width - tile_size)
  and bottom = float (height - tile_size) in
  let batch = create_batch config.sprites layout ~right ~bottom in
  let positions = Sprite_batch.positions batch in
  let poll () = poll sdl 256 in
  let record () =
    move positions config.sprites ~right ~bottom;
    Renderer.clear renderer;
    Sprite_batch.draw renderer texture batch;
    1
  in
  let present () = Renderer.present renderer in
  print_setup config renderer layout ~width ~height;
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

let () =
  let config = parse_args () in
  try
    with_init [ Video ] (fun sdl ->
        let@ window =
          using Window.destroy
            (Window.create sdl ~title:"Atlas benchmark" ~w:config.width
               ~h:config.height)
        in
        let@ renderer =
          using Renderer.destroy (Renderer.create ?driver:config.driver window)
        in
        benchmark sdl renderer config)
  with Error message | Invalid_argument message ->
    Printf.eprintf "atlas_benchmark: %s\n%!" message;
    exit 1
