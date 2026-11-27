(** A thin binding for SDL 3.4.20 or later. Load this module on the main thread.
    Except where noted, call the binding on that thread, including all cleanup
    calls. *)

exception Error of string
(** An SDL call failed or a loaded SDL library is too old. For a failed call,
    the message names the SDL function and includes its error if available. *)

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
(** Close SDL. Raise [Invalid_argument] if a resource is open or an image load
    is in progress. Calling this again on a closed context does nothing. *)

val with_init : subsystem list -> (context -> 'a) -> 'a
(** Start SDL and call [quit] when the function exits. Close all resources and
    join image loading jobs inside the function, even if an exception occurs. *)

module Path : sig
  (** Platform directories for application assets and user data. Call on the
      main thread. No SDL context is needed. *)

  val base : unit -> string
  (** Copy SDL's base directory for application assets. It can differ from the
      current working directory. The UTF-8 path ends with a separator. Raise
      [Error] if SDL cannot find a base directory. *)

  val pref : org:string -> app:string -> string
  (** Find the user directory for saves and configuration. SDL creates it if
      needed. The UTF-8 path ends with a separator. Use stable names with
      letters, numbers, and spaces for portability. An empty [org] omits the
      organization directory. [app] must not be empty. Both names must be valid
      UTF-8. Do not use NUL, slashes, backslashes, colons, or the names ["."]
      and [".."]. Raise [Error] if SDL cannot provide the directory. *)
end

module Io : sig
  (** File and memory streams. The caller owns each stream and closes it with
      [close]. Use any live SDL context. No subsystem is needed. *)

  type 'access t
  (** The type parameter specifies whether a stream supports reading, writing,
      or both. *)

  type _ file_mode =
    | Read : [ `Read ] file_mode  (** Open an existing file for reading. *)
    | Write : [ `Write ] file_mode  (** Create or empty a file for writing. *)
    | Append : [ `Write ] file_mode
        (** Create a file if needed. Write at the end, even after a seek. *)
    | Update : [ `Read | `Write ] file_mode
        (** Read and write an existing file. Keep its contents. *)
    | Create : [ `Read | `Write ] file_mode
        (** Create or empty a file for reading and writing. *)
    | Append_update : [ `Read | `Write ] file_mode
        (** Read and append to a file. Create it if needed. *)

  type origin = Start | Current | End

  val open_file : context -> mode:'access file_mode -> string -> 'access t
  (** Open a file in binary mode. Seek when you switch between reading and
      writing on the same file stream. *)

  val with_file :
    context -> mode:'access file_mode -> string -> ('access t -> 'a) -> 'a
  (** Close the stream when the function exits, even if it raises. Close any
      resource that uses the stream before the function exits. *)

  val of_memory : context -> byte_buffer -> [ `Read ] t
  (** Open a read-only stream over a nonempty buffer. The stream keeps the
      buffer alive without copying it. Use [Bigarray.Array1.sub] to select a
      region of a larger buffer. *)

  val of_memory_rw : context -> byte_buffer -> [ `Read | `Write ] t
  (** Read or write a nonempty buffer without copying it. The stream size is the
      buffer size and does not grow. Writes change the original buffer. *)

  val close : 'access t -> unit
  (** Close the stream, including its file if it has one. Close any resource
      that uses the stream first. If closing raises [Error], the stream is still
      closed. Calling [close] again does nothing. *)

  val size : 'access t -> int64
  val tell : 'access t -> int64

  val seek : 'access t -> from:origin -> int64 -> int64
  (** Move by the given byte offset relative to [from]. Return the new byte
      position. Memory streams limit the position to the buffer bounds. *)

  val read : [> `Read ] t -> byte_buffer -> offset:int -> length:int -> int
  (** Read up to [length] bytes into the buffer at [offset]. Return the byte
      count. Return zero at end of input or if [length] is zero. The buffer
      range must not overlap the stream's backing memory. *)

  val write : [> `Write ] t -> byte_buffer -> offset:int -> length:int -> unit
  (** Write the buffer range at [offset]. A short write raises [Error] after
      writing as many bytes as SDL can. The range must not overlap the stream's
      backing memory. *)

  val flush : [> `Write ] t -> unit
  (** Flush pending output. *)
end

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
  type t =
    | Rgba32
    | Bgra32
    | Rgb24
    | Index8  (** [Index8] stores a one-byte palette index per pixel. *)
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

module Blend_mode : sig
  type factor =
    | Zero
    | One
    | Src_color
    | One_minus_src_color
    | Src_alpha
    | One_minus_src_alpha
    | Dst_color
    | One_minus_dst_color
    | Dst_alpha
    | One_minus_dst_alpha

  type operation = Sum | Subtract | Reverse_subtract | Minimum | Maximum
  type equation = { src : factor; dst : factor; op : operation }

  type custom
  (** A mode made by [compose]. *)

  type t = None | Blend | Add | Mod | Mul | Custom of custom

  val compose : color:equation -> alpha:equation -> t
  (** Make a blend mode for [Renderer.set_draw_blend_mode] or
      [Texture.set_blend_mode]. The source is the pixel being drawn. The
      destination is the pixel already in the target. Multiply each by its
      factor, then apply [op] to the products. [Subtract] takes source minus
      destination. [Reverse_subtract] takes destination minus source.

      This function needs no SDL context and works on any thread. SDL checks
      support when you set the mode. If the renderer does not support it, the
      setter raises [Error]. The software renderer does not support custom
      equations beyond those that map to SDL's standard modes. *)
end

module Surface : sig
  (** A pixel buffer in memory. Use any live SDL context. No subsystem is
      needed. *)

  type t
  type scale_mode = Nearest | Linear
  type flip = No_flip | Horizontal | Vertical | Both
  type color_key = Color of Color.t | Index of int

  module Palette : sig
    (** An owned color table for [Index8] surfaces. *)

    type t

    val create : context -> Color.t array -> t
    (** Create 256 entries. Copy up to 256 colors starting at index zero and
        leave the remaining entries opaque white. *)

    val set_colors : t -> first:int -> Color.t array -> unit
    (** Replace consecutive entries starting at [first]. Indices start at zero.
        The whole range must fit. All surfaces that use this table see the new
        colors. Textures already made from them stay unchanged. *)

    val destroy : t -> unit
    (** Release the caller's reference. Surfaces that use this palette keep
        their own references. Calling [destroy] again does nothing. *)
  end

  val create : ?format:Pixel_format.t -> context -> w:int -> h:int -> t
  (** Create a surface with zeroed pixels. The default format is [Rgba32]. An
      [Index8] surface starts with an opaque white palette. Dimensions must be
      positive. The byte size, including row padding, must fit a C [int]. *)

  val load_bmp : context -> string -> t
  val save_bmp : t -> string -> unit

  val load_bmp_io : [> `Read ] Io.t -> t
  (** Read a BMP from the current position in a seekable stream. The stream
      stays open and the surface does not retain it. *)

  val save_bmp_io : t -> [> `Write ] Io.t -> unit
  (** Write a BMP to a seekable stream. The stream stays open. Raise
      [Invalid_argument] for an append stream because SDL seeks back to update
      the BMP header. *)

  val destroy : t -> unit
  val size : t -> int * int

  val format : t -> Pixel_format.t option
  (** Return [None] if the format is not listed in [Pixel_format]. *)

  val fill : ?rect:Rect.t -> t -> Color.t -> unit
  val read_pixel : t -> x:int -> y:int -> Color.t

  val read_rgba : t -> byte_buffer -> unit
  (** Copy the whole surface into the buffer in red, green, blue, alpha byte
      order. Rows have no padding. SDL converts other pixel formats to RGBA.
      Raise [Invalid_argument] if the buffer holds fewer than
      [4 * width * height] bytes. Bytes after the image stay unchanged. *)

  val blit : ?src:Rect.t -> ?dst:Rect.t -> t -> t -> unit
  (** [blit source target] copies pixels from [source] to [target] without
      scaling. The surfaces must be distinct. If [src] is absent, use the whole
      source. Use only [x] and [y] of [dst], or [(0, 0)] if it is absent. SDL
      clips the copy to both surfaces. The source controls blending. Use formats
      with whole bytes per pixel. The surface dimensions must be at most 65,535
      pixels. *)

  val blit_scaled :
    ?src:Rect.t -> ?dst:Rect.t -> ?scale_mode:scale_mode -> t -> t -> unit
  (** Like [blit], but resize the source region to fit the destination
      rectangle. Both rectangles default to the respective whole surface. The
      source rectangle must lie inside the source. SDL clips to the destination.
      Empty rectangles draw nothing. The default scale mode is [Nearest].

      When scaling, the width and height of each rectangle must be at most
      32,767 pixels. For linear filtering, use true-color surfaces and no source
      color key. If a scaled copy is clipped at the destination and the source
      has a color key, convert the source to [Rgba32] first. *)

  val convert : t -> format:Pixel_format.t -> t
  (** Copy into a new surface with the requested format. You can destroy the
      source first. If the destination format is [Index8], SDL chooses its
      palette and maps colors to that palette. *)

  val scale : ?scale_mode:scale_mode -> t -> w:int -> h:int -> t
  (** Copy at the given size without blending into another image. Destroy the
      result separately. The default scale mode is [Nearest]. Each dimension of
      the source and result must be in [1, 32767]. Use a format with whole bytes
      per pixel. An [Index8] copy always uses nearest sampling. It keeps the
      indices and shares the original palette. The copy keeps any color key. *)

  val flip : t -> flip -> unit
  (** Change the surface in place. [Both] reverses rows and columns. *)

  val set_color_key : t -> color_key option -> unit
  (** Set the source pixel that SDL treats as transparent in copies. [Color c]
      maps the RGB channels to a source pixel and ignores [c.a]. [Index i]
      selects an exact palette entry. Pass [None] to disable the key. For a
      surface with an alpha channel, use blend mode [Blend_mode.None] if you
      want blits to use the key instead of source alpha. *)

  val set_blend_mode : t -> Blend_mode.t -> unit
  (** Select how SDL combines this source with the destination in a blit. Custom
      equations that do not map to a standard mode raise [Error]. *)

  val set_palette : t -> Palette.t -> unit
  (** Change the colors of an [Index8] surface without changing its pixel
      indices. The surface retains its own reference to the palette. *)

  module Locked : sig
    (** Access to the pixels of one surface. All operations raise
        [Invalid_argument] after the lock ends. *)

    type t

    val size : t -> int * int
    val read_pixel : t -> x:int -> y:int -> Color.t

    val set_pixel : t -> x:int -> y:int -> Color.t -> unit
    (** Write one color in the surface's format. An indexed surface maps it to a
        palette entry. Coordinates must be inside the surface. *)

    val read_index : t -> x:int -> y:int -> int

    val set_index : t -> x:int -> y:int -> int -> unit
    (** Read or write an exact pixel index on an [Index8] surface. A written
        index must exist in the current palette. *)

    val copy_from : t -> byte_buffer -> pitch:int -> unit
    (** Copy rows from the buffer into the whole surface. Use the surface's byte
        order: RGBA, BGRA, RGB, or one palette index per pixel. Only the four
        formats in [Pixel_format] support this operation.

        [pitch] is the byte distance between buffer rows. It must cover at least
        one row of pixels. The last row does not need padding. SDL does not
        retain the buffer. Do not change it during the call. *)

    val copy_to : t -> byte_buffer -> pitch:int -> unit
    (** Copy rows in the same format as [copy_from]. Leave all buffer bytes
        outside the pixels, including padding, unchanged. *)
  end

  val with_lock : t -> (Locked.t -> 'a) -> 'a
  (** Run the callback on the main thread with read and write access. The lock
      preserves existing pixels. It ends when the callback returns or raises,
      and writes before an exception stay in the surface.

      Use a surface with whole bytes per pixel, not a packed bitmap or a YUV
      surface. Destroy any software renderer for the surface before locking it.
      During the callback, do not lock, destroy, or use the surface for a copy,
      save, or draw. Use [Locked] to access the pixels. You can still call
      [size] and [format]. *)
end

module Image_data : sig
  (** Decode trusted BMP assets on any thread, including an OCaml worker domain.
      Use a live SDL context. No subsystem is needed. These calls run to
      completion on the calling thread. They do not create threads or keep SDL
      surfaces open. Join loading jobs before calling [quit]. The decoded byte
      count must fit both an OCaml [int] and a C [int]. *)

  type t = private { w : int; h : int; rgba : byte_buffer }
  (** The buffer holds [4 * w * h] bytes in red, green, blue, alpha order. Rows
      start at the top and have no padding. The result can outlive the SDL
      context and needs no explicit cleanup. Use a synchronized handoff such as
      [Domain.join] to pass it to another domain. Do not change its bytes while
      another thread reads or uploads them. *)

  val load_bmp : context -> string -> t
  (** Open a BMP file, decode it, and close the file. *)

  val load_bmp_memory : context -> byte_buffer -> t
  (** Decode a nonempty buffer. Keep the input bytes unchanged during this call.
      The result does not retain the input. *)
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

  val set_icon : t -> Surface.t -> unit
  (** Copy an unlocked surface for the window icon. You can destroy the source
      after the call. Some windowing systems do not support icons. *)

  val set_size : t -> w:int -> h:int -> unit

  val set_minimum_size : t -> w:int -> h:int -> unit
  (** Set the minimum client area size in window coordinates. Each dimension
      must be nonnegative. Zero removes the limit for that dimension. *)

  val set_position : t -> x:int -> y:int -> unit
  (** Request a move to the given screen coordinates. The window manager can
      apply the move later, change the coordinates, or refuse the request. *)

  val set_resizable : t -> bool -> unit
  (** Allow or prevent the user from resizing the window. Raise [Error] if the
      video driver does not support this change. *)

  val set_fullscreen_mode : t -> Display.mode option -> unit
  (** Select a mode for exclusive fullscreen. Use a mode from
      [Display.fullscreen_modes] on the window's current display. All four
      fields must match. If several modes match, use the first in SDL's list.
      Raise [Invalid_argument] if no mode matches. Use [None] for borderless
      fullscreen at the desktop mode.

      This call does not enter fullscreen. Use [set_fullscreen] to do that. If
      the window is already fullscreen, the mode change can take effect later.
  *)

  val set_fullscreen : t -> bool -> unit

  val set_mouse_grab : t -> bool -> unit
  (** Confine the pointer to this window while the window has input focus. Set
      this to [false] to release the grab. Unlike [Mouse.capture], a grab keeps
      the pointer inside the window. *)

  val mouse_grab : t -> bool
  (** Whether SDL reports an active mouse grab for this window. *)

  val show : t -> unit
  val hide : t -> unit
  val minimize : t -> unit

  val maximize : t -> unit
  (** Request to maximize a resizable window. *)

  val restore : t -> unit
end

type +'access texture
(** A texture handle. The type parameter marks how you can use it. *)

module Renderer : sig
  type t
  type presentation = Stretch | Letterbox | Overscan | Integer_scale

  type geometry_buffer =
    (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t
  (** A flat buffer of 32-bit floats that you can reuse between draws. *)

  type geometry_indices =
    (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
  (** A flat buffer of zero-based vertex indices. *)

  val drivers : unit -> string list
  (** List the renderer drivers built into SDL, in preference order. You can
      call this without an SDL context and on any thread. A listed driver can
      still fail to start. *)

  val create : ?driver:string -> Window.t -> t
  (** Create a renderer for a window with no renderer or GPU claim. *)

  val create_software : Surface.t -> t
  (** Draw to the surface. Destroy the renderer before locking or destroying
      that surface. *)

  val destroy : t -> unit

  val name : t -> string
  (** Copy the name of the selected driver. *)

  val max_texture_size : t -> int option
  (** Get the reported limit in pixels for each texture axis. [None] means the
      driver reports no limit. Allocation can still fail below this limit. *)

  val texture_formats : t -> string list
  (** Copy the SDL names of the native texture formats that the driver reports,
      such as ["SDL_PIXELFORMAT_ARGB8888"]. SDL can also convert other formats
      when it uploads a surface. *)

  val output_size : t -> int * int
  (** The output size in pixels, as reported by SDL. If you draw to a texture,
      use [current_output_size]. *)

  val current_output_size : t -> int * int
  (** The size of the current target, adjusted for logical presentation. *)

  val set_vsync : t -> bool -> unit

  val vsync : t -> int
  (** Get the vertical refresh interval. [0] means disabled, [-1] means
      adaptive, and positive values count display refreshes per presentation. *)

  val set_target : t -> [ `Target ] texture option -> unit
  (** Draw to a texture that belongs to this renderer. Pass [None] to draw to
      the window or surface again. *)

  val set_logical_presentation : t -> (int * int * presentation) option -> unit
  (** Set a virtual width and height for the current target. Pass [None] to turn
      off logical presentation for that target. *)

  val logical_presentation_rect : t -> Frect.t
  (** Get the current target's presentation rectangle in output pixels. When
      logical presentation is off, this covers the whole target. *)

  val set_viewport : t -> Rect.t option -> unit
  (** Set the drawing area of the current target. Its top-left becomes the
      drawing origin. Its dimensions must be nonnegative. Pass [None] to use the
      entire target again. *)

  val viewport : t -> Rect.t
  (** Get the current target's drawing area in render units. This also returns
      the effective area when no explicit rectangle is set. *)

  val viewport_is_set : t -> bool
  (** Return true if the current target has an explicit viewport. Use this to
      distinguish a saved rectangle from the automatic viewport. *)

  val set_clip_rect : t -> Rect.t option -> unit
  (** Limit drawing on the current target, without moving its origin. The
      rectangle is relative to the viewport. Its dimensions must be nonnegative.
      Pass [None] to disable this extra clip. *)

  val clip_rect : t -> Rect.t option
  (** Get the current target's clip rectangle, or [None] when it is disabled. An
      enabled empty rectangle is [Some rect], not [None]. *)

  val set_scale : t -> x:float -> y:float -> unit
  (** Set the horizontal and vertical drawing scales on the current target. The
      factors must be finite and positive and keep the view in SDL's coordinate
      range. Pass [1.] on both axes to reset the scale. *)

  val scale : t -> float * float
  (** Get the current target's drawing scale, without logical presentation. *)

  val coordinates_from_window : t -> x:float -> y:float -> float * float
  (** Convert a point from window units to render units for the default target.
      SDL uses pixel density, logical presentation, drawing scale, and viewport.
      The result can lie outside the drawing area. On a software surface
      renderer, use surface pixels instead of window units. *)

  val coordinates_to_window : t -> x:float -> y:float -> float * float
  (** Convert a point from the default target's render units to window units.
      Like [coordinates_from_window], this uses the default target's view even
      when a texture is active. *)

  val set_draw_color : t -> Color.t -> unit
  val set_draw_blend_mode : t -> Blend_mode.t -> unit

  val clear : t -> unit
  (** Clear the entire current target, even if a viewport or clip is set. *)

  val fill_rect : t -> Frect.t -> unit
  val draw_rect : t -> Frect.t -> unit

  val fill_rects : t -> Frect.t array -> unit
  (** Fill all rectangles with the current drawing color in one call to SDL. An
      empty array draws nothing. *)

  val draw_rects : t -> Frect.t array -> unit
  (** Draw the outlines of all rectangles in one call to SDL. An empty array
      draws nothing. *)

  val draw_line : t -> x1:float -> y1:float -> x2:float -> y2:float -> unit

  val draw_geometry :
    ?texture:'access texture * geometry_buffer ->
    ?indices:geometry_indices * int ->
    t ->
    positions:geometry_buffer ->
    colors:geometry_buffer ->
    vertex_count:int ->
    unit
  (** Draw a list of triangles on the main thread. For each of the first
      [vertex_count] vertices, supply a finite [x, y] pair in [positions] and a
      red, green, blue, alpha group in [colors]. Each color component must be
      between 0 and 1, inclusive. Positions use the renderer's current
      coordinate system, including logical presentation.

      Without [indices], each group of three consecutive vertices forms a
      triangle. With [indices:(buffer, count)], use the first [count] indices
      instead. Each index must be nonnegative and less than [vertex_count]. The
      number of vertices or indices that form triangles must be a multiple of
      three. Counts must be nonnegative. If the triangle count is zero, check
      the handles and buffer sizes but draw nothing.

      For a textured draw, pass [texture:(image, uv)] with one [u, v] pair per
      vertex. Both coordinates must be between 0 and 1, inclusive. The pair
      [0, 0] is the top-left corner of the texture and [1, 1] the bottom-right.
      The texture must belong to this renderer. It cannot be locked or be the
      current target.

      Vertex colors replace the renderer's draw color or the texture's color and
      alpha settings. Untextured triangles use the renderer's draw blend mode.
      Textured triangles use the texture's blend mode. They use its scale mode
      on accelerated renderers. The software renderer uses nearest filtering and
      limits coordinate ranges and the size of textured triangles.

      Draw in the given order. Raise [Invalid_argument] for invalid input before
      drawing. An SDL error can occur after SDL queues some triangles. SDL does
      not retain the buffers. Do not change them during the call. *)

  val read_pixels : ?rect:Rect.t -> t -> Surface.t
  (** Copy pixels from the current target on the main thread. The optional
      rectangle uses absolute target pixels, not drawing coordinates. Its
      dimensions must be positive. The read is clipped to the viewport and
      target bounds. Without a rectangle, read the whole visible viewport. The
      drawing clip does not restrict the read.

      Read after drawing and before [present] when the target is the window.
      This call can be slow. Use a texture target with the [vulkan] renderer. An
      empty read or an unsupported read raises [Error].

      On a software surface target, use a format with whole bytes per pixel. A
      copy of an indexed surface has its own palette. The result can outlive the
      renderer and target. Destroy it with {!Surface.destroy} before you quit
      SDL. *)

  val present : t -> unit
  (** Present the frame. Raise [Invalid_argument] if a texture is the current
      target. *)
end

module Texture : sig
  (** An image owned by a renderer. Use that renderer for all draws. Do not draw
      a locked texture or draw a texture into itself. *)

  type t = [ `Static | `Streaming | `Target ] texture
  (** A drawable texture. Use [(tex :> Texture.t)] to store [streaming],
      [target], and other textures together. *)

  type streaming = [ `Streaming ] texture
  type target = [ `Target ] texture
  type scale_mode = Surface.scale_mode = Nearest | Linear
  type flip = Surface.flip = No_flip | Horizontal | Vertical | Both

  type borders = { left : float; right : float; top : float; bottom : float }
  (** Widths of the left and right borders and heights of the top and bottom
      borders, in source pixels. *)

  val of_surface : Renderer.t -> Surface.t -> t
  (** Copy the pixels. You can then destroy the surface. *)

  val of_image_data : Renderer.t -> Image_data.t -> t
  (** Create a static texture from decoded pixels on the main thread. The
      texture does not retain the buffer. Keep its bytes unchanged during the
      call. *)

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

  val set_color_mod : 'access texture -> Color.t -> unit
  (** For texture copies, multiply each red, green, and blue channel by the
      corresponding value divided by 255. White resets the color. Ignore the
      color's alpha and keep the texture's alpha setting. *)

  val set_alpha_mod : 'access texture -> int -> unit
  (** Multiply the texture's opacity by this value divided by 255. Use a value
      in [0, 255]. This does not change its RGB setting. *)

  val draw :
    ?src:Frect.t -> ?dst:Frect.t -> Renderer.t -> 'access texture -> unit
  (** Draw with the renderer that owns the texture. Do not draw a texture into
      itself. If you omit [src] or [dst], SDL uses the whole texture or
      viewport, respectively. *)

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
    ?pivot:float * float ->
    Renderer.t ->
    'access texture ->
    angle:float ->
    unit
  (** Like [draw], but rotate clockwise by [angle] degrees. [pivot] is relative
      to the top-left of the unrotated destination, in destination units. It can
      lie outside the rectangle. The default is the center. Flipping does not
      move the pivot. Destination dimensions must be nonnegative. The software
      renderer skips rotated or flipped copies smaller than one unit on either
      axis. *)

  val draw_affine :
    ?src:Frect.t ->
    Renderer.t ->
    'access texture ->
    origin:float * float ->
    right:float * float ->
    down:float * float ->
    unit
  (** Map the source's top-left, top-right, and bottom-left corners to the given
      points. The fourth corner is [right + down - origin]. All three points are
      absolute positions in the current render coordinates, not offsets. [src]
      defaults to the whole texture. If supplied, it must have positive
      dimensions and lie inside the texture. The software renderer uses nearest
      filtering and limits the size of the resulting triangles. *)

  val draw_tiled :
    ?src:Frect.t ->
    ?dst:Frect.t ->
    ?scale:float ->
    Renderer.t ->
    'access texture ->
    unit
  (** Repeat [src] across [dst], starting at its top-left. The last tiles can be
      partial. [src] defaults to the whole texture. If supplied, it must have
      positive dimensions and lie inside the texture. [dst] defaults to the
      whole viewport. Destination dimensions must be nonnegative. A zero width
      or height draws nothing. [scale] is a finite positive multiplier for the
      tile size and defaults to [1.]. On paths where SDL can queue each tile
      separately, the draw is limited to 1,048,576 tiles. *)

  val draw_nine_slice :
    ?src:Frect.t ->
    ?dst:Frect.t ->
    ?scale:float ->
    Renderer.t ->
    'access texture ->
    borders:borders ->
    unit
  (** Draw a resizable panel from a 3 by 3 grid. Scale each corner by [scale]
      and stretch the edges and center. [src] defaults to the whole texture. If
      supplied, it must have positive dimensions and lie inside the texture.
      [dst] defaults to the whole viewport. The borders must be nonnegative and
      leave a positive center in the source. The destination must fit both pairs
      of borders after SDL scales and rounds each border up. Use a finite
      nonnegative [scale]. The default is [1.]. Passing [0.] has the same
      effect. *)
end

module Sprite_batch : sig
  (** Reusable storage for an ordered batch of sprites from one texture. You can
      create and edit a batch without an SDL context. Do not access the same
      batch from multiple threads or domains at the same time. *)

  type t

  val create : capacity:int -> t
  (** Allocate an empty batch with a fixed capacity. Zero is allowed. *)

  val capacity : t -> int
  val length : t -> int

  val clear : t -> unit
  (** Remove all sprites without freeing the storage. *)

  val add :
    ?tint:Color.t ->
    ?opacity:int ->
    ?angle:float ->
    ?pivot_x:float ->
    ?pivot_y:float ->
    ?flip:Texture.flip ->
    t ->
    src:Rect.t ->
    x:float ->
    y:float ->
    w:float ->
    h:float ->
    unit
  (** Append a sprite. [src] selects a rectangle in texture pixels. Its origin
      must be nonnegative. Its size and the destination size [w, h] must be
      positive. [x, y] is the top-left of the unrotated destination.

      [angle] is clockwise in degrees and defaults to zero. [pivot_x] and
      [pivot_y] are relative to [x, y], in destination units. They default to
      half of [w] and [h], respectively, and can be outside the rectangle.
      [flip] mirrors the source within the sprite and does not move its pivot.

      The default tint is white and the default opacity is 255. [opacity] must
      be in [0, 255]. It multiplies [tint.a]. Both affect the texture's own
      pixel colors and alpha, not its persistent modulation settings.

      Raise [Invalid_argument] if the batch is full or if the source, size,
      pivot, rotation, or opacity is invalid. [draw] checks positions and source
      bounds against the chosen texture. *)

  val positions : t -> Float.Array.t
  (** The stored destination positions as consecutive [x, y] pairs. The array
      length is twice [capacity]. Edit the first [2 * length] entries in place
      to move existing sprites without rebuilding the batch. Do not edit the
      array during a draw. *)

  val set_tint : t -> index:int -> Color.t -> unit
  (** Replace the tint, including its alpha, without changing the sprite's
      opacity or draw order. Raise [Invalid_argument] if the zero-based [index]
      is negative or at least the batch's [length]. *)

  val set_opacity : t -> index:int -> int -> unit
  (** Set the opacity without changing the sprite's tint or draw order. The
      opacity multiplies the tint's alpha and must be between 0 and 255. Raise
      [Invalid_argument] if the opacity or [index] is out of range. *)

  val draw : Renderer.t -> 'access texture -> t -> unit
  (** Draw the sprites on the main thread in insertion order. The texture must
      belong to the renderer. It cannot be locked or be the current render
      target. An empty batch draws nothing. SDL does not retain the batch.

      Each source rectangle must fit inside the texture. Positions and
      transformed corners must fit finite C floats. The software renderer also
      limits coordinates and sizes to its integer and fixed-point ranges. It
      skips rotated or flipped sprites with a destination width or height less
      than one. Raise [Invalid_argument] without drawing if any sprite is
      invalid. If an SDL call raises [Error], earlier sprites can already be
      queued.

      Sprites use the texture's scale and blend modes. Their tint and opacity
      replace its color and alpha modulation for this draw only. Use
      [Blend_mode.Blend] for transparency. *)
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

  module Blend : sig
    type t = { color : Blend_mode.equation; alpha : Blend_mode.equation }
    (** Combine the fragment shader output (source) with the current target
        pixel (destination). Apply [color] to RGB and [alpha] to the alpha
        channel. In the alpha equation, a color factor uses the corresponding
        alpha. [Minimum] and [Maximum] compare the unscaled values, so the GPU
        ignores their factors. *)

    val straight_alpha : t
    (** Multiply source RGB by source alpha before blending. The RGB result adds
        that product to [destination RGB * (1 - source alpha)]. The alpha result
        is [source alpha + destination alpha * (1 - source alpha)]. *)

    val premultiplied_alpha : t
    (** Like [straight_alpha], but the shader must output RGB already multiplied
        by source alpha. *)

    val additive : t
    (** Add [source RGB * source alpha] to destination RGB. Preserve destination
        alpha. *)

    val modulate : t
    (** Multiply source and destination RGB. Preserve destination alpha. *)

    val multiply : t
    (** Add [source RGB * destination RGB] to
        [destination RGB * (1 - source alpha)], as in [Blend_mode.Mul]. Preserve
        destination alpha. *)
  end

  type color_component = Red | Green | Blue | Alpha
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
    ?blend:Blend.t ->
    ?color_write_mask:color_component list ->
    swapchain ->
    vertex:vertex shader ->
    fragment:fragment shader ->
    primitive:primitive ->
    graphics_pipeline
  (** Create a pipeline for the claim's current pixel format. Both shaders must
      belong to the device that claimed the window. If the vertex shader has
      attributes, pass its layout for one vertex buffer. Otherwise omit
      [vertex_layout]. The pipeline uses one color target with no depth test or
      face culling.

      Without [blend], fragments replace the target values. If
      [color_write_mask] is present, draws write only the listed channels,
      whether or not blending is enabled. An empty list writes no channels.
      Omitting the mask writes all channels. The mask does not affect clears.

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
      order. *)

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

  val set_text_input_area : ?cursor:int -> Window.t -> Rect.t option -> unit
  (** Tell the system where text input occurs. Use window coordinates, not
      renderer coordinates. [cursor] is a horizontal offset from the area's [x],
      not a text index. It defaults to zero. Pass [None] to clear the area and
      reset the offset. The system can use this area to place suggestions. *)

  val text_input_area : Window.t -> Rect.t * int
  (** Return the rectangle and cursor offset stored by SDL. Both are zero before
      you set an area and after you clear it. *)
end

module Clipboard : sig
  (** Copy and paste plain text. Start SDL with [Video] and call these functions
      on the main thread. *)

  val set_text : context -> string -> unit
  (** Copy valid UTF-8 without NUL bytes to the clipboard. Pass an empty string
      to clear the clipboard. *)

  val get_text : context -> string
  (** Copy clipboard text into an OCaml string. SDL returns an empty string if
      there is no text or if the system returns no data. *)

  val has_text : context -> bool
  (** Ask whether the clipboard contains nonempty text. The contents can change
      before the next read. *)
end

module Mouse : sig
  (** Mouse state, movement, and cursors. Start SDL with [Video] and call these
      functions on the main thread. [is_pressed] can read a saved button state
      on any thread. *)

  type button = Left | Middle | Right | X1 | X2 | Other of int
  type buttons
  type state = { x : float; y : float; buttons : buttons }
  type relative_state = { dx : float; dy : float; buttons : buttons }

  val is_pressed : buttons -> button -> bool

  val state : context -> state
  (** Read the cached position and pressed buttons without pumping events. [x]
      and [y] are relative to the top-left of the window with mouse focus. If no
      window has mouse focus, the coordinates are not tied to a window. *)

  val global_state : context -> state
  (** Ask the system for the current pointer position on the desktop and the
      pressed buttons. This can cost more than [state]. SDL falls back to
      [state] on drivers without a desktop query. *)

  val relative_state : context -> relative_state
  (** Read the pressed buttons and the movement that SDL accumulated since the
      last call. Each call resets that movement. Read it once per frame if other
      code also needs the result. *)

  val set_relative_mode : Window.t -> bool -> unit

  val capture : context -> bool -> unit
  (** Send mouse events to the focused window even when the pointer leaves it.
      Capture does not confine the pointer. Coordinates stay relative to the
      window and can be outside its bounds. Set this to [false] when a drag ends
      or the window loses keyboard focus. SDL can capture automatically while a
      button is down. If the driver does not support explicit capture, this
      function raises [Error]. *)

  val warp_in_window : Window.t -> x:float -> y:float -> unit
  (** Request a pointer move in window coordinates. The coordinates must fit
      finite C floats and the C [int] range. SDL normally queues a motion event
      outside relative mode. Some systems ignore the move. *)

  module Cursor : sig
    type t
    (** An owned cursor. Destroy it before quitting SDL. *)

    type system =
      | Default
      | Text
      | Wait
      | Crosshair
      | Progress
      | Resize_nwse
      | Resize_nesw
      | Resize_ew
      | Resize_ns
      | Move
      | Not_allowed
      | Pointer
      | Resize_nw
      | Resize_n
      | Resize_ne
      | Resize_e
      | Resize_se
      | Resize_s
      | Resize_sw
      | Resize_w

    val create_color : Surface.t -> hot_x:int -> hot_y:int -> t
    (** Create a cursor from a surface. The hot spot is the pixel that points at
        the target. Both offsets must lie inside the surface. Newer SDL versions
        can use hot spot metadata from a loaded cursor image. You can destroy
        the surface after this call. *)

    val create_system : context -> system -> t
    (** Create a cursor in a system style. If the driver cannot create it, raise
        [Error]. *)

    val set : t -> unit
    (** Select this cursor for the application, without changing visibility. *)

    val reset : context -> unit
    (** Select SDL's default cursor. This does not destroy any cursor. *)

    val destroy : t -> unit
    (** Destroy the cursor. If it is active, SDL selects the default cursor. It
        is safe to destroy the same cursor again. *)

    val show : context -> unit
    val hide : context -> unit

    val visible : context -> bool
    (** Read SDL's visibility setting. For example, relative mode can still hide
        a cursor that this setting marks as visible. *)
  end
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

  val rumble : t -> low:int -> high:int -> duration_ms:int -> unit
  (** Set vibration on the low and high frequency motors. Each intensity is in
      [0, 65535]. A new effect replaces the old one. Set both intensities to
      zero to stop. Otherwise, use a positive duration in milliseconds. The
      duration must fit an unsigned 32-bit integer. SDL can shorten long
      effects. Keep reading events so SDL can update the effect. Raise [Error]
      if SDL cannot start the effect. *)
end

module Audio : sig
  (** Start SDL with [Audio] to list devices and open streams. *)

  type playback
  type recording
  type 'direction stream
  type t = playback stream
  type format = U8 | S16 | S32 | F32

  type spec = { format : format; channels : int; frequency : int }
  (** A frame contains one sample per channel. [channels] is between 1 and 8.
      [frequency] is the number of frames per second. Multi-byte samples use
      native byte order. *)

  type buffer = byte_buffer

  module Device : sig
    type 'direction id
    (** A device ID can become invalid if the device disconnects. Do not save
        IDs for later runs. *)

    val list_playback : context -> playback id list
    val list_recording : context -> recording id list
    val name : context -> 'direction id -> string
  end

  val open_playback : ?device:playback Device.id -> context -> spec -> t
  (** Open a paused playback stream. The device defaults to the system's
      playback device. [spec] describes the samples that you queue. *)

  val open_recording :
    ?device:recording Device.id -> context -> spec -> recording stream
  (** Open a paused recording stream. The device defaults to the system's
      recording device. SDL converts the recorded samples to [spec]. *)

  val close : 'direction stream -> unit
  (** Close the stream and its device connection. *)

  val pause : 'direction stream -> unit
  val resume : 'direction stream -> unit

  val clear : 'direction stream -> unit
  (** Drop pending data. *)

  val flush : 'direction stream -> unit
  (** Tell SDL to finish converting any buffered input. Use this at the end of
      playback, or after pausing a recording to read the remaining data. *)

  val queued_bytes : t -> int

  val queue : t -> buffer -> unit
  (** Copy samples into the stream. Use [Bigarray.Array1.sub] to queue part of a
      buffer without a slice copy. *)

  val available_bytes : recording stream -> int
  (** Number of converted bytes ready to read. SDL can add more before the next
      call to [read]. *)

  val read : recording stream -> buffer -> int
  (** Copy available data into the buffer without waiting for more samples.
      Return the number of bytes written in whole frames, or zero if none fit or
      none are ready. Leave the rest of the buffer unchanged. You can pass a
      bigarray slice. Its address must be a multiple of the sample size in
      bytes. *)
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
    | Mouse_entered  (** The window gained mouse focus. *)
    | Mouse_left  (** The window lost mouse focus. *)

  type display_change =
    | Connected
    | Disconnected
    | Layout_changed
    | Desktop_mode_changed
    | Current_mode_changed
    | Content_scale_changed

  type touch_change = Down | Up | Motion | Canceled

  type drop_change =
    | Begin
    | File of string
    | Text of string
    | Complete
    | Position of { x : float; y : float }
        (** SDL uses [Begin] and [Complete] to group items in one drop. [File]
            and [Text] hold copies of the path and text. [Position] uses window
            coordinates. *)

  type render_change =
    | Targets_reset  (** Draw the contents of texture targets again. *)
    | Device_reset  (** Destroy and recreate all textures for the renderer. *)
    | Device_lost
        (** Stop drawing with this renderer. SDL cannot recover it. *)

  type audio_device =
    | Playback of Audio.playback Audio.Device.id
    | Recording of Audio.recording Audio.Device.id

  type audio_change = Added | Removed

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
    | Drop of { window : Window.id option; change : drop_change }
        (** [window] is [None] when SDL reports no target window. *)
    | Other of int32
    | Render of { window : Window.id option; change : render_change }
        (** [window] is [None] when SDL reports no window ID. The binding does
            not recreate or invalidate handles when it reports this event. *)
    | Audio_device of { device : audio_device; change : audio_change }
        (** SDL sends [Added] for devices it finds at startup too. It can also
            send [Removed] for an open connection, whose ID is not in the device
            lists. Refresh the lists rather than opening a removed ID. These
            events do not close or invalidate stream handles. *)

  type t = { timestamp_ns : int64; kind : kind }

  val poll : context -> t option
  (** Remove the next event from the queue. [None] means the queue is empty.
      Unbound event types keep their SDL type number in [Other]. *)

  val wait_timeout : context -> timeout_ms:int -> t option
  (** Wait on the main thread and remove the next event from the same queue as
      [poll]. Return [None] if the wait ends without an event. Use [Video],
      [Audio], or another subsystem that starts [Events], or start [Events]
      directly. The timeout must be in [0, 2147483647] milliseconds. Zero is a
      poll. Other OCaml threads can run during a positive wait. System
      scheduling can make the wait longer than requested. *)

  val to_render_coordinates : Renderer.t -> t -> t
  (** Convert an event from the renderer's window to render units on the main
      thread. Use the default target's view and leave the original event
      unchanged. Convert positions in mouse motion, mouse buttons, touch, and
      drop position events. Scale mouse and touch movement without moving the
      origin of the movement. Convert normalized touch positions and movement to
      render units. Wheel scroll amounts do not change.

      Return other events unchanged, including events with no matching window.
      Pass the original event, not the result of a previous conversion. *)
end

module Timer : sig
  (** Time calls are safe on any thread. *)

  val ticks_ns : unit -> int64
  val ticks_ms : unit -> int64

  val delay_ns : int64 -> unit
  (** Sleep for at least this many nanoseconds. Other OCaml threads can run. *)
end
