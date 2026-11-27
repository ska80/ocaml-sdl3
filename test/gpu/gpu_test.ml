open Sdl3

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) scope f = scope f
let rect x y w h = Rect.make ~x ~y ~w ~h

let byte_buffer size =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size

let packed_bytes bytes =
  Bigarray.Array1.init Bigarray.int8_unsigned Bigarray.c_layout
    (Bytes.length bytes) (Bytes.get_uint8 bytes)

let with_copy_pass commands f =
  using Gpu.end_copy_pass (Gpu.begin_copy_pass commands) f

let with_color_pass ?mip_level ?store ?cycle commands ~target ~load f =
  using Gpu.end_render_pass
    (Gpu.begin_render_pass ?mip_level ?store ?cycle commands ~target ~load)
    f

let submit_gpu device record =
  let open Gpu in
  using cancel_command_buffer (acquire_command_buffer device) (fun commands ->
      record commands;
      using release_fence (submit_and_acquire_fence commands) wait_fence)

let bytes_match ?(tolerance = 0) actual expected =
  let size = String.length expected in
  let rec matches i =
    i = size
    ||
    let got = actual.{i} and want = Char.code expected.[i] in
    if abs (got - want) <= tolerance then matches (i + 1)
    else (
      Printf.eprintf "GPU byte %d: got %d, expected %d\n%!" i got want;
      false)
  in
  Bigarray.Array1.dim actual = size && matches 0

let gpu_buffer_matches device src expected =
  let open Gpu in
  let size = String.length expected in
  let@ dst =
    using release_download_buffer (create_download_buffer device ~size)
  in
  submit_gpu device (fun commands ->
      with_copy_pass commands (fun pass ->
          download_from_buffer pass ~src ~dst ~size));
  let actual = byte_buffer size in
  read_download_buffer dst actual;
  bytes_match actual expected

let gpu_texture_matches device src expected ~tolerance =
  let open Gpu in
  let size = String.length expected in
  let@ dst =
    using release_download_buffer
      (create_download_buffer device ~size:((size + 3) land lnot 3))
  in
  submit_gpu device (fun commands ->
      with_copy_pass commands (fun pass -> download_from_texture pass ~src ~dst));
  let actual = byte_buffer size in
  read_download_buffer dst actual;
  bytes_match ~tolerance actual expected

let create_color_target device claim =
  Gpu.(
    create_texture device ~format:(swapchain_format claim) ~usage:Color_target
      ~w:1 ~h:1)

let image_matches device ?(tolerance = 0) ?mip_level target pixel =
  let region = Gpu.texture_region ?mip_level target in
  let { Rect.w; h; _ } = region.rect in
  let bgra =
    match Gpu.texture_format target with
    | Bgra8_unorm | Bgra8_srgb -> true
    | Rgba8_unorm | Rgba8_srgb -> false
    | _ -> failwith "Expected an 8-bit RGBA or BGRA target"
  in
  let expected = Bytes.create (w * h * 4) in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let { Color.r; g; b; a } = pixel x y in
      let offset = 4 * ((y * w) + x) in
      Bytes.set_uint8 expected offset (if bgra then b else r);
      Bytes.set_uint8 expected (offset + 1) g;
      Bytes.set_uint8 expected (offset + 2) (if bgra then r else b);
      Bytes.set_uint8 expected (offset + 3) a
    done
  done;
  gpu_texture_matches device region (Bytes.to_string expected) ~tolerance

let color_target_matches device target color ~tolerance =
  image_matches device ~tolerance target (fun _ _ -> color)

let command_buffers device =
  let open Gpu in
  using cancel_command_buffer (acquire_command_buffer device) (fun commands ->
      using cancel_command_buffer (acquire_command_buffer device) (fun other ->
          invalid (fun () -> destroy_device device);
          Domain.join
            (Domain.spawn (fun () ->
                 invalid (fun () -> submit_command_buffer commands);
                 invalid (fun () -> cancel_command_buffer commands)));
          cancel_command_buffer commands;
          invalid (fun () -> submit_command_buffer commands);
          submit_command_buffer other;
          invalid (fun () -> submit_command_buffer other)));
  using cancel_command_buffer (acquire_command_buffer device) (fun commands ->
      using release_fence (submit_and_acquire_fence commands) (fun fence ->
          invalid (fun () -> destroy_device device);
          invalid (fun () -> submit_and_acquire_fence commands);
          Domain.join
            (Domain.spawn (fun () -> invalid (fun () -> release_fence fence)));
          wait_fence fence;
          check (fence_signaled fence) "Fence after wait";
          release_fence fence;
          invalid (fun () -> fence_signaled fence)))

let buffer_uploads device =
  let open Gpu in
  let old_data = packed_bytes (Bytes.of_string "0123456789abcdef") in
  let new_data = packed_bytes (Bytes.of_string "wxyz") in
  invalid (fun () -> create_vertex_buffer device ~size:0);
  invalid (fun () -> create_index_buffer device ~format:Uint16 ~size:6);
  invalid (fun () -> create_upload_buffer device ~size:(-4));
  (if Sys.int_size > 32 then
     let overflow = Int64.to_int 4_294_967_296L in
     invalid (fun () -> create_vertex_buffer device ~size:overflow));
  using release_buffer (create_vertex_buffer device ~size:16) (fun dst ->
      invalid (fun () -> destroy_device device);
      using release_upload_buffer (create_upload_buffer device ~size:16)
        (fun src ->
          using cancel_command_buffer (acquire_command_buffer device)
            (fun commands ->
              let closed_pass =
                with_copy_pass commands (fun pass ->
                    invalid (fun () -> begin_copy_pass commands);
                    invalid (fun () -> submit_command_buffer commands);
                    invalid (fun () -> submit_and_acquire_fence commands);
                    invalid (fun () -> cancel_command_buffer commands);
                    Domain.join
                      (Domain.spawn (fun () ->
                           invalid (fun () -> end_copy_pass pass);
                           invalid (fun () -> write_upload_buffer src old_data);
                           invalid (fun () -> release_buffer dst)));
                    invalid (fun () -> upload_to_buffer pass ~src ~dst ~size:4);
                    invalid (fun () ->
                        write_upload_buffer src (packed_bytes Bytes.empty));
                    invalid (fun () ->
                        write_upload_buffer src (packed_bytes (Bytes.create 20)));
                    write_upload_buffer src old_data;
                    invalid (fun () ->
                        upload_to_buffer ~src_offset:2 pass ~src ~dst ~size:4);
                    invalid (fun () ->
                        upload_to_buffer ~dst_offset:16 pass ~src ~dst ~size:4);
                    invalid (fun () ->
                        upload_to_buffer ~cycle:true pass ~src ~dst ~size:4);
                    upload_to_buffer ~src_offset:4 pass ~src ~dst ~size:12;
                    write_upload_buffer src new_data;
                    invalid (fun () ->
                        upload_to_buffer ~src_offset:4 pass ~src ~dst ~size:4);
                    upload_to_buffer ~dst_offset:12 pass ~src ~dst ~size:4;
                    pass)
              in
              invalid (fun () -> upload_to_buffer closed_pass ~src ~dst ~size:4);
              release_upload_buffer src;
              invalid (fun () -> write_upload_buffer src old_data);
              using release_fence (submit_and_acquire_fence commands) wait_fence;
              invalid (fun () -> begin_copy_pass commands)));
      check
        (gpu_buffer_matches device dst "456789abcdefwxyz")
        "GPU upload bytes";
      using release_upload_buffer (create_upload_buffer device ~size:4)
        (fun src ->
          write_upload_buffer src new_data;
          using cancel_command_buffer (acquire_command_buffer device)
            (fun commands ->
              with_copy_pass commands (fun pass ->
                  upload_to_buffer pass ~src ~dst ~size:4);
              cancel_command_buffer commands));
      check
        (gpu_buffer_matches device dst "456789abcdefwxyz")
        "Canceled upload changed bytes");
  using release_upload_buffer (create_upload_buffer device ~size:4) (fun _ ->
      invalid (fun () -> destroy_device device))

