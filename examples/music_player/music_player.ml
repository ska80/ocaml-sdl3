open Sdl3
open Music_player_support
open Scope

let caption : Playback.status -> string * bool = function
  | Empty -> ("Drag and drop music files", false)
  | Unplayable -> ("No playable files. Drop music files to try again.", false)
  | Playing song -> (song.title, true)
  | Paused song -> (song.title ^ "  (Paused)", true)
  | Finished song -> (song.title ^ "  (Finished)", false)

type controls = { mutable fullscreen : bool; mutable dropped : string list }

let handle_key window player controls keycode =
  match String.lowercase_ascii (Keycode.name keycode) with
  | "q" -> false
  | "f" ->
      let fullscreen = not controls.fullscreen in
      (try
         Window.set_fullscreen window fullscreen;
         controls.fullscreen <- fullscreen
       with Error message -> Printf.eprintf "%s\n%!" message);
      true
  | "space" ->
      Playback.toggle_pause player;
      true
  | "p" ->
      Playback.previous player;
      true
  | "n" ->
      Playback.next player;
      true
  | _ -> true

let handle_drop player controls : Event.drop_change -> unit = function
  | Begin -> controls.dropped <- []
  | File path -> controls.dropped <- path :: controls.dropped
  | Complete ->
      let paths = List.rev controls.dropped in
      controls.dropped <- [];
      Playback.replace player paths
  | Position _ | Text _ -> ()

let poll sdl window id player controls =
  let rec loop remaining =
    if remaining = 0 then true
    else
      match Event.poll sdl with
      | None -> true
      | Some event ->
          let keep_running =
            match event.kind with
            | Quit -> false
            | Window { window; change = Close_requested } when window = id ->
                false
            | Key { window = target; keycode; down = true; repeat = false; _ }
              when target = id ->
                handle_key window player controls keycode
            | Drop { window = target; change }
              when target = None || target = Some id ->
                handle_drop player controls change;
                true
            | _ -> true
          in
          keep_running && loop (remaining - 1)
  in
  (* Let the audio queue refill even during a flood of input events. *)
  loop 256

let frame_ns = Int64.div 1_000_000_000L 60L

let play sdl window player view ~frame_limit =
  let id = Window.id window in
  let controls = { fullscreen = false; dropped = [] } in
  let spectrum = Playback.spectrum player in
  let rec loop frame deadline previous status show_bars =
    if frame < frame_limit && poll sdl window id player controls then (
      Playback.tick player;
      let current = Playback.status player in
      let show_bars =
        if current = status then show_bars
        else
          let text, show_bars = caption current in
          View.set_caption view text;
          show_bars
      in
      let now = Timer.ticks_ns () in
      let dt = min 0.1 (Int64.to_float (Int64.sub now previous) *. 1e-9) in
      let drawn = View.draw view window spectrum ~show_bars ~dt in
      let frame = if drawn then frame + 1 else frame in
      if frame < frame_limit then (
        let deadline = Int64.add deadline frame_ns in
        let after = Timer.ticks_ns () in
        if after < deadline then Timer.delay_ns (Int64.sub deadline after);
        loop frame (max deadline after) now current show_bars))
  in
  let status = Playback.status player in
  let text, show_bars = caption status in
  View.set_caption view text;
  let now = Timer.ticks_ns () in
  loop 0 now now status show_bars

let run ~frame_limit paths =
  let@ sdl = with_init [ Video; Audio ] in
  let@ mixer_context = Sdl3_mixer.with_init sdl in
  let@ font_context = Sdl3_ttf.with_init sdl in
  let@ player = Playback.with_player sdl mixer_context in
  let@ device = using Gpu.destroy_device (Gpu.create_device sdl [ Spirv ]) in
  let@ window =
    using Window.destroy
      (Window.create
         ~flags:[ Resizable; High_pixel_density ]
         sdl ~title:"Music Player" ~w:960 ~h:540)
  in
  let@ swapchain = using Gpu.release_window (Gpu.claim_window device window) in
  let@ view = View.with_view font_context device swapchain in
  Playback.replace player paths;
  play sdl window player view ~frame_limit;
  Gpu.wait_idle device

let () =
  let frame_limit = ref max_int and paths = ref [] in
  let set_frames n =
    if n < 1 then raise (Arg.Bad "Use a positive frame count");
    frame_limit := n
  in
  Arg.parse
    [ ("--frames", Arg.Int set_frames, "Stop after this many drawn frames") ]
    (fun path -> paths := path :: !paths)
    "music_player [--frames COUNT] [FILE ...]";
  try run ~frame_limit:!frame_limit (List.rev !paths) with
  | Error message | Fun.Finally_raised (Error message) | Sys_error message ->
      Printf.eprintf "Music Player: %s\n%!" message;
      exit 1
  | Fftw3.S.Failure message ->
      Printf.eprintf "Music Player: FFTW plan creation failed: %s\n%!" message;
      exit 1
