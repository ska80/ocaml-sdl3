external version : unit -> Sdl3.version = "osdl_image_version"
external load : Sdl3.context -> string -> Sdl3.Surface.t = "osdl_image_load"

external load_memory : Sdl3.context -> Sdl3.byte_buffer -> Sdl3.Surface.t
  = "osdl_image_load_memory"

external load_texture : Sdl3.Renderer.t -> string -> Sdl3.Texture.t
  = "osdl_image_load_texture"

external save_png : Sdl3.Surface.t -> string -> unit = "osdl_image_save_png"

external save_jpg : ?quality:int -> Sdl3.Surface.t -> string -> unit
  = "osdl_image_save_jpg"
