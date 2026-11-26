open Sdl3_mixer

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Sdl3.Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) scope body = scope body
let spec = Sdl3.Audio.{ format = S16; channels = 1; frequency = 48_000 }

let write_wav ?title ?(frequency = spec.frequency) path frames =
  let length = frames * 2 in
  let title_bytes =
    match title with
    | None -> 0
    | Some text -> String.length text + 1
  in
  let title_padded = title_bytes + (title_bytes mod 2) in
  let list_size = if title_bytes = 0 then 0 else 20 + title_padded in
  let data = Bytes.make (44 + length + list_size) '\000' in
  let str pos s = Bytes.blit_string s 0 data pos (String.length s) in
  let i16 = Bytes.set_int16_le data
  and i32 pos n = Bytes.set_int32_le data pos (Int32.of_int n) in
  str 0 "RIFF";
  i32 4 (36 + length + list_size);
  str 8 "WAVEfmt ";
  i32 16 16;
  (* PCM format chunk length *)
  i16 20 1;
  i16 22 spec.channels;
  i32 24 frequency;
  i32 28 (frequency * 2);
  i16 32 2;
  (* Bytes per frame *)
  i16 34 16;
  str 36 "data";
  i32 40 length;
  for i = 0 to frames - 1 do
    i16 (44 + (i * 2)) (if i < frames / 2 then 4096 else 8192)
  done;
  Option.iter
    (fun title ->
      let offset = 44 + length in
      str offset "LIST";
      i32 (offset + 4) (12 + title_padded);
      str (offset + 8) "INFOINAM";
      i32 (offset + 16) title_bytes;
      str (offset + 20) title)
    title;
  Out_channel.with_open_bin path (fun ch -> Out_channel.output_bytes ch data)

let audio_title context =
  using Sys.remove (Filename.temp_file "sdl3-mixer-title" ".wav") (fun path ->
      write_wav ~title:"Étude" path 96;
      let title =
        using Audio.destroy (Audio.load context path) (fun audio ->
            Domain.join
              (Domain.spawn (fun () -> invalid (fun () -> Audio.title audio)));
            let title = Audio.title audio in
            Audio.destroy audio;
            invalid (fun () -> Audio.title audio);
            title)
      in
      check (title = Some "Étude") "Copy the WAV title before the audio closes";
      write_wav ~title:"" path 96;
      using Audio.destroy (Audio.load context path) (fun audio ->
          check (Audio.title audio = None) "Empty WAV title"))

let selected_device () =
  let old_id =
    Sdl3.with_init [ Sdl3.Audio ] (fun sdl ->
        let id =
          match Sdl3.Audio.Device.list_playback sdl with
          | [ device ] -> device
          | _ -> failwith "Expected one dummy playback device"
        in
        with_init sdl (fun context ->
            using Mixer.destroy (Mixer.create_device ~device:id ~spec context)
              (fun mixer -> Mixer.set_gain mixer 0.5));
        id)
  in
  Sdl3.with_init [ Sdl3.Audio ] (fun sdl ->
      with_init sdl (fun context ->
          sdl_error "MIX_CreateMixerDevice" (fun () ->
              Mixer.create_device ~device:old_id context |> Mixer.destroy)))

let sample buffer i =
  let a = Bigarray.Array1.get buffer (i * 2)
  and b = Bigarray.Array1.get buffer ((i * 2) + 1) in
  if Sys.big_endian then (a lsl 8) lor b else (b lsl 8) lor a

