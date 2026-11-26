open Sdl3_ttf

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Sdl3.Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let scalable_font = "../../examples/music_player/assets/DejaVuSans.ttf"
let uchar c = Uchar.of_char c

let with_text context path ~ptsize string f =
  using Font.close (Font.open_ context path ~ptsize) (fun font ->
      using Text_engine.destroy (Text_engine.create_surface context)
        (fun engine ->
          using Text.destroy (Text.create engine font string) (f font)))

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
                        "Renderer text draws changed text and color";
                      Text.delete text ~offset:0 ~length:2;
                      Text.insert text ~offset:0 "A";
                      Font.set_style font [ Underline ];
                      Font.set_wrap_alignment font Right;
                      Text.set_wrap_width text 20;
                      let sub = Text.substring_at text ~offset:0 in
                      check (sub.rect.x > 0) "Renderer text uses wrap alignment";
                      Renderer.clear renderer;
                      Text.draw_renderer text ~x:0. ~y:4.;
                      Renderer.present renderer;
                      check
                        (count_color target ~x:sub.rect.x ~y:4 ~w:8 ~h:10 green
                        > 0)
                        "Renderer text draws edited text with new font settings")));
          Renderer.destroy renderer;
          invalid (fun () -> Text_engine.create_renderer context renderer)))

let font_settings sdl context =
  let module Surface = Sdl3.Surface in
  with_text context scalable_font ~ptsize:28. "AVA" (fun font text ->
      let bounds = Font.glyph_metrics font (uchar 'A') in
      check
        (bounds.min_x <= 1
        && bounds.max_x > bounds.min_x
        && bounds.min_y <= 0 && bounds.max_y > 0 && bounds.advance > 0)
        "Glyph bearings and advance";
      using Surface.destroy (Surface.create sdl ~w:110 ~h:48) (fun target ->
          let pixels =
            Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout
              (110 * 48 * 4)
          in
          let draw () =
            Surface.fill target black;
            Text.draw_surface text target ~x:2 ~y:2;
            Surface.read_rgba target pixels;
            String.init (Bigarray.Array1.dim pixels) (fun i ->
                Char.chr pixels.{i})
          in
          let original = draw () in
          check
            (Font.style font = [])
            "Regular font starts without added styles";
          List.iter
            (fun style ->
              Font.set_style font [ style; style ];
              check (Font.style font = [ style ]) "Set an individual style";
              check
                (draw () <> original)
                "The existing text draws with the new style")
            Font.[ Bold; Italic; Underline; Strikethrough ];
          Font.set_style font [ Strikethrough; Underline; Italic; Bold ];
          check
            (Font.style font = [ Bold; Italic; Underline; Strikethrough ])
            "Combine font styles";
          Font.set_style font [];
          check (draw () = original) "Reset all font styles";
          Font.set_outline font 2;
          check (Font.outline font = 2) "Outline thickness";
          check (draw () <> original) "Outline changes the drawn glyphs";
          let outlined = Font.glyph_metrics font (uchar 'A') in
          check (outlined.max_x > bounds.max_x) "Outline affects glyph bounds";
          invalid (fun () -> Font.set_outline font (-1));
          invalid (fun () -> Font.set_outline font 32768);
          check
            (Font.outline font = 2)
            "Invalid outlines do not change the font";
          Font.set_outline font 0;
          check (draw () = original) "Remove the outline");
      List.iter
        (fun mode ->
          Font.set_hinting font mode;
          check (Font.hinting font = mode) "Set a hinting mode";
          Text.update text)
        Font.[ Light; Mono; No_hinting; Normal ];
      let pair_kerning = Font.glyph_kerning font (uchar 'A') (uchar 'V') in
      check (pair_kerning < 0) "AV has negative kerning in the test font";
      let v_x () = (Text.substring_at text ~offset:1).rect.x in
      Font.set_kerning font true;
      let kerned = v_x () in
      Font.set_kerning font false;
      check (not (Font.kerning font)) "Disable kerning";
      check (v_x () > kerned) "Disabling kerning updates existing layout";
      check
        (Font.glyph_kerning font (uchar 'A') (uchar 'V') = pair_kerning)
        "Pair metrics do not depend on layout kerning";
      Font.set_kerning font true;
      check (Font.kerning font && v_x () = kerned) "Restore kerning";
      Text.set_string text "A\nAA";
      Text.set_wrap_width text 90;
      let line_x alignment =
        Font.set_wrap_alignment font alignment;
        check (Font.wrap_alignment font = alignment) "Wrap alignment";
        (Text.substring_at text ~offset:0).rect.x
      in
      let left = line_x Left in
      let center = line_x Center in
      let right = line_x Right in
      check (left < center && center < right) "Alignment moves a wrapped line";
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> Font.set_style font [ Bold ]);
             invalid (fun () -> Font.glyph_metrics font (uchar 'A')))))

