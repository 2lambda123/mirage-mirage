open Mirage

let context_singleton key value =
  let info = Cmdliner.Term.info "" in
  let term = Key.context (Key.Set.singleton @@ Key.abstract key) in
  let argv = [| "mirage"; "--target"; value |] in
  match Cmdliner.Term.eval ~argv (term, info) with
  | `Ok x -> x
  | _ -> assert false

let print_banner s =
  print_endline s;
  print_endline @@ String.make (String.length s) '=';
  print_newline ()

let info context =
  Info.v ~packages:[] ~keys:[] ~context ~src:`None
    ~build_cmd:[ "mirage"; "build" ] ~build_dir:(Fpath.v "BUILD_DIR") "NAME"

let test target =
  print_banner target;
  let context = context_singleton Key.target target in
  let env = Action.env ~files:(`Files []) () in
  Action.dry_run_trace ~env @@ Configure.configure @@ info context;
  print_newline ()

let () = List.iter test [ "unix"; "xen"; "virtio" ]
