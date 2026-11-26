open Sdl3

external push_events : int32 -> unit = "test_push_events"
external push_device_events : int32 -> unit = "test_push_device_events"
external push_render_events : int32 -> unit = "test_push_render_events"
external cursor_is_default : unit -> bool = "test_cursor_is_default"
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

let reject_clipboard context =
  invalid (fun () -> Clipboard.set_text context "no clipboard");
  invalid (fun () -> Clipboard.get_text context);
  invalid (fun () -> Clipboard.has_text context)

let reject_text_input_area window =
  invalid (fun () -> Keyboard.set_text_input_area window None);
  invalid (fun () -> Keyboard.text_input_area window)

let reject_mouse_context context =
  invalid (fun () -> Mouse.state context);
  invalid (fun () -> Mouse.global_state context);
  invalid (fun () -> Mouse.relative_state context);
  invalid (fun () -> Mouse.capture context true);
  invalid (fun () -> Mouse.Cursor.create_system context Crosshair);
  invalid (fun () -> Mouse.Cursor.reset context);
  invalid (fun () -> Mouse.Cursor.show context);
  invalid (fun () -> Mouse.Cursor.hide context);
  invalid (fun () -> Mouse.Cursor.visible context)

let reject_mouse_window window =
  invalid (fun () -> Mouse.warp_in_window window ~x:1. ~y:2.);
  invalid (fun () -> Window.set_mouse_grab window true);
  invalid (fun () -> Window.mouse_grab window)

let main_thread context window =
  let worker () =
    check (not (is_main_thread ())) "Wrong thread identity";
    invalid (fun () -> Window.size window);
    invalid (fun () -> Window.display window);
    invalid (fun () -> Display.list context);
    invalid (fun () -> Touch.devices context);
    invalid (fun () -> Gamepad.list context);
    reject_mouse_context context;
    reject_mouse_window window;
    reject_clipboard context;
    reject_text_input_area window;
    invalid (fun () -> Window.destroy window);
    invalid (fun () -> init []);
    invalid (fun () -> quit context);
    invalid (fun () -> Gpu.supports_shader_formats context [ Spirv ]);
    check ((version ()).major = 3) "SDL version on another thread";
    check
      (List.mem "software" (Renderer.drivers ()))
      "Render drivers on another thread";
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
  check
    ((next ()).kind = Drop { window = Some id; change = Begin })
    "Begin drop";
  check
    ((next ()).kind
    = Drop { window = Some id; change = Position { x = 8.5; y = 12.25 } })
    "Drop position";
  let path =
    match (next ()).kind with
    | Drop { window = Some window; change = File path } ->
        check (window = id) "File drop window ID";
        path
    | _ -> failwith "File drop event"
  in
  check
    ((next ()).kind = Drop { window = None; change = Text "Dropped text" })
    "Text drop with no window";
  check
    ((next ()).kind = Drop { window = Some id; change = Complete })
    "Complete drop";
  (match (next ()).kind with
  | Other _ -> ()
  | _ -> failwith "Unbound event");
  check ((next ()).kind = Quit) "Quit event";
  check (poll context = None) "Empty queue";
  check (text = "é") "UTF-8 text after more polls";
  check (path = "a b/é.wav") "UTF-8 file path after more polls"

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
      Mouse_entered;
      Mouse_left;
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

