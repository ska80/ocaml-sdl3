# Implementation guide

- Read the installed SDL3 headers before you bind a function.
- Keep native handles abstract and release them explicitly on the main thread.
- Match SDL ownership rules. Release child handles before their parents.
- Use `Sdl3.Error` for SDL failures and `Invalid_argument` for binding misuse.
- Root OCaml values across C allocations. Do not call SDL from garbage collector finalizers.
- Keep C field and constructor order in sync with OCaml types.
- Keep each add-on independent. Do not make `sdl3` link to any add-on.
- Add tests for new APIs. Run `dune build @install` and `dune runtest`.