let track_controls mixer track buffer =
  check (Track.frequency_ratio track = 1.) "Default track speed";
  Track.set_frequency_ratio track 2.;
  check (Track.frequency_ratio track = 2.) "Change track speed";
  Track.set_frequency_ratio track 0.01;
  Track.frequency_ratio track |> Track.set_frequency_ratio track;
  List.iter
    (fun ratio -> invalid (fun () -> Track.set_frequency_ratio track ratio))
    [ -1.; 0.; 0.001; 101.; nan; infinity ];
  Track.set_frequency_ratio track 1.;
  invalid (fun () -> Track.play ~loops:(-2) track);
  invalid (fun () -> Track.set_loops track (-2));
  List.iter
    (fun frame ->
      invalid (fun () -> Track.play ~start_frame:frame track);
      invalid (fun () -> Track.seek track frame))
    [ -1L; 97L; Int64.max_int ];
  List.iter
    (fun frames ->
      invalid (fun () -> Track.play ~fade_in_frames:frames track);
      invalid (fun () -> Track.stop ~fade_frames:frames track))
    [ -1L; 2_147_483_648L ];
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Track.position track);
         invalid (fun () -> Track.set_loops track 0)));
  let chunk = Bigarray.Array1.sub buffer 0 8 in
  let generate () =
    check (Mixer.generate mixer chunk = 8) "Mix four input frames"
  in
  Track.play track;
  generate ();
  Track.stop track;
  Track.play ~loops:1 ~start_frame:48L ~fade_in_frames:8L track;
  check (Track.position track = 48L) "Start at the requested frame";
  check (Track.loops track = 1) "Set loops at play";
  check (Track.fade_frames track = 8L) "Begin fade-in";
  generate ();
  check (Track.position track = 52L) "Advance input position";
  check (Track.fade_frames track = 4L) "Advance fade-in";
  check (sample chunk 0 = 0 && sample chunk 3 > 0) "Fade in from silence";
  generate ();
  check (Track.fade_frames track = 0L) "Finish fade-in";
  generate ();
  check (abs (sample chunk 0 - 4096) <= 1) "Play the second half of the WAV";
  Track.pause track;
  Track.seek track 8L;
  Track.set_loops track (-1);
  check (Track.loops track = -1) "Change to infinite loops while paused";
  Track.set_loops track 0;
  check (Track.loops track = 0) "Disable the remaining loops";
  check (Mixer.generate mixer chunk = 0) "Paused track is silent";
  check (Track.position track = 8L) "Seek while paused";
  Track.resume track;
  generate ();
  check (abs (sample chunk 0 - 2048) <= 1) "Play the first half after seeking";
  Track.stop ~fade_frames:4L track;
  check (Track.fade_frames track = -4L) "Begin fade-out";
  generate ();
  check (sample chunk 0 > sample chunk 3) "Fade out samples";
  check (Track.fade_frames track = 0L) "Finish fade-out";
  check
    ((not (Track.is_playing track)) && Track.loops track = 0)
    "Stop after fade";
  check (Mixer.generate mixer buffer = 0) "No mixed audio after fade"

let pcm bytes =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout bytes

let with_track mixer audio f =
  let@ track = using Track.destroy (Track.create mixer) in
  Track.set_audio track (Some audio);
  f track

let stereo left right = Some Track.{ left; right }
let point x y z = Some Track.{ x; y; z }

let expect_mix mixer buffer expected label =
  check (Mixer.generate mixer buffer = Bigarray.Array1.dim buffer) label;
  List.iteri
    (fun i want ->
      let got = sample buffer i in
      if abs (got - want) > 1 then
        failwith
          (Printf.sprintf "%s: channel %d, expected %d, got %d" label i want got))
    expected