let converted_events context window renderer =
  let window_id = Window.id window in
  let rec take predicate =
    match Event.poll context with
    | Some event when predicate event.kind -> event
    | Some _ -> take predicate
    | None -> failwith "Missing event to convert"
  in
  let open Event in
  let convert event =
    let rendered = to_render_coordinates renderer event in
    check
      (rendered.timestamp_ns = event.timestamp_ns)
      "Converted event timestamp";
    rendered.kind
  in
  push_events (Window.id_to_int32 window_id);
  let event =
    take (function
      | Mouse_motion _ -> true
      | _ -> false)
  in
  (match event.kind with
  | Mouse_motion motion ->
      check
        (convert event
        = Mouse_motion
            { motion with x = -3.375; y = 1.5; dx = -0.375; dy = 0.5 })
        "Mouse position and movement in render units";
      check (motion.x = 2.5 && motion.dx = -1.5) "Original mouse event";
      Renderer.set_viewport renderer (Some (Rect.make ~x:1 ~y:2 ~w:4 ~h:14));
      check
        (convert event
        = Mouse_motion
            { motion with x = -1.375; y = 1.5; dx = -0.375; dy = 0.5 })
        "Convert the same event for another viewport";
      Renderer.set_viewport renderer (Some (Rect.make ~x:3 ~y:2 ~w:4 ~h:14));
      invalid (fun () ->
          convert { event with kind = Mouse_motion { motion with x = nan } });
      using Window.destroy
        (Window.create context ~title:"Other window" ~w:8 ~h:8) (fun other ->
          let event =
            {
              event with
              kind = Mouse_motion { motion with window = Window.id other };
            }
          in
          check
            (to_render_coordinates renderer event == event)
            "Event from another window")
  | _ -> assert false);
  let event =
    take (function
      | Mouse_button _ -> true
      | _ -> false)
  in
  (match event.kind with
  | Mouse_button button ->
      check
        (convert event = Mouse_button { button with x = -3.6875; y = 0.75 })
        "Converted button position"
  | _ -> assert false);
  let wheel =
    take (function
      | Mouse_wheel _ -> true
      | _ -> false)
  in
  check
    (to_render_coordinates renderer wheel == wheel)
    "Unchanged wheel scroll amounts";
  let drop =
    take (function
      | Drop { change = Position _; _ } -> true
      | _ -> false)
  in
  check
    (convert drop
    = Drop
        { window = Some window_id; change = Position { x = -1.875; y = 10.25 } }
    )
    "Drop position in render units";
  let file =
    take (function
      | Drop { change = File _; _ } -> true
      | _ -> false)
  in
  check (to_render_coordinates renderer file == file) "Unchanged file drop";
  let go_quit = take (( = ) Quit) in
  check
    (to_render_coordinates renderer go_quit == go_quit)
    "Unchanged quit event";
  check (poll context = None) "Event conversion does not enqueue events";
  push_device_events (Window.id_to_int32 window_id);
  let touch =
    take (function
      | Touch { change = Motion; _ } -> true
      | _ -> false)
  in
  (match touch.kind with
  | Touch info ->
      let finger = { info.finger with x = -2.; y = 16. } in
      check
        (convert touch = Touch { info with finger; dx = -1.; dy = 12. })
        "Normalized touch becomes render position and movement"
  | _ -> assert false);
  let canceled =
    take (function
      | Touch { change = Canceled; _ } -> true
      | _ -> false)
  in
  check
    (to_render_coordinates renderer canceled == canceled)
    "Touch without a window";
  while Option.is_some (poll context) do
    ()
  done

let render_events context window renderer =
  let id = Window.id window in
  push_render_events (Window.id_to_int32 id);
  let window = Some id in
  let open Event in
  List.iteri
    (fun index (window, change) ->
      match poll context with
      | None -> failwith "Missing render event"
      | Some event ->
          let timestamp_ns =
            Int64.add 0x1234_5678_9abc_def0L (Int64.of_int index)
          in
          check
            (event = { timestamp_ns; kind = Render { window; change } })
            "Render event fields";
          check
            (to_render_coordinates renderer event == event)
            "Coordinate conversion leaves render events unchanged")
    [
      (window, Targets_reset);
      (window, Device_reset);
      (window, Device_lost);
      (None, Device_lost);
    ];
  check (poll context = None) "No extra render events"

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

