open Sdl3

external push_events : int32 -> unit = "test_push_events"
external push_device_events : int32 -> unit = "test_push_device_events"
external attach_gamepad : unit -> int32 = "test_attach_gamepad"
external detach_gamepad : int32 -> unit = "test_detach_gamepad"

external set_gamepad_state : int32 -> axis:int -> pressed:bool -> unit
  = "test_set_gamepad_state"

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
    invalid (fun () -> Window.display window);
    invalid (fun () -> Display.list context);
    invalid (fun () -> Touch.devices context);
    invalid (fun () -> Gamepad.list context);
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

let displays context window =
  let primary = Display.primary context in
  let displays = Display.list context in
  check (List.mem primary displays) "Primary display in the display list";
  check (Display.id_to_int32 primary <> 0l) "Display ID";
  check (Display.name context primary <> "") "Display name";
  let bounds = Display.bounds context primary in
  let usable = Display.usable_bounds context primary in
  check (bounds.w > 0 && bounds.h > 0) "Display bounds";
  check (usable.w > 0 && usable.h > 0) "Usable display bounds";
  check (Display.content_scale context primary > 0.) "Display content scale";
  let check_mode (mode : Display.mode) =
    check (mode.w > 0 && mode.h > 0) "Display mode size";
    check (mode.pixel_density > 0.) "Display mode pixel density";
    check (mode.refresh_rate >= 0.) "Display mode refresh rate"
  in
  check_mode (Display.desktop_mode context primary);
  check_mode (Display.current_mode context primary);
  List.iter check_mode (Display.fullscreen_modes context primary);
  check (Window.display window = primary) "Window's display";
  check (Window.display_scale window > 0.) "Window display scale";
  check (Window.title window = "Core test") "Initial title";
  Window.set_title window "Core test é";
  check (Window.title window = "Core test é") "Changed UTF-8 title";
  Window.set_resizable window true;
  Window.set_position window ~x:7 ~y:9;
  check (Window.position window = (7, 9)) "Window position";
  invalid (fun () -> Window.set_position window ~x:0x2fff_0000 ~y:0);
  if Sys.int_size > 32 then
    invalid (fun () -> Window.set_position window ~x:0 ~y:max_int)

let device_events context window =
  let window_id = Window.id window in
  let primary = Display.primary context in
  let mouse_touch =
    List.find (fun id -> Touch.id_to_int64 id = -1L) (Touch.devices context)
  in
  check (Touch.name context mouse_touch <> "") "Touch device name";
  check (Touch.device_type context mouse_touch = Direct) "Touch device type";
  check (Touch.fingers context mouse_touch = []) "No active fingers";
  push_device_events (Window.id_to_int32 window_id);
  let next () =
    match Event.poll context with
    | Some { kind; _ } -> kind
    | None -> failwith "Missing device event"
  in
  let open Event in
  List.iter
    (fun change ->
      check (next () = Window { window = window_id; change }) "Window event")
    [
      Moved (-17, 23);
      Display_changed primary;
      Shown;
      Hidden;
      Minimized;
      Maximized;
      Restored;
      Display_scale_changed;
      Entered_fullscreen;
      Left_fullscreen;
    ];
  List.iter
    (fun change ->
      check (next () = Display { display = primary; change }) "Display event")
    [
      Connected;
      Disconnected;
      Layout_changed;
      Desktop_mode_changed;
      Current_mode_changed;
      Content_scale_changed;
    ];
  (match next () with
  | Display { display; change = Disconnected } ->
      check (Display.id_to_int32 display = -1l) "Full display ID width";
      sdl_error "SDL_GetDisplayBounds" (fun () ->
          Display.bounds context display);
      sdl_error "SDL_GetFullscreenDisplayModes" (fun () ->
          Display.fullscreen_modes context display)
  | _ -> failwith "Missing display removal");
  List.iter
    (fun change ->
      match next () with
      | Touch { window; device; finger; change = actual; dx; dy } ->
          check (actual = change) "Touch event change";
          check
            (Touch.finger_id_to_int64 finger.id = 0xf123_4567_89ab_cdefL)
            "Full finger ID width";
          check (finger.x = 0.25 && finger.y = 0.75) "Finger coordinates";
          check
            (finger.pressure = 0.625 && dx = -0.125 && dy = 0.5)
            "Finger pressure and motion";
          if change = Canceled then (
            check (window = None) "Touch event without a window";
            check
              (Touch.id_to_int64 device = 0xbeef_0000_dead_9876L)
              "Full touch device ID width";
            sdl_error "SDL_GetTouchFingers" (fun () ->
                Touch.fingers context device))
          else
            check
              (window = Some window_id && device = mouse_touch)
              "Touch event window and device"
      | _ -> failwith "Expected a touch event")
    [ Down; Motion; Up; Canceled ];
  (match next () with
  | Gamepad_remapped id ->
      check (Gamepad.id_to_int32 id = 123l) "Gamepad mapping event ID"
  | _ -> failwith "Expected a gamepad mapping event");
  check (next () = Other 0x650l) "Unknown gamepad axis event";
  check (next () = Other 0x651l) "Unknown gamepad button event"