let spatial context audio =
  let@ mixer =
    using Mixer.destroy (Mixer.create context { spec with channels = 2 })
  in
  let@ track = with_track mixer audio in
  let mix = expect_mix mixer (pcm 16) in
  Track.set_stereo track (stereo 1. 0.25);
  Track.play track;
  mix [ 4096; 1024 ] "Set independent stereo gains";
  Track.set_stereo track (stereo 0. 2.);
  List.iter
    (fun gain ->
      invalid (fun () -> Track.set_stereo track (stereo gain 1.));
      invalid (fun () -> Track.set_stereo track (stereo 1. gain)))
    [ -1.; nan; infinity; Float.max_float ];
  mix [ 0; 8192 ] "Set stereo gains during playback";
  Track.set_3d_position track (point 1. 0. 0.);
  mix [ 0; 4096 ] "Pan right in 3D instead of using stereo gains";
  Track.set_3d_position track (point (-1.) 0. 0.);
  mix [ 4096; 0 ] "Pan left in 3D";
  Track.set_3d_position track (point 4. 0. 0.);
  List.iter
    (fun x -> invalid (fun () -> Track.set_3d_position track (point x 0. 0.)))
    [ nan; neg_infinity; Float.max_float; 1e20 ];
  mix [ 0; 1024 ] "Reduce volume as the sound moves away";
  Track.set_stereo track None;
  mix [ 4096; 4096 ] "Disable 3D through set_stereo";
  Track.set_3d_position track (point 0. 8. 0.);
  Track.set_stereo track (stereo 0.5 1.);
  mix [ 2048; 4096 ] "Replace 3D with stereo gains";
  Track.set_3d_position track None;
  mix [ 4096; 4096 ] "Disable stereo through set_3d_position";
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Track.set_stereo track None);
         invalid (fun () -> Track.set_3d_position track None)));
  Track.destroy track;
  invalid (fun () -> Track.set_stereo track None);
  invalid (fun () -> Track.set_3d_position track None)

let spatial_mono_and_surround context audio =
  let@ mono = using Mixer.destroy (Mixer.create context spec) in
  let@ track = with_track mono audio in
  let mix = expect_mix mono (pcm 8) in
  invalid (fun () -> Track.set_stereo track (stereo 1. 0.));
  Track.set_3d_position track (point 0. 2. 0.);
  Track.play track;
  mix [ 2048 ] "Distance reduces volume for mono output";
  Track.set_3d_position track (point 0. 0. 0.);
  mix [ 4096 ] "Moving only on Y can change the distance";
  let@ surround =
    using Mixer.destroy (Mixer.create context { spec with channels = 4 })
  in
  let@ track = with_track surround audio in
  let buffer = pcm 32 in
  Track.set_stereo track (stereo 1. 0.5);
  Track.play track;
  expect_mix surround buffer [ 4096; 2048; 0; 0 ]
    "Force stereo on a surround mixer";
  Track.set_3d_position track (point 1. 0. 0.);
  check (Mixer.generate surround buffer = 32) "Mix at due right";
  let at_right = List.init 4 (sample buffer) in
  Track.set_3d_position track (point 1. 0. 1.5e-7);
  expect_mix surround buffer at_right "Mix near due right on a surround mixer"

