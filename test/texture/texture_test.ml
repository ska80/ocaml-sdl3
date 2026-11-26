open Sdl3

external read_pixel : Renderer.t -> int -> int -> Color.t
  = "test_texture_read_pixel"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let check ok message = if not ok then failwith message

let invalid name f =
  match f () with
  | exception Invalid_argument _ -> ()
  | () -> failwith ("Expected Invalid_argument: " ^ name)

let unsupported fn f =
  match f () with
  | exception Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | () -> failwith ("Expected an SDL error from " ^ fn)

let pixel ?(tolerance = 0) renderer x y (expected : Color.t) =
  let got = read_pixel renderer x y in
  let close a b = abs (a - b) <= tolerance in
  if
    not
      (close got.r expected.r && close got.g expected.g
     && close got.b expected.b && close got.a expected.a)
  then
    failwith
      (Printf.sprintf "Pixel %d,%d: expected (%d,%d,%d,%d), got (%d,%d,%d,%d)" x
         y expected.r expected.g expected.b expected.a got.r got.g got.b got.a)

let black = Color.rgb 0 0 0
let red = Color.rgb 255 0 0
let green = Color.rgb 0 255 0
let blue = Color.rgb 0 0 255
let white = Color.rgb 255 255 255
let magenta = Color.rgb 255 0 255
let rect x y w h = Rect.make ~x ~y ~w ~h
let frect x y w h = Frect.make ~x ~y ~w ~h
let quad = frect 2. 2. 8. 8.
let white_region = frect 6. 6. 4. 4.
let grid = frect 2. 2. 12. 12.
let borders = Texture.{ left = 2.; right = 4.; top = 3.; bottom = 2. }

let clear renderer color =
  Renderer.set_draw_color renderer color;
  Renderer.clear renderer

let make_texture context renderer ~size paint =
  using Surface.destroy (Surface.create context ~w:size ~h:size) (fun surface ->
      paint surface;
      Texture.of_surface renderer surface)

let using_texture texture f =
  using Texture.destroy texture (fun texture ->
      Texture.set_scale_mode texture Nearest;
      Texture.set_blend_mode texture None;
      f texture)

let pattern context renderer ~pad =
  let offset, size = if pad then (2, 16) else (0, 8) in
  make_texture context renderer ~size (fun surface ->
      Surface.fill surface magenta;
      List.iter
        (fun (x, y, color) ->
          Surface.fill ~rect:(rect (offset + x) (offset + y) 4 4) surface color)
        [ (0, 0, red); (4, 0, green); (0, 4, blue); (4, 4, white) ])

let color_mod renderer texture =
  clear renderer black;
  Texture.set_blend_mode texture Blend;
  Texture.set_alpha_mod texture 128;
  Texture.set_color_mod texture (Color.rgba 128 96 200 0);
  Texture.draw ~src:white_region ~dst:(frect 2. 2. 4. 4.) renderer texture;
  Texture.set_color_mod texture white;
  Texture.draw ~src:white_region ~dst:(frect 8. 2. 4. 4.) renderer texture;
  Texture.set_alpha_mod texture 255;
  Texture.draw ~src:white_region ~dst:(frect 14. 2. 4. 4.) renderer texture;
  pixel ~tolerance:1 renderer 3 3 (Color.rgb 64 48 100);
  pixel ~tolerance:1 renderer 9 3 (Color.rgb 128 128 128);
  pixel renderer 15 3 white;
  Texture.set_blend_mode texture None