let gamepads context =
  let gamepad = attach_gamepad () in
  using detach_gamepad gamepad (fun raw_id ->
      let id =
        List.find
          (fun id -> Gamepad.id_to_int32 id = raw_id)
          (Gamepad.list context)
      in
      let name = Gamepad.name_for_id context id in
      check (name <> "") "Gamepad name before opening";
      using Gamepad.close (Gamepad.open_ context id) (fun pad ->
          check (Gamepad.connected pad && Gamepad.id pad = id) "Opened gamepad";
          check (Gamepad.name pad = name) "Opened gamepad name";
          check (Gamepad.has_axis pad Left_x) "Mapped gamepad axis";
          check (not (Gamepad.has_axis pad Right_y)) "Unmapped gamepad axis";
          check (Gamepad.has_button pad Left_paddle2) "Mapped gamepad button";
          check
            (not (Gamepad.has_button pad Dpad_right))
            "Unmapped gamepad button";
          (* Finish the current SDL poll cycle before changing the inputs. *)
          while Option.is_some (Event.poll context) do
            ()
          done;
          let state pressed axis_value =
            set_gamepad_state raw_id ~axis:axis_value ~pressed;
            let rec events axis_seen button_seen =
              match Event.poll context with
              | Some
                  { kind = Gamepad_axis { gamepad; axis = Left_x; value }; _ }
                when gamepad = id && value = axis_value ->
                  events true button_seen
              | Some
                  {
                    kind =
                      Gamepad_button { gamepad; button = Left_paddle2; down };
                    _;
                  }
                when gamepad = id && down = pressed ->
                  events axis_seen true
              | Some _ -> events axis_seen button_seen
              | None -> check (axis_seen && button_seen) "Gamepad state events"
            in
            events false false;
            check (Gamepad.axis pad Left_x = axis_value) "Gamepad axis value";
            check
              (Gamepad.button pad Left_paddle2 = pressed)
              "Gamepad button value"
          in
          (* SDL 3.2 can round the mapped center from zero to one. *)
          state true (-32768);
          state false 32767;
          Gamepad.close pad;
          invalid (fun () -> Gamepad.has_axis pad Left_x)));
  check
    (not
       (List.exists
          (fun id -> Gamepad.id_to_int32 id = gamepad)
          (Gamepad.list context)))
    "Detached gamepad not in the list"

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

