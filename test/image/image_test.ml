open Sdl3

let check condition message = if not condition then failwith message

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let buffer size =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size

let bytes_from_file file =
  let s = In_channel.with_open_bin file In_channel.input_all in
  let data = buffer (String.length s) in
  String.iteri (fun i c -> data.{i} <- Char.code c) s;
  data

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let stream_images context =
  using Surface.destroy (Surface.create context ~w:8 ~h:8) (fun surface ->
      let pixel = Color.rgba 44 90 135 177 in
      Surface.fill surface pixel;
      using Io.close
        (Io.of_memory_rw context (buffer 1))
        (fun io ->
          sdl_error "IMG_SaveJPG_IO" (fun () ->
              Sdl3_image.save_jpg_io surface io);
          check (Io.tell io = 1L) "Short image write leaves the stream open");
      let encode save =
        let storage = buffer 4096 in
        using Io.close (Io.of_memory_rw context storage) (fun io ->
            save surface io;
            let len = Int64.to_int (Io.tell io) in
            check (len > 1 && len < 4096) "Image bytes written";
            Bigarray.Array1.sub storage 0 len)
      in
      let png = encode Sdl3_image.save_png_io in
      let jpg = encode (Sdl3_image.save_jpg_io ~quality:90) in
      let decode data =
        using Io.close (Io.of_memory context data) (fun io ->
            let image = Sdl3_image.load_io io in
            using Surface.destroy image (fun image ->
                check (Io.tell io > 0L) "Image reader leaves the stream open";
                Io.close io;
                check (Surface.size image = (8, 8)) "Image stream size";
                Surface.read_pixel image ~x:0 ~y:0))
      in
      check (decode png = pixel) "PNG stream round trip color";
      ignore (decode jpg);
      using Io.close
        (Io.of_memory_rw context (buffer 16))
        (fun io ->
          Surface.with_lock surface (fun _ ->
              invalid (fun () -> Sdl3_image.save_png_io surface io);
              invalid (fun () -> Sdl3_image.save_jpg_io surface io));
          check (Io.tell io = 0L) "A locked surface cannot write image data";
          invalid (fun () -> Sdl3_image.save_jpg_io ~quality:101 surface io);
          check (Io.tell io = 0L) "Invalid JPEG quality does not write";
          let zero = buffer 16 in
          Bigarray.Array1.fill zero 0;
          Io.write io zero ~offset:0 ~length:16;
          ignore (Io.seek io ~from:Start 0L);
          sdl_error "IMG_Load_IO" (fun () -> Sdl3_image.load_io io);
          check (Io.size io = 16L) "Failed image load leaves the stream open";
          Io.close io;
          invalid (fun () -> Sdl3_image.load_io io));
      using Renderer.destroy (Renderer.create_software surface) (fun renderer ->
          let texture =
            using Io.close (Io.of_memory context png) (fun io ->
                Sdl3_image.load_texture_io renderer io)
          in
          using Texture.destroy texture (fun t ->
              check (Texture.size t = (8., 8.)) "Texture loaded from a stream";
              Texture.draw renderer t;
              Renderer.present renderer)))

