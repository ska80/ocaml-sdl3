type axis = { limit : int; mutable position : int; mutable step : int }

let axis ~extent ~view ~delta =
  let limit = max 0 (extent - view) in
  { limit; position = limit / 3; step = min delta limit }

let advance axis =
  let next = axis.position + axis.step in
  if next < 0 then (
    axis.position <- -next;
    axis.step <- -axis.step)
  else if next > axis.limit then (
    axis.position <- (2 * axis.limit) - next;
    axis.step <- -axis.step)
  else axis.position <- next

(* Both the viewport and the tile interval have an exclusive end. *)
let visible ~tiles ~tile_size ~offset ~span =
  ( min tiles (offset / tile_size),
    min tiles ((offset + span + tile_size - 1) / tile_size) )

let capacity ~tiles ~tile_size ~span =
  min tiles (1 + ((span + tile_size - 2) / tile_size))
