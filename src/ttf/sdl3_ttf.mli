(** Load fonts and render UTF-8 text. Call these functions on the main thread,
    except [version], which is safe on any thread. *)

type context

val version : unit -> Sdl3.version
val init : Sdl3.context -> context

val quit : context -> unit
(** Close the font handles before calling [quit]. *)

val with_init : Sdl3.context -> (context -> 'a) -> 'a

module Font : sig
  type t
  type mode = Solid | Blended

  val open_ : context -> string -> ptsize:float -> t
  val close : t -> unit
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
