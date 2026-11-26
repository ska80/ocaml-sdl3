open Sdl3
module Palette = Surface.Palette
module Locked = Surface.Locked

let check condition message = if not condition then failwith message

let invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) use f = use f

let with_surface ?format context ~w ~h =
  using Surface.destroy (Surface.create ?format context ~w ~h)

let area x y w h = Rect.make ~x ~y ~w ~h
let black = Color.rgb 0 0 0
let white = Color.rgb 255 255 255
let red = Color.rgb 255 0 0
let green = Color.rgb 0 255 0
let blue = Color.rgb 0 0 255
let transparent = Color.rgba 0 0 0 0

let expect_pixel surface x y (expected : Color.t) =
  let actual = Surface.read_pixel surface ~x ~y in
  if actual <> expected then
    failwith
      (Printf.sprintf "Pixel %d,%d: expected (%d,%d,%d,%d), got (%d,%d,%d,%d)" x
         y expected.r expected.g expected.b expected.a actual.r actual.g
         actual.b actual.a)

let buffer length =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout length

let blits context =
  let@ source = with_surface context ~w:3 ~h:2 in
  let@ target = with_surface context ~w:6 ~h:4 in
  Surface.fill source red;
  Surface.fill ~rect:(area 1 0 1 1) source green;
  Surface.fill ~rect:(area 2 0 1 1) source blue;
  Surface.fill ~rect:(area 2 1 1 1) source green;
  Surface.fill target black;
  Surface.blit ~src:(area 1 0 2 2) ~dst:(area 3 1 (-1) 0) source target;
  expect_pixel target 3 1 green;
  expect_pixel target 4 1 blue;
  expect_pixel target 4 2 green;
  expect_pixel target 2 1 black;
  expect_pixel target 5 1 black;
  Surface.blit ~src:(area (-1) 0 3 1) ~dst:(area (-2) 0 0 0) source target;
  expect_pixel target 0 0 green;
  expect_pixel target 1 0 black;
  Surface.blit ~dst:(area 3 3 0 0) source target;
  expect_pixel target 3 3 red;
  expect_pixel target 5 3 blue;
  Surface.blit ~src:(area 0 0 0 2) source target;
  expect_pixel target 0 0 green;
  Surface.blit ~dst:(area 6 0 0 0) source target;
  expect_pixel target 5 0 black;
  invalid (fun () -> Surface.blit source source);
  invalid (fun () -> Surface.blit_scaled source source);
  invalid (fun () -> Surface.blit ~src:(area 0 0 (-1) 2) source target);
  invalid (fun () -> Surface.blit ~dst:(area max_int 0 0 0) source target)

