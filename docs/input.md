# Displays and input

The [`Sdl3` interface](../src/core/sdl3.mli) lists the display, window, touch, gamepad, and event
functions. Read events with `Event.poll` on the main thread.

## Displays and windows

Start SDL with `[Sdl3.Video]`. Use `Display.list` or `Display.primary` to get a display ID. Use the
ID to read the display bounds, modes, and content scale. The content scale tells you how large to
draw interface elements. Use `Window.display_scale` for the scale of a specific window.

A request to move, minimize, maximize, or restore a window can take effect later. Read
`Event.Window` to learn what changed.

## Touch

Start SDL with `[Sdl3.Video]`. Use `Touch.devices` to list known touch devices. Use `Touch.fingers`
to copy the active finger positions and pressure. `Event.Touch` reports touches that start, move,
end, or get canceled. A touch event can have no associated window.

## Gamepads

Start SDL with `[Sdl3.Gamepad]`. Use `Gamepad.list` to find connected controllers. Read their names
with `Gamepad.name_for_id` before opening them. Use `Gamepad.has_axis` and `Gamepad.has_button` to
find the controls that SDL maps. Poll for `Event.Gamepad_axis` and `Event.Gamepad_button` to read
changes. Close each open gamepad with `Gamepad.close`.
