open Music_player_support
open Scope

let check condition message = if not condition then failwith message

let peak spectrum =
  let best = ref 0 in
  for i = 1 to Spectrum.band_count - 1 do
    if Spectrum.level spectrum i > Spectrum.level spectrum !best then best := i
  done;
  (!best, Spectrum.level spectrum !best)

let sine hz rate frame = sin (2. *. Float.pi *. hz *. float frame /. float rate)

let stereo_tone bin frames =
  let buffer = byte_buffer (Spectrum.frames_to_bytes frames) in
  let hz = float (bin * Spectrum.sample_rate) /. float Spectrum.size in
  let store offset s =
    let lo = s land 255 and hi = (s lsr 8) land 255 in
    buffer.{offset} <- (if Sys.big_endian then hi else lo);
    buffer.{offset + 1} <- (if Sys.big_endian then lo else hi)
  in
  for i = 0 to frames - 1 do
    let s = int_of_float (16384. *. sine hz Spectrum.sample_rate i) in
    let offset = Spectrum.frames_to_bytes i in
    store offset s;
    store (offset + 2) (-s)
  done;
  (hz, buffer)

let spectrum_test () =
  let open Spectrum in
  let t = create () in
  let silence = byte_buffer (frames_to_bytes size) in
  Bigarray.Array1.fill silence 0;
  let hz, bass = stereo_tone 9 size in
  let expected_band hz =
    int_of_float (float band_count *. log10 (hz /. 20.) /. 3.)
  in
  feed t bass ~frames:(size - 1);
  check (snd (peak t) = 0.) "Wait for a complete FFT window";
  let tail =
    Bigarray.Array1.sub bass (frames_to_bytes (size - 1)) (frames_to_bytes 1)
  in
  feed t tail ~frames:1;
  let first = peak t in
  check
    (fst first = expected_band hz && abs_float (snd first -. 0.9164) < 0.02)
    "Bass peak with opposite-phase stereo samples";
  feed t silence ~frames:(hop - 1);
  check (peak t = first) "Use a 50 percent hop";
  feed t silence ~frames:1;
  check
    (snd (peak t) > 0. && snd (peak t) < snd first)
    "Analyze an overlapping window";
  feed t silence ~frames:hop;
  check (snd (peak t) = 0.) "Silence after a full new window";
  List.iter
    (fun bin ->
      reset t;
      let hz, tone = stereo_tone bin size in
      feed t tone ~frames:size;
      let band, level = peak t in
      check
        (band = expected_band hz && level > 0.89)
        "Tone in the expected frequency band")
    [ 80; 701 ];
  reset t;
  let _, low = stereo_tone 2 size in
  feed t low ~frames:size;
  check
    (level t 0 > 0. && level t 1 > 0.)
    "Share FFT bins across narrow bass bands";
  reset t;
  check (snd (peak t) = 0.) "Clear the spectrum on track changes"

let write_wav path ~hz ~rate ~frames =
  let length = 2 * frames in
  let data = Bytes.create (44 + length) in
  let string offset s = Bytes.blit_string s 0 data offset (String.length s) in
  let u16 = Bytes.set_uint16_le data
  and u32 offset n = Bytes.set_int32_le data offset (Int32.of_int n) in
  string 0 "RIFF";
  u32 4 (36 + length);
  string 8 "WAVEfmt ";
  u32 16 16;
  u16 20 1;
  u16 22 1;
  u32 24 rate;
  u32 28 (rate * 2);
  u16 32 2;
  u16 34 16;
  string 36 "data";
  u32 40 length;
  for i = 0 to frames - 1 do
    Bytes.set_int16_le data
      (44 + (i * 2))
      (int_of_float (16384. *. sine hz rate i))
  done;
  Out_channel.with_open_bin path (fun file ->
      Out_channel.output_bytes file data)

let playback_test () =
  let open Playback in
  let open Sdl3 in
  let@ first =
    using Sys.remove (Filename.temp_file "music-player-low" ".wav")
  in
  let@ second =
    using Sys.remove (Filename.temp_file "music-player-high" ".wav")
  in
  let@ bad =
    using Sys.remove (Filename.temp_file "music-player-empty" ".wav")
  in
  write_wav first ~hz:100. ~rate:48_000 ~frames:9600;
  write_wav second ~hz:8000. ~rate:44_100 ~frames:8820;
  let@ sdl = with_init [ Audio ] in
  let@ mixer = Sdl3_mixer.with_init sdl in
  let@ player = with_player sdl mixer in
  let get () = status player in
  let low = { index = 0; title = Filename.basename first } in
  let high = { index = 2; title = Filename.basename second } in
  let wait_until f message =
    let deadline = Int64.add (Timer.ticks_ns ()) 2_000_000_000L in
    let rec wait () =
      tick player;
      if not (f ()) then (
        check (Timer.ticks_ns () < deadline) message;
        Timer.delay_ns 5_000_000L;
        wait ())
    in
    wait ()
  in
  check (get () = Empty) "Empty playlist";
  replace player [ first; bad; second ];
  check (get () = Playing low) "Start the first track with a file-name title";
  toggle_pause player;
  for _ = 1 to 5 do
    tick player
  done;
  check (get () = Paused low) "Pause the current track";
  toggle_pause player;
  check (get () = Playing low) "Resume the current track";
  wait_until
    (fun () -> snd (peak (spectrum player)) > 0.8)
    "Analyze mixed audio";
  check (fst (peak (spectrum player)) < 10) "Bass in the first track";
  next player;
  check (get () = Playing high) "Skip an unreadable file on next";
  check
    (snd (peak (spectrum player)) = 0.)
    "Discard the previous track's spectrum";
  previous player;
  check (get () = Playing low) "Skip an unreadable file on previous";
  wait_until
    (fun () -> get () = Playing high)
    "Advance when the first track drains";
  wait_until
    (fun () -> snd (peak (spectrum player)) > 0.8)
    "Analyze the resampled track";
  check (fst (peak (spectrum player)) > 24) "Treble in the second track";
  wait_until
    (fun () -> get () = Finished high)
    "Stop at the end of the playlist";
  next player;
  check (get () = Finished high) "Next does not wrap the playlist";
  toggle_pause player;
  check (get () = Playing high) "Replay the last track";
  replace player [ bad ];
  check (get () = Unplayable) "Report a playlist with no playable files";
  replace player [ first ];
  check (get () = Playing low) "Recover on the next drop"

let () =
  match Sys.argv with
  | [| _; "--write-tone"; path |] ->
      write_wav path ~hz:440. ~rate:44_100 ~frames:22_050
  | _ ->
      spectrum_test ();
      playback_test ()
