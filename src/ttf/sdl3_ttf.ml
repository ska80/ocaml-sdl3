type context

external version : unit -> Sdl3.version = "osdl_ttf_version"
external has_harfbuzz : unit -> bool = "osdl_ttf_has_harfbuzz"
external init : Sdl3.context -> context = "osdl_ttf_init"
external quit : context -> unit = "osdl_ttf_quit"
external version_error : unit -> string option = "osdl_ttf_version_error"

let () =
  match version_error () with
  | None -> ()
  | Some message -> raise (Sdl3.Error message)

let with_init sdl f =
  let context = init sdl in
  Fun.protect ~finally:(fun () -> quit context) (fun () -> f context)

type direction = Left_to_right | Right_to_left | Top_to_bottom | Bottom_to_top

module Font = struct
  type t
  type mode = Solid | Blended
  type style = Bold | Italic | Underline | Strikethrough
  type hinting = Normal | Light | Mono | No_hinting
  type alignment = Left | Center | Right

  type glyph_metrics = {
    min_x : int;
    max_x : int;
    min_y : int;
    max_y : int;
    advance : int;
  }

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

  external glyph_metrics_int : t -> int -> glyph_metrics
    = "osdl_ttf_font_glyph_metrics"

  external glyph_kerning_int : t -> int -> int -> int
    = "osdl_ttf_font_glyph_kerning"

  external set_style : t -> style list -> unit = "osdl_ttf_font_set_style"
  external style : t -> style list = "osdl_ttf_font_style"
  external set_outline : t -> int -> unit = "osdl_ttf_font_set_outline"
  external outline : t -> int = "osdl_ttf_font_outline"
  external set_hinting : t -> hinting -> unit = "osdl_ttf_font_set_hinting"
  external hinting : t -> hinting = "osdl_ttf_font_hinting"
  external set_kerning : t -> bool -> unit = "osdl_ttf_font_set_kerning"
  external kerning : t -> bool = "osdl_ttf_font_kerning"

  external set_wrap_alignment : t -> alignment -> unit
    = "osdl_ttf_font_set_wrap_alignment"

  external wrap_alignment : t -> alignment = "osdl_ttf_font_wrap_alignment"

  external set_direction : t -> direction option -> unit
    = "osdl_ttf_font_set_direction"

  external direction : t -> direction option = "osdl_ttf_font_direction"
  external set_script : t -> string option -> unit = "osdl_ttf_font_set_script"
  external script : t -> string option = "osdl_ttf_font_script"
  external add_fallback : t -> fallback:t -> unit = "osdl_ttf_font_add_fallback"

  external remove_fallback : t -> fallback:t -> unit
    = "osdl_ttf_font_remove_fallback"

  external clear_fallbacks : t -> unit = "osdl_ttf_font_clear_fallbacks"

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
  let glyph_metrics font u = glyph_metrics_int font (Uchar.to_int u)

  let glyph_kerning font previous current =
    glyph_kerning_int font (Uchar.to_int previous) (Uchar.to_int current)
end

module Text_engine = struct
  type surface
  type renderer
  type 'target t

  external create_surface : context -> surface t
    = "osdl_ttf_engine_create_surface"

  external create_renderer : context -> Sdl3.Renderer.t -> renderer t
    = "osdl_ttf_engine_create_renderer"

  external destroy : 'target t -> unit = "osdl_ttf_engine_destroy"
end

module Text = struct
  type 'target t

  type substring = {
    offset : int;
    length : int;
    line : int;
    rect : Sdl3.Rect.t;
    direction : direction option;
  }

  external create_raw : 'target Text_engine.t -> Font.t -> string -> 'target t
    = "osdl_ttf_text_create"

  external destroy : 'target t -> unit = "osdl_ttf_text_destroy"
  external string : 'target t -> string = "osdl_ttf_text_string"

  external set_string_raw : 'target t -> string -> unit
    = "osdl_ttf_text_set_string"

  external insert_raw : 'target t -> offset:int -> string -> unit
    = "osdl_ttf_text_insert"

  external delete : 'target t -> offset:int -> length:int -> unit
    = "osdl_ttf_text_delete"

  let check_utf8 string =
    if not (String.is_valid_utf_8 string) then
      invalid_arg "SDL_ttf text must be valid UTF-8"

  let create engine font string =
    check_utf8 string;
    create_raw engine font string

  let set_string text string =
    check_utf8 string;
    set_string_raw text string

  let insert text ~offset string =
    check_utf8 string;
    insert_raw text ~offset string

  external set_color : 'target t -> Sdl3.Color.t -> unit
    = "osdl_ttf_text_set_color"

  external set_wrap_width : 'target t -> int -> unit
    = "osdl_ttf_text_set_wrap_width"

  external set_direction : 'target t -> direction option -> unit
    = "osdl_ttf_text_set_direction"

  external direction : 'target t -> direction option = "osdl_ttf_text_direction"

  external set_script : 'target t -> string option -> unit
    = "osdl_ttf_text_set_script"

  external script : 'target t -> string option = "osdl_ttf_text_script"
  external size : 'target t -> int * int = "osdl_ttf_text_size"
  external update : 'target t -> unit = "osdl_ttf_text_update"

  external substring_at : 'target t -> offset:int -> substring
    = "osdl_ttf_text_substring_at"

  external substring_bounds :
    'target t -> offset:int -> length:int -> Sdl3.Rect.t list
    = "osdl_ttf_text_substring_bounds"

  external hit_test : 'target t -> x:int -> y:int -> substring
    = "osdl_ttf_text_hit_test"

  external draw_surface :
    Text_engine.surface t -> Sdl3.Surface.t -> x:int -> y:int -> unit
    = "osdl_ttf_text_draw_surface"

  external draw_renderer : Text_engine.renderer t -> x:float -> y:float -> unit
    = "osdl_ttf_text_draw_renderer"
end