let surface_rgba context =
  let test format expected_alpha =
    using Surface.destroy (Surface.create ~format context ~w:3 ~h:2)
      (fun surface ->
        let output =
          Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout 32
        in
        Bigarray.Array1.fill output 42;
        Surface.fill surface (Color.rgba 7 101 222 13);
        Surface.fill
          ~rect:(Rect.make ~x:0 ~y:1 ~w:3 ~h:1)
          surface (Color.rgba 19 23 31 13);
        invalid (fun () ->
            Surface.read_rgba surface (Bigarray.Array1.sub output 0 23));
        check (output.{0} = 42) "Short RGBA buffer stays unchanged";
        Surface.read_rgba surface (Bigarray.Array1.sub output 4 28);
        let pixel i =
          (output.{i}, output.{i + 1}, output.{i + 2}, output.{i + 3})
        in
        for x = 0 to 2 do
          check
            (pixel (4 + (4 * x)) = (7, 101, 222, expected_alpha))
            "RGBA first row";
          check
            (pixel (16 + (4 * x)) = (19, 23, 31, expected_alpha))
            "RGBA second row"
        done;
        check (pixel 0 = (42, 42, 42, 42)) "RGBA slice starts at its offset";
        check
          (pixel 28 = (42, 42, 42, 42))
          "RGBA copy leaves trailing bytes unchanged";
        Domain.join
          (Domain.spawn (fun () ->
               invalid (fun () -> Surface.read_rgba surface output)));
        Surface.destroy surface;
        invalid (fun () -> Surface.read_rgba surface output))
  in
  test Rgba32 13;
  test Bgra32 13;
  test Rgb24 255

