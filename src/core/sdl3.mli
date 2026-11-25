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

module Display : sig
  (** Queries for connected displays. Start SDL with [Video]. *)

  type id

  type mode = { w : int; h : int; pixel_density : float; refresh_rate : float }
  (** [w] and [h] are in display coordinates. Multiply by [pixel_density] for
      pixels. [refresh_rate] is in hertz, or zero if SDL does not know it. *)

  val id_to_int32 : id -> int32
  val list : context -> id list
  val primary : context -> id
  val name : context -> id -> string
  val bounds : context -> id -> Rect.t

  val usable_bounds : context -> id -> Rect.t
  (** Display bounds minus areas that the system reserves. *)

  val content_scale : context -> id -> float
  (** The display's suggested scale for text and other content. *)

  val desktop_mode : context -> id -> mode
  (** The mode that the desktop uses outside fullscreen. *)

  val current_mode : context -> id -> mode
  (** The mode in use now. A fullscreen window can change it. *)

  val fullscreen_modes : context -> id -> mode list
  (** Copy the fullscreen modes in the order SDL reports them. *)
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
  val title : t -> string
  val size : t -> int * int
  val size_in_pixels : t -> int * int
  val position : t -> int * int
  val display : t -> Display.id

  val display_scale : t -> float
  (** The suggested scale for content in this window, relative to its pixel
      size. This can differ from the display's content scale. *)

  val set_title : t -> string -> unit
  val set_size : t -> w:int -> h:int -> unit

  val set_position : t -> x:int -> y:int -> unit
  (** Request a move to the given screen coordinates. The window manager can
      apply the move later, change the coordinates, or refuse the request. *)

  val set_resizable : t -> bool -> unit
  val set_fullscreen : t -> bool -> unit
  val show : t -> unit
  val hide : t -> unit
  val minimize : t -> unit

  val maximize : t -> unit
  (** Request to maximize a resizable window. *)

  val restore : t -> unit
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
  (** Create a renderer for a window with no renderer or GPU claim. *)

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
  (** Create a texture for repeated pixel uploads. Fill it with [update] or
      [with_lock] before you draw it. The dimensions must be positive. The byte
      count [w * h * 4] must fit in a C [int]. *)

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

  module Locked : sig
    (** Write-only access to one locked rectangle. All operations raise
        [Invalid_argument] after the lock ends. *)

    type t

    val size : t -> int * int
    (** The width and height of the locked rectangle in pixels. *)

    val set_pixel : t -> x:int -> y:int -> Color.t -> unit
    (** Write one pixel. Coordinates start at zero in the locked rectangle. A
        point outside the rectangle raises [Invalid_argument]. *)

    val fill : t -> Color.t -> unit
    (** Set every pixel in the locked rectangle to the given color. *)

    val copy_from : t -> byte_buffer -> pitch:int -> unit
    (** Copy red, green, blue, and alpha bytes into the whole locked rectangle.
        [pitch] is the byte distance between source rows. It must be a multiple
        of four and at least four times the width of the rectangle. The buffer
        must cover all rows. The last row does not need padding. Do not change
        the source buffer during the call. *)
  end

  val with_lock : ?rect:Rect.t -> streaming -> (Locked.t -> 'a) -> 'a
  (** Call the function with write access to the texture. If you omit [rect],
      lock the whole texture. Otherwise, use a rectangle with positive
      dimensions that lies inside the texture. The lock does not preserve the
      old pixels in the rectangle. Any pixel you do not write becomes
      transparent black.

      Run the function on the main thread. Do not lock, update, draw, or destroy
      the same texture during the call. If the function returns or raises, the
      binding unlocks the texture and keeps the pixel writes. If it raises, the
      binding propagates the exception. *)

  val destroy : 'access texture -> unit
  (** Destroy the texture. End any lock on it first. If it is the current
      target, restore the default target first. *)

  val size : 'access texture -> float * float
  val set_scale_mode : 'access texture -> scale_mode -> unit
  val set_blend_mode : 'access texture -> Blend_mode.t -> unit
  val set_alpha_mod : 'access texture -> int -> unit

  val draw :
    ?src:Frect.t -> ?dst:Frect.t -> Renderer.t -> 'access texture -> unit
  (** Draw with the renderer that owns the texture. Do not draw a texture into
      itself. If you omit [src] or [dst], SDL uses the whole texture or render
      target, respectively. *)

  val draw_sprites :
    Renderer.t ->
    'access texture ->
    positions:Float.Array.t ->
    tints:Color.t array ->
    count:int ->
    unit
  (** Draw [count] copies of the whole texture at its original size, in array
      order. Supply the top-left [x, y] coordinates in consecutive pairs in
      [positions] and one color per copy in [tints]. The colors replace the
      texture's color and alpha settings for these draws only.

      Only the first [2 * count] coordinates and [count] colors are used. A
      count of zero draws nothing. The count must fit both arrays and a C [int].
      The coordinates must fit finite C floats. Do not change the arrays during
      the call. Like [draw], the texture must belong to this renderer and cannot
      be the current target. *)

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

module Gpu : sig
  (** SDL GPU drawing and window presentation. *)

  type device

  type swapchain
  (** A GPU claim on a window. It manages the images used to present frames. *)

  type command_buffer
  (** A list of GPU operations to submit together. *)

  type render_pass
  (** A group of rendering operations that share the same target image. *)

  type copy_pass
  (** A group of GPU copy operations in a command buffer. *)

  type fence
  (** A handle that signals completion of submitted GPU work. *)

  type vertex
  type fragment

  type 'stage shader
  (** A vertex or fragment program for the GPU. *)

  type _ shader_stage =
    | Vertex : vertex shader_stage
    | Fragment : fragment shader_stage

  type graphics_pipeline
  (** The shaders and drawing state for a render pass. *)

  type index

  type 'kind buffer
  (** GPU memory for vertex data or indices. *)

  type upload_buffer
  (** Temporary memory that holds bytes to copy to the GPU. *)

  type texture
  (** A GPU image that a shader can read. *)

  type sampler
  (** Rules for how a shader reads pixels from a texture. *)

  type sampler_filter = Nearest | Linear

  type index_format =
    | Uint16
    | Uint32  (** The width of each unsigned integer in an index buffer. *)

  type vertex_format =
    | Float32
    | Float32x2
    | Float32x3
    | Float32x4
    | Unorm8x4
        (** An attribute's data format. [Unorm8x4] maps four unsigned bytes to
            four values in the range 0 to 1. *)

  type vertex_attribute = {
    location : int;
    format : vertex_format;
    offset : int;
  }
  (** A value read by the vertex shader. Use a unique shader input [location]
      from 0 to 15. The [offset] is in bytes from the start of the vertex and
      must be a multiple of four. *)

  type vertex_layout = { stride : int; attributes : vertex_attribute list }
  (** The layout of one vertex buffer. The [stride] is the byte distance between
      vertices. It must be a positive multiple of four, up to 2048. Supply at
      least one attribute. Each attribute must fit in the stride. *)

  type shader_format = Spirv | Dxbc | Dxil | Msl | Metallib

  type primitive =
    | Triangle_list  (** Separate triangles. *)
    | Triangle_strip  (** Connected triangles. *)
    | Line_list  (** Separate lines. *)
    | Line_strip  (** Connected lines. *)
    | Point_list
        (** Points. Follow the backend's rules for writing a point size in the
            vertex shader. *)

  type present_mode = Vsync | Immediate | Mailbox
  type composition = Sdr | Sdr_linear | Hdr_extended_linear | Hdr10

  val drivers : unit -> string list
  (** The driver names compiled into SDL. This does not check runtime support.
      Safe on any thread. *)

  val supports_shader_formats :
    ?driver:string -> context -> shader_format list -> bool
  (** Test whether SDL can select a driver that accepts at least one format in
      the list. Start SDL with [Video] and pass a nonempty list. *)

  val create_device :
    ?driver:string -> ?debug:bool -> context -> shader_format list -> device
  (** Open a GPU device. Start SDL with [Video] and list the shader formats your
      program can provide. Pass at least one format. If you omit [driver], SDL
      selects the driver. Set [debug] to [true] to enable SDL GPU validation. *)

  val destroy_device : device -> unit
  (** Close the device. Release all its resources first, including claims,
      fences, shaders, pipelines, buffers, textures, and samplers. Submit or
      cancel any open command buffers. *)

  val driver : device -> string
  val shader_formats : device -> shader_format list

  val wait_idle : device -> unit
  (** Wait for the device to finish its submitted work. *)

  val claim_window : device -> Window.t -> swapchain
  (** Claim a window that has no renderer or GPU claim. SDL starts with [Sdr]
      and [Vsync]. The claim keeps the device and window open. *)

  val release_window : swapchain -> unit
  (** Release the claim before destroying the window or device. If a command
      buffer holds an image from this claim, submit that buffer first. Calling
      this again on a released claim does nothing. *)

  val supports_present_mode : swapchain -> present_mode -> bool
  val supports_composition : swapchain -> composition -> bool

  val set_swapchain_parameters :
    swapchain -> composition:composition -> present_mode:present_mode -> unit
  (** Set the display color format and presentation timing. If a command buffer
      holds an image from this claim, submit that buffer first. SDL can reject
      settings that the window does not support. *)

  val create_shader :
    device ->
    stage:'stage shader_stage ->
    format:shader_format ->
    ?entrypoint:string ->
    ?samplers:int ->
    ?uniform_buffers:int ->
    string ->
    'stage shader
  (** Create a shader from code in [format]. Pass valid code for [stage] and a
      format the device supports. The entry point defaults to ["main"].

      Declare the number of texture and sampler pairs in [samplers] (0 to 16).
      Declare the number of uniform blocks in [uniform_buffers] (0 to 4). Both
      counts default to zero. Use consecutive slots from zero within each group.
      For SPIR-V, use sets 0 and 1 for vertex samplers and uniforms. Use sets 2
      and 3 for fragment samplers and uniforms. For the other formats, follow
      the layout in SDL's [SDL_CreateGPUShader] documentation. The binding does
      not inspect the code. Do not use storage resources. *)

  val release_shader : 'stage shader -> unit
  (** Release the shader. Existing pipelines can still use it. Calling this
      again on a released shader does nothing. *)

  val create_swapchain_pipeline :
    ?vertex_layout:vertex_layout ->
    swapchain ->
    vertex:vertex shader ->
    fragment:fragment shader ->
    primitive:primitive ->
    graphics_pipeline
  (** Create a pipeline for the claim's current pixel format. Both shaders must
      belong to the device that claimed the window. If the vertex shader has
      attributes, pass its layout for one vertex buffer. Otherwise omit
      [vertex_layout]. The pipeline uses one color target, with no blending,
      depth test, or face culling.

      The pipeline belongs to the device, not the claim. Use it with any
      swapchain on that device that has the same pixel format. If a change to
      the swapchain parameters changes the format, create a matching pipeline.
  *)

  val release_graphics_pipeline : graphics_pipeline -> unit
  (** Release the pipeline. SDL keeps any work already recorded in command
      buffers valid. If a pass still uses this pipeline, bind another pipeline
      before drawing again. Calling this again on a released pipeline does
      nothing. *)

  val create_vertex_buffer : device -> size:int -> vertex buffer
  (** Allocate space for vertex data. Pass a positive byte size that is a
      multiple of four and fits in an unsigned 32-bit integer. Upload data
      before drawing. *)

  val create_index_buffer :
    device -> format:index_format -> size:int -> index buffer
  (** Allocate space for vertex indices. The same byte size rules apply as for
      [create_vertex_buffer]. Pad an odd number of 16-bit indices with two
      bytes. Pass only the actual index count to the draw call. *)

  val release_buffer : 'kind buffer -> unit
  (** Release a vertex or index buffer. SDL keeps already recorded commands
      valid. Calling this again on a released buffer does nothing. *)

  val create_upload_buffer : device -> size:int -> upload_buffer
  (** Allocate memory for uploads. The same byte size rules apply as for
      [create_vertex_buffer]. *)

  val write_upload_buffer : upload_buffer -> byte_buffer -> unit
  (** Copy a nonempty bigarray to the start of the upload buffer. The array must
      fit in the buffer. Only the bytes written by this call are valid for new
      copies. SDL can use separate storage if a recorded copy still uses the
      previous bytes. The bigarray can be reused after this call. *)

  val release_upload_buffer : upload_buffer -> unit
  (** Release the upload buffer. SDL keeps already recorded copies valid.
      Calling this again on a released buffer does nothing. *)

  val create_sampled_texture : device -> w:int -> h:int -> texture
  (** Allocate a 2D texture with one level. Each pixel uses four bytes in red,
      green, blue, alpha order. Each byte maps to a value from 0 to 1. Width and
      height must be in [1, 16384]. Upload pixels before sampling. *)

  val release_texture : texture -> unit
  (** Release the texture. SDL keeps already recorded commands valid. Calling
      this again on a released texture does nothing. *)

  val create_sampler : device -> filter:sampler_filter -> sampler
  (** Create a sampler for a texture with one level. [Nearest] reads the closest
      pixel. [Linear] blends nearby pixels. Coordinates outside the texture use
      its edge pixels. *)

  val release_sampler : sampler -> unit
  (** Release the sampler. SDL keeps already recorded commands valid. Calling
      this again on a released sampler does nothing. *)

  val acquire_command_buffer : device -> command_buffer
  (** Start recording GPU work. Submit or cancel the buffer when finished. *)

  val push_uniform_data :
    command_buffer ->
    stage:'stage shader_stage ->
    slot:int ->
    byte_buffer ->
    unit
  (** Copy values that stay constant for a draw to a uniform slot from 0 to 3.
      The buffer's length must be 4 to 4096 bytes and a multiple of four. Pack
      the data to match the shader's block in [std140] layout. The binding does
      not inspect the layout.

      Call this before or during a render pass. The data applies to subsequent
      draws in this command buffer until you replace it in the same slot and
      stage. You can reuse the bigarray as soon as this call returns. *)

  val submit_command_buffer : command_buffer -> unit
  (** Queue the recorded work and present any acquired window image. End any
      open pass first. Once SDL receives the buffer, the binding closes it even
      if SDL reports an error. *)

  val submit_and_acquire_fence : command_buffer -> fence
  (** Submit and return a fence for the work. The same rules apply as for
      [submit_command_buffer]. Release the fence when you no longer need it. *)

  val cancel_command_buffer : command_buffer -> unit
  (** Discard recorded work. End any open pass first. If the buffer holds a
      window image, submit it instead. Calling this on a closed buffer does
      nothing. *)

  val fence_signaled : fence -> bool
  (** Return [true] if the GPU finished the work for this fence. *)

  val wait_fence : fence -> unit
  (** Wait for the GPU to finish the work for this fence. *)

  val release_fence : fence -> unit
  (** Release the fence. Calling this again on a released fence does nothing. *)

  val begin_copy_pass : command_buffer -> copy_pass
  (** Start a pass for uploads. End any open pass on the command buffer first.
  *)

  val upload_to_buffer :
    ?src_offset:int ->
    ?dst_offset:int ->
    ?cycle:bool ->
    copy_pass ->
    src:upload_buffer ->
    dst:'kind buffer ->
    size:int ->
    unit
  (** Record a copy from the written bytes in [src] to [dst]. Both buffers must
      belong to the pass's device. Offsets default to zero. Each offset and the
      positive byte size must be a multiple of four.

      With [cycle:true], replace the whole destination. SDL can use separate
      storage if a recorded command still uses the previous bytes. If you cancel
      a buffer with a cycling upload, upload again before drawing. Without
      cycling, the copy updates the existing storage in GPU command order. *)

  val upload_to_texture :
    ?src_offset:int ->
    ?cycle:bool ->
    copy_pass ->
    src:upload_buffer ->
    dst:texture ->
    unit
  (** Record a copy that replaces all pixels in [dst]. Write the pixels to [src]
      in row order with no padding between rows. The byte offset defaults to
      zero and must be a multiple of four. Use an upload buffer and texture from
      the pass's device. The pixels must fit in the written bytes of [src].

      With [cycle:true], SDL can use separate storage for the new pixels. If you
      cancel a buffer with a cycling upload, upload again before sampling.
      Without cycling, the copy updates the existing storage in GPU command
      order.

      On Direct3D 12 before SDL 3.4.2, a texture narrower than 32 pixels with at
      least two rows needs extra capacity in [src]. Leave at least 256 bytes of
      capacity from the start of the next-to-last row. *)

  val end_copy_pass : copy_pass -> unit
  (** End the copy pass. Calling this again on an ended pass does nothing. *)

  val begin_swapchain_render_pass :
    command_buffer -> swapchain -> clear:Color.t -> render_pass option
  (** Wait for a window image and start a pass that clears it. End any open pass
      on the command buffer first. The claim and command buffer must belong to
      the same device. If this returns [None], no image was available and you
      can still cancel the buffer.

      If this returns a pass, end the pass before submitting the buffer. The
      claim stays busy until submission. Do not acquire another image in the
      same buffer. If an SDL call fails here, the binding closes the buffer
      before raising [Error]. It cancels the buffer if no image was acquired.
      Otherwise, it submits the buffer to return the image to SDL. *)

  val bind_graphics_pipeline : render_pass -> graphics_pipeline -> unit
  (** Bind a live pipeline that matches the pass's device and pixel format. Bind
      the vertex buffer and sampler slots that the pipeline needs after each
      call. Uniform data stays in the command buffer. *)

  val bind_samplers :
    ?first_slot:int ->
    render_pass ->
    stage:'stage shader_stage ->
    (texture * sampler) array ->
    unit
  (** Bind texture and sampler pairs to consecutive slots of the current
      pipeline's shader. [first_slot] defaults to zero. The range must fit the
      sampler count for that stage. The resources must belong to the pass's
      device. An empty array does not change any slots. *)

  val bind_vertex_buffer : ?offset:int -> render_pass -> vertex buffer -> unit
  (** Select the vertex data for the current pipeline. The pipeline must have a
      vertex layout. The buffer must belong to the pass's device. The byte
      offset defaults to zero and must be a multiple of four. Leave room for at
      least one vertex. *)

  val bind_index_buffer : ?offset:int -> render_pass -> index buffer -> unit
  (** Select indices for later draws in this pass. The buffer must belong to the
      pass's device. The byte offset defaults to zero and must be a multiple of
      the index width. Leave room for at least one index. *)

  val draw_primitives : ?instances:int -> render_pass -> vertices:int -> unit
  (** Draw with the pipeline bound to this pass. Counts must be positive and no
      greater than [4_294_967_295]. The instance count defaults to 1. Vertex and
      instance indices start at 0. If the pipeline reads vertex data, bind a
      live vertex buffer with room for the requested vertices. Push data for
      each declared uniform slot and bind each declared sampler slot before
      drawing. The textures and samplers must still be live. *)

  val draw_indexed_primitives :
    ?instances:int -> ?first_index:int -> render_pass -> indices:int -> unit
  (** Draw with the current pipeline and index buffer. The index and instance
      counts have the same limits as in [draw_primitives]. [first_index] is
      relative to the bound index buffer offset and defaults to zero. The index
      range must fit in the buffer. If the pipeline reads vertex data, bind a
      live vertex buffer and supply indices into its vertex data. The binding
      does not inspect the index values. The same uniform and sampler rules
      apply as for [draw_primitives]. *)

  val end_render_pass : render_pass -> unit
  (** End the pass. Calling this again on an ended pass does nothing. *)

  val clear_and_present : swapchain -> Color.t -> bool
  (** Wait for a window image, clear it to the given color, and submit it for
      presentation. Return [false] if no image can be acquired, for example if
      the window is minimized. No commands or image handles escape this call. *)
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

module Touch : sig
  (** Touch device and finger queries. Start SDL with [Video]. *)

  type id
  type finger_id

  type device_type =
    | Direct
    | Indirect_absolute
    | Indirect_relative
    | Other of int

  type finger = { id : finger_id; x : float; y : float; pressure : float }

  val id_to_int64 : id -> int64
  val finger_id_to_int64 : finger_id -> int64

  val devices : context -> id list
  (** List known devices. On some systems, a device only appears after use. *)

  val name : context -> id -> string
  val device_type : context -> id -> device_type

  val fingers : context -> id -> finger list
  (** Copy the active fingers on a device. SDL reports coordinates and pressure
      on a scale of zero to one. Coordinates outside the touch area can lie
      outside that range. *)
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

  val id_to_int32 : id -> int32

  val list : context -> id list
  (** List connected gamepads. Start SDL with [Gamepad]. *)

  val name_for_id : context -> id -> string
  (** Read the name before opening a gamepad. *)

  val open_ : context -> id -> t
  (** Open a device from [list] or a [Gamepad_added] event. *)

  val close : t -> unit
  val connected : t -> bool
  val id : t -> id
  val name : t -> string
  val has_axis : t -> axis -> bool
  val has_button : t -> button -> bool

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
        (** [window] is [None] when SDL reports no window under the finger. [dx]
            and [dy] use the same scale as the finger's coordinates. *)
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
