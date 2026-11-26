open Sdl3

external read_pixel : Renderer.t -> int -> int -> Color.t
  = "test_sprite_batch_read_pixel"

let check ok message = if not ok then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | () -> failwith "Expected Invalid_argument"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let pixel ?(tolerance = 0) renderer x y (expected : Color.t) =
  let got = read_pixel renderer x y in
  let close a b = abs (a - b) <= tolerance in
  if
    not
      (close got.r expected.r && close got.g expected.g
     && close got.b expected.b)
  then
    failwith
      (Printf.sprintf "Pixel %d,%d: expected (%d,%d,%d), got (%d,%d,%d)" x y
         expected.r expected.g expected.b got.r got.g got.b)

let black = Color.rgb 0 0 0
let white = Color.rgb 255 255 255
let red = Color.rgb 255 0 0
let green = Color.rgb 0 255 0
let blue = Color.rgb 0 0 255
let yellow = Color.rgb 255 255 0
let rect x y w h = Rect.make ~x ~y ~w ~h
let frect x y w h = Frect.make ~x ~y ~w ~h
let tile = rect 1 2 8 6
let solid = rect 10 1 2 2
let translucent = rect 10 5 2 2

let atlas context renderer =
  using Surface.destroy (Surface.create context ~w:13 ~h:11) (fun surface ->
      Surface.fill surface (Color.rgb 255 0 255);
      Surface.fill ~rect:(rect 1 2 4 3) surface red;
      Surface.fill ~rect:(rect 5 2 4 3) surface green;
      Surface.fill ~rect:(rect 1 5 4 3) surface blue;
      Surface.fill ~rect:(rect 5 5 4 3) surface yellow;
      Surface.fill ~rect:solid surface white;
      Surface.fill ~rect:translucent surface (Color.rgba 255 255 255 128);
      Texture.of_surface renderer surface)

let clear renderer =
  Renderer.set_draw_color renderer black;
  Renderer.clear renderer

let transforms renderer texture =
  clear renderer;
  let batch = Sprite_batch.create ~capacity:8 in
  let add ?flip ?angle ?pivot_x ?pivot_y x y =
    Sprite_batch.add ?flip ?angle ?pivot_x ?pivot_y batch ~src:tile ~x ~y ~w:16.
      ~h:12.
  in
  add 2. 2.;
  add ~flip:Horizontal 22. 2.;
  add ~flip:Vertical 42. 2.;
  add ~flip:Both 2. 18.;
  add ~angle:450. ~pivot_x:2. ~pivot_y:1. 34. 18.;
  add ~angle:(-90.) ~flip:Vertical 47. 19.;
  add ~angle:30. 18. 39.;
  add ~angle:90. ~pivot_x:(-4.) ~pivot_y:0. 74. 39.;
  Sprite_batch.draw renderer texture batch;
  let quadrants x y a b c d =
    pixel renderer (x + 4) (y + 3) a;
    pixel renderer (x + 12) (y + 3) b;
    pixel renderer (x + 4) (y + 9) c;
    pixel renderer (x + 12) (y + 9) d
  in
  quadrants 2 2 red green blue yellow;
  quadrants 22 2 green red yellow blue;
  quadrants 42 2 blue yellow red green;
  quadrants 2 18 yellow blue green red;
  List.iter
    (fun (x, y, color) -> pixel renderer x y color)
    [
      (34, 21, red);
      (34, 29, green);
      (28, 21, blue);
      (28, 29, yellow);
      (53, 28, blue);
      (59, 20, green);
      (24, 40, red);
      (30, 44, green);
      (21, 45, blue);
      (27, 49, yellow);
      (67, 47, red);
      (17, 13, yellow);
      (18, 4, black);
    ]

