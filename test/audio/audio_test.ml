open Sdl3

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let using close handle f =
  Fun.protect ~finally:(fun () -> close handle) (fun () -> f handle)

let make_buffer length =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout length

let spec = Audio.{ format = S16; channels = 2; frequency = 22_050 }

let dummy_device context = function
  | [ device ] ->
      check (Audio.Device.name context device <> "") "Dummy device name";
      device
  | _ -> failwith "Expected one dummy audio device"

let playback context device =
  using Audio.close (Audio.open_playback ~device context spec) (fun stream ->
      let buffer = make_buffer 16 in
      Bigarray.Array1.fill buffer 0;
      Audio.queue stream buffer;
      check (Audio.queued_bytes stream = 16) "Selected playback queue";
      invalid (fun () -> quit context))

let wait_for_samples stream =
  let deadline = Int64.add (Timer.ticks_ms ()) 2_000L in
  let rec wait () =
    if Audio.available_bytes stream < 64 then (
      check (Timer.ticks_ms () < deadline) "Timed out waiting for audio";
      Timer.delay_ns 1_000_000L;
      wait ())
  in
  wait ()

let recording ?device context =
  using Audio.close (Audio.open_recording ?device context spec) (fun stream ->
      let buffer = make_buffer 40 in
      let slice = Bigarray.Array1.sub buffer 2 33 in
      let empty = Bigarray.Array1.sub buffer 1 0 in
      Bigarray.Array1.fill buffer 90;
      check (Audio.available_bytes stream = 0) "Recording starts paused";
      check (Audio.read stream slice = 0 && buffer.{2} = 90) "Empty read";
      check (Audio.read stream empty = 0) "Zero-length read";
      invalid (fun () -> Audio.read stream (Bigarray.Array1.sub buffer 1 16));
      invalid (fun () -> quit context);
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> Audio.Device.list_recording context);
             invalid (fun () -> Audio.available_bytes stream);
             invalid (fun () -> Audio.read stream slice);
             invalid (fun () -> Audio.close stream)));
      Audio.resume stream;
      wait_for_samples stream;
      Audio.pause stream;
      Audio.flush stream;
      let available = Audio.available_bytes stream in
      check (available >= 64) "Pause keeps recorded data";
      check (Audio.read stream slice = 32) "Read whole stereo frames";
      check (Audio.available_bytes stream = available - 32) "Read drains queue";
      for i = 0 to Bigarray.Array1.dim buffer - 1 do
        let expected = if i >= 2 && i < 34 then 0 else 90 in
        check (buffer.{i} = expected) "Dummy recording writes silence"
      done;
      Audio.clear stream;
      check (Audio.available_bytes stream = 0) "Clear recording";
      check (Audio.read stream slice = 0) "No more recorded data";
      Audio.close stream;
      invalid (fun () -> Audio.read stream empty);
      invalid (fun () -> Audio.available_bytes stream))

let () =
  let playback_id, recording_id =
    with_init [ Audio ] (fun context ->
        let output = dummy_device context (Audio.Device.list_playback context)
        and input =
          dummy_device context (Audio.Device.list_recording context)
        in
        Gc.full_major ();
        invalid (fun () ->
            Audio.open_recording context { spec with channels = 9 });
        invalid (fun () ->
            Audio.open_recording context { spec with frequency = 0 });
        playback context output;
        recording context;
        recording ~device:input context;
        (output, input))
  in
  using quit (init []) (fun context ->
      invalid (fun () -> Audio.Device.list_playback context);
      invalid (fun () -> Audio.Device.list_recording context);
      invalid (fun () -> Audio.Device.name context playback_id);
      invalid (fun () -> Audio.open_playback context spec);
      invalid (fun () -> Audio.open_recording context spec);
      quit context;
      invalid (fun () -> Audio.Device.list_recording context));
  with_init [ Audio ] (fun context ->
      sdl_error "SDL_GetAudioDeviceName" (fun () ->
          Audio.Device.name context playback_id);
      sdl_error "SDL_OpenAudioDeviceStream" (fun () ->
          Audio.open_playback ~device:playback_id context spec |> Audio.close);
      sdl_error "SDL_OpenAudioDeviceStream" (fun () ->
          Audio.open_recording ~device:recording_id context spec |> Audio.close))