let render_sprites context renderer other_renderer output =
  let black = Color.rgb 0 0 0 and white = Color.rgb 255 255 255 in
  let red = Color.rgb 255 0 0 and blue = Color.rgb 0 0 255 in
  let transparent = Color.rgba 0 255 0 0 in
  let texture =
    using Surface.destroy (Surface.create context ~w:2 ~h:3) (fun source ->
        Surface.fill source white;
        Texture.of_surface renderer source)
  in
  using Texture.destroy texture (fun texture ->
      (* A batch crosses multiple chunks. The final array entry is unused. *)
      let count = 1025 in
      let positions = Float.Array.make (2 * (count + 1)) 0. in
      let tints = Array.make (count + 1) red in
      let place i x y tint =
        Float.Array.set positions (2 * i) x;
        Float.Array.set positions ((2 * i) + 1) y;
        tints.(i) <- tint
      in
      place 0 (-1.) 1. red;
      place (count - 3) 4. 3. red;
      place (count - 2) 4. 3. transparent;
      place (count - 1) 5. 3. blue;
      place count nan nan white;
      let draw ~count =
        Texture.draw_sprites renderer texture ~positions ~tints ~count
      in
      Renderer.set_draw_color renderer black;
      Renderer.clear renderer;
      Texture.set_blend_mode texture Blend;
      Texture.set_alpha_mod texture 0;
      Texture.draw_sprites renderer texture ~positions:(Float.Array.make 0 0.)
        ~tints:[||] ~count:0;
      invalid (fun () -> draw ~count:(-1));
      invalid (fun () -> draw ~count:(count + 1));
      invalid (fun () ->
          Texture.draw_sprites renderer texture ~positions ~tints:[||] ~count:1);
      invalid (fun () ->
          Texture.draw_sprites renderer texture
            ~positions:(Float.Array.make 1 0.) ~tints ~count:1);
      invalid (fun () ->
          Texture.draw_sprites other_renderer texture ~positions ~tints ~count:1);
      Domain.join (Domain.spawn (fun () -> invalid (fun () -> draw ~count:1)));
      Renderer.present renderer;
      let pixel x y = Surface.read_pixel output ~x ~y in
      check (pixel 0 1 = black) "Invalid sprite batch did not draw";
      draw ~count;
      Texture.draw ~dst:(frect 8. 3. 2. 3.) renderer texture;
      Texture.set_alpha_mod texture 255;
      Texture.draw ~dst:(frect 12. 3. 2. 3.) renderer texture;
      Renderer.present renderer;
      check (pixel 0 3 = red) "Clipped sprite at its original height";
      check (pixel 4 5 = red) "Transparent tint preserves the earlier sprite";
      check (pixel 5 5 = blue && pixel 6 3 = blue) "Last sprite draws on top";
      check (pixel 7 3 = black) "Sprite uses its original width";
      check (pixel 8 3 = black) "Sprite batch preserves the texture alpha";
      check (pixel 12 3 = white) "Sprite batch preserves the texture color";
      Texture.destroy texture;
      invalid (fun () -> draw ~count:1))

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

