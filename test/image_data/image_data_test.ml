open Sdl3

let check condition message = if not condition then failwith message

let invalid ?message f =
  match f () with
  | exception Invalid_argument text ->
      Option.iter (fun expected -> check (text = expected) text) message
  | _ -> failwith "Expected Invalid_argument"

let sdl_error fn f =
  match f () with
  | exception Error message ->
      check (String.starts_with ~prefix:(fn ^ ": ") message) message
  | _ -> failwith ("Expected a failure from " ^ fn)

let using destroy handle f =
  Fun.protect ~finally:(fun () -> destroy handle) (fun () -> f handle)

let ( let@ ) use f = use f

let buffer size =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size

let set_u32 bytes offset n = Bytes.set_int32_le bytes offset (Int32.of_int n)

let bmp_header ~w ~h ~bpp ~offset ~pitch =
  let size = offset + (pitch * h) in
  let bmp = Bytes.make size '\000' in
  Bytes.blit_string "BM" 0 bmp 0 2;
  set_u32 bmp 2 size;
  set_u32 bmp 10 offset;
  set_u32 bmp 14 40;
  set_u32 bmp 18 w;
  set_u32 bmp 22 h;
  Bytes.set_int16_le bmp 26 1;
  Bytes.set_int16_le bmp 28 bpp;
  set_u32 bmp 34 (pitch * h);
  bmp

let colors =
  [|
    Color.rgb 255 0 0;
    Color.rgb 0 255 0;
    Color.rgb 0 0 255;
    Color.rgb 71 32 19;
    Color.rgb 0 81 117;
    Color.rgb 250 178 0;
  |]

let color_at x y = colors.(((3 * y) + x) mod Array.length colors)

let bmp24 ~w ~h =
  let pitch = ((w * 3) + 3) land lnot 3 in
  let bmp = bmp_header ~w ~h ~bpp:24 ~pitch ~offset:54 in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let color = color_at x y in
      let pos = 54 + ((h - 1 - y) * pitch) + (x * 3) in
      Bytes.set_uint8 bmp pos color.b;
      Bytes.set_uint8 bmp (pos + 1) color.g;
      Bytes.set_uint8 bmp (pos + 2) color.r
    done
  done;
  bmp

let memory bytes =
  let size = Bytes.length bytes in
  let data = buffer (size + 7) in
  Bytes.iteri (fun i byte -> data.{i + 3} <- Char.code byte) bytes;
  Bigarray.Array1.sub data 3 size

let expect_size (image : Image_data.t) w h =
  check (image.w = w && image.h = h) "Decoded size";
  check (Bigarray.Array1.dim image.rgba = 4 * w * h) "Packed RGBA rows"

let expect_pixel (image : Image_data.t) x y (color : Color.t) =
  let i = 4 * ((y * image.w) + x) in
  let rgba = image.rgba in
  check
    (rgba.{i} = color.r
    && rgba.{i + 1} = color.g
    && rgba.{i + 2} = color.b
    && rgba.{i + 3} = color.a)
    "Decoded pixel"

let check_bmp24 image ~w ~h =
  expect_size image w h;
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      expect_pixel image x y (color_at x y)
    done
  done

let indexed_bmp context =
  let bmp = bmp_header ~w:3 ~h:1 ~bpp:8 ~pitch:4 ~offset:62 in
  set_u32 bmp 46 2;
  Bytes.set_uint8 bmp 58 255;
  Bytes.set_uint8 bmp 63 1;
  let image = Image_data.load_bmp_memory context (memory bmp) in
  expect_size image 3 1;
  expect_pixel image 0 0 (Color.rgb 0 0 0);
  expect_pixel image 1 0 (Color.rgb 0 0 255);
  expect_pixel image 2 0 (Color.rgb 0 0 0)

let alpha_bmp context =
  let bmp = bmp_header ~w:2 ~h:1 ~bpp:32 ~pitch:8 ~offset:54 in
  Bytes.set_uint8 bmp 54 137;
  Bytes.set_uint8 bmp 55 19;
  Bytes.set_uint8 bmp 56 221;
  Bytes.set_uint8 bmp 57 91;
  Bytes.set_uint8 bmp 59 255;
  let image = Image_data.load_bmp_memory context (memory bmp) in
  expect_size image 2 1;
  expect_pixel image 0 0 (Color.rgba 221 19 137 91);
  expect_pixel image 1 0 (Color.rgba 0 255 0 0);
  image

let concurrent_loads context path bytes =
  let start = Atomic.make false in
  let spawn load =
    Domain.spawn (fun () ->
        while not (Atomic.get start) do
          Domain.cpu_relax ()
        done;
        for _ = 1 to 20 do
          let image = load () in
          expect_size image 127 65;
          expect_pixel image 0 0 (color_at 0 0);
          expect_pixel image 126 64 (color_at 126 64)
        done;
        load ())
  in
  let file =
    spawn (fun () ->
        Image_data.load_bmp context (Bytes.to_string (Bytes.of_string path)))
  in
  let mem =
    match spawn (fun () -> Image_data.load_bmp_memory context bytes) with
    | worker -> worker
    | exception exn ->
        Atomic.set start true;
        ignore (Domain.join file);
        raise exn
  in
  let results = ref [] in
  let join worker =
    match Domain.join worker with
    | image -> Ok image
    | exception exn -> Result.Error exn
  in
  Fun.protect
    ~finally:(fun () ->
      let from_file = join file in
      results := [ from_file; join mem ])
    (fun () ->
      Atomic.set start true;
      Gc.compact ());
  Bigarray.Array1.fill bytes 0;
  List.iter
    (function
      | Ok image -> check_bmp24 image ~w:127 ~h:65
      | Result.Error exn -> raise exn)
    !results