let renderer_views context window =
  let rect x y w h = Rect.make ~x ~y ~w ~h in
  let frect x y w h = Frect.make ~x ~y ~w ~h in
  using Renderer.destroy (Renderer.create ~driver:"software" window)
    (fun renderer ->
      check (Renderer.viewport renderer = rect 0 0 32 24) "Default viewport";
      check (not (Renderer.viewport_is_set renderer)) "Automatic viewport";
      check (Renderer.clip_rect renderer = None) "No clip by default";
      check (Renderer.scale renderer = (1., 1.)) "Default scale";
      check
        (Renderer.logical_presentation_rect renderer = frect 0. 0. 32. 24.)
        "Presentation rectangle without logical sizing";
      let empty = rect (-1) 1 0 5 in
      Renderer.set_viewport renderer (Some empty);
      check
        (Renderer.viewport_is_set renderer && Renderer.viewport renderer = empty)
        "Explicit empty viewport";
      Renderer.set_viewport renderer None;
      Renderer.set_clip_rect renderer (Some empty);
      check (Renderer.clip_rect renderer = Some empty) "Explicit empty clip";
      Renderer.set_clip_rect renderer None;
      check (Renderer.clip_rect renderer = None) "Disabled clip";

      let logical = frect 4. 0. 24. 24. in
      Renderer.set_logical_presentation renderer (Some (12, 12, Letterbox));
      check
        (Renderer.logical_presentation_rect renderer = logical)
        "Letterbox rectangle";
      Renderer.set_scale renderer ~x:2. ~y:0.5;
      check
        (Renderer.scale renderer = (2., 0.5))
        "Scale without the logical multiplier";
      check
        (Renderer.viewport renderer = rect 0 0 6 24)
        "Automatic viewport in render units";
      let viewport = rect 3 2 4 14 and clip = rect (-1) 2 4 6 in
      Renderer.set_viewport renderer (Some viewport);
      Renderer.set_clip_rect renderer (Some clip);
      let roundtrip () =
        let x, y = Renderer.coordinates_from_window renderer ~x:21.5 ~y:14.5 in
        check ((x, y) = (1.375, 12.5)) "Point in render units";
        check
          (Renderer.coordinates_to_window renderer ~x ~y = (21.5, 14.5))
          "Render to window round trip";
        check
          (Renderer.coordinates_from_window renderer ~x:0. ~y:0. = (-4., -2.))
          "Coordinates outside the viewport are not clamped"
      in
      roundtrip ();
      converted_events context window renderer;
      render_events context window renderer;

      let v = version () in
      let old_logical = (v.major, v.minor, v.patch) < (3, 2, 6) in
      using Texture.destroy (Texture.create_target renderer ~w:20 ~h:10)
        (fun target ->
          Renderer.set_target renderer (Some target);
          check
            (Renderer.viewport renderer = rect 0 0 20 10)
            "Texture viewport starts automatic";
          check
            (Renderer.scale renderer = (1., 1.)
            && Renderer.clip_rect renderer = None)
            "Texture has its own scale and clip";
          roundtrip ();
          if old_logical then (
            check
              (Renderer.logical_presentation_rect renderer = logical)
              "Old SDL reports window presentation";
            invalid (fun () ->
                Renderer.set_logical_presentation renderer
                  (Some (10, 5, Stretch))))
          else (
            check
              (Renderer.logical_presentation_rect renderer = frect 0. 0. 20. 10.)
              "Texture presentation size";
            Renderer.set_logical_presentation renderer (Some (5, 5, Letterbox));
            check
              (Renderer.logical_presentation_rect renderer = frect 5. 0. 10. 10.)
              "Texture letterbox rectangle");
          Renderer.set_scale renderer ~x:0.5 ~y:2.;
          let texture_view = rect 1 2 6 10 and texture_clip = rect 0 2 5 3 in
          Renderer.set_viewport renderer (Some texture_view);
          Renderer.set_clip_rect renderer (Some texture_clip);
          roundtrip ();
          Renderer.set_target renderer None;
          check
            (Renderer.viewport renderer = viewport
            && Renderer.clip_rect renderer = Some clip)
            "Window viewport and clip survive switching targets";
          check
            (Renderer.scale renderer = (2., 0.5))
            "Window scale survives switching targets";
          Renderer.set_target renderer (Some target);
          check
            (Renderer.viewport renderer = texture_view
            && Renderer.clip_rect renderer = Some texture_clip
            && Renderer.scale renderer = (0.5, 2.))
            "Texture view survives switching targets";
          Renderer.set_target renderer None);
      roundtrip ();

      List.iter
        (fun rect ->
          invalid (fun () -> Renderer.set_viewport renderer (Some rect));
          invalid (fun () -> Renderer.set_clip_rect renderer (Some rect)))
        [ rect 0 0 (-1) 5; rect 0 0 5 (-1); rect 1_000_000_000 0 5 5 ];
      List.iter
        (fun x -> invalid (fun () -> Renderer.set_scale renderer ~x ~y:1.))
        [ nan; infinity; -1.; 0.; 1e-50; 1e-20; 1e10 ];
      invalid (fun () ->
          Renderer.coordinates_to_window renderer ~x:infinity ~y:0.);
      invalid (fun () -> Renderer.coordinates_from_window renderer ~x:0. ~y:nan);
      invalid (fun () -> Renderer.coordinates_to_window renderer ~x:3e38 ~y:0.);
      check
        (Renderer.viewport renderer = viewport
        && Renderer.clip_rect renderer = Some clip)
        "Rejected settings leave the view unchanged";
      roundtrip ();

      Renderer.set_logical_presentation renderer None;
      Renderer.set_scale renderer ~x:1. ~y:1.;
      let large = rect 200_000_000 0 4 4 in
      Renderer.set_viewport renderer (Some large);
      invalid (fun () -> Renderer.set_scale renderer ~x:4. ~y:1.);
      invalid (fun () ->
          Renderer.set_logical_presentation renderer (Some (2, 2, Stretch)));
      check
        (Renderer.viewport renderer = large
        && Renderer.scale renderer = (1., 1.))
        "Scale checks include the existing viewport";
      Renderer.set_viewport renderer None;
      Renderer.set_clip_rect renderer (Some large);
      invalid (fun () -> Renderer.set_scale renderer ~x:4. ~y:1.);
      check
        (Renderer.clip_rect renderer = Some large)
        "Scale checks include the existing clip";
      Renderer.set_clip_rect renderer None;
      Renderer.set_scale renderer ~x:0.0001 ~y:1.;
      invalid (fun () ->
          Renderer.set_logical_presentation renderer
            (Some (1_000_000, 24, Stretch)));
      Renderer.set_scale renderer ~x:1. ~y:1.;

      Renderer.set_logical_presentation renderer (Some (12, 12, Letterbox));
      Window.set_size window ~w:40 ~h:24;
      check
        (Renderer.logical_presentation_rect renderer = frect 8. 0. 24. 24.)
        "Presentation follows the resized window";
      check
        (Renderer.coordinates_from_window renderer ~x:8. ~y:0. = (0., 0.))
        "Point conversion follows the resized window";
      Window.set_size window ~w:32 ~h:24;

      let quit_event : Event.t = { timestamp_ns = 0L; kind = Quit } in
      let use_renderer () =
        List.iter invalid
          [
            (fun () -> Renderer.set_viewport renderer None);
            (fun () -> ignore (Renderer.viewport renderer));
            (fun () -> ignore (Renderer.viewport_is_set renderer));
            (fun () -> Renderer.set_clip_rect renderer None);
            (fun () -> ignore (Renderer.clip_rect renderer));
            (fun () -> Renderer.set_scale renderer ~x:1. ~y:1.);
            (fun () -> ignore (Renderer.scale renderer));
            (fun () -> ignore (Renderer.logical_presentation_rect renderer));
            (fun () -> ignore (Renderer.name renderer));
            (fun () -> ignore (Renderer.max_texture_size renderer));
            (fun () -> ignore (Renderer.texture_formats renderer));
            (fun () -> ignore (Renderer.vsync renderer));
            (fun () ->
              using Surface.destroy (Renderer.read_pixels renderer) ignore);
            (fun () ->
              ignore (Renderer.coordinates_from_window renderer ~x:1. ~y:2.));
            (fun () ->
              ignore (Renderer.coordinates_to_window renderer ~x:1. ~y:2.));
            (fun () -> ignore (Event.to_render_coordinates renderer quit_event));
          ]
      in
      Domain.join (Domain.spawn use_renderer);
      Renderer.destroy renderer;
      use_renderer ())