let buffer_downloads device =
  let open Gpu in
  let make size = create_download_buffer device ~size in
  invalid (fun () -> make 0);
  invalid (fun () -> make 7);
  if Sys.int_size > 32 then
    invalid (fun () -> make (Int64.to_int 4_294_967_296L));
  let@ dst = using release_download_buffer (make 16) in
  invalid (fun () -> destroy_device device);
  let@ second = using release_download_buffer (make 4) in
  let@ src =
    using release_buffer (create_index_buffer device ~format:Uint16 ~size:16)
  in
  let data = packed_bytes (Bytes.make 14 '!') in
  let read () = read_download_buffer ~dst_offset:3 dst data in
  invalid read;
  wait_idle device;
  invalid read;
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  let pass =
    with_copy_pass commands (fun pass ->
        let@ upload =
          using release_upload_buffer (create_upload_buffer device ~size:16)
        in
        write_upload_buffer upload
          (packed_bytes (Bytes.of_string "0123456789abcdef"));
        upload_to_buffer pass ~src:upload ~dst:src ~size:16;
        invalid (fun () ->
            download_from_buffer ~src_offset:2 pass ~src ~dst ~size:4);
        invalid (fun () ->
            download_from_buffer ~dst_offset:2 pass ~src ~dst ~size:4);
        invalid (fun () ->
            download_from_buffer ~src_offset:16 pass ~src ~dst ~size:4);
        invalid (fun () ->
            download_from_buffer ~dst_offset:12 pass ~src ~dst ~size:8);
        invalid (fun () -> download_from_buffer pass ~src ~dst ~size:0);
        invalid (fun () -> download_from_buffer pass ~src ~dst ~size:2);
        download_from_buffer ~src_offset:4 ~dst_offset:8 pass ~src ~dst ~size:8;
        invalid (fun () -> download_from_buffer pass ~src ~dst ~size:4);
        download_from_buffer ~src_offset:12 pass ~src ~dst:second ~size:4;
        invalid read;
        pass)
  in
  invalid (fun () -> download_from_buffer pass ~src ~dst:second ~size:4);
  wait_idle device;
  invalid read;
  let@ fence = using release_fence (submit_and_acquire_fence commands) in
  let@ next = using cancel_command_buffer (acquire_command_buffer device) in
  with_copy_pass next (fun pass ->
      invalid (fun () -> download_from_buffer pass ~src ~dst ~size:4));
  (* Another fence's wait and a query do not make this batch ready. *)
  submit_gpu device ignore;
  ignore (fence_signaled fence);
  invalid read;
  Gc.compact ();
  wait_fence fence;
  check (fence_signaled fence) "Download fence after wait";
  let data2 = byte_buffer 4 in
  read_download_buffer second data2;
  check (bytes_match data2 "cdef") "Two downloads in one submission";
  release_download_buffer second;
  invalid (fun () -> read_download_buffer dst (byte_buffer 7));
  invalid (fun () -> read_download_buffer ~dst_offset:(-1) dst data);
  invalid (fun () -> read_download_buffer ~dst_offset:max_int dst data);
  invalid (fun () -> read_download_buffer ~pitch:7 dst data);
  Domain.join
    (Domain.spawn (fun () ->
         invalid read;
         invalid (fun () -> release_download_buffer dst)));
  read ();
  check (bytes_match data "!!!456789ab!!!") "Buffer download with offsets";
  let@ canceled = using cancel_command_buffer (acquire_command_buffer device) in
  with_copy_pass canceled (fun pass ->
      download_from_buffer pass ~src ~dst ~size:4);
  wait_fence fence;
  invalid read;
  cancel_command_buffer canceled;
  invalid read;
  release_fence fence;
  with_copy_pass next (fun pass ->
      invalid (fun () -> download_from_buffer pass ~src ~dst:second ~size:4);
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> download_from_buffer pass ~src ~dst ~size:4)));
      download_from_buffer ~src_offset:8 pass ~src ~dst ~size:4);
  release_buffer src;
  submit_command_buffer next;
  invalid read;
  wait_idle device;
  read_download_buffer dst data2;
  check (bytes_match data2 "89ab") "Download after cancel and wait_idle";
  release_download_buffer dst;
  invalid read;
  check (bytes_match data2 "89ab") "Bigarray outlives the download buffer"

let sampled_handles device =
  let open Gpu in
  invalid (fun () -> create_sampled_texture device ~w:0 ~h:2);
  invalid (fun () -> create_sampled_texture device ~w:2 ~h:16385);
  using release_texture (create_sampled_texture device ~w:2 ~h:2)
    (fun texture ->
      invalid (fun () -> destroy_device device);
      Domain.join
        (Domain.spawn (fun () -> invalid (fun () -> release_texture texture))));
  using release_sampler (create_sampler device ~filter:Nearest) (fun sampler ->
      invalid (fun () -> destroy_device device);
      Domain.join
        (Domain.spawn (fun () -> invalid (fun () -> release_sampler sampler))))

let frames claim =
  check (Gpu.supports_present_mode claim Vsync) "Vsync support";
  check (Gpu.supports_composition claim Sdr) "SDR support";
  let mode =
    if Gpu.supports_present_mode claim Immediate then Gpu.Immediate
    else Gpu.Vsync
  in
  Gpu.set_swapchain_parameters claim ~composition:Sdr ~present_mode:mode;
  for i = 0 to 3 do
    let color = Color.rgb (i * 32) 96 192 in
    check (Gpu.clear_and_present claim color) "No frame submitted"
  done

let with_render_pass ?(record = fun _ -> ()) device claim ~clear f =
  let open Gpu in
  using cancel_command_buffer (acquire_command_buffer device) (fun commands ->
      record commands;
      match begin_swapchain_render_pass commands claim ~clear with
      | None -> failwith "No swapchain render pass"
      | Some pass ->
          Fun.protect
            ~finally:(fun () ->
              end_render_pass pass;
              using release_fence (submit_and_acquire_fence commands) wait_fence)
            (fun () -> f commands pass))

let render_pass device claim =
  let open Gpu in
  let clear = Color.rgb 40 80 120 in
  using cancel_command_buffer (acquire_command_buffer device) (fun spare ->
      let commands =
        with_render_pass device claim ~clear (fun commands pass ->
            Gc.full_major ();
            let w, h = render_pass_size pass in
            check (w > 0 && h > 0) "Acquired swapchain image size";
            set_viewport pass None;
            set_scissor pass None;
            invalid (fun () -> submit_command_buffer commands);
            invalid (fun () -> submit_and_acquire_fence commands);
            invalid (fun () -> begin_copy_pass commands);
            invalid (fun () ->
                begin_swapchain_render_pass commands claim ~clear);
            invalid (fun () -> begin_swapchain_render_pass spare claim ~clear);
            invalid (fun () -> clear_and_present claim clear);
            invalid (fun () ->
                set_swapchain_parameters claim ~composition:Sdr
                  ~present_mode:Vsync);
            end_render_pass pass;
            invalid (fun () -> cancel_command_buffer commands);
            invalid (fun () -> release_window claim);
            commands)
      in
      invalid (fun () -> begin_swapchain_render_pass commands claim ~clear);
      check (clear_and_present claim clear) "Claim reusable after submission")

