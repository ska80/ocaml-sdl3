open Sdl3
open Sdl3_ttf

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) scope f = scope f
let dim = Bigarray.Array1.dim

let iter f buffer =
  for i = 0 to dim buffer - 1 do
    f buffer.{i}
  done

let shader_code name =
  In_channel.with_open_bin ("shaders/" ^ name ^ ".spv") In_channel.input_all

let scalable_font = "../../examples/music_player/assets/DejaVuSans.ttf"
let tiny_font = "../ttf/tiny.bdf"
let black = Color.rgb 0 0 0

let w = 192
and h = 160

let bytes size =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size

let copy_pass commands f =
  using Gpu.end_copy_pass (Gpu.begin_copy_pass commands) f

let render_pass commands ~target ~load f =
  using Gpu.end_render_pass (Gpu.begin_render_pass commands ~target ~load) f

let submit device record =
  let open Gpu in
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  record commands;
  using release_fence (submit_and_acquire_fence commands) wait_fence

let atlas data =
  List.find_map
    (fun (seq : Text.gpu_sequence) ->
      match seq.source with
      | Solid -> None
      | Atlas { texture; _ } -> Some texture)
    (Text.gpu_sequences data)
  |> Option.get

let check_geometry data ~clockwise ~atlas_size =
  let open Text in
  List.iter
    (fun { positions; indices; source } ->
      let count = dim positions / 2 in
      check (count > 0 && count mod 4 = 0) "Four vertices per glyph or fill";
      check (dim indices = count / 4 * 6) "Two triangles per glyph or fill";
      iter (fun n -> check (Float.is_finite n) "Finite position") positions;
      iter
        (fun index ->
          let i = Int32.to_int index in
          check (i >= 0 && i < count) "Every index fits its sequence")
        indices;
      for i = 0 to (dim indices / 3) - 1 do
        let point j =
          let x = 2 * Int32.to_int indices.{(3 * i) + j} in
          (positions.{x}, positions.{x + 1})
        in
        let ax, ay = point 0 and bx, by = point 1 and cx, cy = point 2 in
        let area = ((bx -. ax) *. (cy -. ay)) -. ((by -. ay) *. (cx -. ax)) in
        check (if clockwise then area < 0. else area > 0.) "Triangle winding"
      done;
      match source with
      | Solid -> ()
      | Atlas { texture; uv; _ } ->
          check
            (Gpu.texture_size texture = (atlas_size, atlas_size))
            "Atlas dimensions";
          check (Gpu.texture_mip_levels texture = 1) "Atlas has a single level";
          check (Gpu.texture_format texture = Bgra8_unorm) "Atlas format";
          check (dim uv = dim positions) "One UV pair per vertex";
          iter (fun n -> check (n >= 0. && n <= 1.) "Normalized UV") uv)
    (gpu_sequences data)

