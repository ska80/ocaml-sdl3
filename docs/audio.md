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
pitch together. Pass `~fade_frames` to `Track.stop` to fade to silence before stopping.