let wrong_transfer_device device other =
  let open Gpu in
  let data = packed_bytes (Bytes.of_string "data") in
  let with_resources d f =
    let@ src = using release_upload_buffer (create_upload_buffer d ~size:4) in
    write_upload_buffer src data;
    let@ dst = using release_buffer (create_vertex_buffer d ~size:4) in
    let@ texture =
      using release_texture
        (create_texture d ~format:Rgba8_unorm ~usage:Sampled_color_target ~w:1
           ~h:1)
    in
    let@ download =
      using release_download_buffer (create_download_buffer d ~size:4)
    in
    f (src, dst, texture, download)
  in
  let@ src, dst, texture, download = with_resources device in
  let@ other_src, other_dst, other_texture, other_download =
    with_resources other
  in
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  let here = texture_region texture and there = texture_region other_texture in
  invalid (fun () ->
      begin_render_pass commands ~target:other_texture ~load:Dont_care);
  invalid (fun () -> blit_texture commands ~src:there ~dst:here ~load:Dont_care);
  invalid (fun () -> blit_texture commands ~src:here ~dst:there ~load:Dont_care);
  with_copy_pass commands (fun pass ->
      invalid (fun () -> copy_texture pass ~src:there ~dst:here);
      invalid (fun () -> copy_texture pass ~src:here ~dst:there);
      invalid (fun () -> upload_to_buffer pass ~src:other_src ~dst ~size:4);
      invalid (fun () -> upload_to_buffer pass ~src ~dst:other_dst ~size:4);
      invalid (fun () -> upload_to_texture pass ~src:other_src ~dst:texture);
      invalid (fun () -> upload_to_texture pass ~src ~dst:other_texture);
      invalid (fun () ->
          download_from_buffer pass ~src:other_dst ~dst:download ~size:4);
      invalid (fun () ->
          download_from_buffer pass ~src:dst ~dst:other_download ~size:4);
      invalid (fun () -> download_from_texture pass ~src:there ~dst:download);
      invalid (fun () ->
          download_from_texture pass ~src:here ~dst:other_download))

let wrong_device device context claim =
  let open Gpu in
  using destroy_device
    (create_device ~driver:(driver device) context (shader_formats device))
    (fun other ->
      wrong_transfer_device device other;
      using cancel_command_buffer (acquire_command_buffer other)
        (fun commands ->
          invalid (fun () ->
              begin_swapchain_render_pass commands claim
                ~clear:(Color.rgb 0 0 0))))

let shader_code file =
  In_channel.with_open_bin (Filename.concat "shaders" file) In_channel.input_all

let triangle_vertex device =
  Gpu.create_shader device ~stage:Vertex ~format:Spirv
    (shader_code "triangle.vert.spv")

let triangle_fragment device =
  Gpu.create_shader device ~stage:Fragment ~format:Spirv ~entrypoint:"main"
    (shader_code "triangle.frag.spv")

let shader_checks device =
  let open Gpu in
  let code = shader_code "triangle.vert.spv" in
  let create ?entrypoint ?samplers ?uniform_buffers =
    create_shader device ~stage:Vertex ~format:Spirv ?entrypoint ?samplers
      ?uniform_buffers
  in
  invalid (fun () -> create ~samplers:(-1) code);
  invalid (fun () -> create ~samplers:17 code);
  invalid (fun () -> create ~uniform_buffers:(-1) code);
  invalid (fun () -> create ~uniform_buffers:5 code);
  invalid (fun () -> create "");
  invalid (fun () -> create "abcd");
  invalid (fun () -> create (code ^ "a"));
  invalid (fun () -> create ~entrypoint:"" code);
  invalid (fun () -> create ~entrypoint:"main\000x" code);
  let formats = shader_formats device in
  Option.iter
    (fun format ->
      invalid (fun () -> create_shader device ~stage:Vertex ~format code))
    (List.find_opt
       (fun format -> not (List.mem format formats))
       [ Dxbc; Dxil; Msl; Metallib ]);
  using release_shader (create code) (fun shader ->
      invalid (fun () -> destroy_device device);
      Domain.join
        (Domain.spawn (fun () -> invalid (fun () -> release_shader shader)));
      release_shader shader)

let with_triangle_shaders device f =
  using Gpu.release_shader (triangle_vertex device) (fun vertex ->
      using Gpu.release_shader (triangle_fragment device) (f vertex))

let triangle_pipeline device claim =
  with_triangle_shaders device (fun vertex fragment ->
      Gpu.create_swapchain_pipeline claim ~vertex ~fragment
        ~primitive:Triangle_list)

let wrong_pipeline_device device context claim ~clear =
  let open Gpu in
  using destroy_device
    (create_device ~driver:(driver device) context [ Spirv ])
    (fun other ->
      using release_shader (triangle_vertex other) (fun vertex ->
          using release_shader (triangle_fragment device) (fun fragment ->
              invalid (fun () ->
                  create_swapchain_pipeline claim ~vertex ~fragment
                    ~primitive:Triangle_list);
              invalid (fun () ->
                  create_graphics_pipeline device ~format:Rgba8_unorm ~vertex
                    ~fragment ~primitive:Triangle_list)));
      let pipeline =
        using Window.destroy
          (Window.create context ~title:"Other GPU window" ~w:64 ~h:48)
          (fun window ->
            using release_window
              (claim_window other window)
              (triangle_pipeline other))
      in
      using release_graphics_pipeline pipeline (fun pipeline ->
          invalid (fun () -> destroy_device other);
          using release_buffer
            (create_index_buffer other ~format:Uint16 ~size:4) (fun index ->
              with_render_pass device claim ~clear (fun _ pass ->
                  invalid (fun () -> bind_graphics_pipeline pass pipeline);
                  invalid (fun () -> bind_index_buffer pass index)))))

let wrong_pipeline_format device claim pipeline ~clear =
  let open Gpu in
  if supports_composition claim Sdr_linear then (
    set_swapchain_parameters claim ~composition:Sdr_linear ~present_mode:Vsync;
    Fun.protect
      ~finally:(fun () ->
        set_swapchain_parameters claim ~composition:Sdr ~present_mode:Vsync)
      (fun () ->
        with_render_pass device claim ~clear (fun _ pass ->
            invalid (fun () -> bind_graphics_pipeline pass pipeline))))

