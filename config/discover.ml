module C = Configurator.V1

let () =
  let package = ref "" in
  C.main ~name:"ocaml-sdl3"
    ~args:[ ("--package", Arg.Set_string package, "SDL pkg-config module") ]
    (fun c ->
      let pkg_config =
        match C.Pkg_config.get c with
        | Some pkg_config -> pkg_config
        | None -> C.die "pkg-config not found. Install it or set PKG_CONFIG."
      in
      let package = !package in
      (* Keep these in sync with the minimums in the C stubs. *)
      let minimum =
        match package with
        | "sdl3" -> "3.4.20"
        | "sdl3-image" -> "3.4.8"
        | "sdl3-mixer" -> "3.2.4"
        | "sdl3-ttf" -> "3.2.2"
        | _ -> C.die "Unknown SDL pkg-config module: %s" package
      in
      let expr = package ^ " >= " ^ minimum in
      match C.Pkg_config.query_expr_err pkg_config ~package ~expr with
      | Error msg ->
          C.die "Could not find %s. Set PKG_CONFIG_PATH if needed.\n%s" expr msg
      | Ok { cflags; libs } ->
          C.Flags.write_sexp "c_flags.sexp" cflags;
          (* ocamlmklib handles the rpath itself but does not accept the
             optional ELF flag that selects how to store the path. *)
          let libs = List.filter (( <> ) "-Wl,--enable-new-dtags") libs in
          C.Flags.write_sexp "c_library_flags.sexp" libs)