let text_edits context =
  with_text context "tiny.bdf" ~ptsize:8. "AéAA" (fun font text ->
      let saved = Text.string text in
      let initial = Text.size text in
      Text.insert text ~offset:1 "éA";
      check (Text.string text = "AéAéAA") "Insert at a byte boundary";
      check (fst (Text.size text) > fst initial) "Insert updates text size";
      Text.delete text ~offset:1 ~length:3;
      check
        (Text.string text = saved && Text.size text = initial)
        "Delete from the middle";
      Text.insert text ~offset:5 "🙂";
      Text.delete text ~offset:5 ~length:4;
      Text.insert text ~offset:0 "";
      Text.delete text ~offset:5 ~length:0;
      invalid (fun () -> Text.insert text ~offset:2 "A");
      invalid (fun () -> Text.insert text ~offset:(-1) "");
      invalid (fun () -> Text.insert text ~offset:6 "A");
      invalid (fun () -> Text.insert text ~offset:0 "\xed\xa0\x80");
      invalid (fun () -> Text.insert text ~offset:0 "\000");
      invalid (fun () -> Text.delete text ~offset:2 ~length:1);
      invalid (fun () -> Text.delete text ~offset:0 ~length:2);
      invalid (fun () -> Text.delete text ~offset:0 ~length:(-1));
      invalid (fun () -> Text.delete text ~offset:4 ~length:2);
      invalid (fun () -> Text.delete text ~offset:max_int ~length:1);
      invalid (fun () -> Text.set_string text "\xc0\xaf");
      check (Text.string text = saved) "Invalid text edits preserve the string";
      Text.delete text ~offset:0 ~length:5;
      check (Text.string text = "" && Text.size text = (0, 0)) "Delete all text";
      let empty = Text.substring_at text ~offset:0 in
      check
        (empty.offset = 0 && empty.length = 0 && empty.rect.h = Font.height font)
        "Empty text has a position with the font height";
      check (Text.hit_test text ~x:2 ~y:2 = empty) "Hit empty text";
      Text.insert text ~offset:0 "é";
      check (Text.string text = "é") "Insert into empty text";
      Text.destroy text;
      Gc.compact ();
      check (saved = "AéAA") "String snapshots outlive their text";
      invalid (fun () -> Text.insert text ~offset:0 "A");
      invalid (fun () -> Text.delete text ~offset:0 ~length:0);
      invalid (fun () -> Text.string text))

