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

module Io = struct
  type 'access t

  type _ file_mode =
    | Read : [ `Read ] file_mode
    | Write : [ `Write ] file_mode
    | Append : [ `Write ] file_mode
    | Update : [ `Read | `Write ] file_mode
    | Create : [ `Read | `Write ] file_mode
    | Append_update : [ `Read | `Write ] file_mode

  type origin = Start | Current | End

  external open_file_raw : context -> string -> string -> 'access t
    = "osdl_io_open_file"

  let open_file (type a) context ~(mode : a file_mode) path : a t =
    let mode =
      match mode with
      | Read -> "rb"
      | Write -> "wb"
      | Append -> "ab"
      | Update -> "r+b"
      | Create -> "w+b"
      | Append_update -> "a+b"
    in
    open_file_raw context path mode

  external of_memory : context -> byte_buffer -> [ `Read ] t
    = "osdl_io_of_memory"

  external of_memory_rw : context -> byte_buffer -> [ `Read | `Write ] t
    = "osdl_io_of_memory_rw"

  external close : 'access t -> unit = "osdl_io_close"
  external size : 'access t -> int64 = "osdl_io_size"
  external tell : 'access t -> int64 = "osdl_io_tell"
  external seek : 'access t -> from:origin -> int64 -> int64 = "osdl_io_seek"

  external read : [> `Read ] t -> byte_buffer -> offset:int -> length:int -> int
    = "osdl_io_read"

  external write :
    [> `Write ] t -> byte_buffer -> offset:int -> length:int -> unit
    = "osdl_io_write"

  external flush : [> `Write ] t -> unit = "osdl_io_flush"

  let with_file context ~mode path f =
    let stream = open_file context ~mode path in
    Fun.protect ~finally:(fun () -> close stream) (fun () -> f stream)
end

(* Keep temporary SDL arrays in scope while C copies them to OCaml. *)
module Snapshot = struct
  type t

  external create : unit -> t = "osdl_snapshot_create"
  external release : t -> unit = "osdl_snapshot_release"

  let read f =
    let snapshot = create () in
    Fun.protect ~finally:(fun () -> release snapshot) (fun () -> f snapshot)
end

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

module Display = struct
  type id = int32
  type mode = { w : int; h : int; pixel_density : float; refresh_rate : float }

  let id_to_int32 id = id

  external list_raw : context -> Snapshot.t -> id list = "osdl_display_list"
  external primary : context -> id = "osdl_display_primary"
  external name : context -> id -> string = "osdl_display_name"
  external bounds : context -> id -> Rect.t = "osdl_display_bounds"

  external usable_bounds : context -> id -> Rect.t
    = "osdl_display_usable_bounds"

  external content_scale : context -> id -> float = "osdl_display_content_scale"
  external desktop_mode : context -> id -> mode = "osdl_display_desktop_mode"
  external current_mode : context -> id -> mode = "osdl_display_current_mode"

  external fullscreen_modes_raw : context -> id -> Snapshot.t -> mode list
    = "osdl_display_fullscreen_modes"

  let list context = Snapshot.read (list_raw context)

  let fullscreen_modes context id =
    Snapshot.read (fullscreen_modes_raw context id)
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
  external title : t -> string = "osdl_window_title"
  external size : t -> int * int = "osdl_window_size"
  external size_in_pixels : t -> int * int = "osdl_window_size_in_pixels"
  external position : t -> int * int = "osdl_window_position"
  external display : t -> Display.id = "osdl_window_display"
  external display_scale : t -> float = "osdl_window_display_scale"
  external set_title : t -> string -> unit = "osdl_window_set_title"
  external set_size : t -> w:int -> h:int -> unit = "osdl_window_set_size"

  external set_position : t -> x:int -> y:int -> unit
    = "osdl_window_set_position"

  external set_resizable : t -> bool -> unit = "osdl_window_set_resizable"
  external set_fullscreen : t -> bool -> unit = "osdl_window_set_fullscreen"
  external show : t -> unit = "osdl_window_show"
  external hide : t -> unit = "osdl_window_hide"
  external minimize : t -> unit = "osdl_window_minimize"
  external maximize : t -> unit = "osdl_window_maximize"
  external restore : t -> unit = "osdl_window_restore"
end

module Surface = struct
  type t

  external create : ?format:Pixel_format.t -> context -> w:int -> h:int -> t
    = "osdl_surface_create"

  external load_bmp : context -> string -> t = "osdl_surface_load_bmp"
  external save_bmp : t -> string -> unit = "osdl_surface_save_bmp"
  external load_bmp_io : [> `Read ] Io.t -> t = "osdl_surface_load_bmp_io"

  external save_bmp_io : t -> [> `Write ] Io.t -> unit
    = "osdl_surface_save_bmp_io"

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

  module Locked = struct
    type t

    external size : t -> int * int = "osdl_locked_pixels_size"

    external set_pixel : t -> x:int -> y:int -> Color.t -> unit
      = "osdl_locked_pixels_set_pixel"

    external fill : t -> Color.t -> unit = "osdl_locked_pixels_fill"

    external copy_from : t -> byte_buffer -> pitch:int -> unit
      = "osdl_locked_pixels_copy_from"
  end

  external prepare_lock : streaming -> Locked.t = "osdl_texture_prepare_lock"

  external lock_pixels : Rect.t option -> Locked.t -> unit
    = "osdl_texture_lock_pixels"

  external unlock_pixels : Locked.t -> unit = "osdl_texture_unlock_pixels"

  let with_lock ?rect texture f =
    let view = prepare_lock texture in
    Fun.protect
      ~finally:(fun () -> unlock_pixels view)
      (fun () ->
        lock_pixels rect view;
        f view)

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

  external draw_sprites :
    Renderer.t ->
    'access texture ->
    positions:Float.Array.t ->
    tints:Color.t array ->
    count:int ->
    unit = "osdl_texture_draw_sprites"

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
  type command_buffer
  type render_pass
  type copy_pass
  type fence
  type vertex
  type fragment
  type 'stage shader
  type graphics_pipeline
  type index
  type 'kind buffer
  type upload_buffer
  type texture
  type sampler
  type sampler_filter = Nearest | Linear
  type index_format = Uint16 | Uint32
  type vertex_format = Float32 | Float32x2 | Float32x3 | Float32x4 | Unorm8x4

  type vertex_attribute = {
    location : int;
    format : vertex_format;
    offset : int;
  }

  type vertex_layout = { stride : int; attributes : vertex_attribute list }

  type _ shader_stage =
    | Vertex : vertex shader_stage
    | Fragment : fragment shader_stage

  type shader_format = Spirv | Dxbc | Dxil | Msl | Metallib

  type primitive =
    | Triangle_list
    | Triangle_strip
    | Line_list
    | Line_strip
    | Point_list

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

  external create_shader :
    device ->
    stage:'stage shader_stage ->
    format:shader_format ->
    ?entrypoint:string ->
    ?samplers:int ->
    ?uniform_buffers:int ->
    string ->
    'stage shader = "osdl_gpu_create_shader_byte" "osdl_gpu_create_shader"

  external release_shader : 'stage shader -> unit = "osdl_gpu_release_shader"

  external create_swapchain_pipeline :
    ?vertex_layout:vertex_layout ->
    swapchain ->
    vertex:vertex shader ->
    fragment:fragment shader ->
    primitive:primitive ->
    graphics_pipeline = "osdl_gpu_create_swapchain_pipeline"

  external release_graphics_pipeline : graphics_pipeline -> unit
    = "osdl_gpu_release_graphics_pipeline"

  external create_vertex_buffer : device -> size:int -> vertex buffer
    = "osdl_gpu_create_vertex_buffer"

  external create_index_buffer :
    device -> format:index_format -> size:int -> index buffer
    = "osdl_gpu_create_index_buffer"

  external release_buffer : 'kind buffer -> unit = "osdl_gpu_release_buffer"

  external create_upload_buffer : device -> size:int -> upload_buffer
    = "osdl_gpu_create_upload_buffer"

  external write_upload_buffer : upload_buffer -> byte_buffer -> unit
    = "osdl_gpu_write_upload_buffer"

  external release_upload_buffer : upload_buffer -> unit
    = "osdl_gpu_release_upload_buffer"

  external create_sampled_texture : device -> w:int -> h:int -> texture
    = "osdl_gpu_create_sampled_texture"

  external release_texture : texture -> unit = "osdl_gpu_release_texture"

  external create_sampler : device -> filter:sampler_filter -> sampler
    = "osdl_gpu_create_sampler"

  external release_sampler : sampler -> unit = "osdl_gpu_release_sampler"

  external acquire_command_buffer : device -> command_buffer
    = "osdl_gpu_acquire_command_buffer"

  external push_uniform_data :
    command_buffer ->
    stage:'stage shader_stage ->
    slot:int ->
    byte_buffer ->
    unit = "osdl_gpu_push_uniform_data"

  external submit_command_buffer : command_buffer -> unit
    = "osdl_gpu_submit_command_buffer"

  external submit_and_acquire_fence : command_buffer -> fence
    = "osdl_gpu_submit_and_acquire_fence"

  external cancel_command_buffer : command_buffer -> unit
    = "osdl_gpu_cancel_command_buffer"

  external fence_signaled : fence -> bool = "osdl_gpu_fence_signaled"
  external wait_fence : fence -> unit = "osdl_gpu_wait_fence"
  external release_fence : fence -> unit = "osdl_gpu_release_fence"

  external begin_copy_pass : command_buffer -> copy_pass
    = "osdl_gpu_begin_copy_pass"

  external upload_to_buffer :
    ?src_offset:int ->
    ?dst_offset:int ->
    ?cycle:bool ->
    copy_pass ->
    src:upload_buffer ->
    dst:'kind buffer ->
    size:int ->
    unit = "osdl_gpu_upload_to_buffer_byte" "osdl_gpu_upload_to_buffer"

  external upload_to_texture :
    ?src_offset:int ->
    ?cycle:bool ->
    copy_pass ->
    src:upload_buffer ->
    dst:texture ->
    unit = "osdl_gpu_upload_to_texture"

  external end_copy_pass : copy_pass -> unit = "osdl_gpu_end_copy_pass"

  external begin_swapchain_render_pass :
    command_buffer -> swapchain -> clear:Color.t -> render_pass option
    = "osdl_gpu_begin_swapchain_render_pass"

  external bind_graphics_pipeline : render_pass -> graphics_pipeline -> unit
    = "osdl_gpu_bind_graphics_pipeline"

  external bind_samplers :
    ?first_slot:int ->
    render_pass ->
    stage:'stage shader_stage ->
    (texture * sampler) array ->
    unit = "osdl_gpu_bind_samplers"

  external bind_vertex_buffer :
    ?offset:int -> render_pass -> vertex buffer -> unit
    = "osdl_gpu_bind_vertex_buffer"

  external bind_index_buffer :
    ?offset:int -> render_pass -> index buffer -> unit
    = "osdl_gpu_bind_index_buffer"

  external draw_primitives :
    ?instances:int -> render_pass -> vertices:int -> unit
    = "osdl_gpu_draw_primitives"

  external draw_indexed_primitives :
    ?instances:int -> ?first_index:int -> render_pass -> indices:int -> unit
    = "osdl_gpu_draw_indexed_primitives"

  external end_render_pass : render_pass -> unit = "osdl_gpu_end_render_pass"

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

module Touch = struct
  type id = int64
  type finger_id = int64

  type device_type =
    | Direct
    | Indirect_absolute
    | Indirect_relative
    | Other of int

  type finger = { id : finger_id; x : float; y : float; pressure : float }

  let id_to_int64 id = id
  let finger_id_to_int64 id = id

  external devices_raw : context -> Snapshot.t -> id list = "osdl_touch_devices"
  external name : context -> id -> string = "osdl_touch_name"
  external device_type : context -> id -> device_type = "osdl_touch_device_type"

  external fingers_raw : context -> id -> Snapshot.t -> finger list
    = "osdl_touch_fingers"

  let devices context = Snapshot.read (devices_raw context)
  let fingers context id = Snapshot.read (fingers_raw context id)
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
    | Misc1
    | Right_paddle1
    | Left_paddle1
    | Right_paddle2
    | Left_paddle2
    | Touchpad
    | Misc2
    | Misc3
    | Misc4
    | Misc5
    | Misc6

  let id_to_int32 id = id

  external list_raw : context -> Snapshot.t -> id list = "osdl_gamepad_list"
  external name_for_id : context -> id -> string = "osdl_gamepad_name_for_id"
  external open_ : context -> id -> t = "osdl_gamepad_open"
  external close : t -> unit = "osdl_gamepad_close"
  external connected : t -> bool = "osdl_gamepad_connected"
  external id : t -> id = "osdl_gamepad_id"
  external name : t -> string = "osdl_gamepad_name"
  external has_axis : t -> axis -> bool = "osdl_gamepad_has_axis"
  external has_button : t -> button -> bool = "osdl_gamepad_has_button"
  external axis : t -> axis -> int = "osdl_gamepad_axis"
  external button : t -> button -> bool = "osdl_gamepad_button"

  let list context = Snapshot.read (list_raw context)
end

module Event = struct
  type window_change =
    | Close_requested
    | Focus_gained
    | Focus_lost
    | Resized of int * int
    | Pixel_size_changed of int * int
    | Moved of int * int
    | Display_changed of Display.id
    | Shown
    | Hidden
    | Minimized
    | Maximized
    | Restored
    | Display_scale_changed
    | Entered_fullscreen
    | Left_fullscreen

  type display_change =
    | Connected
    | Disconnected
    | Layout_changed
    | Desktop_mode_changed
    | Current_mode_changed
    | Content_scale_changed

  type touch_change = Down | Up | Motion | Canceled

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
    | Gamepad_remapped of Gamepad.id
    | Gamepad_axis of { gamepad : Gamepad.id; axis : Gamepad.axis; value : int }
    | Gamepad_button of {
        gamepad : Gamepad.id;
        button : Gamepad.button;
        down : bool;
      }
    | Display of { display : Display.id; change : display_change }
    | Touch of {
        window : Window.id option;
        device : Touch.id;
        finger : Touch.finger;
        change : touch_change;
        dx : float;
        dy : float;
      }
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