let render_view renderer surface =
  let rect x y w h = Rect.make ~x ~y ~w ~h in
  let frect x y w h = Frect.make ~x ~y ~w ~h in
  let black = Color.rgb 0 0 0 and red = Color.rgb 255 0 0 in
  let blue = Color.rgb 0 0 255 in
  let at x y = Surface.read_pixel surface ~x ~y in
  Renderer.set_logical_presentation renderer (Some (8, 8, Stretch));
  Renderer.set_viewport renderer (Some (rect 1 1 4 4));
  Renderer.set_clip_rect renderer (Some (rect 1 1 4 1));
  Renderer.set_scale renderer ~x:1.5 ~y:1.;
  Renderer.set_draw_color renderer black;
  Renderer.clear renderer;
  Renderer.set_draw_color renderer red;
  Renderer.fill_rect renderer (frect (-2.) (-2.) 10. 10.);
  using Surface.destroy (Renderer.read_pixels renderer) (fun pixels ->
      check (Surface.size pixels = (12, 8)) "Read the scaled viewport";
      check
        (Surface.read_pixel pixels ~x:0 ~y:0 = black)
        "Read pixels outside the drawing clip";
      check
        (Surface.read_pixel pixels ~x:3 ~y:2 = red)
        "Read queued drawing without presenting");
  using Surface.destroy
    (Renderer.read_pixels ~rect:(rect 1 3 10 2) renderer)
    (fun pixels ->
      check
        (Surface.size pixels = (8, 2))
        "Clip absolute pixels to the viewport";
      check (Surface.read_pixel pixels ~x:3 ~y:1 = red) "Cropped pixel color");
  sdl_error "SDL_RenderReadPixels" (fun () ->
      using Surface.destroy
        (Renderer.read_pixels ~rect:(rect 0 0 1 1) renderer)
        ignore);
  Renderer.present renderer;
  check (at 6 4 = red && at 14 5 = red) "Scaled clip inside the viewport";
  check (at 5 4 = black && at 6 3 = black && at 6 6 = black) "Clip edges";
  check (at 15 4 = black) "Clip does not extend the viewport";
  check
    (Renderer.coordinates_from_window renderer ~x:6. ~y:4. = (1., 1.))
    "Convert a surface pixel in the active viewport";
  Renderer.set_draw_color renderer blue;
  Renderer.clear renderer;
  Renderer.present renderer;
  check (at 0 0 = blue && at 15 15 = blue) "Clear covers the whole target";
  Renderer.set_clip_rect renderer None;
  Renderer.set_viewport renderer None;
  Renderer.set_scale renderer ~x:1. ~y:1.;
  Renderer.set_logical_presentation renderer None;
  Renderer.set_viewport renderer (Some (rect (-2) 14 6 6));
  using Surface.destroy (Renderer.read_pixels renderer) (fun pixels ->
      check (Surface.size pixels = (4, 2)) "Clip the viewport to the target";
      check (Surface.read_pixel pixels ~x:0 ~y:0 = blue) "Read the visible area");
  Renderer.set_viewport renderer (Some (rect 0 0 0 3));
  sdl_error "SDL_RenderReadPixels" (fun () ->
      using Surface.destroy (Renderer.read_pixels renderer) ignore);
  Renderer.set_viewport renderer None;
  List.iter
    (fun rect ->
      invalid (fun () ->
          using Surface.destroy (Renderer.read_pixels ~rect renderer) ignore))
    [ rect 0 0 0 1; rect 0 0 1 (-1) ];
  if Sys.int_size > 32 then (
    invalid (fun () ->
        using Surface.destroy
          (Renderer.read_pixels ~rect:(rect max_int 0 1 1) renderer)
          ignore);
    let x = Int32.to_int Int32.max_int - 1 in
    sdl_error "SDL_RenderReadPixels" (fun () ->
        using Surface.destroy
          (Renderer.read_pixels ~rect:(rect x 0 3 1) renderer)
          ignore))

