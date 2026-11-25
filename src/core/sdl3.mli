(** A thin SDL3 binding. Load this module on the main thread. Except where
    noted, call the binding on that thread, including all cleanup calls. *)

exception Error of string
(** An SDL call failed. The message includes the SDL function and its error. *)

type version = { major : int; minor : int; patch : int }

type byte_buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
(** A one-dimensional bigarray of unsigned bytes. *)

val version : unit -> version
(** The version of the loaded SDL library. Safe on any thread. *)

val is_main_thread : unit -> bool
(** Whether this is the thread that loaded the binding. Safe on any thread. *)

type context

type subsystem =
  | Audio
  | Video
  | Joystick
  | Haptic
  | Gamepad
  | Events
  | Sensor
  | Camera

val init : subsystem list -> context
(** Start SDL with the requested subsystems. Only one context can be open at a
    time. Pass [[]] if you do not need any SDL subsystem. *)

val quit : context -> unit
(** Close SDL. Raise [Invalid_argument] if any resources are still open. A
    second call on a closed context does nothing. *)

val with_init : subsystem list -> (context -> 'a) -> 'a
(** Start SDL and call [quit] when the function exits. Close all resources
    inside the function, including when an exception occurs. *)

module Color : sig
  type t = private { r : int; g : int; b : int; a : int }

  val rgba : int -> int -> int -> int -> t
  (** Make a color. Each component must be in [0, 255]. *)

  val rgb : int -> int -> int -> t
  (** Make an opaque color. *)
end

module Rect : sig
  type t = { x : int; y : int; w : int; h : int }

  val make : x:int -> y:int -> w:int -> h:int -> t
end

module Frect : sig
  type t = { x : float; y : float; w : float; h : float }

  val make : x:float -> y:float -> w:float -> h:float -> t
end

module Pixel_format : sig
  type t = Rgba32 | Bgra32 | Rgb24
end

module Window : sig
  type t
  type id

  type flag =
    | Fullscreen
    | Hidden
    | Resizable
    | Borderless
    | High_pixel_density

  val create :
    ?flags:flag list -> context -> title:string -> w:int -> h:int -> t

  val destroy : t -> unit
  val id : t -> id
  val id_to_int32 : id -> int32
  val size : t -> int * int
  val size_in_pixels : t -> int * int
  val set_title : t -> string -> unit
  val set_size : t -> w:int -> h:int -> unit
  val set_fullscreen : t -> bool -> unit
  val show : t -> unit
  val hide : t -> unit
end

module Surface : sig
  (** A pixel buffer in memory. *)

  type t

  val create : ?format:Pixel_format.t -> context -> w:int -> h:int -> t
  val load_bmp : context -> string -> t
  val save_bmp : t -> string -> unit
  val destroy : t -> unit
  val size : t -> int * int
  val fill : ?rect:Rect.t -> t -> Color.t -> unit
  val read_pixel : t -> x:int -> y:int -> Color.t
end

module Blend_mode : sig
  type t = None | Blend | Add | Mod | Mul
end

type +'access texture
(** A texture handle. The type parameter marks how you can use it. *)

module Renderer : sig
  type t
  type presentation = Stretch | Letterbox | Overscan | Integer_scale

  val create : ?driver:string -> Window.t -> t
  val create_software : Surface.t -> t
  val destroy : t -> unit

  val output_size : t -> int * int
  (** The output size in pixels, as reported by SDL. If you draw to a texture,
      use [current_output_size]. *)

  val current_output_size : t -> int * int
  (** The size of the current target, adjusted for logical presentation. *)

  val set_vsync : t -> bool -> unit

  val set_target : t -> [ `Target ] texture option -> unit
  (** Draw to a texture that belongs to this renderer. Pass [None] to draw to
      the window or surface again. *)

  val set_logical_presentation : t -> (int * int * presentation) option -> unit
  (** Set a virtual width and height. Pass [None] to draw in output pixels. *)

  val set_draw_color : t -> Color.t -> unit
  val set_draw_blend_mode : t -> Blend_mode.t -> unit
  val clear : t -> unit
  val fill_rect : t -> Frect.t -> unit
  val draw_rect : t -> Frect.t -> unit

  val fill_rects : t -> Frect.t array -> unit
  (** Fill all rectangles with the current drawing color in one call to SDL. An
      empty array draws nothing. *)

  val draw_rects : t -> Frect.t array -> unit
  (** Draw the outlines of all rectangles in one call to SDL. An empty array
      draws nothing. *)

  val draw_line : t -> x1:float -> y1:float -> x2:float -> y2:float -> unit

  val present : t -> unit
  (** Present the frame. Raise [Invalid_argument] if a texture is the current
      target. *)
end

module Texture : sig
  (** An image owned by a renderer. *)

  type t = [ `Static | `Streaming | `Target ] texture
  (** A drawable texture. Use [(tex :> Texture.t)] to store [streaming],
      [target], and other textures together. *)

  type streaming = [ `Streaming ] texture
  type target = [ `Target ] texture
  type scale_mode = Nearest | Linear
  type flip = No_flip | Horizontal | Vertical | Both

  val of_surface : Renderer.t -> Surface.t -> t
  (** Copy the pixels. You can then destroy the surface. *)

  val create_streaming : Renderer.t -> w:int -> h:int -> streaming
  (** Create a texture for repeated pixel uploads. Fill it with [update] before
      you draw it. The dimensions must be positive. The byte count [w * h * 4]
      must fit in a C [int]. *)

  val create_target : Renderer.t -> w:int -> h:int -> target
  (** Create a texture that you can draw to with {!Renderer.set_target}. Clear
      it before you use it. The size limits are the same as for
      [create_streaming]. *)

  val update : ?rect:Rect.t -> streaming -> byte_buffer -> pitch:int -> unit
  (** Copy pixels in red, green, blue, alpha byte order. If you omit [rect],
      update the whole texture. Otherwise, [rect] must have positive dimensions
      and lie inside the texture. The buffer starts at the first pixel of the
      update.

      [pitch] is the byte distance between rows. It must be a multiple of four
      and at least four times the width of the update. The buffer must contain
      at least [pitch * height] bytes, including padding after the last row. The
      byte count must fit in a C [int]. Do not change the buffer during the
      call. SDL does not keep the buffer. *)

  val destroy : 'access texture -> unit
  (** Destroy the texture. If it is the current target, restore the default
      target first. *)

  val size : 'access texture -> float * float
  val set_scale_mode : 'access texture -> scale_mode -> unit
  val set_blend_mode : 'access texture -> Blend_mode.t -> unit
  val set_alpha_mod : 'access texture -> int -> unit

  val draw :
    ?src:Frect.t -> ?dst:Frect.t -> Renderer.t -> 'access texture -> unit
  (** Draw with the renderer that owns the texture. Do not draw a texture into
      itself. If you omit [src] or [dst], SDL uses the whole texture or render
      target, respectively. *)

  val draw_rotated :
    ?src:Frect.t ->
    ?dst:Frect.t ->
    ?flip:flip ->
    Renderer.t ->
    'access texture ->
    angle:float ->
    unit
  (** Like [draw], but rotate clockwise by [angle] degrees about the center of
      [dst]. *)
end

module Scancode : sig
  (** A physical key position, independent of the keyboard layout. *)

  type t

  val escape : t
  val of_name : string -> t option
  val name : t -> string
  val to_int : t -> int
end

module Keycode : sig
  (** The key as interpreted in the current keyboard layout. *)

  type t

  val name : t -> string
  val to_int32 : t -> int32
end

module Keymod : sig
  type t
  type flag = Shift | Ctrl | Alt | Gui | Caps_lock | Num_lock

  val has : t -> flag -> bool
end

module Keyboard : sig
  val is_pressed : context -> Scancode.t -> bool
  (** Read the keyboard state from the last event pump. *)

  val start_text_input : Window.t -> unit
  val stop_text_input : Window.t -> unit
end

module Mouse : sig
  type button = Left | Middle | Right | X1 | X2 | Other of int
  type buttons

  val is_pressed : buttons -> button -> bool
  val set_relative_mode : Window.t -> bool -> unit
end

module Gamepad : sig
  type t
  type id

  type axis =
    | Left_x
    | Left_y
    | Right_x
    | Right_y
    | Left_trigger
    | Right_trigger

  type button =
    | South
    | East
    | West
    | North
    | Back
    | Guide
    | Start
    | Left_stick
    | Right_stick
    | Left_shoulder
    | Right_shoulder
    | Dpad_up
    | Dpad_down
    | Dpad_left
    | Dpad_right

  val id_to_int32 : id -> int32

  val open_ : context -> id -> t
  (** Open a device identified by a [Gamepad_added] event. *)

  val close : t -> unit
  val connected : t -> bool

  val axis : t -> axis -> int
  (** Read a value from [-32768] to [32767]. Triggers start at [0]. *)

  val button : t -> button -> bool
end

module Event : sig
  type window_change =
    | Close_requested
    | Focus_gained
    | Focus_lost
    | Resized of int * int
    | Pixel_size_changed of int * int

  type kind =
    | Quit
    | Window of { window : Window.id; change : window_change }
    | Key of {
        window : Window.id;
        scancode : Scancode.t;
        keycode : Keycode.t;
        modifiers : Keymod.t;
        down : bool;
        repeat : bool;
      }
    | Text_input of { window : Window.id; text : string }
    | Text_editing of {
        window : Window.id;
        text : string;
        start : int;
        length : int;
      }
    | Mouse_motion of {
        window : Window.id;
        x : float;
        y : float;
        dx : float;
        dy : float;
        buttons : Mouse.buttons;
      }
    | Mouse_button of {
        window : Window.id;
        button : Mouse.button;
        down : bool;
        clicks : int;
        x : float;
        y : float;
      }
    | Mouse_wheel of {
        window : Window.id;
        x : float;
        y : float;
        flipped : bool;
      }
    | Gamepad_added of Gamepad.id
    | Gamepad_removed of Gamepad.id
    | Other of int32

  type t = { timestamp_ns : int64; kind : kind }

  val poll : context -> t option
  (** Remove the next event from the queue. [None] means the queue is empty.
      Unbound event types keep their SDL type number in [Other]. *)
end

module Audio : sig
  type t
  type format = U8 | S16 | S32 | F32
  type spec = { format : format; channels : int; frequency : int }
  type buffer = byte_buffer

  val open_playback : context -> spec -> t
  (** Open a paused stream on the default device. Use the [Audio] subsystem. *)

  val close : t -> unit
  val pause : t -> unit
  val resume : t -> unit
  val clear : t -> unit
  val flush : t -> unit
  val queued_bytes : t -> int

  val queue : t -> buffer -> unit
  (** Copy samples into the stream. Multi-byte samples use native byte order.
      Use [Bigarray.Array1.sub] to queue part of a buffer without a slice copy.
  *)
end

module Timer : sig
  (** Time calls are safe on any thread. *)

  val ticks_ns : unit -> int64
  val ticks_ms : unit -> int64

  val delay_ns : int64 -> unit
  (** Sleep for at least this many nanoseconds. Other OCaml threads can run. *)
end
