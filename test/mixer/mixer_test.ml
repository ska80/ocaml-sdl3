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

let spec = Sdl3.Audio.{ format = S16; channels = 1; frequency = 48_000 }

let write_wav ?title path frames =
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
  i32 24 spec.frequency;
  i32 28 (spec.frequency * 2);
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
