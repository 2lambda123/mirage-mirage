open F0
open Functoria

let main = Functoria.main ~pos:__POS__ "App" job
let () = register ~src:`None "noop" [ main ]
