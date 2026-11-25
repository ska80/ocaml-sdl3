open Sdl3
open Scope
module Music = Sdl3_mixer

let spec : Audio.spec =
  { format = S16; channels = 2; frequency = Spectrum.sample_rate }

let block_frames = 512
let block_bytes = Spectrum.frames_to_bytes block_frames
let queue_target = 6 * block_bytes

type song = { index : int; title : string }

type status =
  | Empty
  | Unplayable
  | Playing of song
  | Paused of song
  | Finished of song

type t = {
  context : Music.context;
  mixer : Music.Mixer.offline Music.Mixer.t;
  track : Music.Track.t;
  stream : Audio.t;
  pcm : byte_buffer;
  spectrum : Spectrum.t;
  mutable paths : string array;
  mutable status : status;
  mutable draining : bool;
}

let with_player sdl context f =
  let@ mixer = using Music.Mixer.destroy (Music.Mixer.create context spec) in
  let@ track = using Music.Track.destroy (Music.Track.create mixer) in
  let@ stream = using Audio.close (Audio.open_playback sdl spec) in
  f
    {
      context;
      mixer;
      track;
      stream;
      pcm = byte_buffer block_bytes;
      spectrum = Spectrum.create ();
      paths = [||];
      status = Empty;
      draining = false;
    }

let status t = t.status
let spectrum t = t.spectrum

(* Keep a single line of valid UTF-8 and bound the size of its texture. *)
let caption text =
  let length = String.length text in
  let buffer = Buffer.create (min 128 length) in
  let rec copy i count =
    if i < length then (
      if count = 100 then Buffer.add_string buffer "…"
      else
        let d = String.get_utf_8_uchar text i in
        let uchar = Uchar.utf_decode_uchar d in
        let c = Uchar.to_int uchar in
        if c <= 32 || (c >= 127 && c <= 159) || c = 0x2028 || c = 0x2029 then
          Buffer.add_char buffer ' '
        else Buffer.add_utf_8_uchar buffer uchar;
        copy (i + Uchar.utf_decode_length d) (count + 1))
  in
  copy 0 0;
  String.trim (Buffer.contents buffer)

let title audio path =
  match Option.map caption (Music.Audio.title audio) with
  | Some text when text <> "" -> text
  | _ -> (
      match caption (Filename.basename path) with
      | "" -> "Untitled track"
      | name -> name)

let try_track t index =
  let path = t.paths.(index) in
  try
    let@ audio = using Music.Audio.destroy (Music.Audio.load t.context path) in
    let title = title audio path in
    Music.Track.set_audio t.track (Some audio);
    Music.Track.play t.track;
    (* The track retains the audio after we close our handle. *)
    Some { index; title }
  with Error message ->
    Printf.eprintf "Could not play %S: %s\n%!" path message;
    Music.Track.set_audio t.track None;
    None

let rec refill t queued =
  if queued < queue_target && not t.draining then (
    let mixed = Music.Mixer.generate t.mixer t.pcm in
    if mixed > 0 then (
      let chunk =
        if mixed = block_bytes then t.pcm else Bigarray.Array1.sub t.pcm 0 mixed
      in
      Audio.queue t.stream chunk;
      Spectrum.feed t.spectrum chunk ~frames:(mixed / Spectrum.frames_to_bytes 1));
    if not (Music.Track.is_playing t.track) then (
      Audio.flush t.stream;
      t.draining <- true)
    else if mixed > 0 then refill t (queued + mixed))

let start_from t ~index ~step ~otherwise =
  Audio.pause t.stream;
  Audio.clear t.stream;
  Music.Track.stop t.track;
  Music.Track.set_audio t.track None;
  Spectrum.reset t.spectrum;
  t.draining <- false;
  let rec start index =
    if index < 0 || index >= Array.length t.paths then t.status <- otherwise
    else
      match try_track t index with
      | None -> start (index + step)
      | Some song ->
          t.status <- Playing song;
          refill t 0;
          Audio.resume t.stream
  in
  start index

let replace t = function
  | [] -> ()
  | paths ->
      t.paths <- Array.of_list paths;
      start_from t ~index:0 ~step:1 ~otherwise:Unplayable

let previous t =
  match t.status with
  | Playing song | Paused song | Finished song ->
      start_from t
        ~index:(max 0 (song.index - 1))
        ~step:(-1) ~otherwise:(Finished song)
  | Empty | Unplayable -> ()

let next t =
  match t.status with
  | (Playing song | Paused song | Finished song)
    when song.index + 1 < Array.length t.paths ->
      start_from t ~index:(song.index + 1) ~step:1 ~otherwise:(Finished song)
  | _ -> ()

let toggle_pause t =
  match t.status with
  | Playing song ->
      Audio.pause t.stream;
      (* The offline track only advances when we call [refill]. *)
      t.status <- Paused song
  | Paused song ->
      Audio.resume t.stream;
      t.status <- Playing song
  | Finished song ->
      start_from t ~index:song.index ~step:1 ~otherwise:(Finished song)
  | Empty | Unplayable -> ()

let tick t =
  match t.status with
  | Playing song ->
      let queued = Audio.queued_bytes t.stream in
      if t.draining && queued = 0 then
        start_from t ~index:(song.index + 1) ~step:1 ~otherwise:(Finished song)
      else refill t queued
  | Empty | Unplayable | Paused _ | Finished _ -> ()
