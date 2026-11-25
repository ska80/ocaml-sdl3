open Sdl3

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

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
          Gpu.wait_idle device;
          Window.hide window;
          ignore (Gpu.clear_and_present claim color);
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
      using Gpu.destroy_device (Gpu.create_device context formats)
        (fun device ->
          invalid (fun () -> quit context);
          check (List.mem (Gpu.driver device) (Gpu.drivers ())) "Device driver";
          check (Gpu.shader_formats device <> []) "Device shader formats";
          window device context;
          Gpu.destroy_device device;
          invalid (fun () -> Gpu.wait_idle device)))
