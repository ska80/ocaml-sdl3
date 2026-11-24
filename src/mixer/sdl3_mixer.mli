(** SDL3_mixer uses tracks, not SDL2_mixer channels. Call these functions on the
    main thread, except [version], which is safe on any thread. *)

type context

val version : unit -> Sdl3.version
val init : Sdl3.context -> context

val quit : context -> unit
(** Close the mixers and audio handles before calling [quit]. *)

val with_init : Sdl3.context -> (context -> 'a) -> 'a

module Mixer : sig
  type device
  type offline
  type 'output t

  val create_device : ?spec:Sdl3.Audio.spec -> context -> device t
  (** Send audio to the default playback device. *)

  val create : context -> Sdl3.Audio.spec -> offline t
  (** Mix audio into a memory buffer instead of playing it on a device. *)

  val destroy : 'output t -> unit
  (** Destroy the tracks before calling [destroy]. *)

  val set_gain : 'output t -> float -> unit

  val generate : offline t -> Sdl3.byte_buffer -> int
  (** Fill the buffer and return the number of mixed bytes, without counting any
      silence SDL adds at the end. The length must contain whole frames. *)
end

module Audio : sig
  (** Audio data that tracks can play. A track keeps its own reference. *)

  type t
  type duration = Unknown | Infinite | Frames of int64

  val load : ?predecode:bool -> context -> string -> t
  (** Decode the whole file up front if [predecode] is [true]. The default is
      [false], which lets the mixer decode the data during playback. *)

  val destroy : t -> unit
  val duration : t -> duration
end

module Track : sig
  type t

  val create : 'output Mixer.t -> t
  val destroy : t -> unit
  val set_audio : t -> Audio.t option -> unit

  val play : ?loops:int -> t -> unit
  (** Start or restart playback. [0] plays once and [-1] loops forever. A
      positive number gives the number of extra plays. The default is [0]. *)

  val stop : ?fade_frames:int64 -> t -> unit
  (** Stop after the given number of frames from the input. The default is [0].
  *)

  val pause : t -> unit
  val resume : t -> unit
  val is_playing : t -> bool
  val is_paused : t -> bool
  val set_gain : t -> float -> unit
end