let tags context audio =
  let@ mixer = using Mixer.destroy (Mixer.create context spec) in
  let@ music = with_track mixer audio in
  let@ fx = with_track mixer audio in
  let mix = expect_mix mixer (pcm 8) in
  let game = "jeu-été" in
  Track.tag music game;
  Track.tag fx game;
  Track.tag fx game;
  Track.tag fx "effects";
  Track.play music;
  Track.play fx;
  Mixer.set_tag_gain mixer "effects" 0.25;
  mix [ 5120 ] "Change only the effects volume";
  Mixer.pause_tag mixer game;
  check (Track.is_paused music && Track.is_paused fx) "Pause both tagged tracks";
  Mixer.resume_tag mixer "effects";
  mix [ 1024 ] "Resume only the effects";
  Mixer.set_tag_gain mixer game 0.5;
  Mixer.resume_tag mixer game;
  mix [ 4096 ] "Set gain on an overlapping tag, including paused tracks";
  Track.untag fx game;
  Mixer.pause_tag mixer game;
  mix [ 2048 ] "Removing a tag leaves the track gain and playback unchanged";
  Mixer.resume_tag mixer game;
  Mixer.stop_tag mixer "missing";
  Mixer.pause_tag mixer "missing";
  Mixer.resume_tag mixer "missing";
  Mixer.set_tag_gain mixer "missing" 0.;
  mix [ 4096 ] "Tag commands with no matching tracks do nothing";
  List.iter
    (fun tag ->
      invalid (fun () -> Track.tag music tag);
      invalid (fun () -> Track.untag music tag);
      invalid (fun () -> Mixer.set_tag_gain mixer tag 0.);
      invalid (fun () -> Mixer.stop_tag mixer tag);
      invalid (fun () -> Mixer.pause_tag mixer tag);
      invalid (fun () -> Mixer.resume_tag mixer tag))
    [ ""; "prefix\000tail" ];
  List.iter
    (fun gain -> invalid (fun () -> Mixer.set_tag_gain mixer game gain))
    [ -1.; nan; infinity ];
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Track.tag music "effects");
         invalid (fun () -> Mixer.pause_tag mixer game)));
  Mixer.stop_tag mixer game;
  check (not (Track.is_playing music)) "Stop a tagged track at once";
  mix [ 2048 ] "Keep the untagged track playing";
  Track.destroy music;
  invalid (fun () -> Track.untag music game);
  Track.destroy fx;
  Mixer.destroy mixer;
  invalid (fun () -> Mixer.resume_tag mixer game)

let tag_fades context audio =
  let@ path = using Sys.remove (Filename.temp_file "sdl3-mixer-rate" ".wav") in
  write_wav ~frequency:24_000 path 96;
  let@ slower = using Audio.destroy (Audio.load context path) in
  let@ mixer = using Mixer.destroy (Mixer.create context spec) in
  let@ fast = with_track mixer audio in
  let@ slow = with_track mixer slower in
  let tag = "ambience" in
  List.iter
    (fun track ->
      Track.tag track tag;
      Track.play track)
    [ slow; fast ];
  let fade ms a b =
    Mixer.stop_tag ~fade_ms:ms mixer tag;
    check
      (Track.fade_frames fast = a && Track.fade_frames slow = b)
      "A tag fade uses each track's input rate"
  in
  fade 1L (-48L) (-24L);
  fade 2_000L (-96_000L) (-48_000L);
  List.iter
    (fun fade_ms -> invalid (fun () -> Mixer.stop_tag ~fade_ms mixer tag))
    [ -1L; 44_739_243L; Int64.max_int ];
  check
    (Track.fade_frames fast = -96_000L && Track.fade_frames slow = -48_000L)
    "An invalid tag fade does not change any track";
  Mixer.stop_tag mixer tag;
  check (not (Track.is_playing fast || Track.is_playing slow)) "Stop both rates"

let groups context audio =
  let@ mixer = using Mixer.destroy (Mixer.create context spec) in
  let Sdl3.{ major; minor; patch } = version () in
  if (major, minor, patch) < (3, 2, 4) then (
    sdl_error "MIX_CreateGroup" (fun () -> Group.create mixer |> Group.destroy);
    let@ track = with_track mixer audio in
    Track.set_group track None)
  else
    let@ group = using Group.destroy (Group.create mixer) in
    invalid (fun () -> Mixer.destroy mixer);
    let@ other = using Mixer.destroy (Mixer.create context spec) in
    let@ foreign = using Group.destroy (Group.create other) in
    let@ a = with_track mixer audio in
    let@ b = with_track mixer audio in
    let@ c = with_track mixer audio in
    invalid (fun () -> Track.set_group a (Some foreign));
    Domain.join
      (Domain.spawn (fun () ->
           invalid (fun () -> Group.create mixer |> Group.destroy);
           invalid (fun () -> Group.destroy group);
           invalid (fun () -> Track.set_group a (Some group))));
    List.iter
      (fun track ->
        Track.set_group track (Some group);
        Track.play track)
      [ a; b; c ];
    let mix = expect_mix mixer (pcm 8) in
    mix [ 12288 ] "Mix all tracks in a group";
    Track.set_group b None;
    Track.destroy a;
    invalid (fun () -> Track.set_group a None);
    mix [ 8192 ] "Move a track from the middle and destroy its neighbor";
    Group.destroy group;
    Group.destroy group;
    invalid (fun () -> Track.set_group c (Some group));
    mix [ 8192 ] "Destroy a group without interrupting its remaining track"