let detached_readback context =
  let color = Color.rgba 32 64 96 128 in
  let capture =
    using Surface.destroy (Surface.create context ~w:16 ~h:16) (fun surface ->
        using Renderer.destroy (Renderer.create_software surface)
          (fun renderer ->
            using Texture.destroy (Texture.create_target renderer ~w:7 ~h:5)
              (fun target ->
                Renderer.set_target renderer (Some target);
                Fun.protect
                  ~finally:(fun () -> Renderer.set_target renderer None)
                  (fun () ->
                    Renderer.set_draw_color renderer color;
                    Renderer.clear renderer;
                    Renderer.read_pixels renderer))))
  in
  using Surface.destroy capture (fun pixels ->
      Gc.compact ();
      invalid (fun () -> quit context);
      check (Surface.size pixels = (7, 5)) "Size of texture target readback";
      check
        (Surface.read_pixel pixels ~x:6 ~y:4 = color)
        "Readback keeps its pixels after target and renderer destruction")

let indexed_readback context =
  let red = Color.rgb 255 0 0 and blue = Color.rgb 0 0 255 in
  using Surface.Palette.destroy (Surface.Palette.create context [| red |])
    (fun palette ->
      using Surface.destroy (Surface.create context ~format:Index8 ~w:5 ~h:3)
        (fun surface ->
          Surface.set_palette surface palette;
          using Renderer.destroy (Renderer.create_software surface)
            (fun renderer ->
              Renderer.set_draw_color renderer red;
              Renderer.clear renderer;
              using Surface.destroy (Renderer.read_pixels renderer)
                (fun pixels ->
                  Surface.Palette.set_colors palette ~first:0 [| blue |];
                  check
                    (Surface.read_pixel surface ~x:0 ~y:0 = blue)
                    "Indexed source uses the updated palette";
                  check
                    (Surface.read_pixel pixels ~x:0 ~y:0 = red)
                    "Indexed readback owns a copy of the palette"))))

