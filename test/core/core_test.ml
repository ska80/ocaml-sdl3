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
    invalid (fun () -> Gpu.supports_shader_formats context [ Spirv ]);
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

let frect x y w h = Frect.make ~x ~y ~w ~h

let render_batches renderer output =
  let black = Color.rgb 0 0 0 and red = Color.rgb 255 0 0 in
  let pixel x y = Surface.read_pixel output ~x ~y in
  Renderer.set_draw_color renderer black;
  Renderer.clear renderer;
  Renderer.set_draw_color renderer red;
  Renderer.fill_rects renderer [||];
  Renderer.draw_rects renderer [||];
  invalid (fun () ->
      Renderer.fill_rects renderer [| frect 0. 0. 1. 1.; frect nan 0. 1. 1. |]);
  let invalid_batch = Array.make 65 (frect 0. 0. 2. 2.) in
  invalid_batch.(64) <- frect 0. 0. 1. infinity;
  invalid (fun () -> Renderer.draw_rects renderer invalid_batch);
  Renderer.fill_rects renderer [| frect 2. 2. 2. 2.; frect 7. 2. 2. 2. |];
  let outlines = Array.make 65 (frect 2. 8. 4. 4.) in
  outlines.(64) <- frect 9. 8. 4. 4.;
  Renderer.draw_rects renderer outlines;
  Renderer.present renderer;
  check (pixel 0 0 = black) "Invalid batches did not draw";
  check (pixel 3 3 = red && pixel 8 3 = red) "Filled rectangle batch";
  check (pixel 2 8 = red && pixel 9 8 = red) "Rectangle outline batch";
  check (pixel 3 9 = black && pixel 10 9 = black) "Empty outlines"

let streaming_texture renderer output =
  let open Bigarray in
  let pixel x y = Surface.read_pixel output ~x ~y in
  let red = Color.rgb 255 0 0 and blue = Color.rgb 0 0 255 in
  let green = Color.rgba 0 255 0 127 in
  let buffer = Array1.create int8_unsigned c_layout 28 in
  Array1.fill buffer 0;
  let pixels = Array1.sub buffer 4 24 in
  let put i { Color.r; g; b; a } =
    pixels.{i} <- r;
    pixels.{i + 1} <- g;
    pixels.{i + 2} <- b;
    pixels.{i + 3} <- a
  in
  invalid (fun () -> Texture.create_streaming renderer ~w:0 ~h:2);
  invalid (fun () -> Texture.create_streaming renderer ~w:(1 lsl 28) ~h:2);
  using Texture.destroy (Texture.create_streaming renderer ~w:2 ~h:2)
    (fun texture ->
      let update ~pitch = Texture.update texture pixels ~pitch in
      invalid (fun () -> update ~pitch:0);
      invalid (fun () -> update ~pitch:4);
      invalid (fun () -> update ~pitch:9);
      invalid (fun () ->
          Texture.update texture (Array1.sub pixels 0 23) ~pitch:12);
      let invalid_rect rect =
        invalid (fun () -> Texture.update ~rect texture pixels ~pitch:12)
      in
      invalid_rect (Rect.make ~x:(-1) ~y:0 ~w:1 ~h:1);
      invalid_rect (Rect.make ~x:0 ~y:0 ~w:0 ~h:1);
      invalid_rect (Rect.make ~x:1 ~y:0 ~w:2 ~h:1);
      invalid_rect (Rect.make ~x:0 ~y:1 ~w:1 ~h:2);
      invalid_rect (Rect.make ~x:max_int ~y:0 ~w:1 ~h:1);
      put 0 red;
      put 4 blue;
      put 12 blue;
      put 16 red;
      update ~pitch:12;
      Texture.set_blend_mode texture None;
      let draw () =
        Texture.draw ~dst:(frect 4. 4. 2. 2.) renderer (texture :> Texture.t);
        Renderer.present renderer
      in
      draw ();
      check (pixel 4 4 = red && pixel 5 4 = blue) "Streaming texture first row";
      check (pixel 4 5 = blue && pixel 5 5 = red) "Padded streaming texture row";
      put 0 green;
      put 4 green;
      Texture.update
        ~rect:(Rect.make ~x:1 ~y:0 ~w:1 ~h:2)
        texture (Array1.sub pixels 0 8) ~pitch:4;
      draw ();
      check (pixel 4 4 = red && pixel 4 5 = blue) "Pixels outside update";
      check (pixel 5 4 = green && pixel 5 5 = green) "Partial RGBA update";
      Texture.destroy texture;
      invalid (fun () -> update ~pitch:12))