let triangle device context claim =
  let open Gpu in
  let clear = Color.rgb 18 24 36 in
  using release_graphics_pipeline (triangle_pipeline device claim)
    (fun pipeline ->
      wrong_pipeline_device device context claim ~clear;
      wrong_pipeline_format device claim pipeline ~clear;
      with_render_pass device claim ~clear (fun _ pass ->
          invalid (fun () -> draw_primitives pass ~vertices:3);
          Domain.join
            (Domain.spawn (fun () ->
                 invalid (fun () -> bind_graphics_pipeline pass pipeline);
                 invalid (fun () -> release_graphics_pipeline pipeline)));
          bind_graphics_pipeline pass pipeline;
          Gc.full_major ();
          invalid (fun () -> draw_primitives pass ~vertices:0);
          invalid (fun () -> draw_primitives ~instances:0 pass ~vertices:3);
          (if Sys.int_size > 32 then
             let overflow = Int64.to_int 4_294_967_296L in
             invalid (fun () -> draw_primitives pass ~vertices:overflow));
          draw_primitives pass ~vertices:3;
          end_render_pass pass;
          invalid (fun () -> bind_graphics_pipeline pass pipeline);
          invalid (fun () -> draw_primitives pass ~vertices:3));
      with_render_pass device claim ~clear (fun _ pass ->
          invalid (fun () -> draw_primitives pass ~vertices:3);
          bind_graphics_pipeline pass pipeline;
          draw_primitives ~instances:2 pass ~vertices:3;
          release_graphics_pipeline pipeline;
          invalid (fun () -> draw_primitives pass ~vertices:3);
          invalid (fun () -> bind_graphics_pipeline pass pipeline)))

let mesh_position = Gpu.{ location = 0; format = Float32x2; offset = 0 }

let mesh_layout : Gpu.vertex_layout =
  {
    stride = 12;
    attributes =
      [ mesh_position; { location = 1; format = Unorm8x4; offset = 8 } ];
  }

let with_mesh_shaders device f =
  let open Gpu in
  using release_shader
    (create_shader device ~stage:Vertex ~format:Spirv
       (shader_code "mesh.vert.spv"))
    (fun vertex ->
      using release_shader
        (create_shader device ~stage:Fragment ~format:Spirv
           (shader_code "mesh.frag.spv"))
        (f vertex))

let mesh_pipeline device claim =
  let open Gpu in
  let layout = mesh_layout and position = mesh_position in
  with_mesh_shaders device (fun vertex fragment ->
      let create vertex_layout =
        create_swapchain_pipeline ~vertex_layout claim ~vertex ~fragment
          ~primitive:Triangle_list
      in
      List.iter
        (fun bad -> invalid (fun () -> create bad))
        [
          { layout with stride = 10 };
          { layout with stride = 2052 };
          { layout with attributes = [] };
          { layout with attributes = [ position; position ] };
          { layout with attributes = [ { position with location = 16 } ] };
          { layout with attributes = [ { position with offset = 2 } ] };
          { layout with attributes = [ { position with offset = 8 } ] };
        ];
      create layout)

let mesh_vertices ?color () =
  let vertices = Bytes.make 36 '\255' in
  List.iteri
    (fun i (x, y) ->
      Bytes.set_int32_ne vertices (i * 12) (Int32.bits_of_float x);
      Bytes.set_int32_ne vertices ((i * 12) + 4) (Int32.bits_of_float y);
      let offset = (i * 12) + 8 in
      match color with
      | None -> Bytes.set_uint8 vertices (offset + i) 32
      | Some Color.{ r; g; b; a } ->
          List.iteri
            (fun j byte -> Bytes.set_uint8 vertices (offset + j) byte)
            [ r; g; b; a ])
    [ (-0.75, -0.75); (0.75, -0.75); (0., 0.75) ];
  vertices

let mesh_indices = function
  | Gpu.Uint16 ->
      let bytes = Bytes.make 12 '\000' in
      for i = 0 to 2 do
        Bytes.set_uint16_ne bytes (4 + (2 * i)) i
      done;
      (bytes, 2, 1)
  | Gpu.Uint32 ->
      let bytes = Bytes.make 16 '\000' in
      for i = 0 to 2 do
        Bytes.set_int32_ne bytes (4 + (4 * i)) (Int32.of_int i)
      done;
      (bytes, 4, 0)

let mesh_frame device claim pipeline format =
  let open Gpu in
  let clear = Color.rgb 18 24 36 in
  let vertices = mesh_vertices () in
  let indices, index_offset, first_index = mesh_indices format in
  let vertex_size = Bytes.length vertices
  and index_size = Bytes.length indices in
  let data = packed_bytes (Bytes.cat vertices indices) in
  using release_buffer
    (create_vertex_buffer device ~size:(4 + vertex_size))
    (fun vertex ->
      using release_buffer (create_index_buffer device ~format ~size:index_size)
        (fun index ->
          let record commands =
            using release_upload_buffer
              (create_upload_buffer device ~size:(vertex_size + index_size))
              (fun src ->
                write_upload_buffer src data;
                with_copy_pass commands (fun pass ->
                    invalid (fun () ->
                        begin_swapchain_render_pass commands claim ~clear);
                    upload_to_buffer ~dst_offset:4 pass ~src ~dst:vertex
                      ~size:vertex_size;
                    upload_to_buffer ~src_offset:vertex_size ~cycle:true pass
                      ~src ~dst:index ~size:index_size))
          in
          with_render_pass ~record device claim ~clear (fun _ pass ->
              let draw () =
                draw_indexed_primitives ~first_index pass ~indices:3
              in
              invalid draw;
              bind_graphics_pipeline pass pipeline;
              invalid (fun () -> draw_primitives pass ~vertices:3);
              invalid (fun () -> bind_vertex_buffer ~offset:2 pass vertex);
              invalid (fun () ->
                  bind_vertex_buffer ~offset:vertex_size pass vertex);
              bind_vertex_buffer ~offset:4 pass vertex;
              invalid (fun () -> draw_primitives pass ~vertices:4);
              draw_primitives pass ~vertices:3;
              invalid draw;
              invalid (fun () -> bind_index_buffer ~offset:1 pass index);
              invalid (fun () ->
                  bind_index_buffer ~offset:index_size pass index);
              bind_index_buffer ~offset:index_offset pass index;
              Gc.full_major ();
              invalid (fun () ->
                  draw_indexed_primitives ~first_index:4 pass ~indices:3);
              draw ();
              bind_graphics_pipeline pass pipeline;
              invalid draw;
              bind_vertex_buffer ~offset:4 pass vertex;
              draw ();
              release_buffer index;
              invalid draw;
              invalid (fun () -> bind_index_buffer pass index);
              release_buffer vertex;
              invalid (fun () -> draw_primitives pass ~vertices:3);
              invalid (fun () -> bind_vertex_buffer pass vertex))))

let mesh device claim =
  using Gpu.release_graphics_pipeline (mesh_pipeline device claim)
    (fun pipeline ->
      mesh_frame device claim pipeline Gpu.Uint16;
      mesh_frame device claim pipeline Gpu.Uint32)

