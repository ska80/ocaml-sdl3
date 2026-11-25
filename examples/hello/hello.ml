open Sdl3

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let rec keep_running sdl =
  match Event.poll sdl with
  | None -> true
  | Some { kind = Quit | Window { change = Close_requested; _ }; _ } -> false
  | Some { kind = Key { scancode; down = true; _ }; _ }
    when scancode = Scancode.escape ->
      false
  | Some _ -> keep_running sdl

let run frame_limit =
  with_init [ Video ] (fun sdl ->
      using Window.destroy
        (Window.create ~flags:[ Resizable ] sdl ~title:"SDL3 from OCaml" ~w:640
           ~h:480) (fun window ->
          using Renderer.destroy (Renderer.create window) (fun renderer ->
              let background = Color.rgb 20 26 38 in
              let foreground = Color.rgb 97 192 208 in
              let rec loop frame =
                if frame <> frame_limit && keep_running sdl then (
                  Renderer.set_draw_color renderer background;
                  Renderer.clear renderer;
                  Renderer.set_draw_color renderer foreground;
                  let x =
                    20. +. (200. *. (1. +. sin (float_of_int frame /. 60.)))
                  in
                  Renderer.fill_rect renderer
                    (Frect.make ~x ~y:180. ~w:100. ~h:100.);
                  Renderer.present renderer;
                  Timer.delay_ns 16_000_000L;
                  loop (frame + 1))
              in
              loop 0)))

let () =
  let frames = ref (-1) in
  Arg.parse
    [ ("--frames", Arg.Set_int frames, "Stop after this many frames") ]
    (fun _ -> raise (Arg.Bad "Unexpected argument"))
    "hello [--frames COUNT]";
  try run !frames
  with Error message ->
    prerr_endline message;
    exit 1