let render_target renderer other_renderer output =
  let black = Color.rgb 0 0 0 and blue = Color.rgb 0 0 255 in
  let red = Color.rgb 255 0 0 in
  Renderer.set_draw_color renderer black;
  Renderer.clear renderer;
  invalid (fun () -> Texture.create_target renderer ~w:3 ~h:(-1));
  using Texture.destroy (Texture.create_target renderer ~w:3 ~h:4)
    (fun target ->
      let select () = Renderer.set_target renderer (Some target) in
      invalid (fun () -> Renderer.set_target other_renderer (Some target));
      invalid (fun () -> Renderer.destroy renderer);
      Domain.join
        (Domain.spawn (fun () ->
             invalid select;
             invalid (fun () -> Texture.destroy target)));
      check (Renderer.output_size renderer = (16, 16)) "Default output size";
      select ();
      check (Renderer.current_output_size renderer = (3, 4)) "Target size";
      invalid (fun () -> Renderer.present renderer);
      invalid (fun () -> Texture.draw renderer target);
      invalid (fun () -> Texture.draw_rotated renderer target ~angle:0.);
      Renderer.set_draw_color renderer blue;
      Renderer.clear renderer;
      Renderer.set_draw_color renderer red;
      Renderer.fill_rects renderer [| frect 1. 2. 1. 1. |];
      Renderer.set_target renderer None;
      Texture.set_blend_mode target None;
      Texture.draw ~dst:(frect 4. 4. 3. 4.) renderer target;
      Renderer.present renderer;
      check (Surface.read_pixel output ~x:3 ~y:4 = black) "Outside target draw";
      check (Surface.read_pixel output ~x:4 ~y:4 = blue) "Target clear color";
      check (Surface.read_pixel output ~x:5 ~y:6 = red) "Target rectangle color";
      select ();
      Texture.destroy target;
      check
        (Renderer.current_output_size renderer = (16, 16))
        "Destroying the current target restores the default";
      invalid select;
      Renderer.present renderer)

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
                  invalid (fun () -> Texture.size texture));
              render_batches renderer target;
              streaming_texture renderer target;
              render_target renderer window_renderer target)))

let gpu_without_backend context =
  let driver = "not-an-sdl-gpu-driver" in
  List.iter (fun name -> check (name <> "") "GPU driver name") (Gpu.drivers ());
  invalid (fun () -> Gpu.supports_shader_formats context []);
  invalid (fun () -> Gpu.create_device context []);
  invalid (fun () ->
      Gpu.create_device ~driver:"embedded\000NUL" context [ Spirv ]);
  check
    (not (Gpu.supports_shader_formats ~driver context [ Spirv ]))
    "Missing GPU driver";
  sdl_error "SDL_CreateGPUDevice" (fun () ->
      Gpu.create_device ~driver context [ Spirv ])

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
      gpu_without_backend context;
      audio context);
  let context = init [] in
  invalid (fun () -> Gpu.create_device context [ Spirv ]);
  quit context;
  quit context;
  invalid (fun () -> Surface.create context ~w:1 ~h:1);
  invalid (fun () -> Gpu.supports_shader_formats context [ Spirv ]);
  let next = init [] in
  quit context;
  quit next
