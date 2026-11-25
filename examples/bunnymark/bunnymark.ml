(* OCaml port of Raylib's Bunnymark example, with batched SDL drawing.
   Original example copyright (c) 2014-2025 Ramon Santamaria (@raysan5).
   See bunnymark.LICENSE for the Raylib license notice. *)

open Sdl3

let width = 800
let height = 450
let max_bunnies = 80_000
let bunnies_per_frame = 100

module Swarm = struct
  type t = {
    positions : Float.Array.t;
    velocities : Float.Array.t;
    tints : Color.t array;
    rng : Random.State.t;
    mutable count : int;
  }

  let create () =
    {
      positions = Float.Array.make (2 * max_bunnies) 0.;
      velocities = Float.Array.make (2 * max_bunnies) 0.;
      tints = Array.make max_bunnies (Color.rgb 255 255 255);
      rng = Random.State.make [| 42 |];
      count = 0;
    }

  let add t ~x ~y =
    let i = 2 * t.count in
    let speed () = float_of_int (Random.State.int t.rng 501 - 250) in
    Float.Array.set t.positions i x;
    Float.Array.set t.positions (i + 1) y;
    Float.Array.set t.velocities i (speed ());
    Float.Array.set t.velocities (i + 1) (speed ());
    let r = 50 + Random.State.int t.rng 191 in
    let g = 80 + Random.State.int t.rng 161 in
    let b = 100 + Random.State.int t.rng 141 in
    t.tints.(t.count) <- Color.rgb r g b;
    t.count <- t.count + 1

  let[@inline always] move_axis positions velocities i edge dt =
    let speed = Float.Array.unsafe_get velocities i in
    let next = Float.Array.unsafe_get positions i +. (speed *. dt) in
    if next < 0. then (
      Float.Array.unsafe_set positions i (-.next);
      Float.Array.unsafe_set velocities i (-.speed))
    else if next > edge then (
      Float.Array.unsafe_set positions i ((2. *. edge) -. next);
      Float.Array.unsafe_set velocities i (-.speed))
    else Float.Array.unsafe_set positions i next

  let move t ~right ~bottom ~dt =
    let { positions; velocities; count; _ } = t in
    (* The live bunnies occupy a prefix of both arrays. *)
    for i = 0 to count - 1 do
      move_axis positions velocities (2 * i) right dt;
      move_axis positions velocities ((2 * i) + 1) bottom dt
    done

  let draw t renderer texture =
    Texture.draw_sprites renderer texture ~positions:t.positions ~tints:t.tints
      ~count:t.count
end

type input = {
  mutable x : float;
  mutable y : float;
  mutable held : bool;
  mutable paused : bool;
}

let rec poll sdl pause_key input =
  match Event.poll sdl with
  | None -> true
  | Some { kind = Quit | Window { change = Close_requested; _ }; _ } -> false
  | Some { kind = Key { scancode; down = true; _ }; _ }
    when scancode = Scancode.escape ->
      false
  | Some { kind; _ } ->
      (match kind with
      | Window { change = Focus_lost; _ } -> input.held <- false
      | Key { scancode; down = true; repeat = false; _ }
        when scancode = pause_key ->
          input.paused <- not input.paused
      | Mouse_motion { x; y; buttons; _ } ->
          input.x <- x;
          input.y <- y;
          input.held <- Mouse.is_pressed buttons Left
      | Mouse_button { x; y; button = Left; down; _ } ->
          input.x <- x;
          input.y <- y;
          input.held <- down
      | _ -> ());
      poll sdl pause_key input

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let controls = "Hold left mouse to add bunnies | P to pause"
let seconds () = Int64.to_float (Timer.ticks_ns ()) *. 1e-9

let play sdl window renderer texture ~initial ~frame_limit =
  let swarm = Swarm.create () in
  let sprite_w, sprite_h = Texture.size texture in
  let right = float_of_int width -. sprite_w in
  let bottom = float_of_int height -. sprite_h in
  for _ = 1 to initial do
    let x = Random.State.float swarm.rng right in
    let y = Random.State.float swarm.rng bottom in
    Swarm.add swarm ~x ~y
  done;
  let pause_key = Option.get (Scancode.of_name "P") in
  let input = { x = 0.; y = 0.; held = false; paused = false } in
  Renderer.set_draw_color renderer (Color.rgb 245 245 245);
  let start = seconds () in
  let rec loop frame previous report_time report_frame =
    if frame = frame_limit || not (poll sdl pause_key input) then frame
    else
      let now = seconds () in
      (if input.held then
         let x = max 0. (min right input.x) in
         let y = max 0. (min bottom input.y) in
         let to_add = min bunnies_per_frame (max_bunnies - swarm.count) in
         for _ = 1 to to_add do
           Swarm.add swarm ~x ~y
         done);
      (* Limit the step after a stall so a bunny cannot cross both edges. *)
      if not input.paused then
        Swarm.move swarm ~right ~bottom ~dt:(min 0.25 (now -. previous));
      Renderer.clear renderer;
      Swarm.draw swarm renderer texture;
      Renderer.present renderer;
      let elapsed = now -. report_time in
      if elapsed >= 0.5 then (
        let fps = float_of_int (frame - report_frame) /. elapsed in
        let status = if input.paused then " (paused)" else "" in
        Window.set_title window
          (Printf.sprintf "Bunnymark%s | %d bunnies | %.0f FPS | %s" status
             swarm.count fps controls);
        loop (frame + 1) now now frame)
      else loop (frame + 1) now report_time report_frame
  in
  let frames = loop 0 start start 0 in
  let elapsed = seconds () -. start in
  if frames > 0 && elapsed > 0. then
    Printf.printf "Bunnymark: %d bunnies, %d frames in %.3f s (%.1f FPS)\n%!"
      swarm.count frames elapsed
      (float_of_int frames /. elapsed)

let run ~initial ~frame_limit =
  let sprite =
    Filename.concat (Filename.dirname Sys.executable_name) "assets/raybunny.png"
  in
  with_init [ Video ] (fun sdl ->
      using Window.destroy
        (Window.create sdl
           ~title:("Bunnymark | " ^ controls)
           ~w:width ~h:height)
        (fun window ->
          using Renderer.destroy (Renderer.create window) (fun renderer ->
              Renderer.set_vsync renderer false;
              using Texture.destroy (Sdl3_image.load_texture renderer sprite)
                (fun texture ->
                  Texture.set_scale_mode texture Nearest;
                  Texture.set_blend_mode texture Blend;
                  play sdl window renderer texture ~initial ~frame_limit))))

let () =
  let initial = ref 0 and frame_limit = ref max_int in
  let set_initial n =
    if n < 0 || n > max_bunnies then
      raise
        (Arg.Bad (Printf.sprintf "Use a bunny count from 0 to %d" max_bunnies));
    initial := n
  in
  let set_frames n =
    if n < 1 then raise (Arg.Bad "Use a positive frame count");
    frame_limit := n
  in
  Arg.parse
    [
      ("--bunnies", Arg.Int set_initial, "Start with this many bunnies");
      ("--frames", Arg.Int set_frames, "Stop after this many frames");
    ]
    (fun arg -> raise (Arg.Bad ("Unexpected argument: " ^ arg)))
    "bunnymark [--bunnies COUNT] [--frames COUNT]";
  try run ~initial:!initial ~frame_limit:!frame_limit
  with Error message ->
    prerr_endline message;
    exit 1
