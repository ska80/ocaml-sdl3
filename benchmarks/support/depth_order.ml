type t = { depths : int array; ids : int array; next : int array }

let create ~levels count =
  {
    depths = Array.make count 0;
    ids = Array.make count 0;
    next = Array.make levels 0;
  }

let set t id depth = t.depths.(id) <- depth
let depth t id = t.depths.(id)

let sort t =
  let count = Array.length t.depths in
  let levels = Array.length t.next in
  Array.fill t.next 0 levels 0;
  for id = 0 to count - 1 do
    let depth = t.depths.(id) in
    t.next.(depth) <- t.next.(depth) + 1
  done;
  (* Turn each bucket's count into the offset of its first sprite. *)
  let start = ref 0 in
  for depth = 0 to levels - 1 do
    let size = t.next.(depth) in
    t.next.(depth) <- !start;
    start := !start + size
  done;
  (* Visit IDs in ascending order so ties always use the same draw order. *)
  for id = 0 to count - 1 do
    let depth = t.depths.(id) in
    let i = t.next.(depth) in
    t.ids.(i) <- id;
    t.next.(depth) <- i + 1
  done;
  t.ids