let lifetimes device context =
  let open Gpu in
  List.iter
    (fun atlas_size ->
      invalid (fun () -> Text_engine.create_gpu ~atlas_size context device))
    [ -4; 0; 3; 5; 16388; max_int ];
  let@ font = using Font.close (Font.open_ context tiny_font ~ptsize:8.) in
  check (not (Font.sdf font)) "SDF starts disabled";
  invalid (fun () -> Font.set_sdf font true);
  using Text_engine.destroy
    (Text_engine.create_gpu ~atlas_size:8 context device) (fun engine ->
      using Text.destroy (Text.create engine font "A") (fun text ->
          match Text.update text with
          | exception Error error ->
              check
                (String.starts_with ~prefix:"TTF_GetGPUTextDrawData: " error)
                "The glyph needs room for padding"
          | () -> failwith "Expected a glyph packing error"));
  let@ engine =
    using Text_engine.destroy
      (Text_engine.create_gpu ~atlas_size:12 context device)
  in
  invalid (fun () -> destroy_device device);
  invalid (fun () -> quit context);
  let@ text = using Text.destroy (Text.create engine font "") in
  Text.with_gpu_draw_data text (fun data ->
      check (Text.gpu_sequences data = []) "Empty text");
  Text.set_string text "AéA";
  Font.set_style font [ Underline ];
  Text.set_color text (Color.rgba 220 100 10 110);
  check (Text.color text = Color.rgba 220 100 10 110) "Text color";
  check (Text_engine.gpu_winding engine = Clockwise) "Default winding";
  let@ data = using Text.release_gpu_draw_data (Text.gpu_draw_data text) in
  let sequences = Text.gpu_sequences data in
  check_geometry data ~clockwise:true ~atlas_size:12;
  let glyphs =
    List.filter
      (fun (seq : Text.gpu_sequence) ->
        match seq.source with
        | Atlas _ -> true
        | Solid -> false)
      sequences
  in
  check (List.length glyphs = 2) "Two atlas pages for two different glyphs";
  check
    (List.exists
       (fun (seq : Text.gpu_sequence) -> seq.source = Solid)
       sequences)
    "An underline uses solid geometry";
  let texture = atlas data in
  Gc.compact ();
  check (texture_size texture = (12, 12)) "Atlas survives compaction";
  invalid (fun () -> release_texture texture);
  invalid (fun () -> Text.gpu_draw_data text);
  invalid (fun () -> Text.set_string text "A");
  invalid (fun () -> Text.insert text ~offset:0 "A");
  invalid (fun () -> Text.delete text ~offset:0 ~length:1);
  invalid (fun () -> Text.set_wrap_width text 30);
  invalid (fun () -> Text.size text);
  invalid (fun () -> Text.destroy text);
  invalid (fun () -> Text_engine.destroy engine);
  invalid (fun () -> Font.close font);
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> texture_size texture);
         invalid (fun () -> Text.release_gpu_draw_data data);
         invalid (fun () ->
             Text_engine.set_gpu_winding engine Counter_clockwise)));
  Text_engine.set_gpu_winding engine Counter_clockwise;
  check_geometry data ~clockwise:true ~atlas_size:12;

  let@ from =
    using release_download_buffer
      (create_download_buffer device ~size:(12 * 12 * 4))
  in
  let@ target =
    using release_texture
      (create_texture device ~format:Bgra8_unorm ~usage:Color_target ~w:12 ~h:12)
  in
  let@ commands = using cancel_command_buffer (acquire_command_buffer device) in
  let@ discard = using cancel_command_buffer (acquire_command_buffer device) in
  invalid (fun () -> begin_render_pass commands ~target:texture ~load:Dont_care);
  let region = texture_region texture
  and target_region = texture_region target in
  invalid (fun () ->
      blit_texture commands ~src:target_region ~dst:region ~load:Dont_care);
  using Text.destroy (Text.create engine font "A") (fun other ->
      render_pass commands ~target ~load:(Clear black) (fun _ ->
          invalid (fun () -> Text_engine.destroy engine);
          invalid (fun () -> Text.gpu_draw_data other);
          invalid (fun () -> Text.hit_test other ~x:0 ~y:0)));
  copy_pass commands (fun pass ->
      invalid (fun () -> copy_texture pass ~src:target_region ~dst:region);
      let@ upload =
        using release_upload_buffer (create_upload_buffer device ~size:4)
      in
      invalid (fun () -> upload_to_texture pass ~src:upload ~dst:texture);
      download_from_texture pass ~src:region ~dst:from);
  copy_pass discard (fun pass ->
      copy_texture pass ~src:region ~dst:target_region);

  Text.release_gpu_draw_data data;
  invalid (fun () -> texture_size texture);
  invalid (fun () -> texture_format texture);
  invalid (fun () -> texture_mip_levels texture);
  copy_pass discard (fun pass ->
      invalid (fun () -> copy_texture pass ~src:region ~dst:target_region));
  Text.set_string text "é";
  invalid (fun () -> Text.update text);
  cancel_command_buffer discard;
  invalid (fun () -> Text.size text);
  let@ fence = using release_fence (submit_and_acquire_fence commands) in
  Text.with_gpu_draw_data text (fun later ->
      check_geometry later ~clockwise:false ~atlas_size:12);
  wait_fence fence;
  let pixels = bytes (12 * 12 * 4) in
  read_download_buffer from pixels;
  let covered = ref false in
  for i = 0 to (12 * 12) - 1 do
    if pixels.{(4 * i) + 3} > 0 then covered := true
  done;
  check !covered "A submitted atlas read survives the end of the borrow";
  Text_engine.set_gpu_winding engine Clockwise;
  Text.with_gpu_draw_data text (fun unchanged ->
      check_geometry unchanged ~clockwise:true ~atlas_size:12);
  Text.set_string text (String.make 4097 'A');
  invalid (fun () -> Text.update text);
  Text.set_string text "é";
  let escaped = ref None in
  (match
     Text.with_gpu_draw_data text (fun data ->
         escaped := Some (atlas data);
         raise Exit)
   with
  | exception Exit -> ()
  | _ -> failwith "Expected the draw callback to raise");
  invalid (fun () -> texture_size (Option.get !escaped));
  Text.insert text ~offset:0 "A";
  check (Text.string text = "Aé") "Edit after exception cleanup";
  Text.destroy text;
  Text_engine.destroy engine;
  check
    (dim (List.hd sequences).positions > 0)
    "Copied vertices survive text and engine destruction";
  invalid (fun () -> Text_engine.gpu_winding engine);
  invalid (fun () -> Text.gpu_draw_data text)

