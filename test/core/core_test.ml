open Sdl3

external push_events : int32 -> unit = "test_push_events"

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let main_thread context window =
  let worker () =
    check (not (is_main_thread ())) "Wrong thread identity";
    invalid (fun () -> Window.size window);
    invalid (fun () -> Window.destroy window);
    invalid (fun () -> init []);
    invalid (fun () -> quit context);
    check ((version ()).major = 3) "SDL version on another thread";
    ignore (Timer.ticks_ns ())
  in
  Domain.join (Domain.spawn worker);
  let passed = Atomic.make false in
  let thread =
    Thread.create
      (fun () ->
        worker ();
        Atomic.set passed true)
      ()
  in
  Thread.join thread;
  check (Atomic.get passed) "Thread check failed in the main domain"

let events context window =
  let id = Window.id window in
  let next () =
    match Event.poll context with
    | Some event -> event
    | None -> failwith "Missing event"
  in
  push_events (Window.id_to_int32 id);
  let open Event in
  (match next () with
  | {
   kind = Window { window; change = Resized (320, 240) };
   timestamp_ns = 1234L;
  } ->
      check (window = id) "Resize window ID"
  | _ -> failwith "Resize event");
  (match (next ()).kind with
  | Window { change = Pixel_size_changed (640, 480); _ } -> ()
  | _ -> failwith "Pixel-size event");
  (match (next ()).kind with
  | Window { change = Close_requested; _ } -> ()
  | _ -> failwith "Close event");
  (match (next ()).kind with
  | Key { window; scancode; keycode; down = true; repeat = true; modifiers } ->
      check (window = id && scancode = Scancode.escape) "Key event and scancode";
      check (Keycode.name keycode = "Escape") "Keycode name";
      check
        (Keymod.has modifiers Shift && not (Keymod.has modifiers Ctrl))
        "Key modifiers"
  | _ -> failwith "Key event");
  let text =
    match (next ()).kind with
    | Text_input { window; text } ->
        check (window = id) "Text window ID";
        text
    | _ -> failwith "Text-input event"
  in
  (match (next ()).kind with
  | Text_editing { text = "test"; start = 1; length = 2; _ } -> ()
  | _ -> failwith "Text-editing event");
  (match (next ()).kind with
  | Mouse_motion { x = 2.5; y = 3.5; dx = -1.5; dy = 0.5; buttons; _ } ->
      check
        (Mouse.is_pressed buttons Left && not (Mouse.is_pressed buttons Right))
        "Mouse mask";
      check
        (not (Mouse.is_pressed buttons (Other max_int)))
        "Invalid mouse index"
  | _ -> failwith "Mouse-motion event");
  (match (next ()).kind with
  | Mouse_button { button = X1; down = true; clicks = 2; x = 1.25; y = 2.75; _ }
    ->
      ()
  | _ -> failwith "Mouse-button event");
  (match (next ()).kind with
  | Mouse_wheel { x = 0.5; y = -1.0; flipped = true; _ } -> ()
  | _ -> failwith "Mouse-wheel event");
  let added = (next ()).kind in
  let removed = (next ()).kind in
  (match (added, removed) with
  | Gamepad_added added, Gamepad_removed gone ->
      check (gone = added && Gamepad.id_to_int32 added = 123l) "Gamepad ID";
      sdl_error "SDL_OpenGamepad" (fun () -> Gamepad.open_ context added)
  | _ -> failwith "Gamepad events");
  (match (next ()).kind with Other _ -> () | _ -> failwith "Unbound event");
  check ((next ()).kind = Quit) "Quit event";
  check (poll context = None) "Empty queue";
  check (text = "é") "UTF-8 text after more polls"

