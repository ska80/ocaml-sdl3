# Displays and input

The [`Sdl3` interface](../src/core/sdl3.mli) lists the display, window, touch, gamepad, and event
functions. Read events with `Event.poll` on the main thread.

## Displays and windows

Start SDL with `[Sdl3.Video]`. Use `Display.list` or `Display.primary` to get a display ID. Use the
ID to read the display bounds, modes, and content scale. The content scale tells you how large to
draw interface elements. Use `Window.display_scale` for the scale of a specific window.

A request to move, minimize, maximize, or restore a window can take effect later. Read
`Event.Window` to learn what changed.

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