let transforms context =
  let@ source = with_surface context ~w:3 ~h:2 in
  let@ target = with_surface context ~w:6 ~h:4 in
  Surface.set_blend_mode source None;
  Surface.fill source red;
  Surface.fill ~rect:(area 1 0 1 2) source green;
  Surface.fill ~rect:(area 2 0 1 1) source blue;
  Surface.fill target black;
  Surface.blit_scaled ~src:(area 1 0 2 2) ~dst:(area 1 0 4 4) source target;
  expect_pixel target 1 0 green;
  expect_pixel target 2 3 green;
  expect_pixel target 3 1 blue;
  expect_pixel target 4 2 red;
  expect_pixel target 5 0 black;
  Surface.fill target black;
  Surface.blit_scaled ~src:(area 1 0 2 2) ~dst:(area (-2) 0 4 4) source target;
  expect_pixel target 0 0 blue;
  expect_pixel target 1 3 red;
  expect_pixel target 2 0 black;
  Surface.blit_scaled ~dst:(area 0 0 0 4) source target;
  expect_pixel target 0 0 blue;
  Surface.blit_scaled ~dst:(area 6 0 3 4) source target;
  expect_pixel target 5 0 black;
  invalid (fun () -> Surface.blit_scaled ~src:(area 1 0 3 2) source target);
  invalid (fun () -> Surface.blit_scaled ~dst:(area 0 0 4 (-1)) source target);
  invalid (fun () -> Surface.blit_scaled ~dst:(area 0 0 4 32768) source target);
  Surface.flip source Horizontal;
  expect_pixel source 0 0 blue;
  expect_pixel source 2 0 red;
  Surface.flip source Vertical;
  expect_pixel source 0 0 red;
  expect_pixel source 0 1 blue;
  Surface.flip source Both;
  Surface.flip source No_flip;
  expect_pixel source 0 0 red;
  expect_pixel source 2 0 blue;
  let@ scaled = using Surface.destroy (Surface.scale source ~w:6 ~h:4) in
  check (Surface.size scaled = (6, 4)) "Scaled size";
  expect_pixel scaled 3 0 green;
  expect_pixel scaled 5 1 blue;
  expect_pixel scaled 5 3 red;
  Surface.fill ~rect:(area 1 0 1 2) source red;
  let@ linear =
    using Surface.destroy (Surface.scale ~scale_mode:Linear source ~w:6 ~h:2)
  in
  let check_linear surface =
    expect_pixel surface 0 0 red;
    expect_pixel surface 5 0 blue;
    let mixed = Surface.read_pixel surface ~x:3 ~y:0 in
    check (mixed.r > 0 && mixed.b > 0 && mixed.g = 0) "Linear filtering"
  in
  check_linear linear;
  Surface.blit_scaled ~scale_mode:Linear source target;
  check_linear target;
  invalid (fun () -> Surface.scale source ~w:0 ~h:2 |> Surface.destroy);
  invalid (fun () -> Surface.scale source ~w:32768 ~h:2 |> Surface.destroy);
  Surface.destroy source;
  expect_pixel scaled 3 0 green;
  invalid (fun () -> Surface.scale source ~w:2 ~h:2 |> Surface.destroy)

let filtered_regions context =
  let@ rgb = with_surface ~format:Rgb24 context ~w:4 ~h:2 in
  let@ target = with_surface context ~w:6 ~h:2 in
  Surface.fill rgb red;
  Surface.fill ~rect:(area 1 0 1 2) rgb green;
  Surface.fill ~rect:(area 2 0 1 2) rgb blue;
  Surface.fill ~rect:(area 3 0 1 2) rgb white;
  Surface.blit_scaled ~src:(area 1 0 2 2) ~scale_mode:Linear rgb target;
  expect_pixel target 0 0 green;
  expect_pixel target 5 1 blue;
  let mixed = Surface.read_pixel target ~x:2 ~y:1 in
  check (mixed.r = 0 && mixed.g > 0 && mixed.b > 0) "Filter the source crop";
  let@ single = with_surface context ~w:1 ~h:1 in
  Surface.fill single white;
  Surface.fill target black;
  Surface.blit_scaled ~dst:(area (-9) 0 10 1) single target;
  expect_pixel target 0 0 white;
  expect_pixel target 1 0 black

let conversions context =
  let@ source = with_surface context ~w:3 ~h:2 in
  let pixel = Color.rgba 17 123 235 199 in
  Surface.fill source pixel;
  let@ bgra = using Surface.destroy (Surface.convert source ~format:Bgra32) in
  let@ rgb = using Surface.destroy (Surface.convert bgra ~format:Rgb24) in
  Surface.destroy source;
  Surface.destroy bgra;
  check (Surface.format rgb = Some Rgb24) "Converted format";
  expect_pixel rgb 2 1 (Color.rgb 17 123 235);
  Surface.fill rgb red;
  let@ indexed = using Surface.destroy (Surface.convert rgb ~format:Index8) in
  check (Surface.format indexed = Some Index8) "Converted indexed format";
  expect_pixel indexed 1 1 red;
  let@ rgba = using Surface.destroy (Surface.convert indexed ~format:Rgba32) in
  expect_pixel rgba 1 1 red;
  invalid (fun () -> Surface.convert source ~format:Rgba32 |> Surface.destroy)

