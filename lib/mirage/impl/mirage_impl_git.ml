open Functoria
open Mirage_impl_time
open Mirage_impl_mclock
open Mirage_impl_pclock
open Mirage_impl_tcp
open Mirage_impl_mimic

type git_client = Git_client

let git_client = Type.v Git_client

let git_merge_clients =
  let packages = [ package "mimic" ] in
  let connect _ _modname = function
    | [ a; b ] -> Fmt.str "Lwt.return (Mimic.merge %s %s)" a b
    | [ x ] -> Fmt.str "%s.ctx" x
    | _ -> Fmt.str "Lwt.return Mimic.empty"
  in
  impl ~packages ~connect "Mimic.Merge"
    (git_client @-> git_client @-> git_client)

let git_tcp =
  let packages =
    [ package "git-mirage" ~sublibs:[ "tcp" ] ~min:"3.10.0" ~max:"3.16.0" ]
  in
  let connect _ modname = function
    | [ _tcpv4v6; ctx ] -> Fmt.str {ocaml|%s.connect %s|ocaml} modname ctx
    | _ -> assert false
  in
  impl ~packages ~connect "Git_mirage_tcp.Make"
    (tcpv4v6 @-> mimic @-> git_client)

let git_ssh ?authenticator key password =
  let packages =
    [ package "git-mirage" ~sublibs:[ "ssh" ] ~min:"3.13.0" ~max:"3.16.0" ]
  in
  let connect _ modname = function
    | [ _mclock; _tcpv4v6; _time; ctx ] -> (
        match authenticator with
        | None ->
            Fmt.str
              {ocaml|%s.connect %s >>= %s.with_optionnal_key ~key:%a ~password:%a|ocaml}
              modname ctx modname Runtime_arg.call key Runtime_arg.call password
        | Some authenticator ->
            Fmt.str
              {ocaml|%s.connect %s >>= %s.with_optionnal_key ?authenticator:%a ~key:%a ~password:%a|ocaml}
              modname ctx modname Runtime_arg.call authenticator
              Runtime_arg.call key Runtime_arg.call password)
    | _ -> assert false
  in
  let runtime_args =
    Runtime_arg.v key
    :: Runtime_arg.v password
    :: List.map Runtime_arg.v (Option.to_list authenticator)
  in
  impl ~packages ~connect ~runtime_args "Git_mirage_ssh.Make"
    (mclock @-> tcpv4v6 @-> time @-> mimic @-> git_client)

let git_http ?authenticator headers =
  let packages =
    [ package "git-mirage" ~sublibs:[ "http" ] ~min:"3.10.0" ~max:"3.16.0" ]
  in
  let runtime_args =
    let keys = [] in
    let keys =
      match headers with
      | Some headers -> Runtime_arg.v headers :: keys
      | None -> keys
    in
    let keys =
      match authenticator with
      | Some authenticator -> Runtime_arg.v authenticator :: keys
      | None -> []
    in
    keys
  in
  let connect _ modname = function
    | [ _pclock; _tcpv4v6; ctx ] ->
        let serialize_headers ppf = function
          | None -> ()
          | Some headers -> Fmt.pf ppf " ?headers:%a" Runtime_arg.call headers
        in
        let serialize_authenticator ppf = function
          | None -> ()
          | Some authenticator ->
              Fmt.pf ppf " ?authenticator:%a" Runtime_arg.call authenticator
        in
        Fmt.str
          {ocaml|%s.connect %s >>= fun ctx -> %s.with_optional_tls_config_and_headers%a%a ctx|ocaml}
          modname ctx modname serialize_authenticator authenticator
          serialize_headers headers
    | _ -> assert false
  in
  impl ~packages ~connect ~runtime_args "Git_mirage_http.Make"
    (pclock @-> tcpv4v6 @-> mimic @-> git_client)
