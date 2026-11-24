(lang dune 3.25)
(name ocaml-sdl3)
(version 0.1.0)
(generate_opam_files true)

(package
 (name sdl3)
 (synopsis "OCaml bindings for SDL3")
 (depends (ocaml (>= 5.4)) dune-configurator conf-pkg-config))

(package
 (name sdl3-image)
 (synopsis "OCaml bindings for SDL3_image")
 (depends (sdl3 (= :version)) dune-configurator conf-pkg-config))

(package
 (name sdl3-mixer)
 (synopsis "OCaml bindings for SDL3_mixer")
 (depends (sdl3 (= :version)) dune-configurator conf-pkg-config))

(package
 (name sdl3-ttf)
 (synopsis "OCaml bindings for SDL3_ttf")
 (depends (sdl3 (= :version)) dune-configurator conf-pkg-config))