let animations context =
  let module A = Sdl3_image.Animation in
  (* A fixture made for this test. Each 3 by 2 frame has a different color. *)
  let file = "two_frames.gif" in
  let red = Color.rgb 255 0 0 and green = Color.rgb 0 255 0 in
  let read surface = Surface.read_pixel surface ~x:0 ~y:0 in
  let check_frames animation =
    check (A.size animation = (3, 2)) "Animation size";
    check (A.frame_count animation = 2) "Frame count";
    check (A.frame_delay_ms animation ~index:0 = 70) "First frame delay";
    check (A.frame_delay_ms animation ~index:1 = 130) "Second frame delay"
  in
  using A.destroy (A.load context file) (fun animation ->
      check_frames animation;
      invalid (fun () -> quit context);
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> A.frame_count animation);
             invalid (fun () -> A.destroy animation)));
      List.iter
        (fun index ->
          invalid (fun () -> A.frame_delay_ms animation ~index);
          invalid (fun () -> A.copy_frame animation ~index))
        [ -1; 2; max_int ];
      using Surface.destroy (A.copy_frame animation ~index:0) (fun copy ->
          check (read copy = red) "First frame pixels";
          Surface.fill copy (Color.rgb 0 0 0);
          using Surface.destroy (A.copy_frame animation ~index:0)
            (fun original ->
              check
                (read original = red)
                "Changing a copy leaves the frame unchanged"));
      using Surface.destroy (A.copy_frame animation ~index:0) (fun copy ->
          using Surface.destroy (Surface.create context ~w:3 ~h:2)
            (fun target ->
              using Renderer.destroy (Renderer.create_software target)
                (fun renderer ->
                  invalid (fun () ->
                      A.frame_texture renderer animation ~index:2);
                  using Texture.destroy
                    (A.frame_texture renderer animation ~index:1)
                    (fun texture ->
                      A.destroy animation;
                      invalid (fun () -> A.size animation);
                      invalid (fun () -> A.copy_frame animation ~index:0);
                      check (read copy = red) "Copied frame outlives animation";
                      check
                        (Texture.size texture = (3., 2.))
                        "Frame texture size";
                      invalid (fun () -> Renderer.destroy renderer);
                      Texture.draw renderer texture;
                      Renderer.present renderer;
                      check
                        (read target = green)
                        "Frame texture outlives animation")))));
  let data = bytes_from_file file in
  let length = Bigarray.Array1.dim data in
  let prefixed = buffer (length + 2) in
  prefixed.{0} <- 0;
  prefixed.{1} <- 0;
  Bigarray.Array1.blit data (Bigarray.Array1.sub prefixed 2 length);
  using Io.close (Io.of_memory context prefixed) (fun io ->
      check (Io.seek io ~from:Start 2L = 2L) "Seek to animation data";
      using A.destroy (A.load_io io) (fun animation ->
          check
            (Io.size io = Int64.of_int (length + 2))
            "Animation leaves stream open";
          Io.close io;
          check_frames animation));
  let bad = buffer 16 in
  Bigarray.Array1.fill bad 0;
  using Io.close (Io.of_memory context bad) (fun io ->
      sdl_error "IMG_LoadAnimation_IO" (fun () -> A.load_io io |> A.destroy);
      check (Io.size io = 16L) "Animation load failure leaves stream open";
      Io.close io;
      invalid (fun () -> A.load_io io));
  sdl_error "IMG_LoadAnimation" (fun () ->
      A.load context "sdl3-test-missing-animation.gif" |> A.destroy)

let () =
  let { major; minor; patch } = Sdl3_image.version () in
  check ((major, minor, patch) >= (3, 4, 6)) "Minimum SDL_image version";
  with_init [] (fun context ->
      stream_images context;
      animations context;
      using Sys.remove (Filename.temp_file "sdl3-image" ".png") (fun path ->
          using Surface.destroy (Surface.create context ~w:9 ~h:7)
            (fun surface ->
              let pixel = Color.rgba 28 12 99 177 in
              Surface.fill surface pixel;
              Sdl3_image.save_png surface path;
              using Sdl3_image.Animation.destroy
                (Sdl3_image.Animation.load context path) (fun animation ->
                  check
                    (Sdl3_image.Animation.frame_count animation = 1)
                    "Still image gives one frame");
              let check_image loaded =
                check (Surface.size loaded = (9, 7)) "Loaded PNG size";
                check
                  (Surface.read_pixel loaded ~x:0 ~y:0 = pixel)
                  "Loaded PNG color"
              in
              using Surface.destroy (Sdl3_image.load context path) check_image;
              using Surface.destroy
                (Sdl3_image.load_memory context (bytes_from_file path))
                check_image;
              using Renderer.destroy (Renderer.create_software surface)
                (fun renderer ->
                  using Texture.destroy (Sdl3_image.load_texture renderer path)
                    (fun texture ->
                      check
                        (Texture.size texture = (9., 7.))
                        "SDL_image texture size";
                      (match Renderer.destroy renderer with
                      | exception Invalid_argument _ -> ()
                      | () ->
                          failwith
                            "SDL_image texture must keep its renderer open");
                      Texture.draw renderer texture;
                      Renderer.present renderer)));
          using Sys.remove (Filename.temp_file "sdl3-image" ".jpg") (fun jpg ->
              using Surface.destroy (Surface.create context ~w:8 ~h:8)
                (fun surface ->
                  Surface.fill surface (Color.rgb 128 128 128);
                  Sdl3_image.save_jpg ~quality:90 surface jpg;
                  using Surface.destroy (Sdl3_image.load context jpg)
                    (fun loaded ->
                      check (Surface.size loaded = (8, 8)) "Loaded JPEG size"))));
      match Sdl3_image.load context "sdl3-test-missing-image.png" with
      | exception Error message ->
          check (String.starts_with ~prefix:"IMG_Load: " message) message
      | _ -> failwith "Loading a missing image must fail")
