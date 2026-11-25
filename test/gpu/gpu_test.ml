open Sdl3

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

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

let with_render_pass device claim ~clear f =
  let open Gpu in
  using cancel_command_buffer (acquire_command_buffer device) (fun commands ->
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

let wrong_device device context claim =
  let open Gpu in
  using destroy_device
    (create_device ~driver:(driver device) context (shader_formats device))
    (fun other ->
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
  let create ?entrypoint =
    create_shader device ~stage:Vertex ~format:Spirv ?entrypoint
  in
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
          with_render_pass device claim ~clear (fun _ pass ->
              invalid (fun () -> bind_graphics_pipeline pass pipeline))))

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
          if List.mem Gpu.Spirv (Gpu.shader_formats device) then
            triangle device context claim
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
          if List.mem Gpu.Spirv (Gpu.shader_formats device) then
            shader_checks device;
          window device context;
          Gpu.destroy_device device;
          invalid (fun () -> Gpu.wait_idle device);
          invalid (fun () -> Gpu.acquire_command_buffer device)))
