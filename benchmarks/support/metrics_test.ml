open Benchmark_metrics

let check ok message = if not ok then failwith message

let percentile_rank () =
  let values = Float.Array.init 21 (fun i -> float (20 - i)) in
  check (percentiles values 21 = (10., 19., 20.)) "Use nearest-rank percentiles";
  check
    (percentiles values 1 = (20., 20., 20.))
    "One frame supplies all percentiles"

let traced_frames () =
  let record () =
    ignore (Sys.opaque_identity (Bytes.create 1024));
    Gc.minor ();
    2
  in
  let result =
    measure ~frames:4 ~trace_gc:true
      ~poll:(fun () -> true)
      ~record ~present:ignore
  in
  check
    (result.frames = 4 && result.draw_calls = 8)
    "Measure draws in all completed frames";
  check
    (result.allocated_bytes >= 4096.)
    "Count allocations during the measurement";
  (match result.gc_pauses with
  | Unavailable reason -> failwith ("Runtime events are unavailable: " ^ reason)
  | Measured pauses ->
      check
        (pauses.count >= result.frames)
        "Count the forced stop-the-world collections";
      check
        (pauses.total_ms >= pauses.longest_ms && pauses.longest_ms >= 0.)
        "Measure pause lengths");
  for i = 0 to result.frames - 1 do
    let frame = Float.Array.get result.frame_ms i in
    let record = Float.Array.get result.record_ms i in
    let present = Float.Array.get result.present_ms i in
    check
      (record >= 0. && present >= 0.
      && abs_float (frame -. record -. present) < 1e-9)
      "Frame time includes recording and presentation"
  done

let early_stop () =
  let calls = ref 0 in
  let result =
    measure ~frames:4 ~trace_gc:false
      ~poll:(fun () -> !calls < 2)
      ~record:(fun () ->
        incr calls;
        1)
      ~present:ignore
  in
  check
    (result.frames = 2 && result.draw_calls = 2)
    "Report only completed frames";
  check
    (result.gc_pauses = Unavailable "disabled")
    "Do not report pauses without tracing"

let () =
  percentile_rank ();
  traced_frames ();
  early_stop ()
