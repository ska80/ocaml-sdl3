# Callback dispatch

Keep application code on the main thread. Poll events and use audio queues. If an application needs
a mixer stop notice, read it from a stop watch.

A callback is a function that SDL calls when something happens. SDL can run a callback on its own
thread or during an SDL call from OCaml. To run OCaml from an SDL thread, the binding must register
that thread with an OCaml domain and acquire its runtime lock. The audio thread can hold an SDL lock
while it waits for the runtime lock. If OCaml waits for the SDL lock, neither thread can
continue. Even without that conflict, a delay in the callback can interrupt playback.

Do not call OCaml from a callback that the bindings give to SDL, even on the main thread. Do not
store OCaml values in the callback's C state. If SDL produces a notice, application code handles it
after an explicit read, outside the SDL call. An exception then returns to the OCaml caller without
crossing an SDL callback.

## Events

Use the existing SDL event queue. Call `Sdl3.Event.poll` on the main thread. If you have no work
while the queue is empty, use `Sdl3.Event.wait_timeout` on that thread. Both calls remove events
from the same queue and copy supported data into OCaml values. Call application handlers in the
order that SDL returns events. Do not install an event watch or add a second queue for this
dispatch.

```ocaml
let dispatch_events sdl ~limit handle =
  if limit < 0 then invalid_arg "Event limit must not be negative";
  let rec loop left =
    if left > 0 then
      match Sdl3.Event.poll sdl with
      | None -> ()
      | Some event ->
          handle event;
          loop (left - 1)
  in
  loop limit
```

The limit caps the number of events per call, not the time spent in a handler. If a handler raises,
the event is already removed. The remaining events stay in SDL's queue for the next poll. Keep the
SDL context open during dispatch. Do not poll it again inside a handler if order matters.

An event filter decides whether SDL adds an event to the queue. A handler that runs after polling
cannot make that decision. The bindings will not expose OCaml event filters. SDL also requires
immediate handling for some mobile application events. Polling does not replace that handling.

## Audio streams

Use the existing playback and recording queues without audio callbacks. For playback, count queued
input bytes with `Audio.queued_bytes` and supply whole frames with `Audio.queue`. Refill before the
queue runs out. A larger queue tolerates longer pauses in the application loop, but adds delay.  The
queued byte count does not measure when a sample reaches the speaker.

For recording, read with `Audio.read` into a reusable buffer. It returns the converted bytes that
fit, without waiting for more samples. `Audio.available_bytes` is a snapshot. Read regularly, or use
`Audio.clear` if the application can drop all pending input. SDL does not cap the recording queue
for the application.

An SDL stream callback can ask for more bytes for the current device request. A later read on the
main thread cannot meet that request. The same rule applies to hooks that change the mix before it
goes to the device. Do not wrap these hooks as deferred OCaml functions. If an application needs
processing at device time, design a separate C path with its own timing and buffer rules.

## Mixer stop notices

Use `Track.is_playing` and `Track.is_paused` if the application only needs the current state. If it
needs to remember a stop across a restart, open a watch with `Sdl3_mixer.Track.watch_stops`. See the
[audio guide](audio.md#read-stop-notices-on-the-main-thread) for an example. The notice does not say
why the track stopped or when the last sample reaches the speaker. Use mixer loops for repeats that
must not wait for the main thread.

Each track can have one watch. `Track.Stop_watch.take` returns `true` if SDL_mixer reported a stop
since registration or the last read. It clears the notice. Pausing does not report a stop. Several
stops before one read give one notice. The watch does not report order across tracks or wake an SDL
event wait. Read it during the application update.

### How the watch works

The binding allocates a C flag before it registers `MIX_SetTrackStoppedCallback`. The callback sets
the flag to one with `SDL_SetAtomicInt`. It does not allocate memory, take an application lock, or
push an SDL event. An atomic exchange sets a flag and returns its old value in one operation. The
read uses the same function to set zero. A stop that happens at the same time is either included in
this read or stays pending.

The watch is a child of the track. The binding rejects a second watch and rejects track destruction
while the watch is open. It allocates the OCaml handle before it allocates the C flag. If
registration fails, it frees the flag and raises `Sdl3.Error`.

On `Track.Stop_watch.close`, the binding removes the callback before it frees the C flag. Playback
continues. If removal fails, the watch stays open and the binding raises `Sdl3.Error`. On success,
it discards any unread notice and releases the child handle. Repeated close calls do nothing.

SDL_mixer 3.2.4 holds the same track lock to run and replace the callback. This lock belongs to the
track's output stream, not the mixer. Successful removal waits for a callback that is already
running. Do not assume this for other hooks without reading the SDL_mixer source.

Run `dune runtest --force test/mixer` for the stop watch tests. They use both mixing to memory and
the dummy audio driver. They also close watches during device playback.

Source references: [`SDL_events.h`](https://github.com/libsdl-org/SDL/blob/release-3.4.16/include/SDL3/SDL_events.h),
[`SDL_audio.h`](https://github.com/libsdl-org/SDL/blob/release-3.4.16/include/SDL3/SDL_audio.h),
and `TrackStopped` and `MIX_SetTrackStoppedCallback` in SDL_mixer
[3.2.4](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c).
