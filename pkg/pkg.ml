#!/usr/bin/env ocaml
#use "topfind"
#require "topkg"
open Topkg

let metas = [
  Pkg.meta_file ~install:false "pkg/META.mirage";
  Pkg.meta_file ~install:false "pkg/META.mirage-types";
]

let opams =
  let lint_deps_excluding = None in
  let install = false in
  [
    Pkg.opam_file ~install ~lint_deps_excluding "mirage.opam";
    Pkg.opam_file ~install ~lint_deps_excluding "mirage-types.opam";
    Pkg.opam_file ~install ~lint_deps_excluding "mirage-types-lwt.opam";
  ]

let lwt = Conf.key ~doc:"Build Mirage Lwt types" "with-lwt-types" ~absent:false Conf.bool
let delegate = Cmd.(v "toy-github-topkg-delegate")

let () =
  Pkg.describe ~delegate ~metas ~opams "mirage" @@ fun c ->
  let lwt = Conf.value c lwt in
  match Conf.pkg_name c with
  | "mirage" ->
    Ok [ Pkg.lib "pkg/META.mirage" ~dst:"META";
         Pkg.mllib "lib/mirage.mllib";
         Pkg.mllib "lib_runtime/mirage-runtime.mllib";
         Pkg.bin "lib/mirage_cli" ~dst:"mirage"; ]
  | "mirage-types" ->
    Ok [ Pkg.lib "pkg/META.mirage-types" ~dst:"META";
         Pkg.lib ~exts:Exts.interface "types/V1";
         Pkg.mllib "types/mirage-types.mllib";
         Pkg.lib ~cond:lwt ~exts:Exts.interface "types/V1_LWT"; ]
  | other ->
    R.error_msgf "unknown package name: %s" other
