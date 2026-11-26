(** A binding for SDL3_image 3.4.8 or later. SDL3_image does not require
    separate initialization. Call these functions on the main thread, except
    [version], which is safe on any thread. *)

val version : unit -> Sdl3.version
val load : Sdl3.context -> string -> Sdl3.Surface.t

val load_memory : Sdl3.context -> Sdl3.byte_buffer -> Sdl3.Surface.t
(** Decode the image during this call. The decoder does not retain the buffer.
*)

val load_io : [> `Read ] Sdl3.Io.t -> Sdl3.Surface.t
(** Read an image from a seekable stream. The stream stays open and the surface
    does not retain it. *)

val load_texture : Sdl3.Renderer.t -> string -> Sdl3.Texture.t

val load_texture_io : Sdl3.Renderer.t -> [> `Read ] Sdl3.Io.t -> Sdl3.Texture.t
(** Load a texture from a seekable stream. The stream stays open and the texture
    does not retain it. *)

val save_png : Sdl3.Surface.t -> string -> unit

val save_jpg : ?quality:int -> Sdl3.Surface.t -> string -> unit
(** Quality ranges from [0] to [100] and defaults to [90]. *)

val save_png_io : Sdl3.Surface.t -> [> `Write ] Sdl3.Io.t -> unit
(** Write PNG data to the stream. The stream stays open. *)

val save_jpg_io :
  ?quality:int -> Sdl3.Surface.t -> [> `Write ] Sdl3.Io.t -> unit
(** Write JPEG data to the stream. The stream stays open. The quality range and
    default match [save_jpg]. *)

module Animation : sig
  (** An animation owns its decoded frames. Frame indices start at zero. *)

  type t

  val load : Sdl3.context -> string -> t
  (** Decode all frames of an image such as an animated GIF. The supported
      formats depend on the SDL_image build. *)

  val load_io : [> `Read ] Sdl3.Io.t -> t
  (** Decode all frames from the current position in a seekable stream. The
      stream stays open and the animation does not retain it. *)

  val destroy : t -> unit
  (** Free the animation and its decoded frames. Frame copies and textures stay
      open. *)

  val size : t -> int * int
  val frame_count : t -> int

  val frame_delay_ms : t -> index:int -> int
  (** Return SDL_image's display time for the frame in milliseconds. *)

  val copy_frame : t -> index:int -> Sdl3.Surface.t
  (** Copy a frame into a new surface. You can change the pixels and keep the
      surface after destroying the animation. Call [Sdl3.Surface.destroy] when
      done. *)

  val frame_texture : Sdl3.Renderer.t -> t -> index:int -> Sdl3.Texture.t
  (** Upload a frame directly to a new texture. The texture belongs to the
      renderer, not the animation. Call [Sdl3.Texture.destroy] when done. *)
end
