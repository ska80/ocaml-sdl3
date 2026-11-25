exception Error of string

type version = { major : int; minor : int; patch : int }

type byte_buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

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

external bind_main_thread : unit -> unit = "osdl_bind_main_thread"
external is_main_thread : unit -> bool = "osdl_is_main_thread" [@@noalloc]
external version : unit -> version = "osdl_version"
external init : subsystem list -> context = "osdl_init"
external quit : context -> unit = "osdl_quit"

let () =
  if not (Domain.is_main_domain ()) then
    invalid_arg "Load Sdl3 on the main domain";
  Callback.register_exception "ocaml-sdl3.error" (Error "");
  bind_main_thread ()

let with_init subsystems f =
  let context = init subsystems in
  Fun.protect ~finally:(fun () -> quit context) (fun () -> f context)

module Color = struct
  type t = { r : int; g : int; b : int; a : int }

  let rgba r g b a =
    let bits = r lor g lor b lor a in
    if bits land lnot 255 <> 0 then
      invalid_arg "Sdl3.Color.rgba: components must be in [0, 255]";
    { r; g; b; a }

  let rgb r g b = rgba r g b 255
end

module Rect = struct
  type t = { x : int; y : int; w : int; h : int }

  let make ~x ~y ~w ~h = { x; y; w; h }
end

module Frect = struct
  type t = { x : float; y : float; w : float; h : float }

  let make ~x ~y ~w ~h = { x; y; w; h }
end

module Pixel_format = struct
  type t = Rgba32 | Bgra32 | Rgb24
end

module Window = struct
  type t
  type id = int32

  type flag =
    | Fullscreen
    | Hidden
    | Resizable
    | Borderless
    | High_pixel_density

  let id_to_int32 id = id

  external create :
    ?flags:flag list -> context -> title:string -> w:int -> h:int -> t
    = "osdl_window_create"

  external destroy : t -> unit = "osdl_window_destroy"
  external id : t -> id = "osdl_window_id"
  external size : t -> int * int = "osdl_window_size"
  external size_in_pixels : t -> int * int = "osdl_window_size_in_pixels"
  external set_title : t -> string -> unit = "osdl_window_set_title"
  external set_size : t -> w:int -> h:int -> unit = "osdl_window_set_size"
  external set_fullscreen : t -> bool -> unit = "osdl_window_set_fullscreen"
  external show : t -> unit = "osdl_window_show"
  external hide : t -> unit = "osdl_window_hide"
end

module Surface = struct
  type t

  external create : ?format:Pixel_format.t -> context -> w:int -> h:int -> t
    = "osdl_surface_create"

  external load_bmp : context -> string -> t = "osdl_surface_load_bmp"
  external save_bmp : t -> string -> unit = "osdl_surface_save_bmp"
  external destroy : t -> unit = "osdl_surface_destroy"
  external size : t -> int * int = "osdl_surface_size"
  external fill : ?rect:Rect.t -> t -> Color.t -> unit = "osdl_surface_fill"

  external read_pixel : t -> x:int -> y:int -> Color.t
    = "osdl_surface_read_pixel"
end

module Blend_mode = struct
  type t = None | Blend | Add | Mod | Mul
end

type +'access texture

module Renderer = struct
  type t
  type presentation = Stretch | Letterbox | Overscan | Integer_scale

  external create : ?driver:string -> Window.t -> t = "osdl_renderer_create"
  external create_software : Surface.t -> t = "osdl_renderer_create_software"
  external destroy : t -> unit = "osdl_renderer_destroy"
  external output_size : t -> int * int = "osdl_renderer_output_size"

  external current_output_size : t -> int * int
    = "osdl_renderer_current_output_size"

  external set_vsync : t -> bool -> unit = "osdl_renderer_set_vsync"

  external set_target : t -> [ `Target ] texture option -> unit
    = "osdl_renderer_set_target"

  external set_logical_presentation :
    t -> (int * int * presentation) option -> unit
    = "osdl_renderer_set_logical_presentation"

  external set_draw_color : t -> Color.t -> unit
    = "osdl_renderer_set_draw_color"

  external set_draw_blend_mode : t -> Blend_mode.t -> unit
    = "osdl_renderer_set_draw_blend_mode"

  external clear : t -> unit = "osdl_renderer_clear"
  external fill_rect : t -> Frect.t -> unit = "osdl_renderer_fill_rect"
  external draw_rect : t -> Frect.t -> unit = "osdl_renderer_draw_rect"
  external fill_rects : t -> Frect.t array -> unit = "osdl_renderer_fill_rects"
  external draw_rects : t -> Frect.t array -> unit = "osdl_renderer_draw_rects"

  external draw_line : t -> x1:float -> y1:float -> x2:float -> y2:float -> unit
    = "osdl_renderer_draw_line"

  external present : t -> unit = "osdl_renderer_present"
end

module Texture = struct
  type t = [ `Static | `Streaming | `Target ] texture
  type streaming = [ `Streaming ] texture
  type target = [ `Target ] texture
  type scale_mode = Nearest | Linear
  type flip = No_flip | Horizontal | Vertical | Both

  external of_surface : Renderer.t -> Surface.t -> t = "osdl_texture_of_surface"

  external create_streaming : Renderer.t -> w:int -> h:int -> streaming
    = "osdl_texture_create_streaming"

  external create_target : Renderer.t -> w:int -> h:int -> target
    = "osdl_texture_create_target"

  external update :
    ?rect:Rect.t -> streaming -> byte_buffer -> pitch:int -> unit
    = "osdl_texture_update"

  external destroy : 'access texture -> unit = "osdl_texture_destroy"
  external size : 'access texture -> float * float = "osdl_texture_size"

  external set_scale_mode : 'access texture -> scale_mode -> unit
    = "osdl_texture_set_scale_mode"

  external set_blend_mode : 'access texture -> Blend_mode.t -> unit
    = "osdl_texture_set_blend_mode"

  external set_alpha_mod : 'access texture -> int -> unit
    = "osdl_texture_set_alpha_mod"

  external draw :
    ?src:Frect.t -> ?dst:Frect.t -> Renderer.t -> 'access texture -> unit
    = "osdl_texture_draw"

  external draw_rotated :
    ?src:Frect.t ->
    ?dst:Frect.t ->
    ?flip:flip ->
    Renderer.t ->
    'access texture ->
    angle:float ->
    unit = "osdl_texture_draw_rotated_byte" "osdl_texture_draw_rotated"