let draw_with_view renderer texture =
  clear renderer;
  Renderer.set_scale renderer ~x:2. ~y:0.5;
  Renderer.set_viewport renderer (Some (rect 3 10 20 20));
  (* Clip at texel edges. SDL 3.2.0 can round the source when a scaled
     software copy is clipped within a texel. *)
  Renderer.set_clip_rect renderer (Some (rect 4 4 10 20));
  let batch = Sprite_batch.create ~capacity:1 in
  Sprite_batch.add batch ~src:solid ~x:1. ~y:0. ~w:6. ~h:8.;
  Sprite_batch.draw renderer texture batch;
  Renderer.set_clip_rect renderer None;
  Renderer.set_viewport renderer None;
  Renderer.set_scale renderer ~x:1. ~y:1.;
  pixel renderer 14 7 white;
  pixel renderer 19 8 white;
  pixel renderer 13 7 black;
  pixel renderer 14 6 black;
  pixel renderer 20 8 black

let ordered renderer texture =
  clear renderer;
  let batch = Sprite_batch.create ~capacity:1027 in
  let fill () =
    let add ?tint ?opacity x =
      Sprite_batch.add ?tint ?opacity batch ~src:solid ~x ~y:2. ~w:4. ~h:4.
    in
    for i = 0 to 1024 do
      match i with
      | 0 -> add ~tint:blue 2.
      | 1 -> add ~tint:red 2.
      | 511 -> add ~tint:blue 4.
      | 512 -> add ~tint:green 4.
      | 1023 -> add ~tint:red 6.
      | 1024 -> add ~tint:blue ~opacity:128 6.
      | _ -> Sprite_batch.add batch ~src:solid ~x:(-8.) ~y:0. ~w:2. ~h:2.
    done
  in
  fill ();
  let draw () = Sprite_batch.draw renderer texture batch in
  let positions = Sprite_batch.positions batch in
  Float.Array.set positions 2048 nan;
  invalid draw;
  Float.Array.set positions 2048 6.;
  pixel renderer 2 3 black;
  Sprite_batch.add batch ~src:(rect 12 0 2 1) ~x:0. ~y:0. ~w:1. ~h:1.;
  invalid draw;
  pixel renderer 2 3 black;
  Sprite_batch.clear batch;
  fill ();
  (* This position is outside the live prefix. *)
  Float.Array.set positions 2050 infinity;
  draw ();
  pixel renderer 2 3 red;
  pixel renderer 5 3 green;
  pixel ~tolerance:1 renderer 6 3 (Color.rgb 127 0 128);
  pixel renderer 10 3 black;
  clear renderer;
  Sprite_batch.set_tint batch ~index:512 yellow;
  Sprite_batch.set_opacity batch ~index:1024 255;
  draw ();
  pixel renderer 2 3 red;
  pixel renderer 5 3 yellow;
  pixel renderer 6 3 blue

let reuse renderer texture =
  clear renderer;
  let batch = Sprite_batch.create ~capacity:1 in
  let positions = Sprite_batch.positions batch in
  let draw () = Sprite_batch.draw renderer texture batch in
  let add () =
    Sprite_batch.add
      ~tint:(Color.rgba 64 128 255 128)
      ~opacity:128 batch ~src:solid ~x:(-2.) ~y:4. ~w:4. ~h:3.
  in
  check
    (Sprite_batch.capacity batch = 1 && Sprite_batch.length batch = 0)
    "Empty batch";
  draw ();
  add ();
  invalid add;
  check (Sprite_batch.length batch = 1) "A full batch keeps its length";
  Texture.set_alpha_mod texture 0;
  draw ();
  Texture.draw ~src:(frect 10. 1. 2. 2.) ~dst:(frect 6. 4. 4. 3.) renderer
    texture;
  pixel ~tolerance:1 renderer 0 5 (Color.rgb 16 32 64);
  pixel renderer 2 5 black;
  pixel renderer 6 5 black;
  Texture.set_alpha_mod texture 255;
  Texture.draw ~src:(frect 10. 1. 2. 2.) ~dst:(frect 6. 4. 4. 3.) renderer
    texture;
  pixel renderer 6 5 white;
  clear renderer;
  Gc.compact ();
  Float.Array.set positions 0 6.;
  Float.Array.set positions 1 8.;
  draw ();
  pixel renderer 0 5 black;
  pixel ~tolerance:1 renderer 6 9 (Color.rgb 16 32 64);
  Sprite_batch.clear batch;
  clear renderer;
  draw ();
  pixel renderer 6 9 black;
  check
    (Sprite_batch.positions batch == positions && Sprite_batch.length batch = 0)
    "Reused storage";
  Sprite_batch.add batch ~src:tile ~x:0. ~y:0. ~w:8. ~h:6.;
  draw ();
  pixel renderer 1 1 red;
  pixel renderer 6 4 yellow;
  Sprite_batch.clear batch;
  clear renderer;
  Sprite_batch.add ~opacity:128 batch ~src:translucent ~x:0. ~y:0. ~w:2. ~h:2.;
  draw ();
  pixel ~tolerance:1 renderer 1 1 (Color.rgb 64 64 64)