module Stop_watch = Track.Stop_watch

let notice watch label =
  check (Stop_watch.take watch) label;
  check (not (Stop_watch.take watch)) "Reading the notice clears it"

let stop_watches context audio =
  let@ mixer = using Mixer.destroy (Mixer.create context spec) in
  let@ track = with_track mixer audio in
  let@ other = with_track mixer audio in
  let@ watch = using Stop_watch.close (Track.watch_stops track) in
  invalid (fun () -> Track.watch_stops track |> Stop_watch.close);
  invalid (fun () -> Track.destroy track);
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Track.watch_stops other |> Stop_watch.close);
         invalid (fun () -> Stop_watch.take watch);
         invalid (fun () -> Stop_watch.close watch)));
  let@ other_watch = using Stop_watch.close (Track.watch_stops other) in
  check (not (Stop_watch.take watch)) "A new watch has no notice";
  Track.tag track "dialogue";
  Track.play track;
  Mixer.pause_tag mixer "dialogue";
  check (not (Stop_watch.take watch)) "Pausing does not report a stop";
  Track.stop track;
  Track.play track;
  notice watch "A manual stop survives a restart";
  check (not (Stop_watch.take other_watch)) "A different track has no notice";
  Track.stop track;
  Track.play track;
  Track.stop track;
  notice watch "Two stops give one notice";
  Track.stop track;
  check (not (Stop_watch.take watch)) "Stopping a stopped track gives no notice";
  Gc.compact ();
  Track.play ~loops:1 track;
  check (Mixer.generate mixer (pcm 256) = 256) "Mix through the first loop";
  check (not (Stop_watch.take watch)) "Looping does not report a stop";
  check (Mixer.generate mixer (pcm 512) = 128) "Finish the final loop";
  notice watch "Report the end of playback";
  Track.play track;
  Mixer.stop_tag ~fade_ms:1L mixer "dialogue";
  check (not (Stop_watch.take watch)) "No stop notice at the start of a fade";
  check (Mixer.generate mixer (pcm 256) = 96) "Mix through the fade";
  notice watch "Report a stop after a tag fade";
  Track.play track;
  Mixer.stop_tag mixer "dialogue";
  Track.play track;
  Stop_watch.close watch;
  check (Track.is_playing track) "Closing a watch does not stop playback";
  invalid (fun () -> Stop_watch.take watch);
  let@ fresh = using Stop_watch.close (Track.watch_stops track) in
  Stop_watch.close watch;
  check (not (Stop_watch.take fresh)) "Reopening discards the old notice";
  Track.stop track;
  notice fresh "A new watch works after a stale close";
  Stop_watch.close fresh;
  Track.destroy track;
  invalid (fun () -> Track.watch_stops track |> Stop_watch.close)

let device_watches context audio =
  let@ device = using Mixer.destroy (Mixer.create_device context) in
  let@ track = with_track device audio in
  invalid (fun () -> Track.set_stereo track (stereo 1. 0.));
  Track.set_3d_position track (point 1. 0. 0.);
  let@ watch = using Stop_watch.close (Track.watch_stops track) in
  Track.play track;
  let deadline = Int64.add (Sdl3.Timer.ticks_ms ()) 2000L in
  let rec wait () =
    if not (Stop_watch.take watch) then (
      check (Sdl3.Timer.ticks_ms () < deadline) "Wait for an audio thread stop";
      Sdl3.Timer.delay_ns 1_000_000L;
      wait ())
  in
  wait ();
  check (not (Stop_watch.take watch)) "Device notice is cleared";
  Stop_watch.close watch;
  for i = 1 to 24 do
    let@ _ = using Stop_watch.close (Track.watch_stops track) in
    Track.play track;
    if i mod 2 = 0 then Sdl3.Timer.delay_ns 2_000_000L
  done;
  Track.stop track;
  let@ requested = using Mixer.destroy (Mixer.create_device ~spec context) in
  let@ track = with_track requested audio in
  invalid (fun () -> Track.set_3d_position track (point 0. 0. 0.));
  Track.set_3d_position track None

