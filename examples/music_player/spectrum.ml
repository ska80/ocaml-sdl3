open Bigarray
module Fft = Fftw3.S

let sample_rate = 48_000
let size = 4096
let hop = size / 2
let band_count = 32
let frames_to_bytes n = n * 4

(* Give each band a share of each bin it overlaps. At the bass end, a band
   can be narrower than a single FFT bin. *)
type band = { first_bin : int; weights : Float.Array.t }

let bin_width = float sample_rate /. float size

let logarithmic_edges =
  Array.init (band_count + 1) (fun i ->
      20. *. (1000. ** (float i /. float band_count)))

let band_between low high =
  let first_bin = max 1 (int_of_float ((low /. bin_width) +. 0.5)) in
  let last_bin =
    min ((size / 2) - 1) (int_of_float ((high /. bin_width) +. 0.5))
  in
  let weights =
    Float.Array.init
      (last_bin - first_bin + 1)
      (fun i ->
        let center = float (first_bin + i) *. bin_width in
        let a = max low (center -. (0.5 *. bin_width)) in
        let b = min high (center +. (0.5 *. bin_width)) in
        max 0. ((b -. a) /. bin_width))
  in
  { first_bin; weights }

let bands =
  Array.init band_count (fun i ->
      band_between logarithmic_edges.(i) logarithmic_edges.(i + 1))

let window =
  Float.Array.init size (fun i ->
      0.5 -. (0.5 *. cos (2. *. Float.pi *. float i /. float size)))

(* One-sided power, corrected for the Hann window and averaged over both
   channels. A full-scale sine in one band on both channels is about 0 dBFS. *)
let power_scale =
  let window_energy =
    Float.Array.fold_left (fun sum w -> sum +. (w *. w)) 0. window
  in
  2. /. (float size *. window_energy)

let level_of_power power =
  if power <= 0. then 0.
  else max 0. (min 1. (1. +. (10. *. log10 power /. 72.)))

type samples = (float, float32_elt, c_layout) Array1.t

type t = {
  left : samples;
  right : samples;
  input : samples;
  output : samples;
  plan : Fft.r2r Fft.plan;
  power : samples;
  levels : samples;
  mutable cursor : int;
  mutable until_fft : int;
}

let create () =
  let input = Fft.Array1.create Fft.float c_layout size in
  let output = Fft.Array1.create Fft.float c_layout size in
  let plan = Fft.Array1.r2r Fft.R2HC ~meas:Fft.Estimate input output in
  let samples n = Array1.create float32 c_layout n in
  let levels = samples band_count in
  Array1.fill levels 0.;
  {
    left = samples size;
    right = samples size;
    input;
    output;
    plan;
    power = samples band_count;
    levels;
    cursor = 0;
    until_fft = size;
  }

let reset t =
  (* The first new window overwrites the ring before we read it. *)
  t.cursor <- 0;
  t.until_fft <- size;
  Array1.fill t.levels 0.

let transform t (ring : samples) =
  for i = 0 to size - 1 do
    let sample = ring.{(t.cursor + i) land (size - 1)} in
    t.input.{i} <- sample *. Float.Array.get window i
  done;
  Fft.exec t.plan

(* R2HC stores the real part at k and the imaginary part at size - k. *)
let band_power (output : samples) { first_bin; weights } =
  let sum = ref 0. in
  for i = 0 to Float.Array.length weights - 1 do
    let k = first_bin + i in
    let re = output.{k} and im = output.{size - k} in
    sum := !sum +. (((re *. re) +. (im *. im)) *. Float.Array.get weights i)
  done;
  !sum

let analyze t =
  transform t t.left;
  for i = 0 to band_count - 1 do
    t.power.{i} <- band_power t.output bands.(i)
  done;
  (* Add power, not samples. Opposite-phase channels do not cancel. *)
  transform t t.right;
  for i = 0 to band_count - 1 do
    let power = t.power.{i} +. band_power t.output bands.(i) in
    t.levels.{i} <- level_of_power (power *. power_scale)
  done

let low, high = if Sys.big_endian then (1, 0) else (0, 1)

let sample_s16 (pcm : Sdl3.byte_buffer) offset =
  let lo = pcm.{offset + low} and hi = pcm.{offset + high} in
  let signed_hi = if hi < 128 then hi else hi - 256 in
  (signed_hi lsl 8) lor lo

let feed t pcm ~frames =
  if frames < 0 || frames > Array1.dim pcm / frames_to_bytes 1 then
    invalid_arg "Spectrum frame count is outside the audio buffer";
  for i = 0 to frames - 1 do
    let offset = frames_to_bytes i in
    let cursor = t.cursor in
    (* Keep the float conversion in this loop so it need not box each sample. *)
    t.left.{cursor} <- float (sample_s16 pcm offset) *. (1. /. 32768.);
    t.right.{cursor} <- float (sample_s16 pcm (offset + 2)) *. (1. /. 32768.);
    t.cursor <- (cursor + 1) land (size - 1);
    t.until_fft <- t.until_fft - 1;
    if t.until_fft = 0 then (
      analyze t;
      t.until_fft <- hop)
  done

let level t i = t.levels.{i}
