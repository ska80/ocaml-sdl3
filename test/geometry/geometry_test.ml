open Sdl3
open Bigarray

external read_pixel : Renderer.t -> int -> int -> Color.t
  = "test_geometry_read_pixel"

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let invalid name f =
  match f () with
  | exception Invalid_argument _ -> ()
  | () -> failwith ("Expected Invalid_argument: " ^ name)

let pixel ?(tolerance = 0) renderer x y (r, g, b) =
  let got = read_pixel renderer x y in
  let close a b = abs (a - b) <= tolerance in
  if not (close r got.r && close g got.g && close b got.b) then
    failwith
      (Printf.sprintf "Pixel %d,%d: expected (%d,%d,%d), got (%d,%d,%d)" x y r g
         b got.r got.g got.b)

let floats data = Array1.of_array float32 c_layout data
let ints data = Array1.of_array int32 c_layout data

let rgba n r g b a =
  Array1.init float32 c_layout (4 * n) (fun i ->
      match i mod 4 with
      | 0 -> r
      | 1 -> g
      | 2 -> b
      | _ -> a)

let rect x y w h = Rect.make ~x ~y ~w ~h
let frect x y w h = Frect.make ~x ~y ~w ~h

let clear renderer r g b =
  Renderer.set_draw_color renderer (Color.rgb r g b);
  Renderer.clear renderer

let triangle () = floats [| 2.; 2.; 22.; 2.; 2.; 22. |]
let quad () = floats [| 2.; 2.; 22.; 2.; 22.; 22.; 2.; 22. |]
let draw = Renderer.draw_geometry

let gradient renderer =
  clear renderer 0 0 0;
  Renderer.set_draw_blend_mode renderer None;
  let positions =
    Array1.sub (floats [| nan; 2.; 2.; 22.; 2.; 2.; 22.; nan |]) 1 7
  in
  let colors =
    Array1.sub
      (floats [| nan; 1.; 0.; 0.; 1.; 0.; 1.; 0.; 1.; 0.; 0.; 1.; 1.; nan |])
      1 13
  in
  draw renderer ~positions ~colors ~vertex_count:3;
  for v = 0 to 2 do
    positions.{2 * v} <- positions.{2 * v} +. 26.;
    colors.{4 * v} <- 0.;
    colors.{(4 * v) + 1} <- 1.;
    colors.{(4 * v) + 2} <- 0.
  done;
  Gc.compact ();
  draw renderer ~positions ~colors ~vertex_count:3;
  pixel ~tolerance:3 renderer 6 6 (140, 57, 57);
  pixel renderer 32 6 (0, 255, 0);
  pixel renderer 20 20 (0, 0, 0)

let draw_with_view renderer =
  clear renderer 0 0 0;
  Renderer.set_draw_blend_mode renderer None;
  Renderer.set_scale renderer ~x:2. ~y:0.5;
  Renderer.set_viewport renderer (Some (rect 6 8 20 40));
  Renderer.set_clip_rect renderer (Some (rect 4 4 5 8));
  draw renderer
    ~positions:(floats [| 0.; 0.; 16.; 0.; 0.; 28. |])
    ~colors:(rgba 3 1. 0. 0. 1.) ~vertex_count:3;
  Renderer.set_clip_rect renderer None;
  Renderer.set_viewport renderer None;
  Renderer.set_scale renderer ~x:1. ~y:1.;
  pixel renderer 21 7 (255, 0, 0);
  List.iter
    (fun (x, y) -> pixel renderer x y (0, 0, 0))
    [ (19, 7); (30, 7); (22, 5); (22, 10) ]

let make_texture context renderer =
  using Surface.destroy (Surface.create context ~w:16 ~h:16) (fun surface ->
      Surface.fill surface (Color.rgb 255 0 0);
      Surface.fill ~rect:(rect 8 0 8 8) surface (Color.rgb 0 255 0);
      Surface.fill ~rect:(rect 0 8 8 8) surface (Color.rgb 0 0 255);
      Surface.fill ~rect:(rect 8 8 8 8) surface (Color.rgb 255 255 0);
      Texture.of_surface renderer surface)

