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

let black = Sdl3.Color.rgb 0 0 0
let white = Sdl3.Color.rgb 255 255 255
let red = Sdl3.Color.rgb 255 0 0
let green = Sdl3.Color.rgb 0 255 0

let count_color surface ~x ~y ~w ~h color =
  let count = ref 0 in
  for py = y to y + h - 1 do
    for px = x to x + w - 1 do
      if Sdl3.Surface.read_pixel surface ~x:px ~y:py = color then incr count
    done
  done;
  !count

let surface_text sdl context =
  let module Surface = Sdl3.Surface in
  using Text_engine.destroy (Text_engine.create_surface context) (fun engine ->
      invalid (fun () -> quit context);
      using Font.close (Font.open_ context "tiny.bdf" ~ptsize:8.) (fun font ->
          invalid (fun () -> Text.create engine font "A\000A");
          using Text.destroy (Text.create engine font "A") (fun text ->
              invalid (fun () -> Text_engine.destroy engine);
              invalid (fun () -> Font.close font);
              Domain.join
                (Domain.spawn (fun () ->
                     invalid (fun () -> Text.size text);
                     invalid (fun () -> Text.destroy text)));
              Gc.full_major ();
              let w, h = Text.size text in
              check (w > 0 && h > 0) "Text has a size";
              using Surface.destroy (Surface.create sdl ~w:40 ~h:32)
                (fun target ->
                  Surface.fill target black;
                  Surface.with_lock target (fun _ ->
                      invalid (fun () ->
                          Text.draw_surface text target ~x:4 ~y:2));
                  Text.draw_surface text target ~x:4 ~y:2;
                  check
                    (count_color target ~x:4 ~y:2 ~w ~h white > 0)
                    "Surface text draws in white by default";
                  check
                    (count_color target ~x:0 ~y:0 ~w:4 ~h black = 4 * h)
                    "Surface text respects the draw position";
                  invalid (fun () -> Text.set_string text "A\000A");
                  check
                    (Text.size text = (w, h))
                    "Invalid string leaves text unchanged";
                  Text.set_string text "A é";
                  check
                    (fst (Text.size text) > w)
                    "Changing text updates its size";
                  invalid (fun () -> Text.set_wrap_width text (-1));
                  Text.set_wrap_width text w;
                  Text.update text;
                  let wrapped = Text.size text in
                  check (snd wrapped > h) "Text wraps to the next line";
                  Text.set_wrap_width text 0;
                  Text.set_string text "A\né";
                  check (Text.size text = wrapped) "Text wraps at newlines";
                  Text.set_color text red;
                  Surface.fill target black;
                  Text.draw_surface text target ~x:(-2) ~y:2;
                  check
                    (count_color target ~x:0 ~y:2 ~w ~h red > 0)
                    "Surface text clips at a negative position";
                  let line = Font.line_skip font in
                  check
                    (count_color target ~x:0 ~y:(2 + line) ~w ~h red > 0)
                    "Surface text draws the second line in the new color";
                  Text.set_string text "";
                  check (Text.size text = (0, 0)) "Empty text has no size";
                  Surface.fill target black;
                  Text.draw_surface text target ~x:4 ~y:2;
                  check
                    (count_color target ~x:0 ~y:0 ~w:40 ~h:32 black = 40 * 32)
                    "Empty text does not draw";
                  Surface.destroy target;
                  invalid (fun () -> Text.draw_surface text target ~x:0 ~y:0));
              Text.destroy text;
              invalid (fun () -> Text.update text));
          Text_engine.destroy engine;
          invalid (fun () -> Text.create engine font "A")))

let renderer_text sdl context =
  let module Renderer = Sdl3.Renderer in
  let module Surface = Sdl3.Surface in
  using Surface.destroy (Surface.create sdl ~w:40 ~h:24) (fun target ->
      using Renderer.destroy (Renderer.create_software target) (fun renderer ->
          using Text_engine.destroy
            (Text_engine.create_renderer context renderer) (fun engine ->
              invalid (fun () -> Renderer.destroy renderer);
              using Font.close (Font.open_ context "tiny.bdf" ~ptsize:8.)
                (fun font ->
                  using Text.destroy (Text.create engine font "A") (fun text ->
                      invalid (fun () -> Text_engine.destroy engine);
                      invalid (fun () -> Font.close font);
                      invalid (fun () -> Text.draw_renderer text ~x:nan ~y:0.);
                      invalid (fun () ->
                          Text.draw_renderer text ~x:0. ~y:infinity);
                      Renderer.set_draw_color renderer black;
                      Renderer.clear renderer;
                      Text.set_color text red;
                      Text.draw_renderer text ~x:3. ~y:4.;
                      Text.set_color text green;
                      Text.set_string text "é";
                      Text.draw_renderer text ~x:20. ~y:4.;
                      Renderer.present renderer;
                      check
                        (count_color target ~x:3 ~y:4 ~w:8 ~h:8 red > 0)
                        "Renderer text draws the first color";
                      check
                        (count_color target ~x:20 ~y:4 ~w:8 ~h:8 green > 0)
                        "Renderer text draws changed text and color")));
          Renderer.destroy renderer;
          invalid (fun () -> Text_engine.create_renderer context renderer)))

let () =
  check ((version ()).major = 3) "SDL_ttf version";
  Sdl3.with_init [] (fun sdl ->
      let surface =
        with_init sdl (fun context ->
            invalid (fun () -> Sdl3.quit sdl);
            stream_fonts sdl context;
            surface_text sdl context;
            renderer_text sdl context;
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