let render context window =
  sdl_error "SDL_CreateRenderer" (fun () ->
      Renderer.create ~driver:"missing-renderer" window);
  using Renderer.destroy (Renderer.create ~driver:"software" window)
    (fun window_renderer ->
      check
        (Renderer.output_size window_renderer = (32, 24))
        "Window renderer output size";
      check (Renderer.name window_renderer = "software") "Active renderer name";
      check
        (Renderer.max_texture_size window_renderer = None)
        "Software renderer reports no texture limit";
      let formats = Renderer.texture_formats window_renderer in
      check
        (formats <> [] && not (List.mem "SDL_PIXELFORMAT_UNKNOWN" formats))
        "Native texture formats without the sentinel";
      Renderer.set_vsync window_renderer false;
      check (Renderer.vsync window_renderer = 0) "VSync disabled";
      let color = Color.rgb 8 16 32 in
      Renderer.set_draw_color window_renderer color;
      Renderer.clear window_renderer;
      using Surface.destroy (Renderer.read_pixels window_renderer)
        (fun pixels ->
          check (Surface.size pixels = (32, 24)) "Window readback size";
          check
            (Surface.read_pixel pixels ~x:3 ~y:5 = color)
            "Window pixel color");
      Renderer.present window_renderer;
      invalid (fun () -> Window.destroy window);
      using Surface.destroy (Surface.create context ~w:16 ~h:16) (fun target ->
          using Renderer.destroy (Renderer.create_software target)
            (fun renderer ->
              invalid (fun () -> Surface.destroy target);
              render_view renderer target;
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

let mouse context window =
  let open Mouse in
  let x = 7.25 and y = 9.5 in
  let rec drain () = if Event.poll context <> None then drain () in
  drain ();
  check (not (Window.mouse_grab window)) "Initial mouse grab";
  Window.set_mouse_grab window true;
  Window.set_mouse_grab window false;
  check (not (Window.mouse_grab window)) "Released mouse grab";
  sdl_error "SDL_CaptureMouse" (fun () -> capture context true);
  warp_in_window window ~x ~y;
  let snapshot = state context in
  check (snapshot.x = x && snapshot.y = y) "Window mouse position";
  check (not (is_pressed snapshot.buttons Left)) "Mouse button state";
  check
    (global_state context = snapshot)
    "Dummy desktop query uses cached state";
  ignore (relative_state context);
  let rel = relative_state context in
  check (rel.dx = 0. && rel.dy = 0.) "Consumed relative mouse movement";
  check (rel.buttons = snapshot.buttons) "Relative mouse button state";
  List.iter
    (fun bad ->
      invalid (fun () -> warp_in_window window ~x:bad ~y);
      invalid (fun () -> warp_in_window window ~x ~y:bad))
    [ nan; infinity; neg_infinity; Float.max_float; 1e20; -1e20 ];
  check (state context = snapshot) "Invalid warps did not move the mouse";
  let rec motion () =
    match Event.poll context with
    | Some { kind = Mouse_motion { x; y; _ }; _ } -> (x, y)
    | Some _ -> motion ()
    | None -> failwith "Missing mouse warp motion"
  in
  check (motion () = (x, y)) "Mouse warp motion coordinates";
  drain ()

let cursors context =
  let open Mouse.Cursor in
  sdl_error "SDL_CreateSystemCursor" (fun () -> create_system context Pointer);
  let cursor =
    using Surface.destroy (Surface.create context ~w:5 ~h:4) (fun image ->
        Surface.fill image (Color.rgba 16 128 255 128);
        List.iter
          (fun (hot_x, hot_y) ->
            invalid (fun () -> create_color image ~hot_x ~hot_y))
          [ (-1, 0); (5, 0); (0, -1); (0, 4); (max_int, max_int) ];
        Domain.join
          (Domain.spawn (fun () ->
               invalid (fun () -> create_color image ~hot_x:0 ~hot_y:0)));
        create_color image ~hot_x:4 ~hot_y:3)
  in
  using destroy cursor (fun cursor ->
      invalid (fun () -> quit context);
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> set cursor);
             invalid (fun () -> destroy cursor)));
      Gc.compact ();
      check (cursor_is_default ()) "Initial default cursor";
      hide context;
      hide context;
      check (not (visible context)) "Hidden cursor";
      set cursor;
      check (not (cursor_is_default ())) "Selected custom cursor";
      check (not (visible context)) "Selecting a cursor preserves visibility";
      reset context;
      check (cursor_is_default ()) "Reset to the default cursor";
      show context;
      show context;
      check (visible context) "Visible cursor";
      set cursor;
      destroy cursor;
      check (cursor_is_default ())
        "Destroying the active cursor selects the default";
      invalid (fun () -> set cursor));
  using Surface.destroy (Surface.create context ~w:1 ~h:1) (fun image ->
      Surface.destroy image;
      invalid (fun () -> create_color image ~hot_x:0 ~hot_y:0))