let locked_texture renderer output =
  let open Texture in
  let red = Color.rgba 200 12 56 255 and blue = Color.rgba 18 48 207 127 in
  let green = Color.rgba 34 160 78 242 and clear = Color.rgba 0 0 0 0 in
  let rect x y w h = Rect.make ~x ~y ~w ~h in
  let pixels =
    let open Bigarray in
    let buffer = Array1.create int8_unsigned c_layout 24 in
    let pixels = Array1.sub buffer 4 20 in
    Array1.fill buffer 42;
    let put i { Color.r; g; b; a } =
      pixels.{i} <- r;
      pixels.{i + 1} <- g;
      pixels.{i + 2} <- b;
      pixels.{i + 3} <- a
    in
    put 0 green;
    put 4 blue;
    put 12 blue;
    put 16 green;
    pixels
  in
  using destroy (create_streaming renderer ~w:3 ~h:3) (fun texture ->
      let draw () =
        Texture.draw ~dst:(frect 9. 9. 3. 3.) renderer texture;
        Renderer.present renderer
      in
      let pixel x y = Surface.read_pixel output ~x:(x + 9) ~y:(y + 9) in
      let unexpected _ = failwith "The texture lock callback must not run" in
      let region = rect 1 1 2 2 in
      List.iter
        (fun rect -> invalid (fun () -> with_lock ~rect texture unexpected))
        [
          rect (-1) 0 1 1;
          rect 0 0 0 1;
          rect 2 0 2 1;
          rect 0 2 1 2;
          rect max_int 0 1 1;
        ];
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> with_lock texture unexpected)));
      set_blend_mode texture None;
      let stale =
        with_lock texture (fun view ->
            check (Locked.size view = (3, 3)) "Whole lock size";
            Locked.fill view red;
            Locked.set_pixel view ~x:0 ~y:0 blue;
            view)
      in
      draw ();
      check (pixel 0 0 = blue && pixel 2 2 = red) "Whole lock writes";
      invalid (fun () -> Locked.size stale);
      invalid (fun () -> Locked.fill stale clear);
      invalid (fun () -> Locked.set_pixel stale ~x:0 ~y:0 red);
      invalid (fun () -> Locked.copy_from stale pixels ~pitch:12);
      with_lock ~rect:region texture (fun view ->
          Gc.compact ();
          check (Locked.size view = (2, 2)) "Partial lock size";
          invalid (fun () -> Locked.fill stale clear);
          invalid (fun () -> Locked.set_pixel view ~x:(-1) ~y:0 red);
          invalid (fun () -> Locked.set_pixel view ~x:2 ~y:0 red);
          invalid (fun () -> Locked.set_pixel view ~x:0 ~y:max_int red);
          List.iter
            (fun pitch ->
              invalid (fun () -> Locked.copy_from view pixels ~pitch))
            [ 0; 4; 10 ];
          invalid (fun () ->
              Locked.copy_from view (Bigarray.Array1.sub pixels 0 19) ~pitch:12);
          invalid (fun () -> with_lock texture unexpected);
          invalid (fun () ->
              update ~rect:(rect 0 0 1 1) texture pixels ~pitch:4);
          invalid draw;
          invalid (fun () -> draw_rotated renderer texture ~angle:30.);
          invalid (fun () ->
              draw_sprites renderer texture ~positions:(Float.Array.make 2 0.)
                ~tints:[| red |] ~count:1);
          invalid (fun () -> destroy texture);
          Domain.join
            (Domain.spawn (fun () -> invalid (fun () -> Locked.fill view clear)));
          Locked.copy_from view pixels ~pitch:12);
      draw ();
      check (pixel 1 1 = green && pixel 2 1 = blue) "First copied row";
      check (pixel 1 2 = blue && pixel 2 2 = green) "Last copied row";
      check
        (pixel 0 2 = red && pixel 2 0 = red)
        "Pixels outside the locked rectangle";
      let failure = Failure "Stop writing pixels" in
      let saved = ref None in
      (match
         with_lock ~rect:region texture (fun view ->
             saved := Some view;
             Locked.set_pixel view ~x:1 ~y:1 blue;
             raise failure)
       with
      | exception exn when exn == failure -> ()
      | _ -> failwith "Expected the texture lock callback exception");
      invalid (fun () -> Locked.fill (Option.get !saved) red);
      draw ();
      check (pixel 2 2 = blue) "Writes before an exception stay in the texture";
      check
        (pixel 1 1 = clear && pixel 1 2 = clear && pixel 0 2 = red)
        "Unwritten pixels are clear";
      with_lock ~rect:(rect 0 0 1 1) texture (fun _ -> ());
      draw ();
      check (pixel 0 0 = clear) "An empty lock clears only its rectangle";
      check (pixel 2 2 = blue) "The empty lock did not change other pixels";
      destroy texture;
      invalid (fun () -> with_lock texture unexpected))

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
      invalid (fun () ->
          Texture.draw_sprites renderer target
            ~positions:(Float.Array.make 2 0.) ~tints:[| blue |] ~count:1);
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
              render_sprites context renderer window_renderer target;
              streaming_texture renderer target;
              locked_texture renderer target;
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
          displays context window;
          events context window;
          device_events context window;
          render context window);
      gamepads context;
      gpu_without_backend context;
      audio context);
  let context = init [] in
  invalid (fun () -> Gpu.create_device context [ Spirv ]);
  invalid (fun () -> Display.list context);
  invalid (fun () -> Touch.devices context);
  invalid (fun () -> Gamepad.list context);
  quit context;
  quit context;
  invalid (fun () -> Display.primary context);
  invalid (fun () -> Touch.devices context);
  invalid (fun () -> Gamepad.list context);
  invalid (fun () -> Surface.create context ~w:1 ~h:1);
  invalid (fun () -> Gpu.supports_shader_formats context [ Spirv ]);
  let next = init [] in
  quit context;
  quit next
