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
  (** Destroy the tracks and groups before calling [destroy]. *)

  val set_gain : 'output t -> float -> unit

  val set_tag_gain : 'output t -> string -> float -> unit
  (** Replace the gain of each track that has this tag on this mixer. The gain
      must be finite, nonnegative, and fit in a C float. This does not set a
      default for tracks that get the tag later. If no track matches, do
      nothing. Tags must be nonempty UTF-8 strings without NUL bytes. *)

  val stop_tag : ?fade_ms:int64 -> 'output t -> string -> unit
  (** Stop all tracks with this tag on this mixer. The default is zero, which
      stops at once. The time uses milliseconds, not frames. It must be in
      [0, 2_147_483_647_000]. The fade must fit in 2,147,483,647 input frames
      for each track. A paused track does not advance its fade until it resumes.
      If no track matches, do nothing. *)

  val pause_tag : 'output t -> string -> unit
  (** Pause each playing track with this tag on this mixer. *)

  val resume_tag : 'output t -> string -> unit
  (** Resume each paused track with this tag on this mixer. *)

  val generate : offline t -> Sdl3.byte_buffer -> int
  (** Fill the buffer and return the number of mixed bytes, without counting any
      silence SDL adds at the end. The length must contain whole frames. If a
      mix exceeds SDL_mixer's size limit, split it into smaller blocks. *)
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

  val title : t -> string option
  (** Copy the title from the file's metadata. Return [None] if the decoder
      reports no title or an empty title. *)
end

module Group : sig
  (** A mixing group combines its tracks before SDL adds them to the final
      output. It is independent of track tags. *)

  type t

  val create : 'output Mixer.t -> t
  (** Create a group owned by this mixer. Requires SDL_mixer 3.2.4 or later.
      Earlier versions raise {!Sdl3.Error}. *)

  val destroy : t -> unit
  (** Return any assigned tracks to the mixer's default group. Does not stop
      playback. Repeated destruction does nothing. *)
end

module Track : sig
  type t
  type stereo_gains = { left : float; right : float }
  type position_3d = { x : float; y : float; z : float }

  val create : 'output Mixer.t -> t

  val destroy : t -> unit
  (** Close the stop watch, if any, before destroying the track. *)

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

  val set_stereo : t -> stereo_gains option -> unit
  (** Send this track to the front left and right channels with independent
      gains. Use [0.] for silence and [1.] for unchanged volume. Gains must be
      finite, nonnegative, and fit in a C float. Enabling this mode replaces 3D
      positioning and requires a mixer that mixes to memory with at least two
      output channels. [None] disables both modes. *)

  val set_3d_position : t -> position_3d option -> unit
  (** Set a sound position relative to the listener at [(0, 0, 0)]. Positive [x]
      is right, positive [y] is up, and positive [z] is behind the listener. SDL
      mixes the track as mono, chooses the speakers, and reduces volume beyond
      one unit of distance. Mono output only reduces volume with distance.
      Coordinates must be finite and the squared distance must not exceed half
      the largest C float. This mode replaces forced stereo. If the mixer plays
      to a device, create it without [~spec] to use this mode. [None] disables
      both modes. *)

  val tag : t -> string -> unit
  (** Add a tag. A track can have several tags. Adding a duplicate does nothing.
      Tags must be nonempty UTF-8 strings without NUL bytes. *)

  val untag : t -> string -> unit
  (** Remove a tag. If the track does not have the tag, do nothing. This does
      not reset the track's gain or change whether it plays. *)

  val set_group : t -> Group.t option -> unit
  (** Move the track to a group owned by the same mixer. [None] returns it to
      the default group. This does not change the track's tags. *)

  module Stop_watch : sig
    type t

    val take : t -> bool
    (** Read and clear the notice. Several stops between reads give one notice.
        Pausing gives no notice. Restarting does not clear a notice. *)

    val close : t -> unit
    (** Remove the watch and discard its unread notice without stopping the
        track. Repeated calls do nothing. *)
  end

  val watch_stops : t -> Stop_watch.t
  (** Watch future stops due to playback ending or an explicit stop. Only one
      watch can be open per track. Poll it on the main thread. It does not wake
      event waits or report when samples reach the speaker. *)
end
