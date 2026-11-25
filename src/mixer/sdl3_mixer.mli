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

  val create_device :
    ?device:Sdl3.Audio.playback Sdl3.Audio.Device.id ->
    ?spec:Sdl3.Audio.spec ->
    context ->
    device t
  (** Send audio to the selected playback device. If you omit [device], use the
      system default. [spec] requests a format for the device. SDL can choose a
      different format. *)

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

  val load_io : ?predecode:bool -> context -> [> `Read ] Sdl3.Io.t -> t
  (** Load all audio data from a seekable stream. The stream stays open. The
      audio does not retain the stream, even when [predecode] is [false]. *)

  val destroy : t -> unit
  val duration : t -> duration
end

module Track : sig
  type t

  val create : 'output Mixer.t -> t
  val destroy : t -> unit
  val set_audio : t -> Audio.t option -> unit

  val play :
    ?loops:int -> ?start_frame:int64 -> ?fade_in_frames:int64 -> t -> unit
  (** Start or restart playback. All options default to zero. [loops] counts
      extra plays. Use [-1] to loop forever. [start_frame] follows the same
      position rules as [seek]. [fade_in_frames] is the number of input frames
      to fade from silence to full volume. The fade limit is 2,147,483,647
      frames.

      If you restart a playing or paused track, SDL can mix samples it already
      decoded at the old position. To discard that input, call [stop] with no
      fade before you restart. *)

  val stop : ?fade_frames:int64 -> t -> unit
  (** Fade to silence over the given number of input frames, then stop. The
      default is zero, which stops at once. The same fade limit applies. *)

  val pause : t -> unit
  val resume : t -> unit
  val is_playing : t -> bool
  val is_paused : t -> bool

  val position : t -> int64
  (** Current position in input frames. If playback pauses or stops, return the
      position where it halted. *)

  val seek : t -> int64 -> unit
  (** Move to a nonnegative position in the input. If the duration is known, the
      position must not exceed it. The decoder must support seeking. A later
      call to [play] resets the position. *)

  val loops : t -> int
  (** Number of extra plays left, or [-1] for an infinite loop. Return zero if
      the track is stopped. *)

  val set_loops : t -> int -> unit
  (** Set the number of extra plays left on a playing or paused track. Use [0]
      to end after the current play or [-1] to loop forever. *)

  val fade_frames : t -> int64
  (** Number of input frames left in a fade. The count is positive for a
      fade-in, negative for a fade-out, and zero if there is no fade. *)

  val set_gain : t -> float -> unit
  val frequency_ratio : t -> float

  val set_frequency_ratio : t -> float -> unit
  (** Change playback speed and pitch. The ratio must be between [0.01] and
      [100.0]. A ratio of [1.0] is normal speed. *)
end