let keys_and_blending context =
  let@ source = with_surface context ~w:2 ~h:1 in
  let@ target = with_surface context ~w:4 ~h:2 in
  let key = Color.rgba 255 0 255 19 and ink = Color.rgba 255 0 0 128 in
  Surface.fill source key;
  Surface.fill ~rect:(area 1 0 1 1) source ink;
  Surface.fill target blue;
  Surface.set_blend_mode source None;
  Surface.set_color_key source (Some (Color (Color.rgb 255 0 255)));
  Surface.blit source target;
  expect_pixel target 0 0 blue;
  expect_pixel target 1 0 ink;
  Surface.blit_scaled source target;
  expect_pixel target 0 1 blue;
  expect_pixel target 3 1 ink;
  let@ scaled = using Surface.destroy (Surface.scale source ~w:4 ~h:2) in
  Surface.fill target blue;
  Surface.blit scaled target;
  expect_pixel target 0 1 blue;
  expect_pixel target 3 1 ink;
  invalid (fun () -> Surface.set_color_key source (Some (Index 0)));
  invalid (fun () -> Surface.blit_scaled ~scale_mode:Linear source target);
  invalid (fun () -> Surface.blit_scaled ~dst:(area (-2) 0 4 2) source target);
  let@ rgba = using Surface.destroy (Surface.convert source ~format:Rgba32) in
  check ((Surface.read_pixel rgba ~x:0 ~y:0).a = 0) "Convert the key to alpha";
  Surface.blit_scaled ~dst:(area (-2) 0 4 2) rgba target;
  Surface.set_color_key source None;
  Surface.blit source target;
  expect_pixel target 0 0 key;
  Surface.fill target blue;
  Surface.set_blend_mode source Blend;
  Surface.blit source target;
  let blended = Surface.read_pixel target ~x:1 ~y:0 in
  check
    (abs (blended.r - 128) <= 2
    && blended.g = 0
    && abs (blended.b - 127) <= 2
    && abs (blended.a - 255) <= 2)
    "Source alpha blends into the target";
  let mode =
    Blend_mode.compose
      ~color:Blend_mode.{ src = One; dst = One; op = Maximum }
      ~alpha:Blend_mode.{ src = One; dst = Zero; op = Sum }
  in
  sdl_error "SDL_SetSurfaceBlendMode" (fun () ->
      Surface.set_blend_mode source mode)

let locked_rows context =
  let run format bpp pixel_bytes expected =
    let@ surface = with_surface ~format context ~w:3 ~h:2 in
    let row = 3 * bpp and pitch = (3 * bpp) + 1 in
    let len = pitch + row in
    let input = buffer (len + 2) and output = buffer (len + 2) in
    Bigarray.Array1.fill input 87;
    Bigarray.Array1.fill output 93;
    for y = 0 to 1 do
      for x = 0 to 2 do
        Array.iteri
          (fun i byte -> input.{1 + (y * pitch) + (x * bpp) + i} <- byte)
          pixel_bytes
      done
    done;
    Surface.fill surface black;
    Surface.with_lock surface (fun view ->
        check (Locked.size view = (3, 2)) "Locked size";
        check (Surface.format surface = Some format) "Format during the lock";
        check (Locked.read_pixel view ~x:2 ~y:1 = black) "Keep old pixels";
        Locked.copy_from view (Bigarray.Array1.sub input 1 len) ~pitch;
        check (Locked.read_pixel view ~x:2 ~y:1 = expected) "Pixel byte order";
        invalid (fun () -> Locked.copy_from view input ~pitch:(row - 1));
        invalid (fun () ->
            Locked.copy_from view (Bigarray.Array1.sub input 1 (len - 1)) ~pitch);
        invalid (fun () ->
            Locked.copy_to view (Bigarray.Array1.sub output 1 (len - 1)) ~pitch);
        invalid (fun () -> Locked.read_index view ~x:0 ~y:0);
        invalid (fun () -> Locked.set_index view ~x:0 ~y:0 0);
        Locked.copy_to view (Bigarray.Array1.sub output 1 len) ~pitch;
        for y = 0 to 1 do
          for x = 0 to row - 1 do
            let i = 1 + (y * pitch) + x in
            check (output.{i} = input.{i}) "Pixel rows round trip"
          done
        done;
        check
          (output.{0} = 93 && output.{1 + row} = 93 && output.{len + 1} = 93)
          "Leave padding and unused bytes unchanged";
        Locked.set_pixel view ~x:2 ~y:1 white);
    expect_pixel surface 0 1 expected;
    expect_pixel surface 2 1 white
  in
  run Rgba32 4 [| 17; 109; 213; 71 |] (Color.rgba 17 109 213 71);
  run Bgra32 4 [| 213; 109; 17; 71 |] (Color.rgba 17 109 213 71);
  run Rgb24 3 [| 17; 109; 213 |] (Color.rgb 17 109 213)