let substring_layout context =
  with_text context "tiny.bdf" ~ptsize:8. "Aé\né A" (fun font text ->
      let first = Text.substring_at text ~offset:1 in
      let second = Text.substring_at text ~offset:4 in
      check
        (first.offset = 1 && first.length = 2 && first.line = 0
       && second.offset = 4 && second.length = 2 && second.line = 1
        && first.rect.y < second.rect.y)
        "Substring byte offsets and lines";
      check
        (Text.substring_at text ~offset:2 = first)
        "Find a group from a continuation byte";
      check
        (Text.hit_test text
           ~x:(first.rect.x + (first.rect.w / 2))
           ~y:(first.rect.y + 2)
        = first)
        "Hit test in text-local coordinates";
      let end_of_line = Text.hit_test text ~x:100 ~y:(first.rect.y + 2) in
      check (end_of_line.offset = 3) "Hit beyond the end of a line";
      check
        (Text.substring_bounds text ~offset:1 ~length:5
        = [ first.rect; second.rect ])
        "Bounds across two lines in line order";
      check
        (Text.substring_bounds text ~offset:2 ~length:1 = [ first.rect ])
        "Substring bounds include an entire multibyte glyph";
      let ending = Text.substring_at text ~offset:8 in
      check
        (ending.offset = 8 && ending.length = 0)
        "Position after the last byte";
      check
        (Text.substring_bounds text ~offset:8 ~length:0 = [])
        "Empty range has no bounds";
      invalid (fun () -> Text.substring_at text ~offset:(-1));
      invalid (fun () -> Text.substring_at text ~offset:9);
      invalid (fun () -> Text.substring_bounds text ~offset:5 ~length:4);
      invalid (fun () -> Text.hit_test text ~x:max_int ~y:0);
      Text.set_string text (String.concat "" (List.init 16 (fun _ -> "é")));
      Text.set_wrap_width text (fst (Font.measure font "é"));
      let wrapped_first = Text.substring_at text ~offset:2 in
      check
        (wrapped_first.line = 1 && wrapped_first.length = 2
        && Text.substring_at text ~offset:3 = wrapped_first)
        "Find a multibyte wrap start, not the previous line's end marker";
      check
        (Text.substring_bounds text ~offset:2 ~length:2 = [ wrapped_first.rect ])
        "A wrapped range ending after one glyph spans one line";
      check
        (first.offset = 1 && first.rect.w > 0)
        "Layout results are snapshots";
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> Text.hit_test text ~x:0 ~y:0);
             invalid (fun () -> Text.insert text ~offset:0 "A")));
      Text.destroy text;
      invalid (fun () -> Text.substring_at text ~offset:0);
      invalid (fun () -> Text.substring_bounds text ~offset:0 ~length:0))

let shaping context =
  with_text context scalable_font ~ptsize:18. "office" (fun font text ->
      check
        (Font.direction font = None && Font.script font = None)
        "Font shaping defaults";
      check
        (Text.direction text = None && Text.script text = None)
        "Text shaping defaults";
      Font.set_direction font (Some Left_to_right);
      check
        (Text.direction text = Some Left_to_right)
        "Text inherits font direction";
      invalid (fun () -> Font.set_script font (Some "lat"));
      invalid (fun () -> Text.set_script text (Some "12e!"));
      invalid (fun () -> Text.set_script text (Some "\000atn"));
      if has_harfbuzz () then (
        Font.set_script font (Some "Latn");
        check
          (Font.script font = Some "Latn" && Text.script text = Some "Latn")
          "Text inherits font script";
        let ligature = Text.substring_at text ~offset:2 in
        check
          (ligature.offset = 1 && ligature.length = 3)
          "Three code points share a ligature";
        check
          (Text.substring_bounds text ~offset:2 ~length:1 = [ ligature.rect ])
          "A selection inside a ligature covers the whole glyph";
        Text.set_string text "مرحبا";
        Text.set_script text (Some "Arab");
        Text.set_direction text (Some Right_to_left);
        let first = Text.substring_at text ~offset:0 in
        let last = Text.substring_at text ~offset:8 in
        check
          (Text.script text = Some "Arab" && Font.script font = Some "Latn")
          "Per-text script override";
        check
          (Text.direction text = Some Right_to_left
          && first.direction = Some Right_to_left
          && first.rect.x > last.rect.x)
          "Right-to-left layout orders glyphs from the right";
        List.iter
          (fun direction ->
            Text.set_direction text (Some direction);
            check
              (Text.direction text = Some direction)
              "Vertical text direction")
          [ Top_to_bottom; Bottom_to_top ];
        Text.set_script text None;
        Text.set_direction text None;
        check
          (Text.script text = Some "Latn"
          && Text.direction text = Some Left_to_right)
          "Restore the font shaping defaults";
        Font.set_script font None;
        check (Text.script text = None) "Reset the font script")
      else (
        sdl_error "TTF_SetTextDirection" (fun () ->
            Text.set_direction text (Some Right_to_left));
        sdl_error "TTF_SetFontDirection" (fun () ->
            Font.set_direction font (Some Top_to_bottom));
        sdl_error "TTF_SetFontScript" (fun () ->
            Font.set_script font (Some "Latn"));
        sdl_error "TTF_SetTextScript" (fun () ->
            Text.set_script text (Some "Arab"));
        check
          (Text.direction text = Some Left_to_right && Text.script text = None)
          "No HarfBuzz leaves shaping settings unchanged");
      Font.set_direction font None;
      check (Text.direction text = None) "Reset the font direction")

