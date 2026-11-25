(** Load fonts and render UTF-8 text. Call these functions on the main thread,
    except [version], which is safe on any thread. *)

type context

val version : unit -> Sdl3.version
val init : Sdl3.context -> context

val quit : context -> unit
(** Close the fonts and destroy the text engines before calling [quit]. *)

val with_init : Sdl3.context -> (context -> 'a) -> 'a

module Font : sig
  type t
  type mode = Solid | Blended

  val open_ : context -> string -> ptsize:float -> t

  val open_io : context -> [> `Read ] Sdl3.Io.t -> ptsize:float -> t
  (** Open a font from the start of a seekable stream. The font uses the stream
      until you close the font. You cannot use or close the stream in that time.
      Do not change a memory stream's backing buffer while the font uses it. The
      caller still owns the stream and must close it after the font. *)

  val close : t -> unit
  (** Destroy all text objects that use this font before you close it. *)

  val set_size : t -> ptsize:float -> unit
  val height : t -> int
  val ascent : t -> int
  val descent : t -> int
  val line_skip : t -> int
  val has_glyph : t -> Uchar.t -> bool

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

  val create : 'target Text_engine.t -> Font.t -> string -> 'target t
  (** Copy a UTF-8 string without NUL bytes. The default color is white. The
      font and engine must stay open until you destroy the text. *)

  val destroy : 'target t -> unit

  val set_string : 'target t -> string -> unit
  (** Replace the text with a UTF-8 string without NUL bytes. *)

  val set_color : 'target t -> Sdl3.Color.t -> unit

  val set_wrap_width : 'target t -> int -> unit
  (** Set a nonnegative line width in pixels. The default is zero, which wraps
      only at newlines. *)

  val size : 'target t -> int * int
  (** Return the width and height in pixels. *)

  val update : 'target t -> unit
  (** Prepare the text after a change. Drawing and size queries also do this
      when needed. *)

  val draw_surface :
    Text_engine.surface t -> Sdl3.Surface.t -> x:int -> y:int -> unit
  (** Draw at a pixel position relative to the surface's top left corner. *)

  val draw_renderer : Text_engine.renderer t -> x:float -> y:float -> unit
  (** Draw at the given position on the engine renderer's current target.
      Coordinates use the renderer's units. *)
end