let rotated renderer texture =
  clear renderer black;
  Texture.draw_rotated ~src:quad ~dst:(frect 18. 12. 8. 8.) ~pivot:(0., 0.)
    renderer texture ~angle:90.;
  Texture.draw_rotated ~src:quad ~dst:(frect 25. 12. 8. 8.) renderer texture
    ~angle:90.;
  Texture.draw_rotated ~src:quad ~dst:(frect 33. 20. 8. 8.) ~pivot:(10., 0.)
    ~flip:Horizontal renderer texture ~angle:450.;
  Texture.draw_rotated ~src:quad ~dst:(frect 48. 12. 8. 8.) renderer texture
    ~angle:(360. *. 1e10);
  Renderer.set_viewport renderer (Some (rect 2 26 8 8));
  Texture.draw_rotated ~src:quad renderer texture ~angle:90.;
  Renderer.set_viewport renderer None;
  List.iter
    (fun (x, y, color) -> pixel renderer x y color)
    [
      (12, 14, blue);
      (16, 14, red);
      (12, 18, white);
      (16, 18, green);
      (19, 14, black);
      (27, 14, blue);
      (31, 14, red);
      (37, 12, white);
      (41, 12, green);
      (37, 16, blue);
      (41, 16, red);
      (44, 12, black);
      (49, 13, red);
      (4, 28, blue);
      (8, 28, red);
    ]

let affine renderer texture =
  clear renderer black;
  Texture.draw_affine ~src:quad renderer texture ~origin:(6., 4.)
    ~right:(22., 8.) ~down:(10., 20.);
  List.iter
    (fun (x, y, color) -> pixel renderer x y color)
    [
      (11, 9, red);
      (19, 11, green);
      (13, 17, blue);
      (21, 19, white);
      (6, 15, black);
      (25, 10, black);
    ];
  Texture.set_color_mod texture (Color.rgb 128 128 128);
  Texture.set_alpha_mod texture 128;
  Texture.set_blend_mode texture Blend;
  Texture.draw_affine ~src:quad renderer texture ~origin:(34., 4.)
    ~right:(50., 8.) ~down:(38., 20.);
  pixel ~tolerance:1 renderer 49 19 (Color.rgb 64 64 64);
  Texture.set_color_mod texture white;
  Texture.set_alpha_mod texture 255;
  Texture.set_blend_mode texture None

let tiled context renderer texture =
  clear renderer black;
  Texture.draw_tiled ~src:quad ~dst:(frect 2. 3. 22. 20.) ~scale:2. renderer
    texture;
  using_texture (pattern context renderer ~pad:false) (fun whole ->
      Renderer.set_viewport renderer (Some (rect 28 4 13 11));
      Texture.draw_tiled renderer whole;
      Renderer.set_viewport renderer None);
  List.iter
    (fun (x, y, color) -> pixel renderer x y color)
    [
      (3, 4, red);
      (11, 4, green);
      (3, 12, blue);
      (11, 12, white);
      (23, 4, red);
      (11, 20, green);
      (23, 22, red);
      (24, 22, black);
      (29, 5, red);
      (33, 5, green);
      (37, 5, red);
      (40, 14, green);
      (27, 5, black);
      (29, 15, black);
    ]

let nine_slice context renderer =
  let yellow = Color.rgb 255 255 0 and gray = Color.rgb 96 96 96 in
  let cyan = Color.rgb 0 255 255 and orange = Color.rgb 255 128 0 in
  let panels =
    make_texture context renderer ~size:16 (fun surface ->
        Surface.fill surface magenta;
        List.iter
          (fun (x, y, w, h, color) ->
            Surface.fill ~rect:(rect x y w h) surface color)
          [
            (2, 2, 2, 3, red);
            (4, 2, 6, 3, yellow);
            (10, 2, 4, 3, green);
            (2, 5, 2, 7, white);
            (4, 5, 6, 7, gray);
            (10, 5, 4, 7, blue);
            (2, 12, 2, 2, cyan);
            (4, 12, 6, 2, orange);
            (10, 12, 4, 2, magenta);
          ])
  in
  using_texture panels (fun texture ->
      clear renderer black;
      Texture.draw_nine_slice ~src:grid ~dst:(frect 10. 8. 24. 19.) ~scale:1.5
        renderer texture ~borders;
      Texture.draw_nine_slice ~src:grid ~dst:(frect 36. 4. 20. 14.) ~scale:0.
        renderer texture ~borders;
      (* The destination can be exactly as wide and high as its corners. *)
      Renderer.set_viewport renderer (Some (rect 2 28 6 5));
      Texture.draw_nine_slice ~src:grid renderer texture ~borders;
      Renderer.set_viewport renderer None;
      List.iter
        (fun (x, y, color) -> pixel renderer x y color)
        [
          (12, 12, red);
          (13, 12, yellow);
          (28, 12, green);
          (12, 13, white);
          (13, 13, gray);
          (28, 13, blue);
          (12, 24, cyan);
          (13, 24, orange);
          (28, 24, magenta);
          (34, 24, black);
          (37, 6, red);
          (38, 6, yellow);
          (38, 7, gray);
          (52, 16, magenta);
          (3, 30, red);
          (4, 30, green);
          (3, 31, cyan);
          (4, 31, magenta);
        ])