let text_input_area window =
  let zero = Rect.make ~x:0 ~y:0 ~w:0 ~h:0 in
  check (Keyboard.text_input_area window = (zero, 0)) "No text input area";
  let area = Rect.make ~x:5 ~y:7 ~w:17 ~h:9 in
  Keyboard.set_text_input_area ~cursor:5 window (Some area);
  Keyboard.start_text_input window;
  Fun.protect
    ~finally:(fun () -> Keyboard.stop_text_input window)
    (fun () ->
      check
        (Keyboard.text_input_area window = (area, 5))
        "Text input area and cursor offset";
      invalid (fun () ->
          Keyboard.set_text_input_area window
            (Some (Rect.make ~x:5 ~y:7 ~w:(-1) ~h:9)));
      if Sys.int_size > 32 then (
        let near_limit = Int64.to_int 0x7fff_fffdL in
        invalid (fun () ->
            Keyboard.set_text_input_area ~cursor:4 window
              (Some (Rect.make ~x:near_limit ~y:7 ~w:1 ~h:9)));
        invalid (fun () ->
            Keyboard.set_text_input_area window
              (Some (Rect.make ~x:5 ~y:near_limit ~w:17 ~h:9))));
      check
        (Keyboard.text_input_area window = (area, 5))
        "Invalid input area leaves SDL state unchanged";
      let caret = Rect.make ~x:10 ~y:9 ~w:0 ~h:6 in
      Keyboard.set_text_input_area window (Some caret);
      check
        (Keyboard.text_input_area window = (caret, 0))
        "A narrow input area and the default cursor";
      Keyboard.set_text_input_area ~cursor:12 window None;
      check
        (Keyboard.text_input_area window = (zero, 0))
        "Clearing the text input area resets the cursor")

let clipboard context =
  Clipboard.set_text context "";
  check (not (Clipboard.has_text context)) "No clipboard text";
  check (Clipboard.get_text context = "") "Empty clipboard read";
  let text = "Épisode\nمرحبا 🙂" in
  Clipboard.set_text context text;
  check (Clipboard.has_text context) "Clipboard has text";
  invalid (fun () -> Clipboard.set_text context "abc\000def");
  invalid (fun () -> Clipboard.set_text context "\xc3");
  let saved = Clipboard.get_text context in
  check (saved = text) "Clipboard round trip after rejected writes";
  Clipboard.set_text context "new content";
  check (Clipboard.get_text context = "new content") "Replace clipboard text";
  Clipboard.set_text context "";
  Gc.compact ();
  check (saved = text) "Clipboard reads keep an independent copy";
  check (not (Clipboard.has_text context)) "Clear clipboard text";
  check (Clipboard.get_text context = "") "Read the cleared clipboard"

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
  check (List.mem "software" (Renderer.drivers ())) "Render drivers before init";
  let start = Timer.ticks_ns () in
  Timer.delay_ns 1_000_000L;
  check (Int64.sub (Timer.ticks_ns ()) start >= 1_000_000L) "Nanosecond timer";
  check (Timer.ticks_ms () >= 1L) "Millisecond timer";
  invalid (fun () -> Timer.delay_ns (-1L));
  invalid (fun () -> Color.rgba 0 256 0 0);
  with_init [ Video; Audio; Gamepad ] (fun context ->
      invalid (fun () -> init []);
      invalid (fun () -> Surface.create context ~w:0 ~h:1);
      surface_rgba context;
      detached_readback context;
      indexed_readback context;
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
          text_input_area window;
          renderer_views context window;
          render context window;
          mouse context window;
          Window.destroy window;
          reject_mouse_window window;
          reject_text_input_area window);
      clipboard context;
      gamepads context;
      gpu_without_backend context;
      audio context;
      cursors context);
  let context = init [] in
  invalid (fun () -> Gpu.create_device context [ Spirv ]);
  invalid (fun () -> Display.list context);
  invalid (fun () -> Touch.devices context);
  invalid (fun () -> Gamepad.list context);
  reject_mouse_context context;
  reject_clipboard context;
  using Surface.destroy (Surface.create context ~w:1 ~h:1) (fun image ->
      invalid (fun () -> Mouse.Cursor.create_color image ~hot_x:0 ~hot_y:0));
  quit context;
  quit context;
  reject_mouse_context context;
  reject_clipboard context;
  invalid (fun () -> Display.primary context);
  invalid (fun () -> Touch.devices context);
  invalid (fun () -> Gamepad.list context);
  invalid (fun () -> Surface.create context ~w:1 ~h:1);
  invalid (fun () -> Gpu.supports_shader_formats context [ Spirv ]);
  let next = init [] in
  quit context;
  quit next