let color_updates renderer texture =
  let batch = Sprite_batch.create ~capacity:3 in
  let draw () =
    clear renderer;
    Sprite_batch.draw renderer texture batch
  in
  let faded x r g b = pixel ~tolerance:1 renderer x 3 (Color.rgb r g b) in
  Sprite_batch.add ~tint:(Color.rgba 255 0 0 128) ~opacity:128 batch ~src:solid
    ~x:2. ~y:2. ~w:4. ~h:4.;
  Sprite_batch.add ~tint:blue batch ~src:solid ~x:4. ~y:2. ~w:4. ~h:4.;
  draw ();
  Sprite_batch.set_opacity batch ~index:0 255;
  Sprite_batch.set_tint batch ~index:1 yellow;
  (* Changes do not affect the draw that is already queued. *)
  faded 2 64 0 0;
  pixel renderer 5 3 blue;
  draw ();
  faded 2 128 0 0;
  pixel renderer 5 3 yellow;

  Sprite_batch.set_opacity batch ~index:0 128;
  Sprite_batch.set_tint batch ~index:0 (Color.rgba 0 255 0 128);
  draw ();
  faded 2 0 64 0;
  pixel renderer 5 3 yellow;
  Sprite_batch.set_opacity batch ~index:0 0;
  Sprite_batch.set_tint batch ~index:0 (Color.rgba 0 255 0 96);
  draw ();
  pixel renderer 2 3 black;
  Sprite_batch.set_opacity batch ~index:0 255;

  List.iter
    (fun index ->
      invalid (fun () -> Sprite_batch.set_tint batch ~index red);
      invalid (fun () -> Sprite_batch.set_opacity batch ~index 0))
    [ -1; 2; max_int ];
  List.iter
    (fun opacity ->
      invalid (fun () -> Sprite_batch.set_opacity batch ~index:0 opacity))
    [ -1; 256; max_int ];
  check (Sprite_batch.length batch = 2) "Color updates keep the batch length";
  Sprite_batch.set_opacity batch ~index:1 128;
  draw ();
  faded 2 0 96 0;
  faded 5 128 176 0;
  faded 7 128 128 0;

  Sprite_batch.clear batch;
  invalid (fun () -> Sprite_batch.set_tint batch ~index:0 red);
  invalid (fun () -> Sprite_batch.set_opacity batch ~index:0 0);
  Sprite_batch.add batch ~src:solid ~x:2. ~y:2. ~w:4. ~h:4.;
  draw ();
  pixel renderer 2 3 white;
  pixel renderer 7 3 black

let logical_coordinates context =
  (* SDL 3.2.0 applies logical presentation only to the default target. *)
  using Surface.destroy (Surface.create context ~w:80 ~h:64) (fun surface ->
      using Renderer.destroy (Renderer.create_software surface) (fun renderer ->
          using Texture.destroy (atlas context renderer) (fun texture ->
              Texture.set_scale_mode texture Nearest;
              Texture.set_blend_mode texture Blend;
              let batch = Sprite_batch.create ~capacity:1 in
              Sprite_batch.add ~angle:90. batch ~src:tile ~x:4. ~y:5. ~w:8.
                ~h:6.;
              Renderer.set_logical_presentation renderer
                (Some (40, 32, Stretch));
              clear renderer;
              Sprite_batch.draw renderer texture batch;
              pixel renderer 20 14 red;
              pixel renderer 12 14 blue;
              pixel renderer 20 22 green;
              pixel renderer 12 22 yellow)))