let blending device claim =
  let open Gpu in
  let rgba = Color.rgba in
  let source = rgba 128 48 96 144 in
  let clear = rgba 40 136 80 112 in
  let data = packed_bytes (mesh_vertices ~color:source ()) in
  let size = Bigarray.Array1.dim data in
  let equation src dst op : Blend_mode.equation = { src; dst; op } in
  let blend color alpha : Blend.t = { color; alpha } in
  using release_buffer (create_vertex_buffer device ~size) (fun vertices ->
      submit_gpu device (fun commands ->
          using release_upload_buffer (create_upload_buffer device ~size)
            (fun src ->
              write_upload_buffer src data;
              with_copy_pass commands (fun pass ->
                  upload_to_buffer pass ~src ~dst:vertices ~size)));
      using release_texture (create_color_target device claim) (fun target ->
          with_mesh_shaders device (fun vertex fragment ->
              let expect ?blend ?color_write_mask label color =
                using release_graphics_pipeline
                  (create_swapchain_pipeline ~vertex_layout:mesh_layout ?blend
                     ?color_write_mask claim ~vertex ~fragment
                     ~primitive:Triangle_list) (fun pipeline ->
                    submit_gpu device (fun commands ->
                        with_color_pass commands ~target ~load:(Clear clear)
                          (fun pass ->
                            bind_graphics_pipeline pass pipeline;
                            bind_vertex_buffer pass vertices;
                            draw_primitives pass ~vertices:3)));
                (* Blending in an 8-bit target can differ by one rounding unit. *)
                let tolerance = if Option.is_some blend then 1 else 0 in
                check
                  (color_target_matches device target color ~tolerance)
                  label
              in
              expect "GPU replace by default" source;
              expect ~blend:Blend.straight_alpha "GPU straight alpha"
                (rgba 90 86 89 193);
              expect ~blend:Blend.premultiplied_alpha "GPU premultiplied alpha"
                (rgba 145 107 131 193);
              expect ~blend:Blend.additive "GPU additive" (rgba 112 163 134 112);
              expect ~blend:Blend.modulate "GPU modulate" (rgba 20 26 30 112);
              expect ~blend:Blend.multiply "GPU multiply" (rgba 37 85 65 112);
              expect
                ~blend:
                  (blend
                     (equation One Dst_alpha Subtract)
                     (equation One_minus_src_color One Reverse_subtract))
                "GPU separate subtraction equations" (rgba 110 0 61 49);
              expect
                ~blend:
                  (blend
                     (equation One_minus_dst_color One_minus_src_color Sum)
                     (equation Dst_color One_minus_dst_alpha Sum))
                "GPU inverse color and alpha factors" (rgba 128 133 116 126);
              expect
                ~blend:
                  (blend
                     (equation Zero Zero Minimum)
                     (equation Zero Zero Maximum))
                "GPU min and max ignore factors" (rgba 40 48 80 144);
              expect ~color_write_mask:[ Red; Blue ] "GPU mask without blending"
                (rgba 128 136 96 112);
              expect ~blend:Blend.straight_alpha
                ~color_write_mask:[ Green; Alpha ] "GPU mask with blending"
                (rgba 40 86 80 193);
              expect ~color_write_mask:[]
                "GPU empty mask preserves the clear color" clear)))

let resource_pipeline device ~format =
  let open Gpu in
  using release_shader
    (create_shader device ~stage:Vertex ~format:Spirv ~samplers:1
       ~uniform_buffers:1
       (shader_code "resources.vert.spv"))
    (fun vertex ->
      using release_shader
        (create_shader device ~stage:Fragment ~format:Spirv ~samplers:2
           ~uniform_buffers:1
           (shader_code "resources.frag.spv"))
        (fun fragment ->
          create_graphics_pipeline device ~format ~vertex ~fragment
            ~primitive:Triangle_list))

let wrong_sampler_device device context claim pipeline texture sampler =
  let open Gpu in
  using destroy_device
    (create_device ~driver:(driver device) context [ Spirv ])
    (fun other ->
      using release_sampler (create_sampler other ~filter:Nearest) (fun s ->
          using release_texture (create_sampled_texture other ~w:2 ~h:2)
            (fun t ->
              with_render_pass device claim ~clear:(Color.rgb 0 0 0)
                (fun _ pass ->
                  bind_graphics_pipeline pass pipeline;
                  invalid (fun () ->
                      bind_samplers pass ~stage:Vertex [| (t, sampler) |]);
                  invalid (fun () ->
                      bind_samplers pass ~stage:Vertex [| (texture, s) |])))))

let uniform_coordinates x y u v =
  let bytes = Bytes.create 16 in
  List.iteri
    (fun i f -> Bytes.set_int32_ne bytes (4 * i) (Int32.bits_of_float f))
    [ x; y; u; v ];
  packed_bytes bytes

let upload_resource_textures device commands a b index =
  let open Gpu in
  let pixels reds =
    let bytes = Bytes.make 16 '\255' in
    List.iteri (fun i red -> Bytes.set_uint8 bytes (4 * i) red) reds;
    bytes
  in
  (* Four offset bytes and two eight-byte rows with no padding. *)
  using release_upload_buffer (create_upload_buffer device ~size:20) (fun src ->
      let ended =
        with_copy_pass commands (fun pass ->
            invalid (fun () -> upload_to_texture pass ~src ~dst:a);
            let first = pixels [ 0; 255; 255; 0 ] in
            write_upload_buffer src
              (packed_bytes (Bytes.cat (Bytes.create 4) first));
            invalid (fun () -> upload_to_texture ~src_offset:2 pass ~src ~dst:a);
            invalid (fun () -> upload_to_texture ~src_offset:8 pass ~src ~dst:a);
            upload_to_texture ~src_offset:4 pass ~src ~dst:a;
            write_upload_buffer src (packed_bytes (pixels [ 255; 0; 0; 255 ]));
            upload_to_texture ~cycle:true pass ~src ~dst:b;
            let indices = Bytes.make 8 '\000' in
            Bytes.set_uint16_ne indices 2 1;
            Bytes.set_uint16_ne indices 4 2;
            write_upload_buffer src (packed_bytes indices);
            upload_to_buffer pass ~src ~dst:index ~size:8;
            pass)
      in
      invalid (fun () -> upload_to_texture ended ~src ~dst:a))

let resource_draws device claim pipeline a b nearest linear =
  let open Gpu in
  let with_target f =
    using release_texture (create_color_target device claim) f
  in
  let with_pass commands target f =
    with_color_pass commands ~target ~load:(Clear (Color.rgba 0 0 0 0)) f
  in
  let vertex = uniform_coordinates 0.75 0.25 0. 0. in
  let initial = uniform_coordinates 0.25 0.25 0.25 0.25 in
  let updated = uniform_coordinates 0.75 0.25 0.75 0.25 in
  let va = [| (a, nearest) |] and fb = [| (a, nearest); (b, linear) |] in
  using release_buffer (create_index_buffer device ~format:Uint16 ~size:8)
    (fun index ->
      with_target (fun first ->
          with_target (fun second ->
              using cancel_command_buffer (acquire_command_buffer device)
                (fun commands ->
                  upload_resource_textures device commands a b index;
                  let push stage slot data =
                    push_uniform_data commands ~stage ~slot data
                  in
                  invalid (fun () -> push Vertex (-1) vertex);
                  invalid (fun () -> push Fragment 4 initial);
                  List.iter
                    (fun size ->
                      invalid (fun () ->
                          push Vertex 0 (packed_bytes (Bytes.create size))))
                    [ 0; 3; 4100 ];
                  push Vertex 3 (packed_bytes (Bytes.make 4096 '\000'));
                  push Vertex 0 vertex;
                  with_pass commands first (fun pass ->
                      let draw () = draw_indexed_primitives pass ~indices:3 in
                      invalid (fun () -> bind_samplers pass ~stage:Vertex va);
                      bind_graphics_pipeline pass pipeline;
                      bind_index_buffer pass index;
                      invalid (fun () ->
                          bind_samplers ~first_slot:(-1) pass ~stage:Vertex va);
                      invalid (fun () ->
                          bind_samplers ~first_slot:1 pass ~stage:Vertex va);
                      invalid (fun () ->
                          bind_samplers ~first_slot:1 pass ~stage:Fragment fb);
                      bind_samplers ~first_slot:2 pass ~stage:Fragment [||];
                      bind_samplers pass ~stage:Vertex va;
                      bind_samplers pass ~stage:Fragment fb;
                      invalid draw;
                      push Fragment 0 initial;
                      Bigarray.Array1.blit updated initial;
                      bind_graphics_pipeline pass pipeline;
                      bind_samplers pass ~stage:Vertex va;
                      bind_samplers ~first_slot:1 pass ~stage:Fragment
                        [| fb.(1) |];
                      invalid draw;
                      bind_samplers pass ~stage:Fragment [| fb.(0) |];
                      Gc.full_major ();
                      draw ());
                  with_pass commands second (fun pass ->
                      bind_graphics_pipeline pass pipeline;
                      invalid (fun () ->
                          bind_samplers pass ~stage:Vertex
                            [| (first, nearest) |]);
                      bind_samplers pass ~stage:Vertex va;
                      bind_samplers pass ~stage:Fragment fb;
                      push Fragment 0 initial;
                      draw_primitives pass ~vertices:3;
                      release_sampler linear;
                      invalid (fun () -> bind_samplers pass ~stage:Fragment fb);
                      fb.(1) <- (b, nearest);
                      invalid (fun () -> draw_primitives pass ~vertices:3);
                      release_texture a;
                      invalid (fun () -> bind_samplers pass ~stage:Vertex va));
                  using release_fence
                    (submit_and_acquire_fence commands)
                    wait_fence;
                  invalid (fun () -> push Vertex 0 vertex));
              check
                (color_target_matches device first (Color.rgb 255 0 255)
                   ~tolerance:0)
                "GPU shader resources in the first draw";
              check
                (color_target_matches device second (Color.rgb 255 255 0)
                   ~tolerance:0)
                "GPU shader resources after a uniform update")))

