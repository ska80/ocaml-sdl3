type context

external version : unit -> Sdl3.version = "osdl_ttf_version"
external init : Sdl3.context -> context = "osdl_ttf_init"
external quit : context -> unit = "osdl_ttf_quit"

let with_init sdl f =
  let context = init sdl in
  Fun.protect ~finally:(fun () -> quit context) (fun () -> f context)

module Font = struct
  type t
  type mode = Solid | Blended

  external open_ : context -> string -> ptsize:float -> t = "osdl_ttf_font_open"

  external open_io : context -> [> `Read ] Sdl3.Io.t -> ptsize:float -> t
    = "osdl_ttf_font_open_io"

  external close : t -> unit = "osdl_ttf_font_close"
  external set_size : t -> ptsize:float -> unit = "osdl_ttf_font_set_size"
  external height : t -> int = "osdl_ttf_font_height"
  external ascent : t -> int = "osdl_ttf_font_ascent"
  external descent : t -> int = "osdl_ttf_font_descent"
  external line_skip : t -> int = "osdl_ttf_font_line_skip"
  external has_glyph_int : t -> int -> bool = "osdl_ttf_font_has_glyph"

  external measure : ?wrap_width:int -> t -> string -> int * int
    = "osdl_ttf_font_measure"

  external render :
    ?mode:mode ->
    ?wrap_width:int ->
    t ->
    string ->
    Sdl3.Color.t ->
    Sdl3.Surface.t = "osdl_ttf_font_render"

  let has_glyph font u = has_glyph_int font (Uchar.to_int u)
end
