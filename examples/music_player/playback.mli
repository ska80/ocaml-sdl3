type song = { index : int; title : string }

type status =
  | Empty
  | Unplayable
  | Playing of song
  | Paused of song
  | Finished of song

type t

val with_player : Sdl3.context -> Sdl3_mixer.context -> (t -> 'a) -> 'a
val replace : t -> string list -> unit
val previous : t -> unit
val next : t -> unit
val toggle_pause : t -> unit
val tick : t -> unit
val status : t -> status
val spectrum : t -> Spectrum.t
