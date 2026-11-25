open Sdl3_mixer

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let spec = Sdl3.Audio.{ format = S16; channels = 1; frequency = 48_000 }

let write_wav path frames =
  let length = frames * 2 in
  let data = Bytes.make (44 + length) '\000' in
  let str pos s = Bytes.blit_string s 0 data pos (String.length s) in
  let i16 = Bytes.set_int16_le data
  and i32 pos n = Bytes.set_int32_le data pos (Int32.of_int n) in
  str 0 "RIFF";
  i32 4 (36 + length);
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
    i16 (44 + (i * 2)) 4096
  done;
  Out_channel.with_open_bin path (fun ch -> Out_channel.output_bytes ch data)

let () =
  check ((version ()).major = 3) "SDL_mixer version";
  Sdl3.with_init [] (fun sdl ->
      with_init sdl (fun context ->
          invalid (fun () -> Sdl3.quit sdl);
          using Mixer.destroy (Mixer.create_device context) (fun device ->
              Mixer.set_gain device 0.5);
          using Sys.remove (Filename.temp_file "sdl3-mixer" ".wav") (fun path ->
              write_wav path 96;
              let module Io = Sdl3.Io in
              using Audio.destroy (Audio.load ~predecode:true context path)
                (fun audio ->
                  check (Audio.duration audio = Frames 96L) "WAV file duration");
              let closed = Io.with_file sdl ~mode:Read path Fun.id in
              invalid (fun () -> Audio.load_io context closed);
              using Mixer.destroy (Mixer.create context spec) (fun mixer ->
                  invalid (fun () -> quit context);
                  using Track.destroy (Track.create mixer) (fun track ->
                      invalid (fun () -> Mixer.destroy mixer);
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
                      Track.destroy track;
                      invalid (fun () -> Track.play track))))))
