# Play and record audio

## Choose a device

Start SDL with `[Sdl3.Audio]` to use the [core audio functions](../src/core/sdl3.mli). Use
`Audio.Device.list_playback` or `Audio.Device.list_recording` to find connected devices. Show a
device name with `Audio.Device.name`. A device ID can become invalid when the device disconnects.
Do not save IDs for later runs.

Omit `~device` to let SDL use the system default. To select a device, pass its ID to
`Audio.open_playback`, `Audio.open_recording`, or `Sdl3_mixer.Mixer.create_device`. The ID must
match the stream direction. The mixer accepts only playback devices.

## Queue or read samples

Core streams start paused. Call `Audio.resume` to start playback or recording. A bigarray is a
buffer outside the OCaml heap. Use `Audio.queue` to send samples from a bigarray to a playback
stream. SDL copies samples between its stream and the bigarray. The binding adds no extra copy.

Use `Audio.read` to read into a reusable bigarray. The call returns the number of bytes that SDL
copied. It does not wait for more samples. It returns only whole frames. A frame contains one sample
per channel.

Read regularly while recording. SDL keeps unread samples in memory. To finish a recording, pause it,
call `Audio.flush`, then read the remaining samples. Use `Audio.clear` to discard pending data.
Close the stream with `Audio.close` before you quit SDL. No audio thread calls OCaml.

## Control mixer tracks

Use [`Sdl3_mixer`](../src/mixer/sdl3_mixer.mli) to play and mix tracks. Pass `~start_frame` or
`~fade_in_frames` to `Track.play`. To discard samples that SDL already decoded, call `Track.stop`
with no fade before restarting. Read the current frame with `Track.position`. If the audio decoder
supports seeking, use `Track.seek` to change the position.

Change remaining repeats with `Track.set_loops`. Use `Track.set_frequency_ratio` to change speed and
pitch together. Pass `~fade_frames` to `Track.stop` to fade to silence before stopping.  Use
`Sdl3_mixer.Audio.title` to copy a title from the file's metadata if the decoder reports one.

The [Music Player example](../examples/music_player/README.md) mixes to memory for playback and
frequency analysis.

## Position a sound

Stereo panning changes the balance between left and right. Set both channel gains with
`Track.set_stereo`. A gain of `0.` silences a channel, and `1.` keeps its original volume.  This
mode needs a memory mixer with at least two output channels. For speaker playback, mix to memory and
send that buffer to `Sdl3.Audio.queue`. SDL_mixer cannot safely force stereo when the mixer output
is mono or can switch to mono.

Use `Track.set_3d_position` for a sound that gets quieter with distance. The listener stays at `(0,
0, 0)`. Use coordinates relative to the listener, not positions on the whole map. Positive X points
right, positive Y points up, and negative Z points forward. Choose a scale: volume drops beyond one
unit of distance. A mono output uses distance, but not direction.

```ocaml
let place_sound track ~right ~forward =
  Sdl3_mixer.Track.set_3d_position track
    (Some { x = right; y = 0.; z = -.forward })
```

If you use 3D positions on a device mixer, omit `~spec` when you create it. SDL_mixer can otherwise
use a different number of channels for the speakers and mix buffer. Stereo and 3D modes replace each
other. Pass `None` to either setter to return to normal mixing.

## Control several tracks with a tag

A tag is a name you attach to a track. Give a track several tags if it belongs to more than one
category. For example, give wind the tags `"ambience"` and `"game"`. Use `Mixer.pause_tag` on
`"game"` to pause gameplay sounds without pausing menu music. Use `Mixer.resume_tag` to resume those
tracks.

```ocaml
let lower_ambience mixer wind =
  let open Sdl3_mixer in
  Track.tag wind "ambience";
  Track.tag wind "game";
  Mixer.set_tag_gain mixer "ambience" 0.25
```

Tag gain replaces the gain on tracks that match now. It does not set a default for new tracks.
Removing a tag with `Track.untag` does not reset gain. To stop the current matches at once, use
`Mixer.stop_tag mixer "game"`. For a fade, pass `~fade_ms:200L`. Unlike `Track.stop`, this call uses
milliseconds so that tracks with different sample rates fade for the same time.

## Assign a mixing group

A mixing group combines its tracks before SDL adds their sound to the final output. For group
assignment, use SDL_mixer 3.2.4 or later. Earlier versions can corrupt the list of tracks when a
track moves between groups.

Create a group with `Group.create mixer`. Assign a track from the same mixer with `Track.set_group
track (Some group)`. A track belongs to one group at a time. Pass `None` to return it to the default
group. `Group.destroy` also returns all its members to that group.  Destroy the tracks and groups
before you destroy the mixer. Use tags, not groups, for volume and playback controls.

## Read stop notices on the main thread

Use `Track.watch_stops` if you need to detect a stop even after playback restarts. In your update
loop, call `Track.Stop_watch.take`. If it returns `true`, handle the stop then. The notice does not
say why the track stopped. Several stops between reads give one notice. Pause does not report a
stop.

```ocaml
let with_stop_notices track run =
  let module Track = Sdl3_mixer.Track in
  let watch = Track.watch_stops track in
  Fun.protect
    ~finally:(fun () -> Track.Stop_watch.close watch)
    (fun () -> run (fun () -> Track.Stop_watch.take watch))
```

Inside `run`, call the supplied function from your main-thread update. Close the watch before you
destroy the track. The [dispatch guide](callback-dispatch.md#mixer-stop-notices) explains how C
records the notice without calling OCaml.