let fallback_fonts context =
  let b = uchar 'B' in
  using Font.close (Font.open_ context scalable_font ~ptsize:8.) (fun first ->
      using Font.close (Font.open_ context scalable_font ~ptsize:12.)
        (fun second ->
          using Font.close (Font.open_ context "tiny.bdf" ~ptsize:8.)
            (fun other ->
              with_text context "tiny.bdf" ~ptsize:8. "BB" (fun font text ->
                  check (not (Font.has_glyph font b)) "The bitmap font lacks B";
                  let missing = Text.size text in
                  invalid (fun () -> Font.add_fallback font ~fallback:font);
                  Font.add_fallback font ~fallback:first;
                  let added = Text.size text in
                  check (added <> missing)
                    "Fallback refreshes cached text layout";
                  Font.add_fallback font ~fallback:second;
                  Font.add_fallback font ~fallback:first;
                  check (Font.has_glyph font b) "Fallback adds coverage";
                  check
                    (Font.glyph_metrics font b = Font.glyph_metrics first b
                    && Text.size text = added)
                    "Fallback fonts are tried in insertion order";
                  invalid (fun () -> Font.add_fallback other ~fallback:font);
                  invalid (fun () -> Font.add_fallback first ~fallback:other);
                  Font.add_fallback other ~fallback:first;
                  invalid (fun () -> Font.close first);
                  invalid (fun () -> Font.close second);
                  Gc.compact ();
                  Font.set_size first ~ptsize:10.;
                  check
                    (Text.size text <> added)
                    "Changing a fallback invalidates cached layout";
                  Font.remove_fallback font ~fallback:first;
                  Font.remove_fallback font ~fallback:first;
                  invalid (fun () -> Font.close first);
                  Font.close other;
                  Font.close first;
                  check
                    (Font.glyph_metrics font b = Font.glyph_metrics second b
                    && Text.size text <> added)
                    "Removing the first fallback selects the next one";
                  Font.clear_fallbacks font;
                  Font.clear_fallbacks font;
                  Font.close second;
                  check
                    ((not (Font.has_glyph font b)) && Text.size text = missing)
                    "Clear fallbacks while a text object stays open";
                  invalid (fun () -> Font.add_fallback font ~fallback:first);
                  invalid (fun () -> Font.wrap_alignment other)))))

let () =
  let Sdl3.{ major; minor; patch } = Sdl3_ttf.version () in
  check ((major, minor, patch) >= (3, 2, 2)) "Minimum SDL_ttf version";
  let shaping_available = has_harfbuzz () in
  check
    (Domain.join (Domain.spawn has_harfbuzz) = shaping_available)
    "HarfBuzz query on another thread";
  Sdl3.with_init [] (fun sdl ->
      let surface =
        with_init sdl (fun context ->
            invalid (fun () -> Sdl3.quit sdl);
            stream_fonts sdl context;
            surface_text sdl context;
            renderer_text sdl context;
            font_settings sdl context;
            text_edits context;
            substring_layout context;
            shaping context;
            fallback_fonts context;
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
