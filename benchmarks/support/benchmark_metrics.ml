type pauses = { count : int; total_ms : float; longest_ms : float }
type gc_pauses = Measured of pauses | Unavailable of string

type t = {
  frames : int;
  frame_ms : Float.Array.t;
  record_ms : Float.Array.t;
  present_ms : Float.Array.t;
  allocated_bytes : float;
  draw_calls : int;
  gc_pauses : gc_pauses;
  peak_resident_kib : int64 option;
}

let milliseconds ns = Int64.to_float ns *. 1e-6
let elapsed_ms first last = milliseconds (Int64.sub last first)

let proc_field file name =
  let rec find channel =
    match In_channel.input_line channel with
    | None -> None
    | Some line -> (
        match String.index_opt line ':' with
        | Some i when String.trim (String.sub line 0 i) = name ->
            Some
              (String.trim
                 (String.sub line (i + 1) (String.length line - i - 1)))
        | _ -> find channel)
  in
  try In_channel.with_open_text file find with Sys_error _ -> None

let peak_resident_kib () =
  match proc_field "/proc/self/status" "VmHWM" with
  | None -> None
  | Some field -> (
      match String.split_on_char ' ' field with
      | value :: _ -> Int64.of_string_opt value
      | [] -> None)

let cpu_model () = proc_field "/proc/cpuinfo" "model name"

let system_name () =
  try
    match
      In_channel.with_open_text "/proc/sys/kernel/ostype" In_channel.input_line
    with
    | Some name -> name
    | None -> Sys.os_type
  with Sys_error _ -> Sys.os_type

let with_gc_trace enabled f =
  if not enabled then f (Error "disabled")
  else
    let cursor =
      try
        Runtime_events.start ();
        Runtime_events.resume ();
        Ok (Runtime_events.create_cursor None)
      with Failure reason | Sys_error reason ->
        Runtime_events.pause ();
        Error reason
    in
    match cursor with
    | Error _ -> f cursor
    | Ok c ->
        Fun.protect
          ~finally:(fun () ->
            Runtime_events.pause ();
            Runtime_events.free_cursor c)
          (fun () -> f cursor)

let read_gc_pauses cursor ~first ~last =
  let open Runtime_events in
  let start = ref None and gc = ref false and lost = ref false in
  let count = ref 0 and total = ref 0L and longest = ref 0L in
  let runtime_begin _ring stamp = function
    | EV_STW_LEADER ->
        start := Some (Timestamp.to_int64 stamp);
        gc := false
    | EV_MINOR | EV_MAJOR_GC_STW | EV_MAJOR_GC_PHASE_CHANGE -> gc := true
    | _ -> ()
  in
  let runtime_end _ring stamp = function
    | EV_STW_LEADER ->
        (* The benchmark runs on one OCaml domain. Count the whole pause once,
           not each GC phase inside it. Other stop-the-world work is not GC. *)
        (match !start with
        | Some start when !gc ->
            let stop = Timestamp.to_int64 stamp in
            if start >= first && stop <= last then (
              let duration = Int64.sub stop start in
              incr count;
              total := Int64.add !total duration;
              longest := Int64.max !longest duration)
        | _ -> ());
        start := None
    | _ -> ()
  in
  let callbacks =
    Callbacks.create ~runtime_begin ~runtime_end
      ~lost_events:(fun _ _ -> lost := true)
      ()
  in
  (* Stop tracing before reading, so decoding the trace cannot extend it. *)
  pause ();
  while read_poll cursor callbacks None > 0 do () done;
  if !lost then Unavailable "runtime events were overwritten"
  else
    Measured
      {
        count = !count;
        total_ms = milliseconds !total;
        longest_ms = milliseconds !longest;
      }

let measure ~frames ~trace_gc ~poll ~record ~present =
  let frame_ms = Float.Array.make frames 0.
  and record_ms = Float.Array.make frames 0.
  and present_ms = Float.Array.make frames 0. in
  with_gc_trace trace_gc (fun trace ->
      let clock () = Runtime_events.Timestamp.(to_int64 (get_current ())) in
      let draw_calls = ref 0 and measured = ref 0 in
      let initial_bytes = Gc.allocated_bytes () in
      let first = clock () in
      while !measured < frames && poll () do
        let start = Sdl3.Timer.ticks_ns () in
        let calls = record () in
        let queued = Sdl3.Timer.ticks_ns () in
        present ();
        let finished = Sdl3.Timer.ticks_ns () in
        let i = !measured in
        Float.Array.unsafe_set frame_ms i (elapsed_ms start finished);
        Float.Array.unsafe_set record_ms i (elapsed_ms start queued);
        Float.Array.unsafe_set present_ms i (elapsed_ms queued finished);
        draw_calls := !draw_calls + calls;
        incr measured
      done;
      let last = clock () in
      let allocated_bytes = Gc.allocated_bytes () -. initial_bytes in
      let peak_resident_kib = peak_resident_kib () in
      let gc_pauses =
        match trace with
        | Error reason -> Unavailable reason
        | Ok cursor -> read_gc_pauses cursor ~first ~last
      in
      {
        frames = !measured;
        frame_ms;
        record_ms;
        present_ms;
        allocated_bytes;
        draw_calls = !draw_calls;
        gc_pauses;
        peak_resident_kib;
      })

let percentiles values count =
  let sorted = Array.init count (Float.Array.get values) in
  Array.sort Float.compare sorted;
  let percentile p = sorted.((((p * count) + 99) / 100) - 1) in
  (percentile 50, percentile 95, percentile 99)

let print_times label values count =
  let p50, p95, p99 = percentiles values count in
  Printf.printf "%s (ms): p50=%.3f p95=%.3f p99=%.3f\n" label p50 p95 p99

let print t =
  print_times "CPU frame time" t.frame_ms t.frames;
  print_times "Scene update and draw recording" t.record_ms t.frames;
  print_times "Present call (includes any driver wait)" t.present_ms t.frames;
  print_endline "GPU frame time: unavailable";
  Printf.printf "OCaml allocations: %.1f bytes/frame\n"
    (t.allocated_bytes /. float t.frames);
  (match t.gc_pauses with
  | Measured { count; total_ms; longest_ms } ->
      Printf.printf
        "GC stop-the-world pauses: %d, total %.3f ms, longest %.3f ms\n" count
        total_ms longest_ms
  | Unavailable reason ->
      Printf.printf "GC stop-the-world pauses: unavailable (%s)\n" reason);
  (match t.peak_resident_kib with
  | Some kib ->
      Printf.printf "Peak resident process memory: %.1f MiB\n"
        (Int64.to_float kib /. 1024.)
  | None -> print_endline "Peak resident process memory: unavailable");
  print_endline "GPU memory: unavailable";
  Printf.printf "Binding draw calls: %d (%.1f/frame)\n" t.draw_calls
    (float t.draw_calls /. float t.frames);
  print_endline "Backend draw calls: unavailable"