(* Hold a private load between native decode and the copy. This makes the
   shutdown check independent of disk speed and domain scheduling. *)
module Pending = struct
  type t

  external prepare : unit -> t = "osdl_image_data_prepare"
  external release : t -> unit = "osdl_image_data_release"

  external decode : context -> t -> byte_buffer -> int * int
    = "osdl_image_data_load_bmp_memory"
end

let reject_quit_during_load context bytes =
  let ready = Atomic.make None in
  let finish = Atomic.make false in
  let worker =
    Domain.spawn (fun () ->
        try
          let@ job = using Pending.release (Pending.prepare ()) in
          let size = Pending.decode context job bytes in
          Atomic.set ready (Some (Ok size));
          while not (Atomic.get finish) do
            Domain.cpu_relax ()
          done;
          raise Exit
        with
        | Exit -> ()
        | exn -> Atomic.set ready (Some (Result.Error exn)))
  in
  Fun.protect
    ~finally:(fun () ->
      Atomic.set finish true;
      Domain.join worker)
    (fun () ->
      let rec wait () =
        match Atomic.get ready with
        | None ->
            Domain.cpu_relax ();
            wait ()
        | Some (Ok size) -> size
        | Some (Result.Error exn) -> raise exn
      in
      check (wait () = (3, 2)) "Worker has a live decode";
      check_bmp24 (Image_data.load_bmp_memory context bytes) ~w:3 ~h:2;
      invalid ~message:"Finish the SDL image loads before quitting" (fun () ->
          quit context);
      let@ surface = using Surface.destroy (Surface.create context ~w:1 ~h:1) in
      check (Surface.size surface = (1, 1)) "Rejected quit leaves SDL open")

let failures context path bytes =
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Surface.load_bmp context path);
         invalid (fun () -> Image_data.load_bmp context "embedded\000NUL");
         invalid (fun () -> Image_data.load_bmp_memory context (buffer 0));
         sdl_error "SDL_LoadBMP" (fun () ->
             Image_data.load_bmp context (path ^ ".missing"));
         let bad = buffer 4 in
         Bigarray.Array1.fill bad 0;
         for _ = 1 to 20 do
           sdl_error "SDL_LoadBMP_IO" (fun () ->
               Image_data.load_bmp_memory context bad)
         done;
         check_bmp24 (Image_data.load_bmp_memory context bytes) ~w:3 ~h:2))

let texture context (image : Image_data.t) =
  let@ target = using Surface.destroy (Surface.create context ~w:2 ~h:1) in
  let@ renderer = using Renderer.destroy (Renderer.create_software target) in
  Domain.join
    (Domain.spawn (fun () ->
         invalid (fun () -> Texture.of_image_data renderer image)));
  let@ texture = using Texture.destroy (Texture.of_image_data renderer image) in
  Bigarray.Array1.fill image.rgba 0;
  Texture.set_blend_mode texture Blend_mode.None;
  Texture.draw renderer texture;
  Renderer.present renderer;
  check
    (Surface.read_pixel target ~x:0 ~y:0 = Color.rgba 221 19 137 91)
    "Texture keeps its own copy of the decoded pixels";
  check
    (Surface.read_pixel target ~x:1 ~y:0 = Color.rgba 0 255 0 0)
    "Texture keeps the decoded alpha";
  Texture.destroy texture;
  Renderer.destroy renderer;
  invalid (fun () -> Texture.of_image_data renderer image)

let () =
  let path = Filename.temp_file "osdl-worker-" ".bmp" in
  let@ path = using Sys.remove path in
  let file = bmp24 ~w:127 ~h:65 in
  Out_channel.with_open_bin path (fun channel -> output_bytes channel file);
  let bytes = memory (bmp24 ~w:3 ~h:2) in
  let closed, image =
    with_init [] (fun context ->
        concurrent_loads context path (memory file);
        reject_quit_during_load context bytes;
        failures context path bytes;
        let@ child = using Surface.destroy (Surface.create context ~w:1 ~h:1) in
        invalid (fun () -> quit context);
        check
          (Surface.size child = (1, 1))
          "Child stays live after rejected quit";
        Domain.join (Domain.spawn (fun () -> indexed_bmp context));
        (context, Domain.join (Domain.spawn (fun () -> alpha_bmp context))))
  in
  invalid (fun () -> Image_data.load_bmp_memory closed bytes);
  with_init [] (fun context ->
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> Image_data.load_bmp_memory closed bytes)));
      quit closed;
      texture context image;
      check_bmp24 (Image_data.load_bmp_memory context bytes) ~w:3 ~h:2)
