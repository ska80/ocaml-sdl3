(** SDL3_image does not require separate initialization. Call these functions on
    the main thread, except [version], which is safe on any thread. *)

val version : unit -> Sdl3.version
val load : Sdl3.context -> string -> Sdl3.Surface.t

val load_memory : Sdl3.context -> Sdl3.byte_buffer -> Sdl3.Surface.t
(** Decode the image during this call. The decoder does not retain the buffer.
*)

val load_texture : Sdl3.Renderer.t -> string -> Sdl3.Texture.t
val save_png : Sdl3.Surface.t -> string -> unit

val save_jpg : ?quality:int -> Sdl3.Surface.t -> string -> unit
(** Quality ranges from [0] to [100] and defaults to [90]. *)