let shader_resources device context claim =
  let open Gpu in
  let texture () = create_sampled_texture device ~w:2 ~h:2 in
  using release_graphics_pipeline
    (resource_pipeline device ~format:(swapchain_format claim))
    (fun pipeline ->
      using release_texture (texture ()) (fun a ->
          using release_texture (texture ()) (fun b ->
              using release_sampler (create_sampler device ~filter:Nearest)
                (fun nearest ->
                  using release_sampler (create_sampler device ~filter:Linear)
                    (fun linear ->
                      wrong_sampler_device device context claim pipeline a
                        nearest;
                      resource_draws device claim pipeline a b nearest linear)))))

let texture_upload_formats device =
  let open Gpu in
  check
    (supports_texture_format device ~format:Rgba8_unorm
       ~usage:Sampled_color_target)
    "RGBA8 can be sampled and rendered to";
  let test format bytes alignment =
    if supports_texture_format device ~format ~usage:Sampled then
      using release_texture
        (create_texture device ~format ~usage:Sampled ~w:1 ~h:1) (fun target ->
          check (texture_format target = format) "GPU texture format";
          check (texture_mip_levels target = 1) "Default mip level count";
          let region = texture_region target in
          let padded = String.make alignment '\000' ^ bytes in
          let size = (String.length padded + 3) land lnot 3 in
          submit_gpu device (fun commands ->
              invalid (fun () ->
                  begin_render_pass commands ~target ~load:Dont_care);
              using release_upload_buffer (create_upload_buffer device ~size)
                (fun src ->
                  write_upload_buffer src
                    (packed_bytes (Bytes.of_string padded));
                  with_copy_pass commands (fun pass ->
                      invalid (fun () ->
                          upload_to_texture ~src_offset:(alignment / 2) pass
                            ~src ~dst:target);
                      upload_to_texture ~src_offset:alignment pass ~src
                        ~dst:target)));
          check
            (gpu_texture_matches device region bytes ~tolerance:0)
            "Packed mip upload bytes";
          release_texture target;
          invalid (fun () -> texture_size target))
  in
  test R8_unorm "\213" 4;
  let half = Bytes.create 8 in
  List.iteri
    (fun i n -> Bytes.set_uint16_ne half (2 * i) n)
    [ 0x3c00; 0x3800; 0x3400; 0x3c00 ];
  test Rgba16_float (Bytes.to_string half) 8;
  let packed = Bytes.create 4 in
  Bytes.set_int32_ne packed 0 0xc8040200l;
  test Rgb10a2_unorm (Bytes.to_string packed) 4

let texture_downloads device =
  let open Gpu in
  let@ texture =
    using release_texture
      (create_texture ~mip_levels:2 device ~format:Rgba8_unorm
         ~usage:Sampled_color_target ~w:8 ~h:8)
  in
  let@ dst =
    using release_download_buffer (create_download_buffer device ~size:44)
  in
  let@ too_small =
    using release_download_buffer (create_download_buffer device ~size:40)
  in
  let@ aligned =
    using release_download_buffer (create_download_buffer device ~size:1024)
  in
  let@ discarded =
    using release_download_buffer (create_download_buffer device ~size:16)
  in
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  let source_bytes = Bytes.init 64 (fun i -> Char.chr ((i * 3) + 1)) in
  let crop = texture_region ~mip_level:1 ~rect:(rect 1 1 2 2) texture in
  let cleared = texture_region ~rect:(rect 3 2 1 2) texture in
  with_color_pass commands ~target:texture
    ~load:(Clear (Color.rgb 17 34 51))
    ignore;
  with_copy_pass commands (fun pass ->
      let@ upload =
        using release_upload_buffer (create_upload_buffer device ~size:64)
      in
      write_upload_buffer upload (packed_bytes source_bytes);
      upload_to_texture ~mip_level:1 pass ~src:upload ~dst:texture;
      invalid (fun () ->
          download_from_texture pass ~src:{ crop with mip_level = 2 } ~dst);
      invalid (fun () ->
          download_from_texture pass ~src:{ crop with rect = rect 3 1 2 2 } ~dst);
      invalid (fun () ->
          download_from_texture pass ~src:{ crop with rect = rect 0 0 0 1 } ~dst);
      invalid (fun () -> download_from_texture ~pitch:4 pass ~src:crop ~dst);
      invalid (fun () -> download_from_texture ~pitch:10 pass ~src:crop ~dst);
      invalid (fun () ->
          download_from_texture ~pitch:max_int pass ~src:crop ~dst);
      invalid (fun () ->
          download_from_texture ~dst_offset:2 pass ~src:crop ~dst);
      invalid (fun () ->
          download_from_texture ~dst_offset:12 ~pitch:16 pass ~src:crop
            ~dst:too_small);
      download_from_texture ~dst_offset:12 ~pitch:16 pass ~src:crop ~dst;
      download_from_texture ~dst_offset:512 ~pitch:256 pass ~src:cleared
        ~dst:aligned;
      download_from_texture pass ~src:crop ~dst:discarded;
      release_download_buffer discarded;
      invalid (fun () -> download_from_texture pass ~src:crop ~dst:discarded));
  release_texture texture;
  let@ fence = using release_fence (submit_and_acquire_fence commands) in
  release_fence fence;
  let packed = byte_buffer 16 in
  invalid (fun () -> read_download_buffer dst packed);
  wait_idle device;
  let actual = byte_buffer 8 in
  read_download_buffer aligned actual;
  check
    (bytes_match actual "\017\034\051\255\017\034\051\255")
    "Aligned download after rendering in the same command buffer";
  let row1 = Bytes.sub_string source_bytes 20 8
  and row2 = Bytes.sub_string source_bytes 36 8 in
  read_download_buffer dst packed;
  check
    (bytes_match packed (row1 ^ row2))
    "Tight bigarray from a padded mip download";
  let padded = packed_bytes (Bytes.make 24 '!') in
  let slice = Bigarray.Array1.sub padded 2 20 in
  invalid (fun () -> read_download_buffer ~dst_offset:2 ~pitch:11 dst slice);
  invalid (fun () -> read_download_buffer ~pitch:max_int dst slice);
  read_download_buffer ~dst_offset:1 ~pitch:11 dst slice;
  check
    (bytes_match padded ("!!!" ^ row1 ^ "!!!" ^ row2 ^ "!!"))
    "Mip download preserves padding and bytes outside the slice";
  let@ next = using cancel_command_buffer (acquire_command_buffer device) in
  with_copy_pass next (fun pass ->
      invalid (fun () -> download_from_texture pass ~src:crop ~dst))

