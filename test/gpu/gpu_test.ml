open Sdl3

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

external gpu_buffer_matches : 'kind Gpu.buffer -> string -> bool
  = "test_gpu_buffer_matches"

type color_target

external create_color_target : Gpu.swapchain -> color_target
  = "test_gpu_create_color_target"

external release_color_target : color_target -> unit
  = "test_gpu_release_color_target"

external begin_color_pass :
  Gpu.command_buffer -> color_target -> Gpu.render_pass
  = "test_gpu_begin_color_pass"

external color_target_matches : color_target -> Color.t -> bool
  = "test_gpu_color_target_matches"

let packed_bytes bytes =
  Bigarray.Array1.init Bigarray.int8_unsigned Bigarray.c_layout
    (Bytes.length bytes) (Bytes.get_uint8 bytes)

let with_copy_pass commands f =
  using Gpu.end_copy_pass (Gpu.begin_copy_pass commands) f

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
      check (gpu_buffer_matches dst "456789abcdefwxyz") "GPU upload bytes";
      using release_upload_buffer (create_upload_buffer device ~size:4)
        (fun src ->
          write_upload_buffer src new_data;
          using cancel_command_buffer (acquire_command_buffer device)
            (fun commands ->
              with_copy_pass commands (fun pass ->
                  upload_to_buffer pass ~src ~dst ~size:4);
              cancel_command_buffer commands));
      check
        (gpu_buffer_matches dst "456789abcdefwxyz")
        "Canceled upload changed bytes");
  using release_upload_buffer (create_upload_buffer device ~size:4) (fun _ ->
      invalid (fun () -> destroy_device device))

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

let wrong_upload_device device other =
  let open Gpu in
  let data = packed_bytes (Bytes.of_string "data") in
  let with_resources d f =
    using release_upload_buffer (create_upload_buffer d ~size:4) (fun src ->
        write_upload_buffer src data;
        using release_buffer (create_vertex_buffer d ~size:4) (fun dst ->
            using release_texture
              (create_sampled_texture d ~w:1 ~h:1)
              (f src dst)))
  in
  with_resources device (fun src dst texture ->
      with_resources other (fun other_src other_dst other_texture ->
          using cancel_command_buffer (acquire_command_buffer device)
            (fun commands ->
              with_copy_pass commands (fun pass ->
                  invalid (fun () ->
                      upload_to_buffer pass ~src:other_src ~dst ~size:4);
                  invalid (fun () ->
                      upload_to_buffer pass ~src ~dst:other_dst ~size:4);
                  invalid (fun () ->
                      upload_to_texture pass ~src:other_src ~dst:texture);
                  invalid (fun () ->
                      upload_to_texture pass ~src ~dst:other_texture)))))

let wrong_device device context claim =
  let open Gpu in
  using destroy_device
    (create_device ~driver:(driver device) context (shader_formats device))
    (fun other ->
      wrong_upload_device device other;
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

let triangle_pipeline device claim =
  let open Gpu in
  using release_shader (triangle_vertex device) (fun vertex ->
      using release_shader (triangle_fragment device) (fun fragment ->
          create_swapchain_pipeline claim ~vertex ~fragment
            ~primitive:Triangle_list))

let wrong_pipeline_device device context claim ~clear =
  let open Gpu in
  using destroy_device
    (create_device ~driver:(driver device) context [ Spirv ])
    (fun other ->
      using release_shader (triangle_vertex other) (fun vertex ->
          using release_shader (triangle_fragment device) (fun fragment ->
              invalid (fun () ->
                  create_swapchain_pipeline claim ~vertex ~fragment
                    ~primitive:Triangle_list)));
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

let mesh_pipeline device claim =
  let open Gpu in
  let position = { location = 0; format = Float32x2; offset = 0 } in
  let color = { location = 1; format = Unorm8x4; offset = 8 } in
  let layout = { stride = 12; attributes = [ position; color ] } in
  using release_shader
    (create_shader device ~stage:Vertex ~format:Spirv
       (shader_code "mesh.vert.spv"))
    (fun vertex ->
      using release_shader
        (create_shader device ~stage:Fragment ~format:Spirv
           (shader_code "mesh.frag.spv"))
        (fun fragment ->
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
          create layout))

let mesh_vertices () =
  let vertices = Bytes.make 36 '\255' in
  List.iteri
    (fun i (x, y) ->
      Bytes.set_int32_ne vertices (i * 12) (Int32.bits_of_float x);
      Bytes.set_int32_ne vertices ((i * 12) + 4) (Int32.bits_of_float y);
      Bytes.set_uint8 vertices ((i * 12) + 8 + i) 32)
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

let resource_pipeline device claim =
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
          create_swapchain_pipeline claim ~vertex ~fragment
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
  using release_upload_buffer (create_upload_buffer device ~size:512)
    (fun src ->
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
    using release_color_target (create_color_target claim) f
  in
  let with_pass commands target f =
    using end_render_pass (begin_color_pass commands target) f
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
                (color_target_matches first (Color.rgb 255 0 255))
                "GPU shader resources in the first draw";
              check
                (color_target_matches second (Color.rgb 255 255 0))
                "GPU shader resources after a uniform update")))

let shader_resources device context claim =
  let open Gpu in
  let texture () = create_sampled_texture device ~w:2 ~h:2 in
  using release_graphics_pipeline (resource_pipeline device claim)
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
          sampled_handles device;
          if List.mem Gpu.Spirv (Gpu.shader_formats device) then
            shader_checks device;
          window device context;
          Gpu.destroy_device device;
          invalid (fun () -> Gpu.wait_idle device);
          invalid (fun () -> Gpu.acquire_command_buffer device)))
