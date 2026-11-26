type context

external version : unit -> Sdl3.version = "osdl_mixer_version"
external init : Sdl3.context -> context = "osdl_mixer_init"
external quit : context -> unit = "osdl_mixer_quit"

let with_init sdl f =
  let context = init sdl in
  Fun.protect ~finally:(fun () -> quit context) (fun () -> f context)

module Mixer = struct
  type device
  type offline
  type 'output t

  external create_device :
    ?device:Sdl3.Audio.playback Sdl3.Audio.Device.id ->
    ?spec:Sdl3.Audio.spec ->
    context ->
    device t = "osdl_mixer_create_device"

  external create : context -> Sdl3.Audio.spec -> offline t
    = "osdl_mixer_create"

  external destroy : 'output t -> unit = "osdl_mixer_destroy"
  external set_gain : 'output t -> float -> unit = "osdl_mixer_set_gain"

  external set_tag_gain : 'output t -> string -> float -> unit
    = "osdl_mixer_set_tag_gain"

  external stop_tag : ?fade_ms:int64 -> 'output t -> string -> unit
    = "osdl_mixer_stop_tag"

  external pause_tag : 'output t -> string -> unit = "osdl_mixer_pause_tag"
  external resume_tag : 'output t -> string -> unit = "osdl_mixer_resume_tag"

  external generate : offline t -> Sdl3.byte_buffer -> int
    = "osdl_mixer_generate"
end

module Audio = struct
  type t
  type duration = Unknown | Infinite | Frames of int64

  external load : ?predecode:bool -> context -> string -> t
    = "osdl_mixer_audio_load"

  external load_io : ?predecode:bool -> context -> [> `Read ] Sdl3.Io.t -> t
    = "osdl_mixer_audio_load_io"

  external destroy : t -> unit = "osdl_mixer_audio_destroy"
  external duration : t -> duration = "osdl_mixer_audio_duration"
  external title : t -> string option = "osdl_mixer_audio_title"
end

module Group = struct
  type t

  external create : 'output Mixer.t -> t = "osdl_mixer_group_create"
  external destroy : t -> unit = "osdl_mixer_group_destroy"
end

module Track = struct
  type t
  type stereo_gains = { left : float; right : float }
  type position_3d = { x : float; y : float; z : float }

  external create : 'output Mixer.t -> t = "osdl_mixer_track_create"
  external destroy : t -> unit = "osdl_mixer_track_destroy"

  external set_audio : t -> Audio.t option -> unit
    = "osdl_mixer_track_set_audio"

  external play :
    ?loops:int -> ?start_frame:int64 -> ?fade_in_frames:int64 -> t -> unit
    = "osdl_mixer_track_play"

  external stop : ?fade_frames:int64 -> t -> unit = "osdl_mixer_track_stop"
  external pause : t -> unit = "osdl_mixer_track_pause"
  external resume : t -> unit = "osdl_mixer_track_resume"
  external is_playing : t -> bool = "osdl_mixer_track_playing"
  external is_paused : t -> bool = "osdl_mixer_track_paused"
  external position : t -> int64 = "osdl_mixer_track_position"
  external seek : t -> int64 -> unit = "osdl_mixer_track_seek"
  external loops : t -> int = "osdl_mixer_track_loops"
  external set_loops : t -> int -> unit = "osdl_mixer_track_set_loops"
  external fade_frames : t -> int64 = "osdl_mixer_track_fade_frames"
  external set_gain : t -> float -> unit = "osdl_mixer_track_set_gain"
  external frequency_ratio : t -> float = "osdl_mixer_track_frequency_ratio"

  external set_frequency_ratio : t -> float -> unit
    = "osdl_mixer_track_set_frequency_ratio"

  external set_stereo : t -> stereo_gains option -> unit
    = "osdl_mixer_track_set_stereo"

  external set_3d_position : t -> position_3d option -> unit
    = "osdl_mixer_track_set_3d_position"

  external tag : t -> string -> unit = "osdl_mixer_track_tag"
  external untag : t -> string -> unit = "osdl_mixer_track_untag"

  external set_group : t -> Group.t option -> unit
    = "osdl_mixer_track_set_group"

  module Stop_watch = struct
    type t

    external take : t -> bool = "osdl_mixer_stop_watch_take"
    external close : t -> unit = "osdl_mixer_stop_watch_close"
  end

  external watch_stops : t -> Stop_watch.t = "osdl_mixer_track_watch_stops"
end