let texture_copies device =
  let open Gpu in
  let make ?mip_levels ~w ~h format usage =
    create_texture ?mip_levels device ~format ~usage ~w ~h
  in
  let red = Color.rgb 255 0 0
  and green = Color.rgb 0 255 0
  and blue = Color.rgb 0 0 255
  and bg = Color.rgb 10 20 30 in
  let pixels =
    Bytes.of_string "\255\000\000\255\000\255\000\255\000\000\255\255"
  in
  invalid (fun () -> make ~mip_levels:0 ~w:4 ~h:2 Rgba8_unorm Sampled);
  invalid (fun () -> make ~mip_levels:4 ~w:4 ~h:2 Rgba8_unorm Sampled);
  let@ source =
    using release_texture
      (make ~mip_levels:3 ~w:4 ~h:2 Rgba8_unorm Sampled_color_target)
  in
  let@ copied =
    using release_texture (make ~w:3 ~h:2 Rgba8_unorm Color_target)
  in
  let@ scaled =
    using release_texture (make ~w:6 ~h:4 Bgra8_unorm Color_target)
  in
  check (texture_mip_levels source = 3) "Configurable GPU mip levels";
  check (texture_size ~mip_level:1 source = (2, 1)) "GPU first mip size";
  check (texture_size ~mip_level:2 source = (1, 1)) "GPU mip size clamps to one";
  invalid (fun () -> texture_size ~mip_level:(-1) source);
  let mip = texture_region ~mip_level:1 source in
  let thin = texture_region ~mip_level:2 source in
  let crop texture x y w h = texture_region ~rect:(rect x y w h) texture in
  let dest = crop copied 1 0 2 1 and enlarged = crop scaled 1 1 4 2 in
  let dst = texture_region scaled and whole_copy = texture_region copied in
  submit_gpu device (fun commands ->
      invalid (fun () ->
          begin_render_pass ~mip_level:2 commands ~target:source ~load:Dont_care);
      invalid (fun () -> blit_texture commands ~src:thin ~dst ~load:Dont_care);
      invalid (fun () ->
          blit_texture commands ~src:whole_copy ~dst ~load:Dont_care);
      invalid (fun () ->
          blit_texture commands ~src:mip ~dst:(texture_region source)
            ~load:Dont_care);
      invalid (fun () ->
          blit_texture ~cycle:true commands ~src:mip ~dst ~load:(Clear bg));
      using release_upload_buffer (create_upload_buffer device ~size:12)
        (fun src ->
          write_upload_buffer src (packed_bytes pixels);
          with_copy_pass commands (fun pass ->
              invalid (fun () ->
                  blit_texture commands ~src:mip ~dst ~load:Dont_care);
              invalid (fun () -> upload_to_texture pass ~src ~dst:source);
              invalid (fun () ->
                  upload_to_texture ~cycle:true ~mip_level:1 pass ~src
                    ~dst:source);
              upload_to_texture ~mip_level:1 pass ~src ~dst:source;
              upload_to_texture ~mip_level:2 ~src_offset:8 pass ~src ~dst:source));
      with_color_pass commands ~target:copied ~load:(Clear bg) ignore;
      with_copy_pass commands (fun pass ->
          invalid (fun () ->
              copy_texture pass ~src:mip ~dst:(crop scaled 0 0 2 1));
          invalid (fun () -> copy_texture pass ~src:mip ~dst:whole_copy);
          invalid (fun () ->
              copy_texture pass ~src:mip ~dst:(crop copied max_int 0 2 1));
          invalid (fun () -> copy_texture pass ~src:mip ~dst:thin);
          invalid (fun () -> copy_texture ~cycle:true pass ~src:mip ~dst:dest);
          copy_texture pass ~src:mip ~dst:dest;
          copy_texture pass ~src:thin ~dst:(crop copied 0 1 1 1));
      blit_texture ~flip:Horizontal commands ~src:mip ~dst:enlarged
        ~load:(Clear bg);
      blit_texture ~filter:Linear commands ~src:mip ~dst:(crop scaled 4 3 1 1)
        ~load:Load);
  check
    (image_matches device copied (fun x y ->
         match (x, y) with
         | 1, 0 -> red
         | 2, 0 -> green
         | 0, 1 -> blue
         | _ -> bg))
    "GPU rectangular copy from two mip levels";
  check
    (image_matches device ~tolerance:1 scaled (fun x y ->
         if y = 3 && x = 4 then Color.rgb 128 128 0
         else if y >= 1 && y <= 2 && x >= 1 && x <= 4 then
           if x <= 2 then green else red
         else bg))
    "GPU flipped nearest blit, linear blit, and BGRA conversion";
  submit_gpu device (fun commands ->
      with_color_pass commands ~target:source ~load:(Clear blue) ignore;
      with_color_pass commands ~target:copied ~load:(Clear bg) ignore;
      with_copy_pass commands (fun pass ->
          copy_texture ~cycle:true pass ~src:(crop source 0 0 3 2)
            ~dst:whole_copy);
      with_color_pass commands ~target:scaled ~load:(Clear bg) ignore;
      invalid (fun () ->
          blit_texture ~cycle:true commands ~src:mip ~dst:enlarged
            ~load:Dont_care);
      blit_texture ~cycle:true commands ~src:mip ~dst ~load:Dont_care);
  check
    (color_target_matches device copied blue ~tolerance:0)
    "Whole cycling GPU copy";
  check
    (image_matches device scaled (fun x _ -> if x < 3 then red else green))
    "Whole cycling GPU blit"