exception Stop_edit

let locks context =
  let@ surface = with_surface context ~w:2 ~h:2 in
  let@ target = with_surface context ~w:2 ~h:2 in
  let@ indexed = with_surface ~format:Index8 context ~w:1 ~h:1 in
  let@ palette = using Palette.destroy (Palette.create context [||]) in
  let@ renderer = using Renderer.destroy (Renderer.create_software target) in
  let@ stream = using Io.close (Io.of_memory_rw context (buffer 512)) in
  invalid (fun () -> Surface.with_lock target (fun _ -> ()));
  let escaped =
    Surface.with_lock surface (fun view ->
        invalid (fun () -> Surface.with_lock surface (fun _ -> ()));
        invalid (fun () -> Surface.destroy surface);
        invalid (fun () -> Surface.fill surface red);
        invalid (fun () -> Surface.read_pixel surface ~x:0 ~y:0);
        invalid (fun () -> Surface.read_rgba surface (buffer 16));
        invalid (fun () -> Surface.blit surface target);
        invalid (fun () -> Surface.blit target surface);
        invalid (fun () -> Surface.blit_scaled surface target);
        invalid (fun () -> Surface.blit_scaled target surface);
        invalid (fun () -> Surface.flip surface Both);
        invalid (fun () -> Surface.set_color_key surface None);
        invalid (fun () -> Surface.set_blend_mode surface None);
        invalid (fun () -> Surface.scale surface ~w:1 ~h:1 |> Surface.destroy);
        invalid (fun () ->
            Surface.convert surface ~format:Rgb24 |> Surface.destroy);
        invalid (fun () -> Surface.save_bmp_io surface stream);
        check (Io.tell stream = 0L) "A locked surface cannot write a BMP";
        invalid (fun () -> Renderer.create_software surface |> Renderer.destroy);
        invalid (fun () ->
            Texture.of_surface renderer surface |> Texture.destroy);
        invalid (fun () -> Locked.set_pixel view ~x:(-1) ~y:0 white);
        invalid (fun () -> Locked.read_pixel view ~x:1 ~y:2);
        invalid (fun () -> Locked.read_pixel view ~x:max_int ~y:0);
        Domain.join
          (Domain.spawn (fun () ->
               invalid (fun () -> Locked.size view);
               invalid (fun () -> Locked.copy_to view (buffer 16) ~pitch:8);
               invalid (fun () -> Locked.set_pixel view ~x:0 ~y:0 red);
               invalid (fun () -> Surface.with_lock target (fun _ -> ()));
               invalid (fun () -> Surface.blit target indexed);
               invalid (fun () -> Palette.set_colors palette ~first:0 [| red |]);
               invalid (fun () -> Palette.destroy palette)));
        Gc.compact ();
        Locked.set_pixel view ~x:0 ~y:0 green;
        view)
  in
  expect_pixel surface 0 0 green;
  Surface.with_lock indexed (fun _ ->
      invalid (fun () -> Surface.set_palette indexed palette));
  invalid (fun () -> Locked.size escaped);
  invalid (fun () -> Locked.read_pixel escaped ~x:0 ~y:0);
  invalid (fun () -> Locked.copy_from escaped (buffer 16) ~pitch:8);
  (match
     Surface.with_lock surface (fun view ->
         invalid (fun () -> Locked.read_pixel escaped ~x:0 ~y:0);
         Locked.set_pixel view ~x:1 ~y:1 white;
         raise Stop_edit)
   with
  | exception Stop_edit -> ()
  | _ -> failwith "The lock must propagate the callback exception");
  expect_pixel surface 0 0 green;
  expect_pixel surface 1 1 white;
  Surface.destroy surface;
  invalid (fun () -> Surface.with_lock surface (fun _ -> ()));
  Renderer.destroy renderer;
  Surface.with_lock target (fun view ->
      check (Locked.size view = (2, 2)) "Relock")