let make_pipeline device ~textured =
  let open Gpu in
  let base = if textured then "text" else "fill" in
  let slots =
    let slot location =
      {
        input_rate = Per_vertex;
        layout =
          {
            stride = 8;
            attributes = [ { location; format = Float32x2; offset = 0 } ];
          };
      }
    in
    if textured then [ slot 0; slot 1 ] else [ slot 0 ]
  in
  let count = if textured then 1 else 0 in
  let@ vertex =
    using release_shader
      (create_shader device ~stage:Vertex ~format:Spirv
         (shader_code (base ^ ".vert")))
  in
  let@ fragment =
    using release_shader
      (create_shader device ~stage:Fragment ~format:Spirv ~samplers:count
         ~uniform_buffers:count
         (shader_code (base ^ ".frag")))
  in
  create_graphics_pipeline ~vertex_layouts:slots
    ~blend:Blend.premultiplied_alpha device ~format:Rgba8_unorm ~vertex
    ~fragment ~primitive:Triangle_list

let style Color.{ r; g; b; a } image =
  let kind =
    match (image : Text.gpu_image) with
    | Alpha -> 0.
    | Color -> 1.
    | Sdf -> 2.
  in
  let floats =
    [|
      float r /. 255.;
      float g /. 255.;
      float b /. 255.;
      float a /. 255.;
      kind;
      0.;
      0.;
      0.;
    |]
  in
  let data = bytes 32 and packed = Bytes.create 32 in
  Array.iteri
    (fun i f -> Bytes.set_int32_ne packed (4 * i) (Int32.bits_of_float f))
    floats;
  Bytes.iteri (fun i c -> data.{i} <- Char.code c) packed;
  data

