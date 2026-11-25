type t

val sample_rate : int
val size : int
val hop : int
val band_count : int
val frames_to_bytes : int -> int
val create : unit -> t
val reset : t -> unit

val feed : t -> Sdl3.byte_buffer -> frames:int -> unit
(** Analyze the first [frames] of stereo S16 samples in native byte order. *)

val level : t -> int -> float
(** The last level in [0, 1] for a band, starting at the lowest frequency. *)