let palettes_and_atlas context =
  let@ first = with_surface ~format:Index8 context ~w:3 ~h:2 in
  let@ second = with_surface ~format:Index8 context ~w:3 ~h:2 in
  let@ atlas = with_surface context ~w:10 ~h:4 in
  expect_pixel first 0 0 white;
  let@ palette =
    using Palette.destroy (Palette.create context [| black; red; green |])
  in
  let indices = buffer 7 in
  Array.iteri (fun i index -> indices.{i} <- index) [| 0; 1; 2; 255; 2; 1; 0 |];
  List.iter
    (fun sprite ->
      Surface.set_palette sprite palette;
      Surface.with_lock sprite (fun view ->
          Locked.copy_from view indices ~pitch:4;
          check (Locked.read_index view ~x:0 ~y:1 = 2) "Read an exact index";
          invalid (fun () -> Locked.set_index view ~x:0 ~y:0 256));
      Surface.set_color_key sprite (Some (Index 0)))
    [ first; second ];
  Surface.fill atlas transparent;
  Surface.blit first atlas;
  expect_pixel atlas 0 0 transparent;
  expect_pixel atlas 1 0 red;
  expect_pixel atlas 2 0 green;
  Palette.set_colors palette ~first:1 [| blue; white |];
  Palette.set_colors palette ~first:256 [||];
  invalid (fun () -> Palette.set_colors palette ~first:(-1) [| black |]);
  invalid (fun () -> Palette.set_colors palette ~first:255 [| black; black |]);
  invalid (fun () -> Surface.set_palette atlas palette);
  invalid (fun () -> Surface.set_color_key first (Some (Index 256)));
  expect_pixel first 1 0 blue;
  expect_pixel second 2 0 white;
  Surface.blit ~dst:(area 0 2 0 0) first atlas;
  expect_pixel atlas 1 0 red;
  expect_pixel atlas 1 2 blue;
  Palette.destroy palette;
  invalid (fun () -> Surface.set_palette first palette);
  invalid (fun () -> Palette.set_colors palette ~first:0 [||]);
  Surface.blit_scaled ~dst:(area 4 0 6 4) second atlas;
  expect_pixel atlas 4 0 transparent;
  expect_pixel atlas 6 0 blue;
  expect_pixel atlas 9 0 white;
  expect_pixel atlas 1 0 red;
  let@ replacement =
    using Palette.destroy (Palette.create context [| black; green; red |])
  in
  Surface.set_palette second replacement;
  Palette.destroy replacement;
  expect_pixel first 1 0 blue;
  expect_pixel second 1 0 green;
  let rgba = buffer (3 * 2 * 4) in
  Surface.read_rgba second rgba;
  check
    (rgba.{3} = 0 && rgba.{5} = 255 && rgba.{7} = 255)
    "Read keyed palette as RGBA";
  let@ output = with_surface context ~w:10 ~h:4 in
  let@ renderer = using Renderer.destroy (Renderer.create_software output) in
  let@ texture = using Texture.destroy (Texture.of_surface renderer atlas) in
  Surface.destroy atlas;
  Surface.fill output black;
  Texture.draw renderer texture;
  Renderer.present renderer;
  expect_pixel output 0 0 black;
  expect_pixel output 1 0 red;
  expect_pixel output 6 0 blue;
  expect_pixel output 9 0 white