let draw device ~glyph_pipeline ~fill_pipeline sampler text =
  let open Gpu in
  let@ data = using Text.release_gpu_draw_data (Text.gpu_draw_data text) in
  let sequences = Text.gpu_sequences data in
  let color = Text.color text in
  let@ target =
    using release_texture
      (create_texture device ~format:Rgba8_unorm ~usage:Color_target ~w ~h)
  in
  submit device (fun commands ->
      render_pass commands ~target ~load:(Clear black) ignore;
      List.iteri
        (fun i (seq : Text.gpu_sequence) ->
          let v_size = 4 * dim seq.positions and i_size = 4 * dim seq.indices in
          let@ positions =
            using release_buffer (create_vertex_buffer device ~size:v_size)
          in
          let@ indices =
            using release_buffer
              (create_index_buffer device ~format:Uint32 ~size:i_size)
          in
          let@ upload =
            using release_upload_buffer
              (create_upload_buffer device ~size:(max v_size i_size))
          in
          let transfer dest values =
            write_upload_buffer upload values;
            copy_pass commands (fun pass ->
                upload_to_buffer pass ~src:upload ~dst:dest
                  ~size:(4 * dim values))
          in
          transfer positions seq.positions;
          transfer indices seq.indices;
          let record pass =
            bind_index_buffer pass indices;
            draw_indexed_primitives pass ~indices:(dim seq.indices)
          in
          match seq.source with
          | Solid ->
              render_pass commands ~target ~load:Load (fun pass ->
                  bind_graphics_pipeline pass fill_pipeline;
                  bind_vertex_buffer pass positions;
                  record pass)
          | Atlas { texture; uv; image } ->
              let@ uv_buffer =
                using release_buffer (create_vertex_buffer device ~size:v_size)
              in
              transfer uv_buffer uv;
              render_pass commands ~target ~load:Load (fun pass ->
                  bind_graphics_pipeline pass glyph_pipeline;
                  bind_vertex_buffers pass [| (positions, 0); (uv_buffer, 0) |];
                  bind_samplers pass ~stage:Fragment [| (texture, sampler) |];
                  push_uniform_data commands ~stage:Fragment ~slot:0
                    (style color image);
                  record pass;
                  if i = List.length sequences - 1 then (
                    Text.release_gpu_draw_data data;
                    invalid (fun () -> record pass);
                    invalid (fun () ->
                        bind_samplers pass ~stage:Fragment
                          [| (texture, sampler) |]))))
        sequences);
  let size = w * h * 4 in
  let@ download =
    using release_download_buffer (create_download_buffer device ~size)
  in
  submit device (fun commands ->
      copy_pass commands (fun pass ->
          download_from_texture pass ~src:(texture_region target) ~dst:download));
  let pixels = bytes size in
  read_download_buffer download pixels;
  pixels

let count_pixels pixels matches =
  let count = ref 0 in
  for i = 0 to (dim pixels / 4) - 1 do
    let p = 4 * i in
    if matches pixels.{p} pixels.{p + 1} pixels.{p + 2} pixels.{p + 3} then
      incr count
  done;
  !count

let glyphs pixels r g b =
  count_pixels pixels (fun cr cg cb a -> cr = r && cg = g && cb = b && a = 255)

let check_image text ~image size =
  Text.with_gpu_draw_data text (fun data ->
      check_geometry data ~clockwise:true ~atlas_size:size;
      List.iter
        (fun (seq : Text.gpu_sequence) ->
          match seq.source with
          | Atlas atlas ->
              check (atlas.image = image) "Expected glyph image type"
          | Solid -> ())
        (Text.gpu_sequences data);
      ignore (atlas data))

