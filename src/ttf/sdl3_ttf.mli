(** A binding for SDL3_ttf 3.2.2 or later. Load fonts and render UTF-8 text.
    Call these functions on the main thread, except [version] and
    [has_harfbuzz], which are safe on any thread. *)

type context

val version : unit -> Sdl3.version

val has_harfbuzz : unit -> bool
(** Whether SDL_ttf uses HarfBuzz to shape text into positioned glyphs. *)

val init : Sdl3.context -> context

val quit : context -> unit
(** Close the fonts and destroy the text engines before calling [quit]. *)

val with_init : Sdl3.context -> (context -> 'a) -> 'a

type direction = Left_to_right | Right_to_left | Top_to_bottom | Bottom_to_top

module Font : sig
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
  (** Glyph bounds in pixels, with [y] increasing above the baseline. [advance]
      is the distance to the next glyph's origin before kerning. *)

  val open_ : context -> string -> ptsize:float -> t

  val open_io : context -> [> `Read ] Sdl3.Io.t -> ptsize:float -> t
  (** Open a font from the start of a seekable stream. The font uses the stream
      until you close the font. You cannot use or close the stream in that time.
      Do not change a memory stream's backing buffer while the font uses it. The
      caller still owns the stream and must close it after the font. *)

  val close : t -> unit
  (** Destroy all text objects that use this font and remove it from other
      fonts' fallback lists first. This releases its own fallback links but does
      not close those fonts. *)

  val set_size : t -> ptsize:float -> unit
  val height : t -> int
  val ascent : t -> int
  val descent : t -> int
  val line_skip : t -> int

  val has_glyph : t -> Uchar.t -> bool
  (** Test for a glyph in this font or its fallback fonts. *)

  val glyph_metrics : t -> Uchar.t -> glyph_metrics
  (** Read the metrics for one Unicode code point. SDL_ttf searches fallback
      fonts. If none contain the glyph, SDL_ttf uses the missing-glyph shape.
      Use [has_glyph] to distinguish this case. *)

  val glyph_kerning : t -> Uchar.t -> Uchar.t -> int
  (** Read the pixel spacing adjustment for a pair in this font. This does not
      use fallback fonts or the font's kerning setting. It is not a substitute
      for laying out a string. *)

  val set_style : t -> style list -> unit
  (** Replace the added styles. Pass [[]] to reset to the styles built into the
      font. This and the other font setters affect all texts that use it. *)

  val style : t -> style list
  (** Return the active styles, including styles built into the font. *)

  val set_outline : t -> int -> unit
  (** Set the outline thickness in pixels for scalable glyphs. Use a value from
      0 to 32767. Zero removes the outline. *)

  val outline : t -> int

  val set_hinting : t -> hinting -> unit
  (** Choose how SDL_ttf fits glyph outlines to the pixel grid. *)

  val hinting : t -> hinting

  val set_kerning : t -> bool -> unit
  (** Turn automatic spacing adjustments between glyphs on or off. *)

  val kerning : t -> bool

  val set_wrap_alignment : t -> alignment -> unit
  (** Align wrapped lines to the left, center, or right of the text area. *)

  val wrap_alignment : t -> alignment

  val set_direction : t -> direction option -> unit
  (** Set the default direction for this font. [None] lets SDL_ttf choose.
      Without HarfBuzz, only [None] and [Some Left_to_right] are supported. *)

  val direction : t -> direction option

  val set_script : t -> string option -> unit
  (** Set the default script for shaping. Pass a four-letter ISO 15924 code,
      such as ["Arab"], or [None] to let SDL_ttf choose. This needs HarfBuzz. *)

  val script : t -> string option

  val add_fallback : t -> fallback:t -> unit
  (** Use another font for glyphs missing from this font. SDL_ttf tries the
      fallbacks in the order you add them. Match the size, style, and outline.
      Adding the same fallback twice does nothing. A fallback cannot have its
      own fallbacks. Remove the link before closing the fallback font. *)

  val remove_fallback : t -> fallback:t -> unit
  (** Remove a link between two open fonts. Do nothing if it does not exist. *)

  val clear_fallbacks : t -> unit
  (** Remove all of this font's fallback links without closing the fonts. *)

  val measure : ?wrap_width:int -> t -> string -> int * int
  (** Return the width and height in pixels. If [wrap_width] is zero, SDL wraps
      only on newlines. If omitted, SDL does not wrap. *)

  val render :
    ?mode:mode ->
    ?wrap_width:int ->
    t ->
    string ->
    Sdl3.Color.t ->
    Sdl3.Surface.t
  (** Render text into a new surface. The default mode is [Blended], which
      smooths glyph edges. The surface can outlive the font. *)
end

module Text_engine : sig
  (** A text engine prepares character images for a drawing target. *)

  type surface
  type renderer
  type 'target t

  val create_surface : context -> surface t
  (** Create an engine that can draw to SDL surfaces. *)

  val create_renderer : context -> Sdl3.Renderer.t -> renderer t
  (** Create an engine for this renderer. Destroy the engine before you destroy
      the renderer. *)

  val destroy : 'target t -> unit
  (** Destroy all text objects from the engine first. *)
end

module Text : sig
  (** Reusable text for an engine. *)

  type 'target t

  type substring = {
    offset : int;
    length : int;
    line : int;
    rect : Sdl3.Rect.t;
    direction : direction option;
  }
  (** A snapshot of part of the layout. Offsets and lengths count UTF-8 bytes.
      Line indices start at zero. The rectangle is relative to the top left of
      the text. [direction] is [None] if SDL_ttf does not report a direction. *)

  val create : 'target Text_engine.t -> Font.t -> string -> 'target t
  (** Copy a valid UTF-8 string without NUL bytes. The default color is white.
      The font and engine must stay open until you destroy the text. *)

  val destroy : 'target t -> unit

  val string : 'target t -> string
  (** Copy the current string. Later edits do not change the copy. *)

  val set_string : 'target t -> string -> unit
  (** Replace the text with a valid UTF-8 string without NUL bytes. *)

  val insert : 'target t -> offset:int -> string -> unit
  (** Insert valid UTF-8 without NUL bytes at a byte offset. The offset must
      start a Unicode code point or equal the byte length of the text. *)

  val delete : 'target t -> offset:int -> length:int -> unit
  (** Delete [length] bytes at [offset]. The whole range must fit in the text.
      Both ends must be at code point boundaries, including the end of text. *)

  val set_color : 'target t -> Sdl3.Color.t -> unit

  val set_wrap_width : 'target t -> int -> unit
  (** Set a nonnegative line width in pixels. The default is zero, which wraps
      only at newlines. *)

  val set_direction : 'target t -> direction option -> unit
  (** Override the font's direction for this text. [None] uses the font setting.
      See [Font.set_direction] for the limits without HarfBuzz. *)

  val direction : 'target t -> direction option
  (** Return the override or the font setting, not the guessed direction. *)

  val set_script : 'target t -> string option -> unit
  (** Override the font's script with a four-letter ISO 15924 code. Pass [None]
      to use the font setting again. This needs HarfBuzz. *)

  val script : 'target t -> string option
  (** Return the override or the font setting, not the guessed script. *)

  val size : 'target t -> int * int
  (** Return the width and height in pixels. *)

  val update : 'target t -> unit
  (** Prepare the text after a change. Drawing, size, and layout queries also do
      this when needed. *)

  val substring_at : 'target t -> offset:int -> substring
  (** Find the group of glyphs that covers a byte. A ligature is one glyph for
      several code points. The offset must be in the text or equal its byte
      length. If no glyphs cover the offset, return a zero-length position. *)

  val substring_bounds :
    'target t -> offset:int -> length:int -> Sdl3.Rect.t list
  (** Return one rectangle per covered line in line order. The range must fit in
      the text. The rectangles include whole glyph groups that overlap the
      range. A range of zero length returns [[]]. *)

  val hit_test : 'target t -> x:int -> y:int -> substring
  (** Find the substring nearest to a point relative to the top left of the
      text. Points can be outside the text. Very large points or layouts raise
      [Invalid_argument] to avoid overflow in SDL_ttf's distance calculation. *)

  val draw_surface :
    Text_engine.surface t -> Sdl3.Surface.t -> x:int -> y:int -> unit
  (** Draw at a pixel position relative to the surface's top left corner. *)

  val draw_renderer : Text_engine.renderer t -> x:float -> y:float -> unit
  (** Draw at the given position on the engine renderer's current target.
      Coordinates use the renderer's units. *)
end