let misuse driver context renderer target texture =
  List.iter
    (fun capacity -> invalid (fun () -> ignore (Sprite_batch.create ~capacity)))
    [ -1; max_int ];
  let empty = Sprite_batch.create ~capacity:0 in
  Sprite_batch.draw renderer texture empty;
  invalid (fun () -> Sprite_batch.add empty ~src:solid ~x:0. ~y:0. ~w:1. ~h:1.);
  let batch = Sprite_batch.create ~capacity:1 in
  let add ?opacity ?angle ?pivot_x ?(src = solid) ?(w = 2.) ?(h = 2.) () =
    Sprite_batch.add ?opacity ?angle ?pivot_x batch ~src ~x:0. ~y:0. ~w ~h
  in
  invalid (add ~src:(rect (-1) 0 1 1));
  invalid (add ~src:(rect 0 0 1 0));
  invalid (add ~w:0.);
  invalid (add ~h:(-1.));
  invalid (add ~w:max_float);
  invalid (add ~angle:nan);
  invalid (add ~pivot_x:infinity);
  invalid (add ~opacity:(-1));
  invalid (add ~opacity:256);
  check
    (Sprite_batch.length batch = 0)
    "Rejected sprites did not enter the batch";
  Sprite_batch.add batch ~src:solid ~x:3e38 ~y:0. ~w:3e38 ~h:1.;
  invalid (fun () -> Sprite_batch.draw renderer texture batch);
  Sprite_batch.clear batch;
  if driver = "software" then (
    clear renderer;
    Sprite_batch.add ~flip:Horizontal batch ~src:solid ~x:0. ~y:0. ~w:0.5 ~h:2.;
    Sprite_batch.draw renderer texture batch;
    pixel renderer 0 0 black;
    Sprite_batch.clear batch;
    add ~angle:33. ~pivot_x:50000. ();
    invalid (fun () -> Sprite_batch.draw renderer texture batch);
    Sprite_batch.clear batch;
    Sprite_batch.add batch ~src:solid ~x:1e10 ~y:0. ~w:4. ~h:4.;
    invalid (fun () -> Sprite_batch.draw renderer texture batch);
    Renderer.set_scale renderer ~x:8. ~y:1.;
    Float.Array.set (Sprite_batch.positions batch) 0 1e8;
    invalid (fun () -> Sprite_batch.draw renderer texture batch);
    Renderer.set_scale renderer ~x:1. ~y:1.;
    Sprite_batch.clear batch);
  Sprite_batch.add batch ~src:(rect 0 0 1 1) ~x:0. ~y:0. ~w:1. ~h:1.;
  invalid (fun () -> Sprite_batch.draw renderer target batch);
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Sprite_batch.draw renderer texture batch)));
  using Surface.destroy (Surface.create context ~w:2 ~h:2) (fun surface ->
      using Renderer.destroy (Renderer.create_software surface) (fun other ->
          invalid (fun () -> Sprite_batch.draw other texture batch)));
  using Texture.destroy (Texture.create_streaming renderer ~w:2 ~h:2)
    (fun stream ->
      Texture.with_lock stream (fun _ ->
          invalid (fun () -> Sprite_batch.draw renderer stream batch));
      Texture.destroy stream;
      invalid (fun () -> Sprite_batch.draw renderer stream batch))

let () =
  let driver =
    Option.value (Sys.getenv_opt "SDL_RENDER_DRIVER") ~default:"software"
  in
  with_init [ Video ] (fun context ->
      logical_coordinates context;
      using Window.destroy
        (Window.create context ~title:"Sprite batch test" ~w:80 ~h:64)
        (fun window ->
          using Renderer.destroy (Renderer.create ~driver window)
            (fun renderer ->
              using Texture.destroy (Texture.create_target renderer ~w:80 ~h:64)
                (fun target ->
                  using Texture.destroy (atlas context renderer) (fun texture ->
                      Texture.set_scale_mode texture Nearest;
                      Texture.set_blend_mode texture Blend;
                      Renderer.set_target renderer (Some target);
                      Fun.protect
                        ~finally:(fun () -> Renderer.set_target renderer None)
                        (fun () ->
                          transforms renderer texture;
                          draw_with_view renderer texture;
                          ordered renderer texture;
                          reuse renderer texture;
                          color_updates renderer texture;
                          misuse driver context renderer target texture))))))
