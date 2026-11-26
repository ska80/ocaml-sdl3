external version : unit -> Sdl3.version = "osdl_image_version"
external version_error : unit -> string option = "osdl_image_version_error"

let () =
  match version_error () with
  | None -> ()
  | Some message -> raise (Sdl3.Error message)

external load : Sdl3.context -> string -> Sdl3.Surface.t = "osdl_image_load"

external load_memory : Sdl3.context -> Sdl3.byte_buffer -> Sdl3.Surface.t
  = "osdl_image_load_memory"

external load_io : [> `Read ] Sdl3.Io.t -> Sdl3.Surface.t = "osdl_image_load_io"

external load_texture : Sdl3.Renderer.t -> string -> Sdl3.Texture.t
  = "osdl_image_load_texture"

external load_texture_io :
  Sdl3.Renderer.t -> [> `Read ] Sdl3.Io.t -> Sdl3.Texture.t
  = "osdl_image_load_texture_io"

external save_png : Sdl3.Surface.t -> string -> unit = "osdl_image_save_png"

external save_jpg : ?quality:int -> Sdl3.Surface.t -> string -> unit
  = "osdl_image_save_jpg"

external save_png_io : Sdl3.Surface.t -> [> `Write ] Sdl3.Io.t -> unit
  = "osdl_image_save_png_io"

external save_jpg_io :
  ?quality:int -> Sdl3.Surface.t -> [> `Write ] Sdl3.Io.t -> unit
  = "osdl_image_save_jpg_io"

module Animation = struct
  type t

  external load : Sdl3.context -> string -> t = "osdl_image_animation_load"
  external load_io : [> `Read ] Sdl3.Io.t -> t = "osdl_image_animation_load_io"
  external destroy : t -> unit = "osdl_image_animation_destroy"
  external size : t -> int * int = "osdl_image_animation_size"
  external frame_count : t -> int = "osdl_image_animation_frame_count"

  external frame_delay_ms : t -> index:int -> int
    = "osdl_image_animation_frame_delay_ms"

  external copy_frame : t -> index:int -> Sdl3.Surface.t
    = "osdl_image_animation_copy_frame"

  external frame_texture : Sdl3.Renderer.t -> t -> index:int -> Sdl3.Texture.t
    = "osdl_image_animation_frame_texture"
end
