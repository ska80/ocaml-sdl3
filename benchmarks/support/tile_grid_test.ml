open Benchmark_support.Tile_grid

let check condition message = if not condition then failwith message

let visible_intervals () =
  for tile_size = 1 to 8 do
    for tiles = 1 to 16 do
      let extent = tiles * tile_size in
      for span = 1 to extent + 4 do
        let bound = capacity ~tiles ~tile_size ~span in
        for offset = 0 to max 0 (extent - span) do
          let first, stop = visible ~tiles ~tile_size ~offset ~span in
          check
            (0 <= first && first < stop && stop <= tiles)
            "Valid visible interval";
          check (stop - first <= bound) "The batch fits at every camera offset";
          for tile = 0 to tiles - 1 do
            let intersects =
              tile * tile_size < offset + span
              && (tile + 1) * tile_size > offset
            in
            check
              (intersects = (tile >= first && tile < stop))
              "Draw only intersecting tiles"
          done
        done
      done
    done
  done

let camera_bounds () =
  let small = axis ~extent:16 ~view:24 ~delta:7 in
  advance small;
  check (small.position = 0) "A map smaller than the viewport does not scroll";
  let short = axis ~extent:22 ~view:20 ~delta:7 in
  advance short;
  check (short.position = 2) "The step is bounded by the scroll range";
  advance short;
  check (short.position = 0) "The camera bounces at the far edge";
  let wide = axis ~extent:510 ~view:71 ~delta:7 in
  for _ = 1 to 200 do
    advance wide;
    check
      (0 <= wide.position && wide.position <= wide.limit)
      "The camera stays inside the map"
  done

let () =
  visible_intervals ();
  camera_bounds ()