let routing_and_notices context path =
  let@ audio = using Audio.destroy (Audio.load context path) in
  spatial context audio;
  spatial_mono_and_surround context audio;
  tags context audio;
  tag_fades context audio;
  groups context audio;
  stop_watches context audio;
  device_watches context audio

let () =
  check ((version ()).major = 3) "SDL_mixer version";
  selected_device ();
  Sdl3.with_init [] (fun sdl ->
      with_init sdl (fun context ->
          invalid (fun () -> Sdl3.quit sdl);
          audio_title context;
          using Mixer.destroy (Mixer.create_device context) (fun device ->
              Mixer.set_gain device 0.5);
          using Sys.remove (Filename.temp_file "sdl3-mixer" ".wav") (fun path ->
              write_wav path 96;
              routing_and_notices context path;
              let module Io = Sdl3.Io in
              using Audio.destroy (Audio.load ~predecode:true context path)
                (fun audio ->
                  check (Audio.duration audio = Frames 96L) "WAV file duration";
                  check (Audio.title audio = None) "No WAV title");
              let closed = Io.with_file sdl ~mode:Read path Fun.id in
              invalid (fun () -> Audio.load_io context closed);
              using Mixer.destroy (Mixer.create context spec) (fun mixer ->
                  invalid (fun () -> quit context);
                  using Track.destroy (Track.create mixer) (fun track ->
                      invalid (fun () -> Mixer.destroy mixer);
                      sdl_error "MIX_PlayTrack" (fun () ->
                          Track.play ~start_frame:8L track);
                      sdl_error "MIX_SetTrackPlaybackPosition" (fun () ->
                          Track.seek track 8L);
                      let loaded =
                        Io.with_file sdl ~mode:Read path (fun io ->
                            let audio = Audio.load_io context io in
                            check (Io.size io = 236L) "WAV stream stays open";
                            audio)
                      in
                      using Audio.destroy loaded (fun audio ->
                          check
                            (Audio.duration audio = Frames 96L)
                            "WAV stream duration";
                          Track.set_audio track (Some audio));
                      let buffer =
                        Bigarray.Array1.create Bigarray.int8_unsigned
                          Bigarray.c_layout 128
                      in
                      Track.set_gain track 0.5;
                      Track.play ~loops:1 track;
                      Track.pause track;
                      check (Track.is_paused track) "Pause track";
                      Track.resume track;
                      check (Track.is_playing track) "Resume track";
                      check
                        (Mixer.generate mixer buffer = 128)
                        "Generate audio from retained track input";
                      check
                        (buffer.{0} <> 0 || buffer.{1} <> 0)
                        "Mixed audio is not silent";
                      check
                        (Mixer.generate mixer buffer = 128)
                        "Mix into the second loop";
                      check
                        (Mixer.generate mixer buffer = 128)
                        "Mix the rest of the second loop";
                      Track.stop track;
                      check (not (Track.is_playing track)) "Stop track";
                      check
                        (Mixer.generate mixer buffer = 0)
                        "No mixed audio after stop";
                      check
                        (buffer.{0} = 0 && buffer.{1} = 0)
                        "Silence after stop";
                      track_controls mixer track buffer;
                      Track.destroy track;
                      invalid (fun () -> Track.play track);
                      invalid (fun () -> Track.fade_frames track))))))
