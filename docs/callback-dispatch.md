# Callback dispatch plan

Keep application code on the main thread. Read events and audio through the existing APIs. If an
application needs a mixer stop notice, pass one flag from C to OCaml. This plan does not add new
bindings.

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

Use the existing SDL event queue. Call `Sdl3.Event.poll` on the main thread. The binding copies
supported event data into OCaml values before it returns. Call application handlers in the order
that SDL returns events. Do not install an event watch or add a second queue for this dispatch.

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
needs to remember a stop across a restart, add an optional stop watch. The notice does not say why
the track stopped or when the last sample reaches the speaker. Use the mixer loop controls for
repeats that must not wait for the main thread.

The proposed API inside `Sdl3_mixer.Track` is:

```ocaml
module Stop_watch : sig
  type t

  val take : t -> bool
  val close : t -> unit
end

val watch_stops : t -> Stop_watch.t
```

Each track can have one watch. `take` returns `true` if SDL_mixer reported a stop since registration
or the last `take`. It clears the notice. Pausing does not report a stop. Several stops before one
`take` give one notice.

The watch does not report the order of stops across tracks or wake an SDL event wait. Read it during
the application update.

Allocate a separate C flag before registering `MIX_SetTrackStoppedCallback`. The callback sets the
flag to one with `SDL_SetAtomicInt`. It does not allocate memory, take an application lock, or push
an SDL event. An atomic exchange sets a flag and returns its old value in one operation.  Use the
same function to exchange zero in `take`. A concurrent stop is either included in this read or stays
pending. Separate read and clear calls can lose a stop.

Make the watch a child handle of the track. Reject a second watch and reject track destruction while
the watch is open. Allocate the OCaml handle before you allocate the C flag. Publish the handle only
after registration succeeds. If registration fails, free the C flag and raise `Sdl3.Error`.

On `close`, remove the callback with `MIX_SetTrackStoppedCallback(track, NULL, NULL)` before freeing
the flag. Do not stop playback. If removal fails, keep the watch and flag alive and raise
`Sdl3.Error`. On success, discard any unread notice and release the child handle. Repeated close
calls on the main thread do nothing.

SDL_mixer 3.2.0 and 3.2.4 hold the same track lock when they run the stop callback and when they
replace it. This is the track's output stream lock, not the mixer lock. Successful removal on these
versions waits for the old callback to finish. Consult the source before relying on removal for a
new hook. A Linux probe used `MIX_StopTrack`, offline mixing, and the dummy audio driver with both
mixer versions. It saw calls on the main thread and on the audio thread. Removal waited for a stop
callback that was already running.

## Tests for a stop watch

Extend the native and bytecode mixer tests when adding the watch:

1. Use offline mixing to test the end of playback, manual stop, fade-out, and pause. Test two stops
   before one read and a stop followed by a restart.
2. Use the dummy audio driver to test a stop from SDL's audio thread. Use a deadline instead of a
   fixed sleep to wait for the notice. Repeat removal while the mixer is active.
3. Test duplicate watches, independent tracks, use from the wrong thread, and use after close.
   Make sure that closing the watch lets the track close. Open a new watch with no pending notice.

Run `dune build @install` and `dune runtest`. Repeat the mixer tests on SDL_mixer 3.2.0. Keep the
core package free of any dependency on SDL_mixer.

Source references: [`SDL_events.h`](https://github.com/libsdl-org/SDL/blob/release-3.2.0/include/SDL3/SDL_events.h),
[`SDL_audio.h`](https://github.com/libsdl-org/SDL/blob/release-3.2.0/include/SDL3/SDL_audio.h),
and `TrackStopped` and `MIX_SetTrackStoppedCallback` in SDL_mixer
[3.2.0](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.0/src/SDL_mixer.c) and
[3.2.4](https://github.com/libsdl-org/SDL_mixer/blob/release-3.2.4/src/SDL_mixer.c).