end

module Gpu = struct
  type device
  type swapchain
  type shader_format = Spirv | Dxbc | Dxil | Msl | Metallib
  type present_mode = Vsync | Immediate | Mailbox
  type composition = Sdr | Sdr_linear | Hdr_extended_linear | Hdr10

  external drivers : unit -> string list = "osdl_gpu_drivers"

  external supports_shader_formats :
    ?driver:string -> context -> shader_format list -> bool
    = "osdl_gpu_supports_shader_formats"

  external create_device :
    ?driver:string -> ?debug:bool -> context -> shader_format list -> device
    = "osdl_gpu_create_device"

  external destroy_device : device -> unit = "osdl_gpu_destroy_device"
  external driver : device -> string = "osdl_gpu_driver"

  external shader_formats : device -> shader_format list
    = "osdl_gpu_shader_formats"

  external wait_idle : device -> unit = "osdl_gpu_wait_idle"

  external claim_window : device -> Window.t -> swapchain
    = "osdl_gpu_claim_window"

  external release_window : swapchain -> unit = "osdl_gpu_release_window"

  external supports_present_mode : swapchain -> present_mode -> bool
    = "osdl_gpu_supports_present_mode"

  external supports_composition : swapchain -> composition -> bool
    = "osdl_gpu_supports_composition"

  external set_swapchain_parameters :
    swapchain -> composition:composition -> present_mode:present_mode -> unit
    = "osdl_gpu_set_swapchain_parameters"

  external clear_and_present : swapchain -> Color.t -> bool
    = "osdl_gpu_clear_and_present"
end

module Scancode = struct
  type t = int

  external get_escape : unit -> t = "osdl_scancode_escape" [@@noalloc]
  external of_name : string -> t option = "osdl_scancode_of_name"
  external name : t -> string = "osdl_scancode_name"

  let escape = get_escape ()
  let to_int scancode = scancode
end

module Keycode = struct
  type t = int32

  let to_int32 keycode = keycode

  external name : t -> string = "osdl_keycode_name"
end

module Keymod = struct
  type t = int
  type flag = Shift | Ctrl | Alt | Gui | Caps_lock | Num_lock

  external has : t -> flag -> bool = "osdl_keymod_has" [@@noalloc]
end

module Keyboard = struct
  external is_pressed : context -> Scancode.t -> bool = "osdl_keyboard_pressed"

  external start_text_input : Window.t -> unit
    = "osdl_keyboard_start_text_input"

  external stop_text_input : Window.t -> unit = "osdl_keyboard_stop_text_input"
end

module Mouse = struct
  type button = Left | Middle | Right | X1 | X2 | Other of int
  type buttons = int32

  external is_pressed : buttons -> button -> bool = "osdl_mouse_pressed"
  [@@noalloc]

  external set_relative_mode : Window.t -> bool -> unit
    = "osdl_mouse_set_relative_mode"
end

module Gamepad = struct
  type t
  type id = int32

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

  let id_to_int32 id = id

  external open_ : context -> id -> t = "osdl_gamepad_open"
  external close : t -> unit = "osdl_gamepad_close"
  external connected : t -> bool = "osdl_gamepad_connected"
  external axis : t -> axis -> int = "osdl_gamepad_axis"
  external button : t -> button -> bool = "osdl_gamepad_button"
end

module Event = struct
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

  external poll : context -> t option = "osdl_event_poll"
end

module Audio = struct
  type t
  type format = U8 | S16 | S32 | F32
  type spec = { format : format; channels : int; frequency : int }
  type buffer = byte_buffer

  external open_playback : context -> spec -> t = "osdl_audio_open_playback"
  external close : t -> unit = "osdl_audio_close"
  external pause : t -> unit = "osdl_audio_pause"
  external resume : t -> unit = "osdl_audio_resume"
  external clear : t -> unit = "osdl_audio_clear"
  external flush : t -> unit = "osdl_audio_flush"
  external queue : t -> buffer -> unit = "osdl_audio_queue"
  external queued_bytes : t -> int = "osdl_audio_queued_bytes"
end

module Timer = struct
  external ticks_ns : unit -> (int64[@unboxed])
    = "osdl_ticks_ns_byte" "osdl_ticks_ns"
  [@@noalloc]

  external ticks_ms : unit -> (int64[@unboxed])
    = "osdl_ticks_ms_byte" "osdl_ticks_ms"
  [@@noalloc]

  external delay_ns : (int64[@unboxed]) -> unit
    = "osdl_delay_ns_byte" "osdl_delay_ns"
end
