open Sdl3

let check condition message = if not condition then failwith message

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let bytes_from_file file =
  let s = In_channel.with_open_bin file In_channel.input_all in
  let buffer =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
      (String.length s)
  in
  String.iteri (fun i c -> buffer.{i} <- Char.code c) s;
  buffer

let () =
  check ((Sdl3_image.version ()).major = 3) "SDL_image version";
  with_init [] (fun context ->
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
