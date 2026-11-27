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

  val set_sdf : t -> bool -> unit
  (** Enable signed distance field (SDF) glyphs on a scalable font. The alpha
      channel holds the signed distance to the glyph edge, not opacity. Use a
      shader to turn it into coverage. This updates texts that use the font. If
      SDL_ttf lacks SDF support, enabling it raises [Sdl3.Error]. *)

  val sdf : t -> bool
  (** Return whether SDF rendering is enabled. It starts disabled. *)

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
  type gpu
  type 'target t

  type winding =
    | Clockwise
    | Counter_clockwise
        (** The order of each GPU triangle's vertices in the plane with Y up. *)

  val create_surface : context -> surface t
  (** Create an engine that can draw to SDL surfaces. *)

  val create_renderer : context -> Sdl3.Renderer.t -> renderer t
  (** Create an engine for this renderer. Destroy the engine before you destroy
      the renderer. *)

  val create_gpu : ?atlas_size:int -> context -> Sdl3.Gpu.device -> gpu t
  (** Create an engine that packs glyphs into square GPU textures. [atlas_size]
      is their width and height in pixels. It defaults to 1024. Use a multiple
      of four from 4 to 16384. Each rendered glyph must fit with one pixel of
      padding. Otherwise preparing the text raises [Sdl3.Error]. The engine
      keeps the device open but does not own it. *)

  val set_gpu_winding : gpu t -> winding -> unit
  (** Set the triangle order for later preparations. This does not change draw
      data you already hold. *)

  val gpu_winding : gpu t -> winding
  (** Return the triangle order. It starts as [Clockwise]. *)

  val destroy : 'target t -> unit
  (** Destroy all text objects from the engine first. For a GPU engine, finish
      recording atlas reads and end the active render pass on its device. *)
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

  val color : 'target t -> Sdl3.Color.t
  (** Read the current color. GPU draw data does not include this color. Pass it
      to the shader if you want to use it. *)

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

  type gpu_coordinates =
    (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
  (** Pairs of 32-bit coordinates, with no padding. *)

  type gpu_indices =
    (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
  (** Zero-based indices for a triangle list. Use [Sdl3.Gpu.Uint32]. *)

  type gpu_image =
    | Alpha  (** The atlas alpha channel holds glyph coverage. *)
    | Color  (** The glyph has its own RGB and alpha data. *)
    | Sdf  (** The atlas alpha channel holds a signed distance. *)

  type gpu_source =
    | Solid  (** Needs no texture, for example for an underline. *)
    | Atlas of {
        texture : Sdl3.Gpu.texture;
        image : gpu_image;
        uv : gpu_coordinates;
      }
        (** A read-only texture and one normalized coordinate pair per vertex.
            Use the coordinates as returned by SDL_ttf when sampling it. *)

  type gpu_sequence = private {
    positions : gpu_coordinates;
    indices : gpu_indices;
    source : gpu_source;
  }
  (** A batch of triangles. Positions use pixels relative to the text's top
      left, with X increasing right and Y increasing up. *)

  type gpu_draw_data
  (** A copy of the geometry and a borrow of the atlas textures for one text. *)

  val gpu_draw_data : Text_engine.gpu t -> gpu_draw_data
  (** Prepare the text and borrow its draw data on the main thread. Do this
      before beginning a render pass on the text's GPU device. If the text needs
      a rebuild, first submit or cancel commands that read an atlas on that
      device. Split text into parts if it needs more than 4096 glyph or fill
      operations. On SDL_ttf 3.2.2, do not mix alpha and SDF glyphs in one text,
      including glyphs from fallback fonts. Empty text gives no sequences.

      There can be one live borrow per text. Release it before editing,
      updating, measuring, or destroying that text. Font changes affect later
      preparations, not this borrow. *)

  val gpu_sequences : gpu_draw_data -> gpu_sequence list
  (** Read the batches in SDL_ttf's draw order. Use the existing GPU buffer and
      sampler APIs to draw them. The bigarrays are independent copies. The
      textures cannot be modified, released, or used in custom 2D renderer
      states. They are valid only while this draw data is live. *)

  val release_gpu_draw_data : gpu_draw_data -> unit
  (** End the borrow. New commands cannot use its textures. The CPU bigarrays
      and any commands already recorded remain valid. Submit or cancel those
      commands before the next atlas update on this device. Calling this again
      does nothing. *)

  val with_gpu_draw_data : Text_engine.gpu t -> (gpu_draw_data -> 'a) -> 'a
  (** Prepare draw data and release it when the function returns or raises. *)
end
