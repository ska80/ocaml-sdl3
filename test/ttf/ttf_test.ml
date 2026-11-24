open Sdl3_ttf

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let () =
  check ((version ()).major = 3) "SDL_ttf version";
  Sdl3.with_init [] (fun sdl ->
      let surface =
        with_init sdl (fun context ->
            invalid (fun () -> Sdl3.quit sdl);
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
