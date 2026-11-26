# Displays and input

The [`Sdl3` interface](../src/core/sdl3.mli) lists the display, window, mouse, touch, gamepad, and
event functions. Read events with `Event.poll` on the main thread.

## Displays and windows

Start SDL with `[Sdl3.Video]`. Use `Display.list` or `Display.primary` to get a display ID. Use the
ID to read the display bounds, modes, and content scale. The content scale tells you how large to
draw interface elements. Use `Window.display_scale` for the scale of a specific window.

A request to move, minimize, maximize, or restore a window can take effect later. Read
`Event.Window` to learn what changed.

Use `Window.set_minimum_size` to keep the window's content area large enough for your controls.
Pass sizes in window coordinates. Set either dimension to zero to remove its limit.

If the windowing system supports icons, pass a surface to `Window.set_icon`. SDL copies the image.
Destroy the source surface after the call.

Borderless fullscreen uses the desktop mode. Exclusive fullscreen can change the display's
resolution or refresh rate. To select an exclusive mode, choose one from `Display.fullscreen_modes`
for `Window.display window`. Pass it as `Some mode` to `Window.set_fullscreen_mode`. To select
borderless fullscreen again, pass `None`. Use `Window.set_fullscreen window true` to enter
fullscreen. Selecting a mode alone does not enter it.

## Wait when idle

Use `Event.wait_timeout` in an idle menu or editor that has no frame to draw. The wait runs on the
main thread. It lets other OCaml threads run. If it returns an event, handle that event before you
read the queue again. The wait already removed it from the queue.

```ocaml
let idle_step context ~handle_event ~on_idle =
  match Sdl3.Event.wait_timeout context ~timeout_ms:250 with
  | Some event -> handle_event event
  | None -> on_idle ()
```

Use a timeout short enough for any work the main thread must do on a schedule. If you need to keep
rendering, use `Event.poll` instead.

## Convert input to drawing coordinates

