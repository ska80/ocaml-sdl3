open Sdl3

external open_failing_stream : context -> [ `Read ] Io.t
  = "test_io_open_failing_stream"

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

let using close handle f =
  Fun.protect ~finally:(fun () -> close handle) (fun () -> f handle)

let buffer n = Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout n

let of_string s =
  let b = buffer (String.length s) in
  String.iteri (fun i c -> b.{i} <- Char.code c) s;
  b

let contents b = String.init (Bigarray.Array1.dim b) (fun i -> Char.chr b.{i})

let files context =
  let seek io n = Io.seek io ~from:Start n in
  using Sys.remove (Filename.temp_file "sdl3-io" ".bin") (fun path ->
      let data = of_string "!ABC\000?" in
      let write io ~offset ~length = Io.write io data ~offset ~length in
      let out = of_string "......" in
      sdl_error "SDL_IOFromFile" (fun () ->
          Io.open_file context ~mode:Read (path ^ ".missing"));
      invalid (fun () -> Io.open_file context ~mode:Read (path ^ "\000"));
      Io.with_file context ~mode:Write path (fun io ->
          write io ~offset:1 ~length:3;
          Io.flush io;
          check (Io.size io = 3L && Io.tell io = 3L) "File size and position");
      Io.with_file context ~mode:Update path (fun io ->
          check (Io.size io = 3L) "Update does not empty the file";
          check (seek io 1L = 1L) "Seek to a file byte";
          write io ~offset:0 ~length:1;
          check (seek io 0L = 0L) "Switch from writing to reading";
          check (Io.read io out ~offset:1 ~length:5 = 3) "Short file read";
          check (contents out = ".A!C..") "Read only the requested byte range";
          check (Io.read io out ~offset:0 ~length:1 = 0) "File end of input");
      Io.with_file context ~mode:Append path (fun io ->
          ignore (seek io 0L);
          write io ~offset:4 ~length:1);
      Io.with_file context ~mode:Append_update path (fun io ->
          check (seek io 0L = 0L) "Seek on append-update file";
          write io ~offset:5 ~length:1;
          check (Io.seek io ~from:End (-2L) = 3L) "Seek from end of file";
          check (Io.read io out ~offset:0 ~length:2 = 2) "Read appended bytes";
          check (contents out = "\000?!C..") "Append does not overwrite data");
      let escaped = Io.with_file context ~mode:Read path Fun.id in
      invalid (fun () -> Io.size escaped);
      Io.close escaped;
      let exception Stop in
      let escaped = ref None in
      (match
         Io.with_file context ~mode:Create path (fun io ->
             escaped := Some io;
             check (Io.size io = 0L) "Create empties an existing file";
             raise Stop)
       with
      | exception Stop -> ()
      | _ -> failwith "Expected the callback exception");
      invalid (fun () -> Io.tell (Option.get !escaped)))

let weak_memory_stream context =
  let data = Bigarray.Array1.sub (of_string ".retained.") 1 8 in
  let weak = Weak.create 1 in
  Weak.set weak 0 (Some data);
  (weak, Io.of_memory context data)

let memory_lifetime context =
  invalid (fun () -> Io.of_memory context (buffer 0));
  invalid (fun () -> Io.of_memory_rw context (buffer 0));
  let weak, stream = weak_memory_stream context in
  using Io.close stream (fun io ->
      invalid (fun () -> quit context);
      Domain.join
        (Domain.spawn (fun () ->
             invalid (fun () -> Io.tell io);
             invalid (fun () -> Io.close io);
             invalid (fun () -> Io.of_memory context (buffer 1))));
      Gc.full_major ();
      check (Weak.check weak 0) "A live stream retains its buffer";
      let data = buffer 8 in
      check (Io.read io data ~offset:0 ~length:8 = 8) "Read retained storage";
      check (contents data = "retained") "Retained bytes");
  Gc.full_major ();
  check (not (Weak.check weak 0)) "A closed stream releases its buffer";
  Io.close stream

let memory_transfers context =
  let storage = of_string "abWXYZcd" in
  let backing = Bigarray.Array1.sub storage 2 4 in
  using Io.close (Io.of_memory_rw context backing) (fun io ->
      check (Io.size io = 4L) "Memory stream size";
      check (Io.seek io ~from:Current Int64.max_int = 4L) "Clamp large seek";
      check (Io.seek io ~from:End Int64.min_int = 0L) "Clamp negative seek";
      check (Io.seek io ~from:End (-2L) = 2L) "Seek from end of memory";
      check (Io.seek io ~from:Current (-2L) = 0L) "Seek from current position";
      invalid (fun () -> Io.read io storage ~offset:1 ~length:2);
      invalid (fun () -> Io.write io storage ~offset:5 ~length:2);
      invalid (fun () -> Io.read io backing ~offset:0 ~length:1);
      invalid (fun () -> Io.read io backing ~offset:(-1) ~length:0);
      invalid (fun () -> Io.write io backing ~offset:2 ~length:max_int);
      invalid (fun () -> Io.write io backing ~offset:0 ~length:(-1));
      invalid (fun () -> Io.read io backing ~offset:5 ~length:0);
      check (Io.read io (buffer 0) ~offset:0 ~length:0 = 0) "Empty read";
      Io.write io backing ~offset:4 ~length:0;
      check (Io.tell io = 0L) "Rejected and empty transfers do not move";
      Io.write io storage ~offset:0 ~length:2;
      check (contents storage = "ababYZcd") "Write into the original view";
      sdl_error "SDL_WriteIO" (fun () ->
          Io.write io (of_string "123") ~offset:0 ~length:3);
      check (contents storage = "abab12cd") "Short write stays in the view";
      check (Io.tell io = 4L) "Short write stops at the buffer end";
      let out = of_string "......" in
      check (Io.seek io ~from:Start 1L = 1L) "Seek for memory read";
      check (Io.read io out ~offset:2 ~length:4 = 3) "Short memory read";
      check (contents out = "..b12.") "Read only available bytes";
      check (Io.read io out ~offset:0 ~length:1 = 0) "Memory end of input")

let bmp context =
  let pixel = Color.rgba 11 22 33 199 in
  using Surface.destroy (Surface.create context ~w:2 ~h:3) (fun surface ->
      Surface.fill surface pixel;
      using Sys.remove (Filename.temp_file "sdl3-io" ".bmp") (fun path ->
          Io.with_file context ~mode:Append path (fun io ->
              invalid (fun () -> Surface.save_bmp_io surface io);
              check (Io.size io = 0L) "No BMP bytes written in append mode"));
      let data = buffer 512 in
      let image =
        using Io.close (Io.of_memory_rw context data) (fun io ->
            check (Io.seek io ~from:Start 4L = 4L) "Start BMP after a prefix";
            Surface.save_bmp_io surface io;
            check (Io.tell io > 4L) "BMP writer leaves stream open";
            ignore (Io.seek io ~from:Start 4L);
            Surface.load_bmp_io io)
      in
      using Surface.destroy image (fun image ->
          check (Surface.size image = (2, 3)) "BMP stream round trip size";
          check (Surface.read_pixel image ~x:1 ~y:2 = pixel) "BMP stream pixel");
      using Io.close
        (Io.of_memory_rw context (buffer 1))
        (fun io ->
          sdl_error "SDL_SaveBMP_IO" (fun () -> Surface.save_bmp_io surface io);
          check (Io.tell io = 1L) "Failed BMP write leaves stream open");
      using Io.close
        (Io.of_memory context (of_string "not a BMP"))
        (fun io ->
          sdl_error "SDL_LoadBMP_IO" (fun () -> Surface.load_bmp_io io);
          check
            (Io.seek io ~from:Start 0L = 0L)
            "Failed BMP load leaves stream open";
          Io.close io;
          invalid (fun () -> Surface.load_bmp_io io)))

let () =
  let context = init [] in
  using quit context (fun context ->
      files context;
      memory_lifetime context;
      memory_transfers context;
      bmp context;
      let io = open_failing_stream context in
      using Io.close io (fun io ->
          let target = of_string ".." in
          sdl_error "SDL_ReadIO" (fun () ->
              Io.read io target ~offset:0 ~length:2);
          check (contents target = "*.") "Read error after a partial transfer";
          sdl_error "SDL_CloseIO" (fun () -> Io.close io);
          invalid (fun () -> Io.tell io)));

  invalid (fun () -> Io.of_memory context (buffer 1))