let draw_tests device context =
  let open Gpu in
  let@ glyph_pipeline =
    using release_graphics_pipeline (make_pipeline device ~textured:true)
  in
  let@ fill_pipeline =
    using release_graphics_pipeline (make_pipeline device ~textured:false)
  in
  let@ sampler = using release_sampler (create_sampler device ~filter:Linear) in
  let draw = draw device ~glyph_pipeline ~fill_pipeline sampler in
  let@ engine =
    using Text_engine.destroy (Text_engine.create_gpu context device)
  in
  let with_text path ptsize string f =
    let@ font = using Font.close (Font.open_ context path ~ptsize) in
    let@ text = using Text.destroy (Text.create engine font string) in
    f font text
  in
  with_text tiny_font 8. "Aé" (fun font text ->
      Font.set_style font [ Underline ];
      Text.set_color text (Color.rgb 255 0 0);
      check_image text ~image:Alpha 1024;
      let pixels = draw text in
      check (glyphs pixels 255 0 0 > 10) "Draw red alpha glyphs";
      check (glyphs pixels 0 255 0 >= 8) "Draw a solid underline";
      check (glyphs pixels 0 0 0 > 1000) "Keep the background");
  with_text scalable_font 34. "GPU text" (fun font text ->
      Text.set_color text (Color.rgb 0 100 255);
      check_image text ~image:Alpha 1024;
      Font.set_sdf font true;
      check (Font.sdf font) "Enable SDF";
      check_image text ~image:Sdf 1024;
      let pixels = draw text in
      check (glyphs pixels 0 100 255 > 150) "Draw blue SDF glyphs";
      Font.set_sdf font false;
      check (not (Font.sdf font)) "Disable SDF";
      check_image text ~image:Alpha 1024);
  if Sdl3_ttf.version () = { major = 3; minor = 2; patch = 2 } then
    with_text tiny_font 8. "AG" (fun primary text ->
        let@ fallback =
          using Font.close (Font.open_ context scalable_font ~ptsize:8.)
        in
        Font.set_sdf fallback true;
        Font.add_fallback primary ~fallback;
        Fun.protect
          ~finally:(fun () -> Font.remove_fallback primary ~fallback)
          (fun () ->
            invalid (fun () -> Text.gpu_draw_data text);
            Text.set_string text "G";
            check_image text ~image:Sdf 1024));
  Option.iter
    (fun path ->
      with_text path 109. "🙂" (fun _ text ->
          Text.set_color text (Color.rgb 0 0 255);
          check_image text ~image:Color 1024;
          let pixels = draw text in
          check
            (count_pixels pixels (fun r g b a ->
                 r > 120 && g > 80 && b < 140 && a = 255)
            > 100)
            "Color glyph keeps its RGB rather than the tint"))
    (Sys.getenv_opt "OSDL_TEST_COLOR_FONT")

let renderer_device sdl context =
  if List.mem "gpu" (Renderer.drivers ()) then
    using Renderer.destroy (Renderer.create_gpu_offscreen sdl) (fun renderer ->
        let device = Option.get (Renderer.gpu_device renderer) in
        using Text_engine.destroy (Text_engine.create_gpu context device)
          (fun engine ->
            invalid (fun () -> Renderer.destroy renderer);
            let@ font =
              using Font.close (Font.open_ context tiny_font ~ptsize:8.)
            in
            let@ text = using Text.destroy (Text.create engine font "A") in
            Text.with_gpu_draw_data text (fun data ->
                check_geometry data ~clockwise:true ~atlas_size:1024;
                if List.mem Gpu.Spirv (Gpu.shader_formats device) then
                  let open Gpu in
                  let@ fragment =
                    using release_shader
                      (create_shader device ~stage:Fragment ~format:Spirv
                         ~samplers:1 ~uniform_buffers:1
                         (shader_code "text.frag"))
                  in
                  let@ sampler =
                    using release_sampler
                      (create_sampler device ~filter:Nearest)
                  in
                  invalid (fun () ->
                      Renderer.create_gpu_render_state renderer ~draw:Untextured
                        ~samplers:[| (atlas data, sampler) |]
                        ~fragment)));
        Renderer.destroy renderer;
        invalid (fun () -> Text_engine.create_gpu context device))

let () =
  Sdl3.with_init [ Video ] (fun sdl ->
      Sdl3_ttf.with_init sdl (fun context ->
          let formats = Gpu.[ Spirv; Dxbc; Dxil; Msl; Metallib ] in
          let@ device =
            using Gpu.destroy_device (Gpu.create_device ~debug:true sdl formats)
          in
          lifetimes device context;
          renderer_device sdl context;
          if List.mem Gpu.Spirv (Gpu.shader_formats device) then
            draw_tests device context
          else
            Printf.eprintf
              "Skipping GPU text drawing: SPIR-V is not supported\n%!"))
