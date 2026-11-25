let using release resource f =
  Fun.protect ~finally:(fun () -> release resource) (fun () -> f resource)

let ( let@ ) scope body = scope body

let byte_buffer size =
  Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout size