Window coordinates can differ from the coordinates you use to draw. Use
`Renderer.coordinates_from_window` to map a point into drawing coordinates. Use
`Renderer.coordinates_to_window` for the reverse direction. SDL uses pixel density, logical
presentation, drawing scale, and the [viewport](rendering.md#draw-in-part-of-a-target).

If you poll a mouse, touch, or drop position event, pass it to `Event.to_render_coordinates` to
convert it. Mouse movement also changes units. Touch positions and movement start as fractions of
the window size and become drawing units. Scroll amounts stay unchanged.

Conversion uses the window's view even when a texture target is active. To test a click in a panel,
set the viewport for that panel on the default target before you convert the event. For split-screen
input, start from the same original event for each viewport.

```ocaml
open Sdl3

let clicked_panel renderer window ~w ~h event =
  let window_id = Window.id window in
  match (Event.to_render_coordinates renderer event).kind with
  | Mouse_button { window; down = true; x; y; _ } when window = window_id ->
      x >= 0. && y >= 0. && x < w && y < h
  | _ -> false
```

The conversion does not clamp points to the viewport or clip rectangle. Test the converted point
against the area that accepts input. Events without a matching window stay unchanged.

## Text input and the clipboard

An input method lets a user compose text before it enters a field. Call `Keyboard.start_text_input`
when your field gains focus. Use `Event.Text_editing` for the preview. Insert text into the field
when you receive `Event.Text_input`. Call `Keyboard.stop_text_input` when the field loses focus.

Use `Keyboard.set_text_input_area` so that the system can place suggestions near the field. Pass a
rectangle in window coordinates. Pass `~cursor` as the horizontal distance from its left edge to the
caret, which marks where new text goes. This is not a byte offset. If you draw with a scaled
renderer, use `Renderer.coordinates_to_window` before setting the area. Update it as the caret or
the field moves. Pass `None` to clear the area.

Start SDL with `[Sdl3.Video]` to use `Clipboard`. Use `Clipboard.set_text` to copy UTF-8 text and
`Clipboard.get_text` to paste. Reading returns an independent string. If the system returns no text,
the string is empty. Use `Clipboard.set_text context ""` to clear it. Keep polling events so SDL can
serve clipboard requests from other programs.

If you use SDL_ttf, pass the current byte offset to this function. It inserts the clipboard text and
returns the new offset. See [Edit text and find its bounds](assets.md#edit-text-and-find-its-bounds)
for byte offsets and pointer positions.

```ocaml
let paste_at context text ~offset =
  let contents = Sdl3.Clipboard.get_text context in
  Sdl3_ttf.Text.insert text ~offset contents;
  offset + String.length contents
```

## Read the mouse and track drags

Start SDL with `[Sdl3.Video]`. Poll events before you read `Mouse.state`. It reports the last
position in the window with mouse focus and the pressed buttons. Use `Mouse.is_pressed` to test a
button. If you need desktop coordinates, use `Mouse.global_state`. Some drivers return the same
result as `Mouse.state` because they cannot query the desktop.

For relative movement, such as turning a camera, enable `Mouse.set_relative_mode` on the window.
Read `Mouse.relative_state` to get the movement since the last read. If several parts of your game
need this value, read it once and share the result.

`Event.Window` reports `Mouse_entered` and `Mouse_left`. Use these events to start or stop checking
the pointer near window edges. If you capture the mouse, test its position too. `Focus_lost` reports
loss of keyboard focus instead.

SDL tries to keep sending mouse events to the window during a drag. This is called capture. If you
need explicit capture, call `Mouse.capture context true` while the window has focus. The pointer can
leave the window and the event coordinates stay relative to it. Release capture with `Mouse.capture
context false` when the drag ends or is canceled. If the window loses keyboard focus, cancel the
drag and release capture. Some drivers do not support explicit capture.

Unlike capture, `Window.set_mouse_grab window true` keeps the pointer inside the window. Use
`Mouse.warp_in_window` to request a move within the window. Pass window coordinates, not drawing
coordinates. The move can produce a mouse motion event.

## Set the cursor

Use `Mouse.Cursor.create_system` for styles such as `Crosshair` and `Pointer`. To use your own
image, pass a surface to `Mouse.Cursor.create_color`. The hot spot is the pixel that points at the
target. Measure it from the image's top-left corner.

```ocaml
open Sdl3

let load_cursor context path ~hot_x ~hot_y =
  let image = Surface.load_bmp context path in
  Fun.protect
    ~finally:(fun () -> Surface.destroy image)
    (fun () -> Mouse.Cursor.create_color image ~hot_x ~hot_y)
```

Create each cursor once, then call `Mouse.Cursor.set` when the interaction changes. For example, use
a crosshair while placing a building. Use `Mouse.Cursor.reset` to return to the default.
`Mouse.Cursor.hide` and `Mouse.Cursor.show` change visibility without selecting another cursor.
Destroy your cursors on the main thread before you quit SDL.

## File drops

Poll for `Event.Drop` to read drag and drop events. Collect `File` paths in order between `Begin`
and `Complete`. SDL can also report dropped text and pointer positions. A drop can have no target
window. The paths and text are OCaml strings that you can keep after polling again.

## Touch

Start SDL with `[Sdl3.Video]`. Use `Touch.devices` to list known touch devices. Use `Touch.fingers`
to copy the active finger positions and pressure. `Event.Touch` reports touches that start, move,
end, or get canceled. A touch event can have no associated window.

## Gamepads

Start SDL with `[Sdl3.Gamepad]`. Use `Gamepad.list` to find connected controllers. Read their names
with `Gamepad.name_for_id` before opening them. Use `Gamepad.has_axis` and `Gamepad.has_button` to
find the controls that SDL maps. Poll for `Event.Gamepad_axis` and `Event.Gamepad_button` to read
changes. Close each open gamepad with `Gamepad.close`.

For vibration, call `Gamepad.rumble pad ~low:20_000 ~high:0 ~duration_ms:120`. The intensities
control the low and high frequency motors. A new effect replaces the previous one. To stop both
motors, set both intensities to zero. Keep reading SDL events so SDL can end the effect. If a
controller does not support vibration, SDL can raise `Sdl3.Error`.