let textured driver renderer texture =
  clear renderer 0 0 0;
  Texture.set_scale_mode texture Nearest;
  Texture.set_blend_mode texture Blend;
  Texture.set_alpha_mod texture 128;
  let uv =
    Array1.sub (floats [| nan; 0.; 1.; 0.; 0.; 1.; 0.; 1.; 1.; nan |]) 1 9
  in
  let indices = Array1.sub (ints [| -1l; 0l; 1l; 2l; 0l; 2l; 3l; -1l |]) 1 7 in
  draw ~texture:(texture, uv) ~indices:(indices, 6) renderer
    ~positions:(quad ()) ~colors:(rgba 4 1. 1. 1. 1.) ~vertex_count:4;
  Array1.fill uv nan;
  Array1.fill indices (-1l);
  (* Geometry must leave the texture's alpha setting unchanged. *)
  Texture.draw ~src:(frect 8. 0. 8. 8.) ~dst:(frect 30. 2. 8. 8.) renderer
    texture;
  pixel renderer 7 6 (0, 0, 255);
  pixel renderer 17 6 (255, 0, 0);
  pixel renderer 17 16 (0, 255, 0);
  pixel renderer 6 17 (255, 255, 0);
  pixel ~tolerance:1 renderer 33 4 (0, 128, 0);
  (* Sample the last texel. Test the exact edge on software. SDL 3.2.0's
     GPU renderer wraps at the edge, so sample the center on that path. *)
  clear renderer 0 0 255;
  Texture.set_blend_mode texture Add;
  let edge = if driver = "gpu" then 15.5 /. 16. else 1. in
  draw
    ~texture:(texture, floats [| edge; edge; edge; edge; edge; edge |])
    renderer
    ~positions:(floats [| -4.; 2.; 14.; 2.; -4.; 18. |])
    ~colors:(rgba 3 0.5 1. 1. 0.5) ~vertex_count:3;
  pixel ~tolerance:2 renderer 2 4 (64, 128, 255);
  pixel renderer 12 13 (0, 0, 255)

let ordered renderer =
  clear renderer 0 0 0;
  Renderer.set_draw_blend_mode renderer None;
  let indices = ints [| 0l; 1l; 2l; 0l; 2l; 3l |] in
  draw ~indices:(indices, 6) renderer ~positions:(quad ())
    ~colors:(rgba 4 1. 0. 0. 0.5) ~vertex_count:4;
  (* Even two adjacent triangles use the selected blend mode. *)
  pixel renderer 7 6 (255, 0, 0);
  pixel renderer 7 16 (255, 0, 0);
  clear renderer 0 0 0;
  Renderer.set_draw_blend_mode renderer Blend;
  let positions =
    floats [| 2.; 2.; 22.; 2.; 2.; 22.; 2.; 2.; 22.; 2.; 2.; 22. |]
  in
  let colors = rgba 6 1. 0. 0. 1. in
  for i = 0 to 2 do
    colors.{4 * i} <- 0.;
    colors.{(4 * i) + 2} <- 1.;
    colors.{(4 * i) + 3} <- 0.5
  done;
  Array1.blit (ints [| 3l; 4l; 5l; 0l; 2l; 1l |]) indices;
  draw ~indices:(indices, 6) renderer ~positions ~colors ~vertex_count:6;
  pixel ~tolerance:2 renderer 6 6 (127, 0, 128)

let bad_buffers renderer texture =
  clear renderer 0 0 0;
  Renderer.set_draw_blend_mode renderer None;
  let positions = triangle () in
  let colors = rgba 3 1. 1. 1. 1. in
  let uv = floats [| 0.; 0.; 0.5; 0.; 0.; 0.5 |] in
  let indices = ints [| 0l; 1l; 2l; 0l; 2l; 1l |] in
  let call ?texture ?indices () =
    draw ?texture ?indices renderer ~positions ~colors ~vertex_count:3
  in
  let empty = floats [||] in
  draw renderer ~positions:empty ~colors:empty ~vertex_count:0;
  call ~texture:(texture, uv) ~indices:(ints [||], 0) ();
  List.iter
    (fun vertex_count ->
      invalid "vertex count" (fun () ->
          draw renderer ~positions ~colors ~vertex_count))
    [ -1; 2; 6; max_int ];
  invalid "short color buffer" (fun () ->
      draw renderer ~positions ~colors:(Array1.sub colors 0 11) ~vertex_count:3);
  invalid "short UV buffer" (fun () ->
      call ~texture:(texture, Array1.sub uv 0 5) ());
  List.iter
    (fun count ->
      invalid "index count" (fun () -> call ~indices:(indices, count) ()))
    [ -1; 2; 9; max_int ];
  List.iter
    (fun index ->
      indices.{5} <- index;
      invalid "last index" (fun () -> call ~indices:(indices, 6) ()))
    [ -1l; 3l; Int32.max_int ];
  List.iter
    (fun x ->
      positions.{5} <- x;
      invalid "nonfinite position" (fun () -> call ()))
    [ nan; infinity; neg_infinity; max_float ];
  positions.{5} <- 22.;
  List.iter
    (fun x ->
      colors.{11} <- x;
      invalid "color component" (fun () -> call ());
      colors.{11} <- 1.;
      uv.{5} <- x;
      invalid "texture coordinate" (fun () -> call ~texture:(texture, uv) ()))
    [ -0.25; 1.25; nan; infinity ];
  pixel renderer 6 6 (0, 0, 0)

let bad_handles context renderer target texture =
  let positions = triangle () and colors = rgba 3 1. 1. 1. 1. in
  let tex t = (t, floats [| 0.; 0.; 1.; 0.; 0.; 1. |]) in
  let call ?texture r () = draw ?texture r ~positions ~colors ~vertex_count:3 in
  invalid "current target" (call ~texture:(tex target) renderer);
  Domain.join (Domain.spawn (fun () -> invalid "other domain" (call renderer)));
  using Surface.destroy (Surface.create context ~w:16 ~h:16) (fun surface ->
      using Renderer.destroy (Renderer.create_software surface) (fun other ->
          invalid "wrong renderer" (call ~texture:(tex texture) other);
          Renderer.destroy other;
          invalid "closed renderer" (call other)));
  using Texture.destroy (Texture.create_streaming renderer ~w:16 ~h:16)
    (fun stream ->
      Texture.with_lock stream (fun _ ->
          invalid "locked texture" (call ~texture:(tex stream) renderer));
      Texture.destroy stream;
      invalid "closed texture" (call ~texture:(tex stream) renderer))

let software_bounds context =
  using Surface.destroy (Surface.create context ~w:80 ~h:64) (fun surface ->
      using Renderer.destroy (Renderer.create_software surface) (fun renderer ->
          clear renderer 0 0 0;
          Renderer.set_logical_presentation renderer (Some (32, 32, Letterbox));
          let positions = floats [| 2.; 2.; 10.; 2.; 2.; 10. |] in
          let colors = rgba 3 0. 1. 0. 1. in
          let call () = draw renderer ~positions ~colors ~vertex_count:3 in
          call ();
          pixel renderer 15 7 (0, 255, 0);
          pixel renderer 10 2 (0, 0, 0);
          positions.{5} <- 1e10;
          invalid "software position range" call;
          Renderer.set_logical_presentation renderer None;
          Renderer.set_scale renderer ~x:1. ~y:8.;
          positions.{5} <- 1e8;
          invalid "scaled software position range" call;
          Renderer.set_scale renderer ~x:1. ~y:1.;
          clear renderer 0 0 0;
          using Texture.destroy (make_texture context renderer) (fun texture ->
              let positions =
                floats
                  [| 2.; 2.; 22.; 2.; 2.; 22.; 0.; 0.; 8192.; 0.; 0.; 8192. |]
              in
              let uv =
                floats [| 0.; 0.; 1.; 0.; 0.; 1.; 1.; 1.; 1.; 1.; 1.; 1. |]
              in
              invalid "software textured triangle area" (fun () ->
                  draw ~texture:(texture, uv) renderer ~positions
                    ~colors:(rgba 6 1. 1. 1. 1.) ~vertex_count:6);
              pixel renderer 6 6 (0, 0, 0))))

let () =
  let driver =
    Option.value (Sys.getenv_opt "SDL_RENDER_DRIVER") ~default:"software"
  in
  with_init [ Video ] (fun context ->
      software_bounds context;
      using Window.destroy
        (Window.create context ~title:"Geometry test" ~w:80 ~h:64)
        (fun window ->
          using Renderer.destroy (Renderer.create ~driver window)
            (fun renderer ->
              using Texture.destroy (Texture.create_target renderer ~w:80 ~h:64)
                (fun target ->
                  using Texture.destroy (make_texture context renderer)
                    (fun texture ->
                      Renderer.set_target renderer (Some target);
                      Fun.protect
                        ~finally:(fun () -> Renderer.set_target renderer None)
                        (fun () ->
                          gradient renderer;
                          draw_with_view renderer;
                          textured driver renderer texture;
                          ordered renderer;
                          bad_buffers renderer texture;
                          bad_handles context renderer target texture))))))