let scale_indices context =
  let@ palette =
    using Palette.destroy (Palette.create context [| black; red; red; blue |])
  in
  let@ source = with_surface ~format:Index8 context ~w:3 ~h:1 in
  Surface.set_palette source palette;
  Surface.with_lock source (fun view ->
      for x = 0 to 2 do
        Locked.set_index view ~x ~y:0 (x + 1)
      done);
  Surface.set_color_key source (Some (Index 2));
  let@ scaled =
    using Surface.destroy (Surface.scale ~scale_mode:Linear source ~w:6 ~h:3)
  in
  Surface.destroy source;
  Surface.with_lock scaled (fun view ->
      for y = 0 to 2 do
        for x = 0 to 5 do
          check
            (Locked.read_index view ~x ~y = (x / 2) + 1)
            "Scaling keeps indices even for duplicate colors"
        done
      done);
  Palette.set_colors palette ~first:2 [| green |];
  Palette.destroy palette;
  expect_pixel scaled 2 1 green;
  let@ target = with_surface context ~w:6 ~h:3 in
  Surface.fill target white;
  Surface.blit scaled target;
  expect_pixel target 1 1 red;
  expect_pixel target 2 1 white;
  expect_pixel target 5 1 blue

let small_palette context =
  (* A 3-by-1 8-bit BMP with two palette entries. *)
  let bmp = Bytes.make 66 '\000' in
  Bytes.blit_string "BM" 0 bmp 0 2;
  Bytes.set_int32_le bmp 2 66l;
  Bytes.set_int32_le bmp 10 62l;
  Bytes.set_int32_le bmp 14 40l;
  Bytes.set_int32_le bmp 18 3l;
  Bytes.set_int32_le bmp 22 1l;
  Bytes.set_int16_le bmp 26 1;
  Bytes.set_int16_le bmp 28 8;
  Bytes.set_int32_le bmp 34 4l;
  Bytes.set_int32_le bmp 46 2l;
  Bytes.set_uint8 bmp 60 255;
  Bytes.set_uint8 bmp 63 1;
  let contents = buffer (Bytes.length bmp) in
  Bytes.iteri (fun i byte -> contents.{i} <- Char.code byte) bmp;
  let@ stream = using Io.close (Io.of_memory context contents) in
  let@ surface = using Surface.destroy (Surface.load_bmp_io stream) in
  check (Surface.format surface = Some Index8) "Loaded indexed BMP";
  expect_pixel surface 1 0 red;
  invalid (fun () -> Surface.set_color_key surface (Some (Index 2)));
  Surface.with_lock surface (fun view ->
      let data = buffer 3 in
      data.{0} <- 1;
      data.{1} <- 1;
      data.{2} <- 2;
      invalid (fun () -> Locked.set_index view ~x:1 ~y:0 2);
      invalid (fun () -> Locked.copy_from view data ~pitch:3);
      check (Locked.read_index view ~x:0 ~y:0 = 0) "Reject all of a bad copy";
      data.{2} <- 0;
      Locked.copy_from view data ~pitch:3);
  expect_pixel surface 0 0 red

let () =
  with_init [] (fun context ->
      invalid (fun () ->
          Surface.create context ~w:32768 ~h:32768 |> Surface.destroy);
      invalid (fun () ->
          Palette.create context (Array.make 257 red) |> Palette.destroy);
      blits context;
      transforms context;
      filtered_regions context;
      conversions context;
      keys_and_blending context;
      locked_rows context;
      locks context;
      palettes_and_atlas context;
      scale_indices context;
      small_palette context;
      let@ _ = using Palette.destroy (Palette.create context [||]) in
      invalid (fun () -> quit context))