let offscreen_rendering device =
  let open Gpu in
  let clear = Color.rgb 5 10 15 and draw_color = Color.rgb 64 191 255 in
  let pipeline =
    with_triangle_shaders device (fun vertex fragment ->
        create_graphics_pipeline device ~format:Rgba8_unorm ~vertex ~fragment
          ~primitive:Triangle_list)
  in
  let@ pipeline = using release_graphics_pipeline pipeline in
  let@ target =
    using release_texture
      (create_texture ~mip_levels:2 device ~format:Rgba8_unorm
         ~usage:Color_target ~w:16 ~h:16)
  in
  let@ other_format =
    using release_texture
      (create_texture device ~format:Bgra8_unorm ~usage:Color_target ~w:1 ~h:1)
  in
  let@ spare = using cancel_command_buffer (acquire_command_buffer device) in
  submit_gpu device (fun commands ->
      with_color_pass commands ~target:other_format ~load:Dont_care
        ~store:Discard (fun pass ->
          invalid (fun () -> bind_graphics_pipeline pass pipeline));
      invalid (fun () ->
          begin_render_pass ~mip_level:2 commands ~target ~load:Dont_care);
      invalid (fun () ->
          begin_render_pass ~cycle:true commands ~target ~load:Dont_care);
      with_color_pass ~mip_level:1 commands ~target ~load:(Clear clear) ignore;
      let ended =
        let@ pass = with_color_pass ~mip_level:1 commands ~target ~load:Load in
        check (render_pass_size pass = (8, 8)) "Offscreen mip pass size";
        Gc.full_major ();
        invalid (fun () -> release_texture target);
        invalid (fun () -> begin_copy_pass commands);
        invalid (fun () -> submit_command_buffer commands);
        invalid (fun () ->
            begin_render_pass spare ~target:other_format ~load:Dont_care);
        Domain.join
          (Domain.spawn (fun () -> invalid (fun () -> set_scissor pass None)));
        let viewport x w = Some (Frect.make ~x ~y:0. ~w ~h:4.) in
        set_viewport pass (viewport 0. 4.);
        set_scissor pass (Some (rect 2 2 1 1));
        invalid (fun () -> set_viewport pass (viewport nan 4.));
        invalid (fun () -> set_viewport pass (viewport 5. 4.));
        invalid (fun () -> set_scissor pass (Some (rect 7 7 2 1)));
        bind_graphics_pipeline pass pipeline;
        draw_primitives pass ~vertices:3;
        set_viewport pass None;
        set_scissor pass None;
        pass
      in
      end_render_pass ended;
      invalid (fun () -> render_pass_size ended);
      invalid (fun () -> set_scissor ended None));
  with_color_pass ~mip_level:1 spare ~target ~load:(Clear draw_color) ignore;
  cancel_command_buffer spare;
  check
    (image_matches device ~tolerance:1 ~mip_level:1 target (fun x y ->
         if x = 2 && y = 2 then draw_color else clear))
    "GPU load preserves the clear outside the viewport and scissor"

let offscreen_sampling device =
  let open Gpu in
  let black = Color.rgb 0 0 0 and red = Color.rgb 255 0 0 in
  let make ?mip_levels w h =
    create_texture ?mip_levels device ~w ~h ~format:Rgba8_unorm
      ~usage:Sampled_color_target
  in
  let@ pipeline =
    using release_graphics_pipeline
      (resource_pipeline device ~format:Rgba8_unorm)
  in
  let@ source = using release_texture (make ~mip_levels:2 4 4) in
  let@ target = using release_texture (make 1 1) in
  invalid (fun () -> create_sampler ~max_mip_level:15 device ~filter:Nearest);
  let@ mip =
    using release_sampler
      (create_sampler ~max_mip_level:1 device ~filter:Nearest)
  in
  let@ base = using release_sampler (create_sampler device ~filter:Nearest) in
  submit_gpu device (fun commands ->
      with_color_pass commands ~target:source ~load:(Clear black) ignore;
      with_color_pass ~mip_level:1 commands ~target:source ~load:(Clear red)
        ignore;
      with_color_pass commands ~target ~load:(Clear red) ignore;
      invalid (fun () ->
          begin_render_pass ~cycle:true commands ~target ~load:Load);
      with_color_pass ~cycle:true commands ~target ~load:(Clear black) ignore;
      push_uniform_data commands ~stage:Vertex ~slot:0
        (uniform_coordinates 0.5 0.5 1. 0.);
      let fragment = uniform_coordinates 0.5 0.5 0.5 0.5 in
      push_uniform_data commands ~stage:Fragment ~slot:0 fragment;
      blit_texture commands ~src:(texture_region source)
        ~dst:(texture_region target) ~load:Load;
      with_color_pass commands ~target ~load:Load (fun pass ->
          bind_graphics_pipeline pass pipeline;
          invalid (fun () ->
              bind_samplers pass ~stage:Vertex [| (target, mip) |]);
          invalid (fun () ->
              bind_samplers pass ~stage:Fragment
                [| (source, base); (target, base) |]);
          bind_samplers pass ~stage:Vertex [| (source, mip) |];
          bind_samplers pass ~stage:Fragment
            [| (source, base); (source, base) |];
          invalid (fun () -> draw_primitives pass ~vertices:3);
          push_uniform_data commands ~stage:Fragment ~slot:0 fragment;
          draw_primitives pass ~vertices:3);
      release_texture source);
  check
    (color_target_matches device target red ~tolerance:0)
    "A later pass samples the mip rendered by an earlier pass"

let hidden_window device claim =
  let open Gpu in
  using cancel_command_buffer (acquire_command_buffer device) (fun commands ->
      match
        begin_swapchain_render_pass commands claim ~clear:(Color.rgb 0 0 0)
      with
      | None -> ()
      | Some pass ->
          end_render_pass pass;
          submit_command_buffer commands)

let window device context =
  using Window.destroy (Window.create context ~title:"SDL GPU test" ~w:64 ~h:48)
    (fun window ->
      using Renderer.destroy (Renderer.create ~driver:"software" window)
        (fun _ -> invalid (fun () -> Gpu.claim_window device window));
      using Gpu.release_window (Gpu.claim_window device window) (fun claim ->
          Gc.full_major ();
          let color = Color.rgb 0 0 0 in
          invalid (fun () -> Window.destroy window);
          invalid (fun () -> Gpu.destroy_device device);
          invalid (fun () -> Gpu.claim_window device window);
          invalid (fun () -> Renderer.create window);
          Domain.join
            (Domain.spawn (fun () ->
                 invalid (fun () -> Gpu.release_window claim);
                 invalid (fun () -> Gpu.clear_and_present claim color)));
          frames claim;
          wrong_device device context claim;
          render_pass device claim;
          if List.mem Gpu.Spirv (Gpu.shader_formats device) then (
            triangle device context claim;
            mesh device claim;
            blending device claim;
            shader_resources device context claim)
          else
            Printf.eprintf
              "Skipping GPU drawing tests: SPIR-V is not supported\n%!";
          Gpu.wait_idle device;
          Window.hide window;
          ignore (Gpu.clear_and_present claim color);
          hidden_window device claim;
          Gpu.release_window claim;
          invalid (fun () -> Gpu.clear_and_present claim color));
      Window.show window;
      using Gpu.release_window (Gpu.claim_window device window) frames;
      using Renderer.destroy (Renderer.create ~driver:"software" window)
        (fun _ -> ()))

let () =
  with_init [ Video ] (fun context ->
      let formats = Gpu.[ Spirv; Dxbc; Dxil; Msl; Metallib ] in
      check
        (Gpu.supports_shader_formats context formats)
        "No SDL GPU driver is available";
      using Gpu.destroy_device (Gpu.create_device ~debug:true context formats)
        (fun device ->
          invalid (fun () -> quit context);
          check (List.mem (Gpu.driver device) (Gpu.drivers ())) "Device driver";
          check (Gpu.shader_formats device <> []) "Device shader formats";
          command_buffers device;
          buffer_uploads device;
          buffer_downloads device;
          sampled_handles device;
          texture_upload_formats device;
          texture_downloads device;
          texture_copies device;
          if List.mem Gpu.Spirv (Gpu.shader_formats device) then (
            shader_checks device;
            offscreen_rendering device;
            offscreen_sampling device);
          window device context;
          Gpu.destroy_device device;
          invalid (fun () -> Gpu.wait_idle device);
          invalid (fun () -> Gpu.acquire_command_buffer device)))
