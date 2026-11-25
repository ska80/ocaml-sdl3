open Sdl3_ttf

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let stream_fonts sdl context =
  let module Io = Sdl3.Io in
  let data = In_channel.with_open_bin "tiny.bdf" In_channel.input_all in
  let length = String.length data in
  let bytes =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout (length + 2)
  in
  String.iteri (fun i c -> bytes.{i + 2} <- Char.code c) data;
  let backing = Bigarray.Array1.sub bytes 2 length in
  using Io.close (Io.of_memory_rw sdl backing) (fun io ->
      check (Io.seek io ~from:Start 2L = 2L) "Seek in font stream";
      invalid (fun () -> Font.open_io context io ~ptsize:0.);
      check (Io.tell io = 2L) "Failed validation does not move the stream";
      using Font.close (Font.open_io context io ~ptsize:8.) (fun font ->
          invalid (fun () -> quit context);
          invalid (fun () -> Io.close io);
          invalid (fun () -> Io.tell io);
          invalid (fun () -> Io.seek ~from:Start io 0L);
          invalid (fun () -> Io.size io);
          invalid (fun () -> Io.flush io);
          invalid (fun () -> Io.read io bytes ~offset:0 ~length:0);
          invalid (fun () -> Io.write io bytes ~offset:0 ~length:0);
          invalid (fun () -> Sdl3.Surface.load_bmp_io io);
          invalid (fun () -> Font.open_io context io ~ptsize:8.);
          Gc.full_major ();
          let w, h = Font.measure font "Aé" in
          check (w > 0 && h > 0) "Font opened from a memory stream");
      check (Io.seek io ~from:Start 0L = 0L) "Seek after closing a font";
      using Font.close (Font.open_io context io ~ptsize:8.) (fun font ->
          check (Font.has_glyph font (Uchar.of_int 233)) "Reuse font stream"));
  let bad = Bigarray.Array1.sub bytes 0 2 in
  Bigarray.Array1.fill bad 0;
  using Io.close (Io.of_memory sdl bad) (fun io ->
      (match Font.open_io context io ~ptsize:8. with
      | exception Sdl3.Error message ->
          check (String.starts_with ~prefix:"TTF_OpenFontIO: " message) message
      | _ -> failwith "Opening an invalid font stream must fail");
      check (Io.size io = 2L) "Failed font open leaves the stream usable";
      Io.close io;
      invalid (fun () -> Font.open_io context io ~ptsize:8.))

let () =
  check ((version ()).major = 3) "SDL_ttf version";
  Sdl3.with_init [] (fun sdl ->
      let surface =
        with_init sdl (fun context ->
            invalid (fun () -> Sdl3.quit sdl);
            stream_fonts sdl context;
            (match
               Font.open_ context "sdl3-test-missing-font.ttf" ~ptsize:8.
             with
            | exception Sdl3.Error message ->
                check
                  (String.starts_with ~prefix:"TTF_OpenFont: " message)
                  message
            | _ -> failwith "Opening a missing font must fail");
            using Font.close (Font.open_ context "tiny.bdf" ~ptsize:8.)
              (fun font ->
                invalid (fun () -> quit context);
                check (Font.has_glyph font (Uchar.of_int 233)) "Unicode glyph";
                check
                  (Font.height font > 0 && Font.line_skip font > 0)
                  "Font metrics";
                let w, h = Font.measure font "Aé" in
                check (w > 0 && h > 0) "Text size";
                let _, wrapped_h = Font.measure ~wrap_width:0 font "A\né" in
                check (wrapped_h > h) "Wrapped text size";
                invalid (fun () -> Font.measure font "A\000A");
                let white = Sdl3.Color.rgb 255 255 255 in
                using Sdl3.Surface.destroy
                  (Font.render ~mode:Solid ~wrap_width:0 font "A\né" white)
                  (fun surface ->
                    check
                      (snd (Sdl3.Surface.size surface) = wrapped_h)
                      "Wrapped surface height");
                let surface = Font.render font "Aé" white in
                Font.close font;
                invalid (fun () -> Font.height font);
                surface))
      in
      using Sdl3.Surface.destroy surface (fun surface ->
          let w, h = Sdl3.Surface.size surface in
          check (w > 0 && h > 0) "Text surface after TTF_Quit";
          invalid (fun () -> Sdl3.quit sdl)))