let blend_mode () =
  let open Blend_mode in
  let copy = { src = One; dst = Zero; op = Sum } in
  check (compose ~color:copy ~alpha:copy = None) "Compose a standard mode";
  compose
    ~color:{ src = One; dst = One_minus_src_color; op = Sum }
    ~alpha:{ src = Zero; dst = One; op = Sum }

let blending driver renderer texture mode =
  let area = frect 2. 2. 6. 6. in
  let background = Color.rgba 32 96 160 192 in
  let foreground = Color.rgba 128 64 0 240 in
  clear renderer background;
  if driver = "software" then (
    unsupported "SDL_SetRenderDrawBlendMode" (fun () ->
        Renderer.set_draw_blend_mode renderer mode);
    unsupported "SDL_SetTextureBlendMode" (fun () ->
        Texture.set_blend_mode texture mode))
  else (
    Renderer.set_draw_blend_mode renderer mode;
    Renderer.set_draw_color renderer foreground;
    Renderer.fill_rect renderer area;
    Texture.set_blend_mode texture mode;
    Texture.set_color_mod texture foreground;
    Texture.set_alpha_mod texture foreground.a;
    Texture.draw ~src:white_region ~dst:(frect 12. 2. 6. 6.) renderer texture;
    let expected = Color.rgba 144 136 160 192 in
    pixel ~tolerance:1 renderer 3 3 expected;
    pixel ~tolerance:1 renderer 13 3 expected);
  pixel renderer 0 0 background;
  Renderer.set_draw_blend_mode renderer None;
  Texture.set_blend_mode texture None;
  Texture.set_color_mod texture white;
  Texture.set_alpha_mod texture 255