let render context window =
  sdl_error "SDL_CreateRenderer" (fun () ->
      Renderer.create ~driver:"missing-renderer" window);
  using Renderer.destroy (Renderer.create ~driver:"software" window)
    (fun window_renderer ->
      check
        (Renderer.output_size window_renderer = (32, 24))
        "Window renderer output size";
      Renderer.present window_renderer;
      invalid (fun () -> Window.destroy window);
      using Surface.destroy (Surface.create context ~w:16 ~h:16) (fun target ->
          using Renderer.destroy (Renderer.create_software target)
            (fun renderer ->
              invalid (fun () -> Surface.destroy target);
              let black = Color.rgb 0 0 0 and red = Color.rgb 255 0 0 in
              let blue = Color.rgb 0 0 255 in
              Renderer.set_logical_presentation renderer
                (Some (16, 16, Letterbox));
              Renderer.set_logical_presentation renderer None;
              Renderer.set_draw_color renderer black;
              Renderer.clear renderer;
              Renderer.set_draw_color renderer red;
              Renderer.fill_rect renderer (Frect.make ~x:2. ~y:2. ~w:4. ~h:4.);
              Renderer.present renderer;
              check
                (Surface.read_pixel target ~x:2 ~y:2 = red)
                "Rectangle color";
              check (Surface.read_pixel target ~x:1 ~y:1 = black) "Clear color";
              invalid (fun () ->
                  Renderer.draw_line renderer ~x1:nan ~y1:0. ~x2:1. ~y2:1.);
              let texture =
                using Surface.destroy
                  (Surface.create context ~format:Bgra32 ~w:2 ~h:3)
                  (fun source ->
                    Surface.fill source blue;
                    Texture.of_surface renderer source)
              in
              using Texture.destroy texture (fun texture ->
                  Gc.full_major ();
                  check (Texture.size texture = (2., 3.)) "Texture size";
                  invalid (fun () -> Texture.draw window_renderer texture);
                  invalid (fun () -> Renderer.destroy renderer);
                  Texture.set_scale_mode texture Nearest;
                  Texture.set_blend_mode texture None;
                  Texture.draw
                    ~dst:(Frect.make ~x:8. ~y:8. ~w:2. ~h:3.)
                    renderer texture;
                  Texture.draw_rotated ~flip:Horizontal
                    ~dst:(Frect.make ~x:0. ~y:8. ~w:2. ~h:3.)
                    renderer texture ~angle:180.;
                  Renderer.present renderer;
                  check
                    (Surface.read_pixel target ~x:8 ~y:8 = blue)
                    "Texture draw";
                  check
                    (Surface.read_pixel target ~x:0 ~y:8 = blue)
                    "Rotated texture draw";
                  Texture.destroy texture;
                  invalid (fun () -> Texture.size texture)))))

let audio context =
  using Audio.close
    (Audio.open_playback context
       { format = S16; channels = 1; frequency = 48_000 })
    (fun stream ->
      let buffer =
        Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout 32
      in
      Bigarray.Array1.fill buffer 0;
      Audio.queue stream (Bigarray.Array1.sub buffer 4 24);
      check (Audio.queued_bytes stream = 24) "Queued stream byte count";
      Audio.flush stream;
      Audio.clear stream;
      check (Audio.queued_bytes stream = 0) "Clear stream";
      Audio.resume stream;
      Audio.pause stream;
      Audio.close stream;
      invalid (fun () -> Audio.queue stream buffer))

let () =
  check (is_main_thread ()) "Main thread";
  check ((version ()).major = 3) "SDL version";
  let start = Timer.ticks_ns () in
  Timer.delay_ns 1_000_000L;
  check (Int64.sub (Timer.ticks_ns ()) start >= 1_000_000L) "Nanosecond timer";
  check (Timer.ticks_ms () >= 1L) "Millisecond timer";
  invalid (fun () -> Timer.delay_ns (-1L));
  invalid (fun () -> Color.rgba 0 256 0 0);
  with_init [ Video; Audio; Gamepad ] (fun context ->
      invalid (fun () -> init []);
      invalid (fun () -> Surface.create context ~w:0 ~h:1);
      invalid (fun () ->
          Window.create context ~title:"embedded\000NUL" ~w:1 ~h:1);
      using Window.destroy
        (Window.create ~flags:[ Hidden ] context ~title:"Core test" ~w:32 ~h:24)
        (fun window ->
          check (Window.size window = (32, 24)) "Window size";
          check (Window.size_in_pixels window = (32, 24)) "Window pixel size";
          invalid (fun () -> quit context);
          check
            (Scancode.of_name "Escape" = Some Scancode.escape)
            "Scancode lookup";
          check (Scancode.of_name "Not a scancode" = None) "Unknown scancode";
          check
            (not (Keyboard.is_pressed context Scancode.escape))
            "Keyboard state";
          main_thread context window;
          events context window;
          render context window);
      audio context);
  let context = init [] in
  quit context;
  quit context;
  invalid (fun () -> Surface.create context ~w:1 ~h:1);
  let next = init [] in
  quit context;
  quit next
