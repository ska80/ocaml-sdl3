open Sdl3

type side = Left | Right
type resource = Context | Surface | Renderer | Texture of side | Stream

type command =
  | Create of resource
  | Destroy of resource
  | Use of resource
  | Load_bad_bmp
  | Lock of side * bool

let create_order =
  [ Context; Surface; Renderer; Texture Left; Texture Right; Stream ]

let destroy_order = List.rev create_order

let parent = function
  | Context -> None
  | Surface | Stream -> Some Context
  | Renderer -> Some Surface
  | Texture _ -> Some Renderer

let resource_name = function
  | Context -> "context"
  | Surface -> "surface"
  | Renderer -> "renderer"
  | Texture Left -> "left texture"
  | Texture Right -> "right texture"
  | Stream -> "stream"

let command_name = function
  | Create id -> "create " ^ resource_name id
  | Destroy id -> "destroy " ^ resource_name id
  | Use id -> "use " ^ resource_name id
  | Load_bad_bmp -> "load a bad BMP"
  | Lock (side, abort) ->
      let suffix = if abort then " and raise" else "" in
      "lock " ^ resource_name (Texture side) ^ suffix

type 'a handles = {
  mutable last : 'a option;
  create : unit -> 'a;
  destroy : 'a -> unit;
  use : 'a -> unit;
}

type slot = Slot : 'a handles -> slot

let handles create destroy use = { last = None; create; destroy; use }

let make_slots () =
  let child parent create () = create (Option.get parent.last) in
  let probe f handle = ignore (f handle) in
  let context = handles (fun () -> init [ Video ]) quit (probe Event.poll) in
  let surface =
    handles
      (child context (Surface.create ~w:8 ~h:8))
      Surface.destroy (probe Surface.size)
  in
  let renderer =
    handles
      (child surface Renderer.create_software)
      Renderer.destroy
      (probe Renderer.output_size)
  in
  let make_texture () =
    handles
      (child renderer (Texture.create_streaming ~w:4 ~h:4))
      Texture.destroy (probe Texture.size)
  in
  let left = make_texture () and right = make_texture () in
  let texture = function
    | Left -> left
    | Right -> right
  in
  let stream =
    handles
      (child context (fun context ->
           let buffer =
             Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout 32
           in
           Bigarray.Array1.fill buffer 0;
           Io.of_memory context buffer))
      Io.close (probe Io.size)
  in
  let slot = function
    | Context -> Slot context
    | Surface -> Slot surface
    | Renderer -> Slot renderer
    | Texture side -> Slot (texture side)
    | Stream -> Slot stream
  in
  (slot, texture, stream)

let expect_invalid f =
  match f () with
  | exception Invalid_argument _ -> ()
  | () -> failwith "Expected Invalid_argument"

let expect_sdl_error f =
  match f () with
  | exception Error _ -> ()
  | () -> failwith "Expected Sdl3.Error"

exception Abort_lock

let lock texture ~abort =
  let escaped = ref None in
  (match
     Texture.with_lock texture (fun view ->
         escaped := Some view;
         Texture.Locked.fill view (Color.rgb 32 64 128);
         expect_invalid (fun () -> Texture.destroy texture);
         if abort then raise Abort_lock)
   with
  | () when not abort -> ()
  | exception Abort_lock when abort -> ()
  | () -> failwith "Expected the texture lock callback exception");
  let view = Option.get !escaped in
  expect_invalid (fun () -> ignore (Texture.Locked.size view))

let exercise ready commands =
  (* If cleanup fails, keep the failing sequence. SDL can only have one
     context, so a new trial could fail just because the old one is still open. *)
  QCheck2.assume !ready;
  let slot, texture, stream = make_slots () in
  (* The model tracks live slots, not SDL pointers or child counts. Keep the
     last real handle in each slot even after it closes. *)
  let live = ref [] in
  let is_live id = List.mem id !live in
  let step = function
    | Create id ->
        (* Each slot holds at most one live handle. *)
        if not (is_live id) then
          let (Slot h) = slot id in
          let previous = h.last in
          let create () = h.last <- Some (h.create ()) in
          if Option.fold ~none:true ~some:is_live (parent id) then (
            create ();
            live := id :: !live;
            Option.iter
              (fun closed ->
                h.destroy closed;
                expect_invalid (fun () -> h.use closed))
              previous;
            h.use (Option.get h.last))
          else expect_invalid create
    | Destroy id ->
        let (Slot h) = slot id in
        let handle = Option.get h.last in
        if List.exists (fun child -> parent child = Some id) !live then (
          expect_invalid (fun () -> h.destroy handle);
          h.use handle)
        else (
          h.destroy handle;
          live := List.filter (( <> ) id) !live)
    | Use id ->
        let (Slot h) = slot id in
        let handle = Option.get h.last in
        if is_live id then h.use handle
        else expect_invalid (fun () -> h.use handle)
    | Load_bad_bmp ->
        let io = Option.get stream.last in
        let load () = Surface.destroy (Surface.load_bmp_io io) in
        if is_live Stream then expect_sdl_error load else expect_invalid load
    | Lock (side, abort) ->
        let handle = Option.get (texture side).last in
        if is_live (Texture side) then lock handle ~abort
        else
          expect_invalid (fun () ->
              Texture.with_lock handle (fun _ ->
                  failwith "The lock callback ran for a closed texture"))
  in
  let run phase =
    List.iteri (fun i command ->
        try step command
        with exn ->
          QCheck2.Test.fail_reportf "%s step %d (%s): %s" phase (i + 1)
            (command_name command) (Printexc.to_string exn))
  in
  let cleanup () =
    (* Try each handle in order after a failure, without hiding the failure. *)
    List.iter
      (fun id ->
        let (Slot h) = slot id in
        try Option.iter h.destroy h.last with _ -> ready := false)
      destroy_order
  in
  try
    (* Start with all slots filled so a short sequence can test every kind
       of handle. QCheck only generates and shrinks the middle of the test. *)
    run "Setup" (List.map (fun id -> Create id) create_order);
    run "Generated" commands;
    let destroy_all = List.map (fun id -> Destroy id) destroy_order in
    run "Teardown" destroy_all;
    run "After teardown" (List.map (fun id -> Use id) create_order @ destroy_all);
    run "Reopen" [ Create Context; Destroy Context ];
    true
  with exn ->
    cleanup ();
    raise exn

let lifecycle =
  let open QCheck2 in
  let commands =
    List.concat_map (fun id -> [ Create id; Destroy id; Use id ]) create_order
    @ [
        Load_bad_bmp;
        Lock (Left, false);
        Lock (Left, true);
        Lock (Right, false);
        Lock (Right, true);
      ]
  in
  (* Drop commands from anywhere in the sequence, not just its end. *)
  let shrink commands =
    List.to_seq commands
    |> Seq.mapi (fun index _ -> List.filteri (fun i _ -> i <> index) commands)
  in
  let gen =
    Gen.(
      list_size (int_range 0 80) (oneof (List.map return commands))
      |> set_shrink shrink)
  in
  Test.make ~name:"core resource lifecycle" ~count:300 ~long_factor:10
    ~print:(Print.list command_name) gen
    (exercise (ref true))

let () = QCheck_base_runner.run_tests_main [ lifecycle ]
