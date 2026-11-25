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

let () =
  check ((Sdl3_image.version ()).major = 3) "SDL_image version";
  with_init [] (fun context ->
      stream_images context;
      using Sys.remove (Filename.temp_file "sdl3-image" ".png") (fun path ->
          using Surface.destroy (Surface.create context ~w:9 ~h:7)
            (fun surface ->
              let pixel = Color.rgba 28 12 99 177 in
              Surface.fill surface pixel;
              Sdl3_image.save_png surface path;
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
