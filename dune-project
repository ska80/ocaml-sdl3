(lang dune 3.25)
(name ocaml-sdl3)
(version 0.1.0)
(authors "Kamil Shakirov")
(maintainers "Kamil Shakirov <kamils80@gmail.com>")
(license MIT)
(source
 (github ska80/ocaml-sdl3))
(documentation https://github.com/ska80/ocaml-sdl3/tree/master/docs)
(generate_opam_files true)

(package
 (name sdl3)
 (synopsis "OCaml bindings for SDL3")
 (description
  "Open windows, draw in 2D or with the GPU, read input, and play or record audio with SDL3.")
 (tags (sdl3 graphics multimedia))
 (depends (ocaml (>= 5.4)) dune-configurator conf-pkg-config))

(package
 (name sdl3-image)
 (synopsis "OCaml bindings for SDL3_image")
 (description
  "Load images and animations, create SDL3 textures from images, and save PNG and JPEG files.")
 (tags (sdl3 graphics image))
 (depends (sdl3 (= :version)) dune-configurator conf-pkg-config))

(package
 (name sdl3-mixer)
 (synopsis "OCaml bindings for SDL3_mixer")
 (description
  "Load audio files, control playback tracks, and mix audio to a device or a buffer in memory.")
 (tags (sdl3 audio multimedia))
 (depends (sdl3 (= :version)) dune-configurator conf-pkg-config))

(package
 (name sdl3-ttf)
 (synopsis "OCaml bindings for SDL3_ttf")
 (description
  "Load fonts, measure UTF-8 text, and draw text to SDL3 surfaces or renderers.")
 (tags (sdl3 fonts text))
 (depends (sdl3 (= :version)) dune-configurator conf-pkg-config))