let invalid_inputs driver renderer texture =
  clear renderer black;
  let area = frect 2. 2. 8. 8. in
  let affine ?src ?(right = (10., 2.)) ?(down = (2., 10.)) () =
    Texture.draw_affine ?src renderer texture ~origin:(2., 2.) ~right ~down
  in
  let tiled ?(src = quad) ?(dst = area) ?(scale = 1.) () =
    Texture.draw_tiled ~src ~dst ~scale renderer texture
  in
  let nine ?(src = quad) ?(dst = area) ?scale ?(borders = borders) () =
    Texture.draw_nine_slice ~src ~dst ?scale renderer texture ~borders
  in
  List.iter
    (fun src ->
      invalid "affine source" (affine ~src);
      invalid "tiled source" (tiled ~src);
      invalid "nine-slice source" (nine ~src))
    [
      frect (-1.) 0. 8. 8.;
      frect 14. 0. 4. 4.;
      frect 0. 0. 0. 8.;
      frect 0. 0. 8. infinity;
    ];
  List.iter
    (fun scale -> invalid "tile scale or count" (tiled ~scale))
    [ 0.; -1.; nan; infinity; 1e-40; 1e-4; 3e38 ];
  invalid "tiled destination" (tiled ~dst:(frect 2. 2. (-1.) 8.));
  invalid "affine point" (affine ~right:(nan, 2.));
  invalid "derived affine corner" (affine ~right:(2e38, 2.) ~down:(2e38, 10.));
  invalid "rotation pivot" (fun () ->
      Texture.draw_rotated ~dst:area ~pivot:(0., infinity) renderer texture
        ~angle:90.);
  invalid "nine-slice borders" (nine ~borders:{ borders with bottom = -1. });
  invalid "nine-slice center" (nine ~borders:{ borders with left = 4. });
  invalid "nine-slice negative scale" (nine ~scale:(-1.));
  invalid "nine-slice scale overflow" (nine ~scale:3e38);
  invalid "nine-slice destination" (nine ~scale:1.5 ~dst:(frect 2. 2. 8. 8.));
  if driver = "software" then (
    invalid "software affine triangle"
      (affine ~right:(8192., 2.) ~down:(2., 8192.));
    invalid "software rotation pivot" (fun () ->
        Texture.draw_rotated ~dst:area ~pivot:(0., 50_000.) renderer texture
          ~angle:33.);
    Renderer.set_scale renderer ~x:8. ~y:1.;
    invalid "scaled software tile bounds" (tiled ~dst:(frect 1e8 0. 8. 8.));
    Renderer.set_scale renderer ~x:1. ~y:1.);
  tiled ~dst:(frect 2. 2. 0. 8.) ();
  pixel renderer 3 3 black

let invalid_handles context renderer target texture =
  let reject renderer texture =
    invalid "rotation handle" (fun () ->
        Texture.draw_rotated renderer texture ~angle:90.);
    invalid "affine handle" (fun () ->
        Texture.draw_affine renderer texture ~origin:(0., 0.) ~right:(8., 0.)
          ~down:(0., 8.));
    invalid "tiled handle" (fun () -> Texture.draw_tiled renderer texture);
    invalid "nine-slice handle" (fun () ->
        Texture.draw_nine_slice renderer texture ~borders)
  in
  reject renderer target;
  Domain.join
    (Domain.spawn (fun () ->
         reject renderer texture;
         invalid "modulation on another domain" (fun () ->
             Texture.set_color_mod texture white)));
  using Surface.destroy (Surface.create context ~w:8 ~h:8) (fun surface ->
      using Renderer.destroy (Renderer.create_software surface) (fun other ->
          reject other texture;
          Renderer.destroy other;
          reject other texture));
  using Texture.destroy (Texture.create_streaming renderer ~w:8 ~h:8)
    (fun stream ->
      Texture.with_lock stream (fun _ -> reject renderer stream);
      Texture.destroy stream;
      reject renderer stream;
      invalid "modulation on a closed texture" (fun () ->
          Texture.set_color_mod stream white))

let () =
  let mode = Domain.join (Domain.spawn blend_mode) in
  let driver =
    Option.value (Sys.getenv_opt "SDL_RENDER_DRIVER") ~default:"software"
  in
  with_init [ Video ] (fun context ->
      using Window.destroy
        (Window.create context ~title:"Texture test" ~w:64 ~h:40) (fun window ->
          using Renderer.destroy (Renderer.create ~driver window)
            (fun renderer ->
              using Texture.destroy (Texture.create_target renderer ~w:64 ~h:40)
                (fun target ->
                  using_texture (pattern context renderer ~pad:true)
                    (fun texture ->
                      Renderer.set_target renderer (Some target);
                      Fun.protect
                        ~finally:(fun () -> Renderer.set_target renderer None)
                        (fun () ->
                          color_mod renderer texture;
                          rotated renderer texture;
                          affine renderer texture;
                          tiled context renderer texture;
                          nine_slice context renderer;
                          blending driver renderer texture mode;
                          invalid_inputs driver renderer texture;
                          invalid_handles context renderer target texture))))))
