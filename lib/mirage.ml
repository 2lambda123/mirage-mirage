(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2013 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open Rresult
open Astring

module Key = Mirage_key
module Name = Functoria_app.Name
module Codegen = Functoria_app.Codegen

let src = Logs.Src.create "mirage" ~doc:"mirage library"
module Log = (val Logs.src_log src : Logs.LOG)

include Functoria

let get_target i = Key.(get (Info.context i) target)

let with_output ?mode f k err =
  match Bos.OS.File.with_oc ?mode f k () with
  | Ok b -> b
  | Error _ -> R.error_msg ("couldn't open output channel for " ^ err)


(** {2 OCamlfind predicates} *)

(* Mirage implementation backing the target. *)
let backend_predicate = function
  | `Xen | `Qubes   -> "mirage_xen"
  | `Virtio | `Ukvm -> "mirage_solo5"
  | `Unix | `MacOSX -> "mirage_unix"

(** {2 Devices} *)
let qrexec = job

let qrexec_qubes = impl @@ object
  inherit base_configurable
  method ty = qrexec
  val name = Name.ocamlify @@ "qrexec_"
  method name = name
  method module_name = "Qubes.RExec"
  method packages = Key.pure [package "mirage-qubes"]
  method configure i =
    match get_target i with
    | `Qubes -> R.ok ()
    | _ ->
      Log.err (fun m -> m "Qubes remote-exec invoked for non-Qubes target, stopping.");
      R.error_msg "non-qubes target"

  method connect _ modname _args =
     Fmt.strf
"@[<v 2>\
         %s.connect ~domid:0 () >>= fun qrexec ->@ \
         Lwt.async (fun () ->@ \
         OS.Lifecycle.await_shutdown_request () >>= fun (`Poweroff | `Reboot ) ->@ \
         %s.disconnect qrexec);@ \
         Lwt.return (`Ok qrexec)@]"
     modname modname
end

let gui = job

let gui_qubes = impl @@ object
  inherit base_configurable
  method ty = gui
  val name = Name.ocamlify @@ "gui"
  method name = name
  method module_name = "Qubes.GUI"
  method packages = Key.pure [package "mirage-qubes"]
  method configure i =
    match get_target i with
    | `Qubes -> R.ok ()
    | _ ->
      Log.err (fun m -> m  "Qubes GUI invoked for non-Qubes target, stopping.");
      R.error_msg "non-qubes target"
  method connect _ modname _args =
     Fmt.strf
"@[<v 2>\
         %s.connect ~domid:0 () >>= fun gui ->@ \
         Lwt.async (fun () -> %s.listen gui);@ \
         Lwt.return (`Ok gui)@]"
     modname modname
end

type qubesdb = QUBES_DB
let qubesdb = Type QUBES_DB

let qubesdb_conf = object
  inherit base_configurable
  method ty = qubesdb
  method name = "qubesdb"
  method module_name = "Qubes.DB"
  method packages = Key.pure [ package "mirage-qubes" ]
  method connect _ modname _args =
     Fmt.strf
"@[<v 2>\
         %s.connect ~domid:0 ()@]"
     modname
end

let default_qubesdb = impl qubesdb_conf

type io_page = IO_PAGE
let io_page = Type IO_PAGE

let io_page_conf = object
  inherit base_configurable
  method ty = io_page
  method name = "io_page"
  method module_name = "Io_page"
  method packages =
    Key.(if_ is_unix) [package ~sublibs:["unix"] "io-page"] [package "io-page"]
end

let default_io_page = impl io_page_conf

type time = TIME
let time = Type TIME

let time_conf = object
  inherit base_configurable
  method ty = time
  method name = "time"
  method module_name = "OS.Time"
end

let default_time = impl time_conf

type pclock = PCLOCK
let pclock = Type PCLOCK

let posix_clock_conf = object
  inherit base_configurable
  method ty = pclock
  method name = "pclock"
  method module_name = "Pclock"
  method packages =
    Key.(if_ is_unix)
      [package "mirage-clock-unix"]
      [package "mirage-clock-freestanding"]
  method connect _ modname _args =
    Printf.sprintf "%s.connect ()" modname
end

let default_posix_clock = impl posix_clock_conf

type mclock = MCLOCK
let mclock = Type MCLOCK

let monotonic_clock_conf = object
  inherit base_configurable
  method ty = mclock
  method name = "mclock"
  method module_name = "Mclock"
  method packages =
    Key.(if_ is_unix)
      [package "mirage-clock-unix"]
      [package "mirage-clock-freestanding"]
  method connect _ modname _args =
    Printf.sprintf "%s.connect ()" modname
end

let default_monotonic_clock = impl monotonic_clock_conf

type random = RANDOM
let random = Type RANDOM

let stdlib_random_conf = object
  inherit base_configurable
  method ty = random
  method name = "random"
  method module_name = "Stdlibrandom"
  method packages = Key.pure [package "mirage-stdlib-random"]
  method connect _ modname _args =
    Printf.sprintf "Lwt.return (%s.initialize ())" modname
end

let stdlib_random = impl stdlib_random_conf


let query_ocamlfind ?(recursive = false) ?(format="%p") ?predicates libs =
  let open Bos in
  let flag = if recursive then "-recursive" else ""
  and format = Cmd.of_list [ "-format" ; format ]
  and predicate = match predicates with
    | None -> []
    | Some x -> [ "-predicates" ; x ]
  in
  let cmd = Cmd.(v "ocamlfind" % "query" % flag %% format %% of_list predicate %% of_list libs) in
  OS.Cmd.run_out cmd |> OS.Cmd.out_lines >>| fst

(* This is to check that entropy is a dependency if "tls" is in
   the package array. *)
let enable_entropy, is_entropy_enabled =
  let r = ref false in
  let f () = r := true in
  let g () = !r in
  (f, g)

let check_entropy libs =
  query_ocamlfind ~recursive:true libs >>= fun ps ->
  if List.mem "nocrypto" ps && not (is_entropy_enabled ()) then begin
    Log.err (fun m -> m
                "The \"nocrypto\" library is loaded but entropy is not enabled!@ \
                 Please enable the entropy by adding a dependency to the nocrypto \
                 device. You can do so by adding ~deps:[abstract nocrypto] \
                 to the arguments of Mirage.foreign.");
    R.error_msg "need crypto"
  end else R.ok ()

let nocrypto = impl @@ object
    inherit base_configurable
    method ty = job
    method name = "nocrypto"
    method module_name = "Nocrypto_entropy"

    method packages =
      Key.match_ Key.(value target) @@ function
      | `Xen | `Qubes ->
        [package ~sublibs:["mirage"] "nocrypto"; package ~ocamlfind:[] "zarith-xen"]
      | `Virtio | `Ukvm ->
        [package ~sublibs:["mirage"] "nocrypto"; package ~ocamlfind:[] "zarith-freestanding"]
      | `Unix | `MacOSX ->
        [package ~sublibs:["lwt"] "nocrypto"]

    method build _ = R.ok (enable_entropy ())
    method connect i _ _ =
      match get_target i with
      | `Xen | `Qubes | `Virtio | `Ukvm -> "Nocrypto_entropy_mirage.initialize ()"
      | `Unix | `MacOSX -> "Nocrypto_entropy_lwt.initialize ()"

  end

let nocrypto_random_conf = object
  inherit base_configurable
  method ty = random
  method name = "random"
  method module_name = "Nocrypto.Rng"
  method packages = Key.pure [package "nocrypto"]
  method deps = [abstract nocrypto]
end

let nocrypto_random = impl nocrypto_random_conf

let default_random =
  match_impl (Key.value @@ Key.prng ()) [
    `Stdlib  , stdlib_random;
    `Nocrypto, nocrypto_random;
  ] ~default:stdlib_random

type console = CONSOLE
let console = Type CONSOLE

let console_unix str = impl @@ object
    inherit base_configurable
    method ty = console
    val name = Name.ocamlify @@ "console_unix_" ^ str
    method name = name
    method module_name = "Console_unix"
    method packages = Key.pure [package "mirage-console-unix"]
    method connect _ modname _args =
      Printf.sprintf "%s.connect %S" modname str
  end

let console_xen str = impl @@ object
    inherit base_configurable
    method ty = console
    val name = Name.ocamlify @@ "console_xen_" ^ str
    method name = name
    method module_name = "Console_xen"
    method packages = Key.pure [package "mirage-console-xen"]
    method connect _ modname _args =
      Printf.sprintf "%s.connect %S" modname str
  end

let console_solo5 str = impl @@ object
    inherit base_configurable
    method ty = console
    val name = Name.ocamlify @@ "console_solo5_" ^ str
    method name = name
    method module_name = "Console_solo5"
    method packages = Key.pure [package "mirage-console-solo5";]
    method connect _ modname _args =
      Printf.sprintf "%s.connect %S" modname str
  end

let custom_console str =
  match_impl Key.(value target) [
    `Xen, console_xen str;
    `Qubes, console_xen str;
    `Virtio, console_solo5 str;
    `Ukvm, console_solo5 str
  ] ~default:(console_unix str)

let default_console = custom_console "0"

type kv_ro = KV_RO
let kv_ro = Type KV_RO

let crunch dirname = impl @@ object
    inherit base_configurable
    method ty = kv_ro
    val name = Name.create ("static" ^ dirname) ~prefix:"static"
    method name = name
    method module_name = String.Ascii.capitalize name
    method packages = Key.pure [package "io-page"; package ~build:true "crunch"]
    method deps = [ abstract default_io_page ]
    method connect _ modname _ = Fmt.strf "%s.connect ()" modname

    method build i =
      match query_ocamlfind  ["crunch"] with
      | Ok _ ->
        let dir = Fpath.(v (Info.root i) // v dirname) in
        let file = Fpath.(v (Info.root i) / name + ".ml") in
        begin match Bos.OS.Path.exists dir with
          | Ok _ ->
            Log.info (fun m -> m "Generating: %a" Fpath.pp file);
            Bos.OS.Cmd.run Bos.Cmd.(v "ocaml-crunch" % "-o" % (Fpath.to_string file) % (Fpath.to_string dir))
          | Error _ ->
            Log.err (fun m -> m "The directory %a does not exist." Fpath.pp dir);
            R.error_msg "no such directory"
        end
      | Error e ->
        Log.err (fun m -> m  "Couldn't find the ocaml-crunch binary.  Please install the opam package crunch.");
        Error e

    method clean _i =
      Bos.OS.File.delete Fpath.(v name + "ml") >>= fun () ->
      Bos.OS.File.delete Fpath.(v name + "mli")

  end

let direct_kv_ro_conf dirname = impl @@ object
    inherit base_configurable
    method ty = kv_ro
    val name = Name.create ("direct" ^ dirname) ~prefix:"direct"
    method name = name
    method module_name = "Kvro_fs_unix"
    method packages = Key.pure [package "mirage-fs-unix"]
    method connect i _modname _names =
      Fmt.strf "Kvro_fs_unix.connect %S" (Filename.concat (Info.root i) dirname)
  end

let direct_kv_ro dirname =
  match_impl Key.(value target) [
    `Xen, crunch dirname;
    `Qubes, crunch dirname;
    `Virtio, crunch dirname;
    `Ukvm, crunch dirname
  ] ~default:(direct_kv_ro_conf dirname)

type block = BLOCK
let block = Type BLOCK
type block_t = { filename: string; number: int }
let all_blocks = Hashtbl.create 7

let make_block_t =
  (* NB: reserve number 0 for the boot disk *)
  let next_number = ref 1 in
  fun filename ->
    let b =
      if Hashtbl.mem all_blocks filename
      then Hashtbl.find all_blocks filename
      else begin
        let number = !next_number in
        incr next_number;
        let b = { filename; number } in
        Hashtbl.add all_blocks filename b;
        b
      end in
    b

class block_conf file =
  let b = make_block_t file in
  let name = Name.create file ~prefix:"block" in
  object (self)
    inherit base_configurable
    method ty = block
    method name = name
    method module_name = "Block"
    method packages =
      Key.match_ Key.(value target) @@ function
      | `Xen | `Qubes -> [package ~sublibs:["front"] "mirage-block-xen"]
      | `Virtio | `Ukvm -> [package "mirage-block-solo5"]
      | `Unix | `MacOSX -> [package "mirage-block-unix"]

    method private connect_name target root =
      match target with
      | `Unix | `MacOSX | `Virtio | `Ukvm ->
        Filename.concat root b.filename (* open the file directly *)
      | `Xen | `Qubes ->
        (* We need the xenstore id *)
        (* Taken from https://github.com/mirage/mirage-block-xen/blob/
           a64d152586c7ebc1d23c5adaa4ddd440b45a3a83/lib/device_number.ml#L64 *)
        (if b. number < 16
         then (202 lsl 8) lor (b.number lsl 4)
         else (1 lsl 28)  lor (b.number lsl 8)) |> string_of_int

    method connect i s _ =
      Printf.sprintf "%s.connect %S" s
        (self#connect_name (get_target i) @@ Info.root i)

  end

let block_of_file file = impl (new block_conf file)

let tar_block dir =
  let name = Name.create ("tar_block" ^ dir) ~prefix:"tar_block" in
  let block_file = name ^ ".img" in
  impl @@ object
    inherit block_conf block_file as super
    method build i =
      Bos.OS.Cmd.run Bos.Cmd.(v "tar" % "-C" % dir % "-cvf" % block_file) >>= fun () ->
      super#build i
  end

let archive_conf = impl @@ object
    inherit base_configurable
    method ty = block @-> kv_ro
    method name = "archive"
    method module_name = "Tar_mirage.Make_KV_RO"
    method packages = Key.pure [ package ~ocamlfind:["tar.mirage"] "tar-format" ]
    method connect _ modname = function
      | [ block ] ->
        Fmt.strf "%s.connect %s" modname block
      | _ -> failwith "The archive connect should receive exactly one argument."

  end

let archive block = archive_conf $ block
let archive_of_files ?(dir=".") () = archive @@ tar_block dir

type fs = FS
let fs = Type FS

let fat_conf = impl @@ object
    inherit base_configurable
    method ty = (block @-> io_page @-> fs)
    method packages = Key.pure [ package "fat-filesystem" ]
    method name = "fat"
    method module_name = "Fat.Fs.Make"
    method connect _ modname l = match l with
      | [ block_name ; _io_page_name ] ->
        Printf.sprintf "%s.connect %s" modname block_name
      | _ -> assert false
  end

let fat ?(io_page=default_io_page) block = fat_conf $ block $ io_page

let fat_block ?(dir=".") ?(regexp="*") () =
  let name = Name.create (Fmt.strf "fat%s:%s" dir regexp) ~prefix:"fat_block" in
  let block_file = name ^ ".img" in
  impl @@ object
    inherit block_conf block_file as super

    method configure i =
      let root = Info.root i in
      let file = Printf.sprintf "make-%s-image.sh" name in
      with_output ~mode:0o755 (Fpath.v file)
        (fun oc () ->
           let fmt = Format.formatter_of_out_channel oc in
           Codegen.append fmt "#!/bin/sh";
           Codegen.append fmt "";
           Codegen.append fmt "echo This uses the 'fat' command-line tool to \
                               build a simple FAT";
           Codegen.append fmt "echo filesystem image.";
           Codegen.append fmt "";
           Codegen.append fmt "FAT=$(which fat)";
           Codegen.append fmt "if [ ! -x \"${FAT}\" ]; then";
           Codegen.append fmt "  echo I couldn\\'t find the 'fat' command-line \
                               tool.";
           Codegen.append fmt "  echo Try running 'opam install fat-filesystem'";
           Codegen.append fmt "  exit 1";
           Codegen.append fmt "fi";
           Codegen.append fmt "";
           Codegen.append fmt "IMG=$(pwd)/%s" block_file;
           Codegen.append fmt "rm -f ${IMG}";
           Codegen.append fmt "cd %s/" (Filename.concat root dir);
           Codegen.append fmt "SIZE=$(du -s . | cut -f 1)";
           Codegen.append fmt "${FAT} create ${IMG} ${SIZE}KiB";
           Codegen.append fmt "${FAT} add ${IMG} %s" regexp;
           Codegen.append fmt "echo Created '%s'" block_file;
           R.ok ())
        "fat shell script" >>= fun () ->
      Bos.OS.Cmd.run (Bos.Cmd.v ("./make-" ^ name ^ "-image.sh")) >>= fun () ->
      super#configure i

    method clean i =
      Bos.OS.File.delete (Fpath.v ("make-" ^ name ^ "-image.sh")) >>= fun () ->
      Bos.OS.File.delete (Fpath.v block_file) >>= fun () ->
      super#clean i
  end

let fat_of_files ?dir ?regexp () = fat @@ fat_block ?dir ?regexp ()


let kv_ro_of_fs_conf = impl @@ object
    inherit base_configurable
    method ty = fs @-> kv_ro
    method name = "kv_ro_of_fs"
    method module_name = "Fat.KV_RO.Make"
    method packages = Key.pure [ package "fat-filesystem" ]
  end

let kv_ro_of_fs x = kv_ro_of_fs_conf $ x

(** generic kv_ro. *)

let generic_kv_ro ?(key = Key.value @@ Key.kv_ro ()) dir =
  match_impl key [
    `Fat    , kv_ro_of_fs @@ fat_of_files ~dir () ;
    `Archive, archive_of_files ~dir () ;
    `Crunch , crunch dir ;
    `Direct , direct_kv_ro dir ;
  ] ~default:(direct_kv_ro dir)

(** network devices *)

type network = NETWORK
let network = Type NETWORK

let all_networks = ref []

let network_conf (intf : string Key.key) =
  let key = Key.abstract intf in
  object
    inherit base_configurable
    method ty = network
    val name = Functoria_app.Name.create "net" ~prefix:"net"
    method name = name
    method module_name = "Netif"
    method keys = [ key ]

    method packages =
      Key.match_ Key.(value target) @@ function
      | `Unix -> [package "mirage-net-unix"]
      | `MacOSX -> [package "mirage-net-macosx"]
      | `Xen -> [package "mirage-net-xen"]
      | `Qubes -> [package "mirage-net-xen" ; package "mirage-qubes"]
      | `Virtio | `Ukvm -> [package "mirage-net-solo5"]

    method connect _ modname _ =
      Fmt.strf "%s.connect %a" modname Key.serialize_call key

    method configure i =
      all_networks := Key.get (Info.context i) intf :: !all_networks;
      R.ok ()

  end

let netif ?group dev = impl (network_conf @@ Key.interface ?group dev)
let tap0 = netif "tap0"

type dhcp = Dhcp_client
let dhcp = Type Dhcp_client

type ethernet = ETHERNET
let ethernet = Type ETHERNET

let ethernet_conf = object
  inherit base_configurable
  method ty = network @-> ethernet
  method name = "ethif"
  method module_name = "Ethif.Make"
  method packages = Key.pure [package ~sublibs:["ethif"] "tcpip"]
  method connect _ modname = function
    | [ eth ] -> Printf.sprintf "%s.connect %s" modname eth
    | _ -> failwith "The ethernet connect should receive exactly one argument."
end

let etif_func = impl ethernet_conf
let etif network = etif_func $ network

type arpv4 = Arpv4
let arpv4 = Type Arpv4

let arpv4_conf = object
  inherit base_configurable
  method ty = ethernet @-> mclock @-> time @-> arpv4
  method name = "arpv4"
  method module_name = "Arpv4.Make"
  method packages = Key.pure [package ~sublibs:["arpv4"] "tcpip"]

  method connect _ modname = function
    | [ eth ; clock ; _time ] -> Printf.sprintf "%s.connect %s %s" modname eth clock
    | _ -> failwith "The arpv4 connect should receive exactly three arguments."

end

let arp_func = impl arpv4_conf
let arp ?(clock = default_monotonic_clock) ?(time = default_time) (eth : ethernet impl) =
  arp_func $ eth $ clock $ time

type v4
type v6
type 'a ip = IP
type ipv4 = v4 ip
type ipv6 = v6 ip

let ip = Type IP
let ipv4: ipv4 typ = ip
let ipv6: ipv6 typ = ip

let meta_ipv4 ppf s =
  Fmt.pf ppf "(Ipaddr.V4.of_string_exn %S)" (Ipaddr.V4.to_string s)

type ipv4_config = {
  network : Ipaddr.V4.t * Ipaddr.V4.Prefix.t;
  gateway : Ipaddr.V4.t option;
}
(** Types for IPv4 manual configuration. *)


let pp_key fmt k = Key.serialize_call fmt (Key.abstract k)
let opt_key s = Fmt.(option @@ prefix (unit ("~"^^s^^":")) pp_key)
let opt_map f = function Some x -> Some (f x) | None -> None
let (@?) x l = match x with Some s -> s :: l | None -> l
let (@??) x y = opt_map Key.abstract x @? y

let ipv4_keyed_conf ?network ?gateway () = impl @@ object
    inherit base_configurable
    method ty = ethernet @-> arpv4 @-> ipv4
    method name = Name.create "ipv4" ~prefix:"ipv4"
    method module_name = "Static_ipv4.Make"
    method packages = Key.pure [package ~sublibs:["ipv4"] "tcpip"]
    method keys = network @?? gateway @?? []
    method connect _ modname = function
    | [ etif ; arp ] ->
        Fmt.strf
          "let (ip, network) = %a in @ \
             %s.connect@[@ ~ip ~network %a@ %s@ %s@]"
          (Fmt.option pp_key) network
          modname
          (opt_key "gateway") gateway
          etif arp
      | _ -> failwith "The ipv4 connect should receive exactly two arguments."
  end

let dhcp_conf = impl @@ object
  inherit base_configurable
  method ty = time @-> network @-> dhcp
  method name = "dhcp_client"
  method module_name = "Dhcp_client_mirage.Make"
  method packages = Key.pure [ package ~sublibs:["mirage"] "charrua-client" ]
  method connect _ modname = function
  | [ _time; network ] ->
    Fmt.strf
      "%s.connect %s "
      modname network
  | _ -> failwith "The dhcp_config connect should receive exactly two arguments."
end

let ipv4_dhcp_conf = impl @@ object
    inherit base_configurable
    method ty = dhcp @-> ethernet @-> arpv4 @-> ipv4
    method name = Name.create "dhcp_ipv4" ~prefix:"dhcp_ipv4"
    method module_name = "Dhcp_ipv4.Make"
    method packages = Key.pure [package ~sublibs:["mirage"] "charrua-client"]
    method connect _ modname = function
          | [ dhcp ; ethernet ; arp ] ->
        Fmt.strf
          "%s.connect@[@ %s@ %s@ %s@]"
          modname
          dhcp ethernet arp
      | _ -> failwith "The ipv4 connect should receive exactly three arguments."
  end


let dhcp time net = dhcp_conf $ time $ net
let ipv4_of_dhcp dhcp ethif arp = ipv4_dhcp_conf $ dhcp $ ethif $ arp

let create_ipv4 ?group ?config etif arp =
  let config = match config with
  | None ->
    let default_address = Ipaddr.V4.of_string_exn "10.0.0.2" in
    {
      network = default_address, Ipaddr.V4.Prefix.make 24 default_address;
      gateway = Some (Ipaddr.V4.of_string_exn "10.0.0.1");
    }
  | Some config -> config
  in
  let network = Key.V4.network ?group config.network in
  let gateway = Key.V4.gateway ?group config.gateway in
  ipv4_keyed_conf ~network ~gateway () $ etif $ arp

type ipv6_config = {
  addresses: Ipaddr.V6.t list;
  netmasks: Ipaddr.V6.Prefix.t list;
  gateways: Ipaddr.V6.t list;
}
(** Types for IP manual configuration. *)

let ipv4_qubes_conf = impl @@ object
  inherit base_configurable
  method ty = qubesdb @-> ethernet @-> arpv4 @-> ipv4
  method name = Name.create "qubes_ipv4" ~prefix:"qubes_ipv4"
  method module_name = "Qubesdb_ipv4.Make"
  method packages = Key.pure [package ~sublibs:["ipv4"] "mirage-qubes"]
  method connect _ modname = function
  | [ db ; ethif; arp ] ->
      Fmt.strf
        "%s.connect %s %s %s"
        modname db ethif arp
  | _ -> failwith "The qubes_ipv4_conf connect should receive exactly three arguments."
end

let ipv4_qubes db ethernet arp = ipv4_qubes_conf $ db $ ethernet $ arp

let ipv6_conf ?addresses ?netmasks ?gateways () = impl @@ object
    inherit base_configurable
    method ty = ethernet @-> time @-> mclock @-> ipv6
    method name = Name.create "ipv6" ~prefix:"ipv6"
    method module_name = "Ipv6.Make"
    method packages = Key.pure [package ~sublibs:["ipv6"] "tcpip"]
    method keys = addresses @?? netmasks @?? gateways @?? []
    method connect _ modname = function
      | [ etif ; _time ; _clock ] ->
        Fmt.strf
          "%s.connect@[@ %a@ %a@ %a@ %s@@]"
          modname
          (opt_key "ip") addresses
          (opt_key "netmask") netmasks
          (opt_key "gateways") gateways
          etif
      | _ -> failwith "The ipv6 connect should receive exactly three arguments."
  end

let create_ipv6
    ?(time = default_time)
    ?(clock = default_monotonic_clock)
    ?group etif { addresses ; netmasks ; gateways } =
  let addresses = Key.V6.ips ?group addresses in
  let netmasks = Key.V6.netmasks ?group netmasks in
  let gateways = Key.V6.gateways ?group gateways in
  ipv6_conf ~addresses ~netmasks ~gateways () $ etif $ time $ clock

type 'a icmp = ICMP
type icmpv4 = v4 icmp

let icmp = Type ICMP
let icmpv4: icmpv4 typ = icmp

let icmpv4_direct_conf () = object
  inherit base_configurable
  method ty : ('a ip -> 'a icmp) typ = ip @-> icmp
  method name = "icmpv4"
  method module_name = "Icmpv4.Make"
  method packages = Key.pure [ package ~sublibs:["icmpv4"] "tcpip" ]
  method connect _ modname = function
    | [ ip ] -> Printf.sprintf "%s.connect %s" modname ip
    | _  -> failwith "The icmpv4 connect should receive exactly one argument."
end

let icmpv4_direct_func () = impl (icmpv4_direct_conf ())
let direct_icmpv4 ip = icmpv4_direct_func () $ ip

type 'a udp = UDP
type udpv4 = v4 udp
type udpv6 = v6 udp

let udp = Type UDP
let udpv4: udpv4 typ = udp
let udpv6: udpv6 typ = udp

(* Value restriction ... *)
let udp_direct_conf () = object
  inherit base_configurable
  method ty : ('a ip -> 'a udp) typ = ip @-> udp
  method name = "udp"
  method module_name = "Udp.Make"
  method packages = Key.pure [package ~sublibs:["udp"] "tcpip" ]
  method connect _ modname = function
    | [ ip ] -> Printf.sprintf "%s.connect %s" modname ip
    | _  -> failwith "The udpv6 connect should receive exactly one argument."
end

(* Value restriction ... *)
let udp_direct_func () = impl (udp_direct_conf ())
let direct_udp ip = udp_direct_func () $ ip

let udpv4_socket_conf ipv4_key = object
  inherit base_configurable
  method ty = udpv4
  val name = Name.create "udpv4_socket" ~prefix:"udpv4_socket"
  method name = name
  method module_name = "Udpv4_socket"
  method keys = [ Key.abstract ipv4_key ]
  method packages =
    Key.match_ Key.(value target) @@ function
    | `Unix | `MacOSX -> [ package ~sublibs:["udpv4-socket"] "tcpip" ]
    | `Xen | `Virtio | `Ukvm | `Qubes  -> failwith "No socket implementation available for unikernel"
  method connect _ modname _ =
    Format.asprintf "%s.connect %a" modname  pp_key ipv4_key
end

let socket_udpv4 ?group ip = impl (udpv4_socket_conf @@ Key.V4.socket ?group ip)

type 'a tcp = TCP
type tcpv4 = v4 tcp
type tcpv6 = v6 tcp

let tcp = Type TCP
let tcpv4 : tcpv4 typ = tcp
let tcpv6 : tcpv6 typ = tcp

(* Value restriction ... *)
let tcp_direct_conf () = object
  inherit base_configurable
  method ty =
    (ip: 'a ip typ) @-> time @-> mclock @-> random @-> (tcp: 'a tcp typ)
  method name = "tcp"
  method module_name = "Tcp.Flow.Make"
  method packages = Key.pure [package ~sublibs:["tcp"] "tcpip" ]
  method connect _ modname = function
    | [ip; _time; clock; _random] -> Printf.sprintf "%s.connect %s %s" modname ip clock
    | _ -> failwith "The tcp connect should receive exactly four arguments."
end

(* Value restriction ... *)
let tcp_direct_func () = impl (tcp_direct_conf ())

let direct_tcp
    ?(clock=default_monotonic_clock) ?(random=default_random) ?(time=default_time) ip =
  tcp_direct_func () $ ip $ time $ clock $ random

let tcpv4_socket_conf ipv4_key = object
  inherit base_configurable
  method ty = tcpv4
  val name = Name.create "tcpv4_socket" ~prefix:"tcpv4_socket"
  method name = name
  method module_name = "Tcpv4_socket"
  method keys = [ Key.abstract ipv4_key ]
  method packages =
    Key.match_ Key.(value target) @@ function
    | `Unix | `MacOSX -> [package ~sublibs:["tcpv4-socket"] "tcpip" ]
    | `Xen | `Virtio | `Ukvm | `Qubes  -> failwith "No socket implementation available for unikernel"
  method connect _ modname _ =
    Format.asprintf "%s.connect %a" modname  pp_key ipv4_key
end

let socket_tcpv4 ?group ip = impl (tcpv4_socket_conf @@ Key.V4.socket ?group ip)

type stackv4 = STACKV4
let stackv4 = Type STACKV4

let add_suffix s ~suffix = if suffix = "" then s else s^"_"^suffix

let stackv4_direct_conf ?(group="") () = impl @@ object
    inherit base_configurable

    method ty =
      time @-> random @-> network @->
      ethernet @-> arpv4 @-> ipv4 @-> icmpv4 @-> udpv4 @-> tcpv4 @->
      stackv4

    val name = add_suffix "stackv4_" ~suffix:group

    method name = name
    method module_name = "Tcpip_stack_direct.Make"

    method packages = Key.pure [package ~sublibs:["stack-direct"] "tcpip" ]

    method connect _i modname = function
      | [ _t; _r; interface; ethif; arp; ip; icmp; udp; tcp ] ->
        Fmt.strf
          "@[<2>let config = {V1_LWT.@ \
           name = %S;@ \
           interface = %s;}@]@ in@ \
           %s.connect config@ %s %s %s %s %s %s"
          name interface
          modname ethif arp ip icmp udp tcp
      | _ -> failwith "Wrong arguments to connect to tcpip direct stack."
  end

let direct_stackv4
    ?(clock=default_monotonic_clock)
    ?(random=default_random)
    ?(time=default_time)
    ?group
    network eth arp ip =
  stackv4_direct_conf ?group ()
  $ time $ random $ network
  $ eth $ arp $ ip
  $ direct_icmpv4 ip
  $ direct_udp ip
  $ direct_tcp ~clock ~random ~time ip

let dhcp_ipv4_stack ?group ?(time = default_time) tap =
  let config = dhcp time tap in
  let e = etif tap in
  let (a : arpv4 impl) = arp e in
  let i = ipv4_of_dhcp config e a in
  direct_stackv4 ?group tap e a i

let static_ipv4_stack ?group ?config tap =
  let e = etif tap in
  let a = arp e in
  let i = create_ipv4 ?group ?config e a in
  direct_stackv4 ?group tap e a i

let qubes_ipv4_stack ?group ?(qubesdb = default_qubesdb) tap =
  let e = etif tap in
  let a = arp e in
  let i = ipv4_qubes qubesdb e a in
  direct_stackv4 ?group tap e a i

let stackv4_socket_conf ?(group="") interfaces = impl @@ object
    inherit base_configurable
    method ty = stackv4
    val name = add_suffix "stackv4_socket" ~suffix:group
    method name = name
    method module_name = "Tcpip_stack_socket"
    method keys = [ Key.abstract interfaces ]
    method packages = Key.pure [ package ~sublibs:["stack-socket"] "tcpip" ]
    method deps = [
      abstract (socket_udpv4 None);
      abstract (socket_tcpv4 None);
    ]

    method connect _i modname = function
      | [ udpv4 ; tcpv4 ] ->
        Fmt.strf
          "let config =@[@ \
           { V1_LWT.name = %S;@ \
           interface = %a ;}@] in@ \
           %s.connect config %s %s"
          name
          pp_key interfaces
          modname udpv4 tcpv4
      | _ -> failwith "Wrong arguments to connect to tcpip socket stack."

  end

let socket_stackv4 ?group ipv4s =
  stackv4_socket_conf ?group (Key.V4.interfaces ?group ipv4s)

(** Generic stack *)

let generic_stackv4
    ?group ?config
    ?(dhcp_key = Key.value @@ Key.dhcp ?group ())
    ?(net_key = Key.value @@ Key.net ?group ())
    (tap : network impl) : stackv4 impl =
  let eq a b = Key.(pure ((=) a) $ b) in
  let choose qubes socket dhcp =
    if qubes then `Qubes
    else if socket then `Socket
    else if dhcp then `Dhcp
    else `Static
  in
  let p = Functoria_key.((pure choose)
          $ eq `Qubes Key.(value target)
          $ eq `Socket net_key
          $ eq true dhcp_key) in
  match_impl p [
    `Dhcp, dhcp_ipv4_stack ?group tap;
    `Socket, socket_stackv4 ?group [Ipaddr.V4.any];
    `Qubes, qubes_ipv4_stack ?group tap;
  ] ~default:(static_ipv4_stack ?config ?group tap)

type conduit_connector = Conduit_connector
let conduit_connector = Type Conduit_connector

let tcp_conduit_connector = impl @@ object
    inherit base_configurable
    method ty = stackv4 @-> conduit_connector
    method name = "tcp_conduit_connector"
    method module_name = "Conduit_mirage.With_tcp"
    method packages =
      Key.pure [
        package ~ocamlfind:[] "mirage-conduit";
        package ~sublibs:["mirage"] "conduit"
      ]
    method connect _ modname = function
      | [ stack ] ->
        Fmt.strf "Lwt.return (%s.connect %s)@;" modname stack
      | _ -> failwith "Wrong arguments to connect to tcp conduit connector."
  end

let tls_conduit_connector = impl @@ object
    inherit base_configurable
    method ty = conduit_connector
    method name = "tls_conduit_connector"
    method module_name = "Conduit_mirage"
    method packages =
      Key.pure [
        package ~sublibs:["mirage"] "tls" ;
        package ~ocamlfind:[] "mirage-conduit" ;
        package ~sublibs:["mirage"] "conduit"
      ]
    method deps = [ abstract nocrypto ]
    method connect _ _ _ = "Lwt.return Conduit_mirage.with_tls"
  end

type conduit = Conduit
let conduit = Type Conduit

let conduit_with_connectors connectors = impl @@ object
    inherit base_configurable
    method ty = conduit
    method name = Name.create "conduit" ~prefix:"conduit"
    method module_name = "Conduit_mirage"
    method packages =
      Key.pure [
        package ~ocamlfind:[] "mirage-conduit";
        package ~sublibs:["mirage"] "conduit"
      ]
    method deps = abstract nocrypto :: List.map abstract connectors

    method connect _i _ = function
      (* There is always at least the nocrypto device *)
      | [] -> invalid_arg "Mirage.conduit_with_connector"
      | _nocrypto :: connectors ->
        let pp_connector = Fmt.fmt "%s >>=@ " in
        let pp_connectors = Fmt.list ~sep:Fmt.nop pp_connector in
        Fmt.strf
          "Lwt.return Conduit_mirage.empty >>=@ \
           %a\
           fun t -> Lwt.return t"
          pp_connectors connectors
  end

let conduit_direct ?(tls=false) s =
  (* TCP must be before tls in the list. *)
  let connectors = [tcp_conduit_connector $ s] in
  let connectors =
    if tls
    then connectors @ [tls_conduit_connector]
    else connectors
  in
  conduit_with_connectors connectors

type resolver = Resolver
let resolver = Type Resolver

let resolver_unix_system = impl @@ object
    inherit base_configurable
    method ty = resolver
    method name = "resolver_unix"
    method module_name = "Resolver_lwt"
    method packages =
      Key.match_ Key.(value target) @@ function
      | `Unix | `MacOSX ->
        [ package ~ocamlfind:[] "mirage-conduit" ;
          package ~sublibs:["mirage";"lwt-unix"] "conduit" ]
      | _ -> failwith "Resolver_unix not supported on unikernel"
    method connect _ _modname _ = "Lwt.return Resolver_lwt_unix.system"
  end

let resolver_dns_conf ~ns ~ns_port = impl @@ object
    inherit base_configurable
    method ty = time @-> stackv4 @-> resolver
    method name = "resolver"
    method module_name = "Resolver_mirage.Make_with_stack"
    method packages =
      Key.pure [ package ~sublibs:["mirage"] "dns"; package "tcpip" ]

    method connect _ modname = function
      | [ _t ; stack ] ->
        let meta_ns = Fmt.Dump.option meta_ipv4 in
        let meta_port = Fmt.(Dump.option int) in
        Fmt.strf
          "let ns = %a in@;\
           let ns_port = %a in@;\
           let res = %s.R.init ?ns ?ns_port ~stack:%s () in@;\
           Lwt.return res@;"
          meta_ns ns
          meta_port ns_port
          modname stack
      | _ -> failwith "The resolver connect should receive exactly two arguments."

  end

let resolver_dns ?ns ?ns_port ?(time = default_time) stack =
  resolver_dns_conf ~ns ~ns_port $ time $ stack

type http = HTTP
let http = Type HTTP

let http_server conduit = impl @@ object
    inherit base_configurable
    method ty = http
    method name = "http"
    method module_name = "Cohttp_mirage.Server_with_conduit"
    method packages = Key.pure [ package "mirage-http" ]
    method deps = [ abstract conduit ]
    method connect _i modname = function
      | [ conduit ] -> Fmt.strf "%s.connect %s" modname conduit
      | _ -> failwith "The http connect should receive exactly one argument."
  end

(** Argv *)

let argv_unix = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_unix"
    method module_name = "OS.Env"
    method connect _ _ _ = "OS.Env.argv ()"
  end

let argv_xen = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_xen"
    method module_name = "Bootvar"
    method packages = Key.pure [ package "mirage-bootvar-xen" ]
    method connect _ _ _ = "Bootvar.argv ()"
  end

let argv_solo5 = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_solo5"
    method module_name = "Bootvar"
    method packages = Key.pure [ package "mirage-bootvar-solo5" ]
    method connect _ _ _ = "Bootvar.argv ()"
  end

let no_argv = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_empty"
    method module_name = "Mirage_runtime"
    method connect _ _ _ = "Lwt.return [|\"\"|]"
  end

let argv_qubes = impl @@ object
    inherit base_configurable
    method ty = Functoria_app.argv
    method name = "argv_qubes"
    method module_name = "Bootvar"
    method packages = Key.pure [ package "mirage-bootvar-xen" ]
    method connect _ _ _ =
      (* Qubes tries to pass some nice arguments.
       * It means well, but we can't do much with them,
       * and they cause Functoria to abort. *)
      "Bootvar.argv ~filter:(fun (key, _) -> List.mem key @@ List.map snd Key_gen.runtime_keys) ()"
  end

let default_argv =
  match_impl Key.(value target) [
    `Xen, argv_xen;
    `Qubes, argv_qubes;
    `Virtio, argv_solo5;
    `Ukvm, argv_solo5
  ] ~default:argv_unix

(** Log reporting *)

type reporter = job
let reporter = job

let pp_level ppf = function
  | Logs.Error    -> Fmt.string ppf "Logs.Error"
  | Logs.Warning  -> Fmt.string ppf "Logs.Warning"
  | Logs.Info     -> Fmt.string ppf "Logs.Info"
  | Logs.Debug    -> Fmt.string ppf "Logs.Debug"
  | Logs.App      -> Fmt.string ppf "Logs.App"

let mirage_log ?ring_size ~default =
  let logs = Key.logs in
  impl @@ object
    inherit base_configurable
    method ty = pclock @-> reporter
    method name = "mirage_logs"
    method module_name = "Mirage_logs.Make"
    method packages = Key.pure [ package "mirage-logs"]
    method keys = [ Key.abstract logs ]
    method connect _ modname = function
    | [ pclock ] ->
      Fmt.strf
        "@[<v 2>\
         let ring_size = %a in@ \
         let reporter = %s.create ?ring_size %s in@ \
         Mirage_runtime.set_level ~default:%a %a;@ \
         %s.set_reporter reporter;@ \
         Lwt.return reporter"
        Fmt.(Dump.option int) ring_size
        modname pclock
        pp_level default
        pp_key logs
        modname
    | _ -> failwith "The Pclock connect should receive exactly one argument."
  end

let default_reporter
    ?(clock=default_posix_clock) ?ring_size ?(level=Logs.Info) () =
  mirage_log ?ring_size ~default:level $ clock

let no_reporter = impl @@ object
    inherit base_configurable
    method ty = reporter
    method name = "no_reporter"
    method module_name = "Mirage_runtime"
    method connect _ _ _ = "assert false"
  end

(** Tracing *)

type tracing = job
let tracing = job

let mprof_trace ~size () =
  let unix_trace_file = "trace.ctf" in
  let key = Key.tracing_size size in
  impl @@ object
    inherit base_configurable
    method ty = job
    method name = "mprof_trace"
    method module_name = "MProf"
    method keys = [ Key.abstract key ]
    method packages =
      Key.match_ Key.(value target) @@ function
      | `Xen | `Qubes -> [package ~sublibs:["xen"] "mirage-profile"]
      | `Virtio | `Ukvm -> failwith  "tracing is not currently implemented for solo5 targets"
      | `Unix | `MacOSX -> [package ~sublibs:["unix"] "mirage-profile"]

    method configure _ =
      match query_ocamlfind ["lwt.tracing"] with
      | Ok _ -> Ok ()
      | Error _ ->
        Log.err (fun m ->
            m "lwt.tracing module not found. Hint:\
               opam pin add lwt 'https://github.com/mirage/lwt.git#tracing'") ;
        Error (`Msg "no lwt.tracing")

    method connect i _ _ = match get_target i with
      | `Virtio | `Ukvm -> failwith  "tracing is not currently implemented for solo5 targets"
      | `Unix | `MacOSX ->
        Fmt.strf
          "Lwt.return ())@.\
           let () = (@ \
             @[<v 2>  let buffer = MProf_unix.mmap_buffer ~size:%a %S in@ \
             let trace_config = MProf.Trace.Control.make buffer MProf_unix.timestamper in@ \
             MProf.Trace.Control.start trace_config@]"
          Key.serialize_call (Key.abstract key)
          unix_trace_file;
      | `Xen | `Qubes ->
        Fmt.strf
          "Lwt.return ())@.\
           let () = (@ \
             @[<v 2>  let trace_pages = MProf_xen.make_shared_buffer ~size:%a in@ \
             let buffer = trace_pages |> Io_page.to_cstruct |> Cstruct.to_bigarray in@ \
             let trace_config = MProf.Trace.Control.make buffer MProf_xen.timestamper in@ \
             MProf.Trace.Control.start trace_config;@ \
             MProf_xen.share_with (module Gnt.Gntshr) (module OS.Xs) ~domid:0 trace_pages@ \
             |> OS.Main.run@]"
          Key.serialize_call (Key.abstract key)

  end

(** Functoria devices *)

type info = Functoria_app.info
let noop = Functoria_app.noop
let info = Functoria_app.info
let app_info = Functoria_app.app_info ~type_modname:"Mirage_info" ()

let configure_main_libvirt_xml ~root ~name =
  let open Codegen in
  let file = Fpath.(v root / (name ^  "_libvirt") + "xml") in
  with_output file
    (fun oc () ->
       let fmt = Format.formatter_of_out_channel oc in
       append fmt "<!-- %s -->" (generated_header ());
       append fmt "<domain type='xen'>";
       append fmt "    <name>%s</name>" name;
       append fmt "    <memory unit='KiB'>262144</memory>";
       append fmt "    <currentMemory unit='KiB'>262144</currentMemory>";
       append fmt "    <vcpu placement='static'>1</vcpu>";
       append fmt "    <os>";
       append fmt "        <type arch='armv7l' machine='xenpv'>linux</type>";
       append fmt "        <kernel>%s/mir-%s.xen</kernel>" root name;
       append fmt "        <cmdline> </cmdline>";
       (* the libxl driver currently needs an empty cmdline to be able to
           start the domain on arm - due to this?
           http://lists.xen.org/archives/html/xen-devel/2014-02/msg02375.html *)
       append fmt "    </os>";
       append fmt "    <clock offset='utc' adjustment='reset'/>";
       append fmt "    <on_crash>preserve</on_crash>";
       append fmt "    <!-- ";
       append fmt "    You must define network and block interfaces manually.";
       append fmt "    See http://libvirt.org/drvxen.html for information about \
                   converting .xl-files to libvirt xml automatically.";
       append fmt "    -->";
       append fmt "    <devices>";
       append fmt "        <!--";
       append fmt "        The disk configuration is defined here:";
       append fmt "        http://libvirt.org/formatstorage.html.";
       append fmt "        An example would look like:";
       append fmt"         <disk type='block' device='disk'>";
       append fmt "            <driver name='phy'/>";
       append fmt "            <source dev='/dev/loop0'/>";
       append fmt "            <target dev='' bus='xen'/>";
       append fmt "        </disk>";
       append fmt "        -->";
       append fmt "        <!-- ";
       append fmt "        The network configuration is defined here:";
       append fmt "        http://libvirt.org/formatnetwork.html";
       append fmt "        An example would look like:";
       append fmt "        <interface type='bridge'>";
       append fmt "            <mac address='c0:ff:ee:c0:ff:ee'/>";
       append fmt "            <source bridge='br0'/>";
       append fmt "        </interface>";
       append fmt "        -->";
       append fmt "        <console type='pty'>";
       append fmt "            <target type='xen' port='0'/>";
       append fmt "        </console>";
       append fmt "    </devices>";
       append fmt "</domain>";
       R.ok ())
    "libvirt.xml"

let clean_main_libvirt_xml ~name =
  Bos.OS.File.delete Fpath.(v (name ^ "_libvirt") + "xml")

(* We generate an example .xl with common defaults, and a generic
   .xl.in which has @VARIABLES@ which must be substituted by sed
   according to the preferences of the system administrator.

   The common defaults chosen for the .xl file will be based on values
   detected from the build host. We assume that the .xl file will
   mainly be used by developers where build and deployment are on the
   same host. Production users should use the .xl.in and perform the
   appropriate variable substition.
*)

let detected_bridge_name =
  (* Best-effort guess of a bridge name stem to use. Note this
     inspects the build host and will probably be wrong if the
     deployment host is different.  *)
  match List.fold_left (fun sofar x -> match sofar with
      | None ->
        (* This is Linux-specific *)
        if Sys.file_exists (Printf.sprintf "/sys/class/net/%s0" x)
        then Some x
        else None
      | Some x -> Some x
    ) None [ "xenbr"; "br"; "virbr" ] with
  | Some x -> x
  | None -> "br"

module Substitutions = struct

  type v =
    | Name
    | Kernel
    | Memory
    | Block of block_t
    | Network of string

  let string_of_v = function
    | Name -> "@NAME@"
    | Kernel -> "@KERNEL@"
    | Memory -> "@MEMORY@"
    | Block b -> Printf.sprintf "@BLOCK:%s@" b.filename
    | Network n -> Printf.sprintf "@NETWORK:%s@" n

  let lookup ts v =
    if List.mem_assoc v ts
    then List.assoc v ts
    else string_of_v v

  let defaults i =
    let blocks = List.map (fun b ->
        Block b, Filename.concat (Info.root i) b.filename
      ) (Hashtbl.fold (fun _ v acc -> v :: acc) all_blocks []) in
    let networks = List.mapi (fun i n ->
        Network n, Printf.sprintf "%s%d" detected_bridge_name i
      ) !all_networks in [
      Name, (Info.name i);
      Kernel, Printf.sprintf "%s/mir-%s.xen" (Info.root i) (Info.name i);
      Memory, "256";
    ] @ blocks @ networks

end

let configure_main_xl ?substitutions ext i =
  let open Substitutions in
  let substitutions = match substitutions with
    | Some x -> x
    | None -> defaults i in
  let file = Fpath.(v (Info.root i) / (Info.name i) + ext) in
  let open Codegen in
  with_output file (fun oc () ->
      let fmt = Format.formatter_of_out_channel oc in
      append fmt "# %s" (generated_header ()) ;
      newline fmt;
      append fmt "name = '%s'" (lookup substitutions Name);
      append fmt "kernel = '%s'" (lookup substitutions Kernel);
      append fmt "builder = 'linux'";
      append fmt "memory = %s" (lookup substitutions Memory);
      append fmt "on_crash = 'preserve'";
      newline fmt;
      let blocks = List.map (fun b ->
          (* We need the Linux version of the block number (this is a
             strange historical artifact) Taken from
             https://github.com/mirage/mirage-block-xen/blob/
             a64d152586c7ebc1d23c5adaa4ddd440b45a3a83/lib/device_number.ml#L128 *)
          let rec string_of_int26 x =
            let high, low = x / 26 - 1, x mod 26 + 1 in
            let high' = if high = -1 then "" else string_of_int26 high in
            let low' =
              String.v 1 (fun _ -> char_of_int (low + (int_of_char 'a') - 1))
            in
            high' ^ low' in
          let vdev = Printf.sprintf "xvd%s" (string_of_int26 b.number) in
          let path = lookup substitutions (Block b) in
          Printf.sprintf "'format=raw, vdev=%s, access=rw, target=%s'" vdev path
        ) (Hashtbl.fold (fun _ v acc -> v :: acc) all_blocks []) in
      append fmt "disk = [ %s ]" (String.concat ~sep:", " blocks);
      newline fmt;
      let networks = List.map (fun n ->
          Printf.sprintf "'bridge=%s'" (lookup substitutions (Network n))
        ) !all_networks in
      append fmt "# if your system uses openvswitch then either edit \
                  /etc/xen/xl.conf and set";
      append fmt "#     vif.default.script=\"vif-openvswitch\"";
      append fmt "# or add \"script=vif-openvswitch,\" before the \"bridge=\" \
                  below:";
      append fmt "vif = [ %s ]" (String.concat ~sep:", " networks);
      R.ok ()) "xl file"

let clean_main_xl ~name ext = Bos.OS.File.delete Fpath.(v name + ext)

let configure_main_xe ~root ~name =
  let open Codegen in
  let file = Fpath.(v name + "xe") in
  with_output ~mode:0o755 file (fun oc () ->
      let fmt = Format.formatter_of_out_channel oc in
      append fmt "#!/bin/sh";
      append fmt "# %s" (generated_header ());
      newline fmt;
      append fmt "set -e";
      newline fmt;
      append fmt "# Dependency: xe";
      append fmt "command -v xe >/dev/null 2>&1 || { echo >&2 \"I require xe but \
                  it's not installed.  Aborting.\"; exit 1; }";
      append fmt "# Dependency: xe-unikernel-upload";
      append fmt "command -v xe-unikernel-upload >/dev/null 2>&1 || { echo >&2 \"I \
                  require xe-unikernel-upload but it's not installed.  Aborting.\"\
                  ; exit 1; }";
      append fmt "# Dependency: a $HOME/.xe";
      append fmt "if [ ! -e $HOME/.xe ]; then";
      append fmt "  echo Please create a config file for xe in $HOME/.xe which \
                  contains:";
      append fmt "  echo server='<IP or DNS name of the host running xapi>'";
      append fmt "  echo username=root";
      append fmt "  echo password=password";
      append fmt "  exit 1";
      append fmt "fi";
      newline fmt;
      append fmt "echo Uploading VDI containing unikernel";
      append fmt "VDI=$(xe-unikernel-upload --path %s/mir-%s.xen)" root name;
      append fmt "echo VDI=$VDI";
      append fmt "echo Creating VM metadata";
      append fmt "VM=$(xe vm-create name-label=%s)" name;
      append fmt "echo VM=$VM";
      append fmt "xe vm-param-set uuid=$VM PV-bootloader=pygrub";
      append fmt "echo Adding network interface connected to xenbr0";
      append fmt "ETH0=$(xe network-list bridge=xenbr0 params=uuid --minimal)";
      append fmt "VIF=$(xe vif-create vm-uuid=$VM network-uuid=$ETH0 device=0)";
      append fmt "echo Atting block device and making it bootable";
      append fmt "VBD=$(xe vbd-create vm-uuid=$VM vdi-uuid=$VDI device=0)";
      append fmt "xe vbd-param-set uuid=$VBD bootable=true";
      append fmt "xe vbd-param-set uuid=$VBD other-config:owner=true";
      List.iter (fun b ->
          append fmt "echo Uploading data VDI %s" b.filename;
          append fmt "echo VDI=$VDI";
          append fmt "SIZE=$(stat --format '%%s' %s/%s)" root b.filename;
          append fmt "POOL=$(xe pool-list params=uuid --minimal)";
          append fmt "SR=$(xe pool-list uuid=$POOL params=default-SR --minimal)";
          append fmt "VDI=$(xe vdi-create type=user name-label='%s' \
                      virtual-size=$SIZE sr-uuid=$SR)" b.filename;
          append fmt "xe vdi-import uuid=$VDI filename=%s/%s" root b.filename;
          append fmt "VBD=$(xe vbd-create vm-uuid=$VM vdi-uuid=$VDI device=%d)"
            b.number;
          append fmt "xe vbd-param-set uuid=$VBD other-config:owner=true";
        ) (Hashtbl.fold (fun _ v acc -> v :: acc) all_blocks []);
      append fmt "echo Starting VM";
      append fmt "xe vm-start uuid=$VM";
      R.ok ())
    "xe file"


let clean_main_xe ~name = Bos.OS.File.delete Fpath.(v name + "xe")

let configure_makefile ~target ~opam_name =
  let open Codegen in
  let file = Fpath.(v "Makefile") in
  with_output file (fun oc () ->
      let fmt = Format.formatter_of_out_channel oc in
      append fmt "# %s" (generated_header ());
      newline fmt;
      let starget = Fmt.to_to_string Mirage_key.pp_target target in
      append fmt "OPAM  = opam\n\
                  \n\
                  .PHONY: all depend clean build\n\
                  all:: build\n\
                  \n\
                  depend::\n\
                  \t$(OPAM) pin add --no-action --yes %s .\n\
                  \t$(OPAM) install --yes --deps-only %s\n\
                  \t$(OPAM) pin remove --no-action %s\n\
                  \n\
                  build::\n\
                  \tmirage build -t %s\n\
                  \n\
                  clean::\n\
                  \tmirage clean -t %s\n"
        opam_name opam_name opam_name starget starget;
      newline fmt;
      append fmt "-include Makefile.user";
      R.ok ())
    "Makefile"

let clean_makefile () = Bos.OS.File.delete Fpath.(v "Makefile")

let fn = Fpath.(v "myocamlbuild.ml")

let configure_myocamlbuild () =
  Bos.OS.File.exists fn >>= fun is ->
  if is then
    R.ok ()
  else
    Bos.OS.File.write fn ""

let clean_myocamlbuild () =
  Bos.OS.File.read fn >>= fun contents ->
  if String.length contents = 0 then
    Bos.OS.File.delete fn
  else
    R.ok ()

let configure_opam ~name ~target info =
  let open Codegen in
  let file = Fpath.(v name + "opam") in
  with_output file (fun oc () ->
      let fmt = Format.formatter_of_out_channel oc in
      append fmt "# %s" (generated_header ());
      Info.opam ~name fmt info;
      append fmt "build: [ \"mirage\" \"build\" \"-t %a\" ]" Key.pp_target target;
      R.ok ())
    "opam file"

let clean_opam ~name = Bos.OS.File.delete Fpath.(v name + "opam")

let unikernel_name target name =
  let target = Fmt.strf "%a" Key.pp_target target in
  String.concat ~sep:"-" ["mirage" ; "unikernel" ; name ; target]

let configure i =
  let name = Info.name i in
  let root = Info.root i in
  let ctx = Info.context i in
  let target = Key.(get ctx target) in
  Log.info (fun m -> m "Configuring for target: %a" Key.pp_target target);
  let opam_name = unikernel_name target name in
  match
    Bos.OS.Dir.with_current Fpath.(v root) (fun () ->
        (match target with
         | `Xen | `Qubes ->
           configure_main_xl "xl" i >>= fun () ->
           configure_main_xl ~substitutions:[] "xl.in" i >>= fun () ->
           configure_main_xe ~root ~name >>= fun () ->
           configure_main_libvirt_xml ~root ~name
         | _ -> R.ok ()) >>= fun () ->
        configure_myocamlbuild () >>= fun () ->
        configure_opam ~target ~name:opam_name i >>= fun () ->
        configure_makefile ~target ~opam_name) ()
  with
  | Ok a -> a
  | Error _ -> R.error_msg "couldn't access root directory"

let compile libs warn_error target =
  let tags =
    [ Printf.sprintf "predicate(%s)" (backend_predicate target);
      "warn(A-4-41-42-44)"; "color(always)"; "debug"; "bin_annot";
      "strict_sequence"; "principal"; "safe_string" ] @
    (if warn_error then ["warn_error(+1..49)"] else []) @
    match target with
    | `MacOSX -> ["thread"] | _ -> []
  and pkgs = String.concat ~sep:"," libs
  and flags =
    let dontlink = ["unix"; "str"; "num"; "threads"] in
    let link = match target with
      | `Xen | `Qubes | `Virtio | `Ukvm ->
        String.concat ~sep:",-dontlink," (""::dontlink)
      | _ -> ""
    in
    Bos.Cmd.of_list [ "-cflag" ; "-g" ; "-lflags" ; ("-g,-linkpkg" ^ link) ]
  in
  let tags = String.concat ~sep:"," tags
  and tag_line = "<static*.*>: warn(-32-34)"
  and result = match target with
    | `Unix | `MacOSX -> "main.native"
    | _ -> "main.native.o"
  in
  let cmd = Bos.Cmd.(v "ocamlbuild" % "-use-ocamlfind" %
                     "-classic-display" %
                     "-tags" % tags %
                     "-pkgs" % pkgs %%
                     flags %
                     "-tag-line" % tag_line %
                     "-X" %  "_build-ukvm" %
                     result)
  in
  Log.info (fun m -> m "executing %a" Bos.Cmd.pp cmd);
  Bos.OS.Cmd.run cmd

(* Implement something similar to the @name/file extended names of findlib. *)
let rec expand_name ~lib param =
  match String.cut param ~sep:"@" with
  | None -> param
  | Some (prefix, name) -> match String.cut name ~sep:"/" with
    | None              -> prefix ^ Fpath.(to_string (v lib / name))
    | Some (name, rest) ->
      let rest = expand_name ~lib rest in
      prefix ^ Fpath.(to_string (v lib / name / rest))

let opam_prefix =
  let cmd = Bos.Cmd.(v "opam" % "config" % "var" % "prefix") in
  lazy (Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.out_string >>| fst)

(* Invoke pkg-config and return output if successful. *)
let pkg_config pkgs args =
  Lazy.force opam_prefix >>= fun prefix ->
  (* the order here matters (at least for ancient 0.26, distributed with
       ubuntu 14.04 versions): use share before lib! *)
  let var = "PKG_CONFIG_PATH"
  and value = Printf.sprintf "%s/share/pkgconfig:%s/lib/pkgconfig" prefix prefix
  in
  Bos.OS.Env.set_var var (Some value) >>= fun () ->
  let cmd = Bos.Cmd.(v "pkg-config" % pkgs %% of_list args) in
  Bos.OS.Cmd.run_out cmd |> Bos.OS.Cmd.out_string >>| fun (data, _) ->
  String.cuts ~sep:" " data

(* Get the linker flags for any extra C objects we depend on.
 * This is needed when building a Xen/Solo5 image as we do the link manually. *)
let extra_c_artifacts target pkgs =
  Lazy.force opam_prefix >>= fun prefix ->
  let lib = prefix ^ "/lib" in
  let format = Printf.sprintf "%%d\t%%(%s_linkopts)" target
  and predicates = "native"
  in
  query_ocamlfind ~recursive:true ~format ~predicates pkgs >>= fun data ->
  let r = List.fold_left (fun acc line ->
      match String.cut line ~sep:"\t" with
      | None -> acc
      | Some (dir, ldflags) ->
        if ldflags <> "" then begin
          let ldflags = String.cuts ldflags ~sep:" " in
          let ldflags = List.map (expand_name ~lib) ldflags in
          acc @ ("-L" ^ dir) :: ldflags
        end else
          acc
    ) [] data
  in
  R.ok r

let static_libs pkg_config_deps = pkg_config pkg_config_deps [ "--static" ; "--libs" ]

let ldflags pkg = pkg_config pkg ["--variable=ldflags"]

let link info name target =
  let libs = Info.libraries info
  and name = "mir-" ^ name
  in
  match target with
  | `Unix | `MacOSX ->
    Bos.OS.Cmd.run Bos.Cmd.(v "ln" % "-nfs" % "_build/main.native" % name) >>= fun () ->
    Ok name
  | `Xen | `Qubes ->
    extra_c_artifacts "xen" libs >>= fun c_artifacts ->
    static_libs "mirage-xen" >>= fun static_libs ->
    let linker = Bos.Cmd.(v "ld" % "-d" % "-static" % "-nostdlib" % "_build/main.native.o" %% of_list c_artifacts %% of_list static_libs) in
    let out = name ^ ".xen" in
    Bos.OS.Cmd.run_out Bos.Cmd.(v "uname" % "-m") |> Bos.OS.Cmd.out_string >>= fun (machine, _) ->
    if String.is_prefix ~affix:"arm" machine then begin
      (* On ARM:
         - we must convert the ELF image to an ARM boot executable zImage,
           while on x86 we leave it as it is.
         - we need to link libgcc.a (otherwise we get undefined references to:
           __aeabi_dcmpge, __aeabi_dadd, ...) *)
      Bos.OS.Cmd.run_out Bos.Cmd.(v "gcc" % "-print-libgcc-file-name") |> Bos.OS.Cmd.out_string >>= fun (libgcc, _) ->
      let link = Bos.Cmd.(linker % libgcc % "-o" % (name ^ ".elf")) in
      Log.info (fun m -> m "linking with %a" Bos.Cmd.pp link);
      Bos.OS.Cmd.run link >>= fun () ->
      Bos.OS.Cmd.run Bos.Cmd.(v "objcopy" % "-O" % "binary" % (name ^ ".elf") % out) >>= fun () ->
      Ok out
    end else begin
      let link = Bos.Cmd.(linker % "-o" % out) in
      Log.info (fun m -> m "linking with %a" Bos.Cmd.pp link);
      Bos.OS.Cmd.run link >>= fun () ->
      Ok out
    end
  | `Virtio ->
    extra_c_artifacts "freestanding" libs >>= fun c_artifacts ->
    static_libs "mirage-solo5" >>= fun static_libs ->
    ldflags "solo5-kernel-virtio" >>= fun ldflags ->
    let out = name ^ ".virtio" in
    let linker = Bos.Cmd.(v "ld" %% of_list ldflags % "_build/main.native.o" %% of_list c_artifacts %% of_list static_libs % "-o" % out) in
    Log.info (fun m -> m "linking with %a" Bos.Cmd.pp linker);
    Bos.OS.Cmd.run linker >>= fun () ->
    Ok out
  | `Ukvm ->
    extra_c_artifacts "freestanding" libs >>= fun c_artifacts ->
    static_libs "mirage-solo5" >>= fun static_libs ->
    ldflags "solo5-kernel-ukvm" >>= fun ldflags ->
    let out = name ^ ".ukvm" in
    let linker = Bos.Cmd.(v "ld" %% of_list ldflags % "_build/main.native.o" %% of_list c_artifacts %% of_list static_libs % "-o" % out) in
    let ukvm_mods =
      let ukvm_filter = function
        | "mirage-net-solo5" -> "net"
        | "mirage-block-solo5" -> "blk"
        | _ -> ""
      in
      List.map ukvm_filter libs
    in
    pkg_config "solo5-kernel-ukvm" ["--variable=libdir"] >>= function
    | [ libdir ] ->
      Bos.OS.Cmd.run Bos.Cmd.(v "ukvm-configure" % (libdir ^ "/src/ukvm") %% of_list ukvm_mods) >>= fun () ->
      Bos.OS.Cmd.run Bos.Cmd.(v "make" % "-f" % "Makefile.ukvm" % "ukvm-bin") >>= fun () ->
      Log.info (fun m -> m "linking with %a" Bos.Cmd.pp linker);
      Bos.OS.Cmd.run linker >>= fun () ->
      Ok out
    | _ -> R.error_msg "pkg-config solo5-kernel-ukvm --variable=libdir failed"

let build i =
  let name = Info.name i in
  let ctx = Info.context i in
  let warn_error = Key.(get ctx warn_error) in
  let target = Key.(get ctx target) in
  let libs = Info.libraries i in
  check_entropy libs >>= fun () ->
  compile libs warn_error target >>= fun () ->
  link i name target >>| fun out ->
  Log.info (fun m -> m "Build succeeded: %s" out)

let clean i =
  let name = Info.name i in
  let ctx = Info.context i in
  let target = Key.(get ctx target) in
  clean_main_xl ~name "xl" >>= fun () ->
  clean_main_xl ~name "xl.in" >>= fun () ->
  clean_main_xe ~name >>= fun () ->
  clean_main_libvirt_xml ~name >>= fun () ->
  clean_myocamlbuild () >>= fun () ->
  clean_makefile () >>= fun () ->
  clean_opam ~name:(unikernel_name target name) >>= fun () ->
  Bos.OS.File.delete Fpath.(v "main.native.o") >>= fun () ->
  Bos.OS.File.delete Fpath.(v "main.native") >>= fun () ->
  Bos.OS.File.delete Fpath.(v ("mir-" ^ name)) >>= fun () ->
  Bos.OS.File.delete Fpath.(v ("mir-" ^ name) + "xen") >>= fun () ->
  Bos.OS.File.delete Fpath.(v ("mir-" ^ name) + "elf") >>= fun () ->
  Bos.OS.File.delete Fpath.(v ("mir-" ^ name) + "virtio") >>= fun () ->
  Bos.OS.File.delete Fpath.(v ("mir-" ^ name) + "ukvm") >>= fun () ->
  Bos.OS.File.delete Fpath.(v "Makefile.ukvm") >>= fun () ->
  Bos.OS.Dir.delete ~recurse:true Fpath.(v "_build-ukvm") >>= fun () ->
  Bos.OS.File.delete Fpath.(v "ukvm-bin")

module Project = struct
  let name = "mirage"
  let version = "%%VERSION%%"
  let prelude =
    "open Lwt.Infix\n\
     let return = Lwt.return\n\
     let run = OS.Main.run"

  let create jobs = impl @@ object
      inherit base_configurable
      method ty = job
      method name = "mirage"
      method module_name = "Mirage_runtime"
      method keys = [
        Key.(abstract target);
        Key.(abstract warn_error);
      ]

      method packages =
        let l = [
          (* XXX: use %%VERSION_NUM%% here instead of hardcoding a version? *)
          package "lwt";
          package ~ocamlfind:[] "mirage-types-lwt";
          package ~sublibs:["lwt"] ~min:"3.0.0"  "mirage-types";
          package ~min:"3.0.0" "mirage-runtime" ;
          package ~build:true "ocamlfind" ;
          package ~build:true "ocamlbuild" ;
        ]
        in
        Key.match_ Key.(value target) @@ function
        | `Xen | `Qubes -> package "mirage-xen" :: l
        | `Virtio -> package ~ocamlfind:[] "solo5-kernel-virtio" :: package "mirage-solo5" :: l
        | `Ukvm -> package ~ocamlfind:[] "solo5-kernel-ukvm" :: package "mirage-solo5" :: l
        | `Unix | `MacOSX -> package "mirage-unix" :: l

      method build = build
      method configure = configure
      method clean = clean
      method connect _ _mod _names = "Lwt.return_unit"
      method deps = List.map abstract jobs
    end

end

include Functoria_app.Make (Project)

(** {Custom registration} *)

let (++) acc x = match acc, x with
  | _       , None   -> acc
  | None    , Some x -> Some [x]
  | Some acc, Some x -> Some (acc @ [x])

(* TODO: ideally we'd combine these *)
let qrexec_init = match_impl Key.(value target) [
  `Qubes, qrexec_qubes;
] ~default:Functoria_app.noop

let gui_init = match_impl Key.(value target) [
  `Qubes, gui_qubes;
] ~default:Functoria_app.noop

let register
    ?(argv=default_argv) ?tracing ?(reporter=default_reporter ())
    ?keys ?(packages=[])
    name jobs =
  let argv = Some (Functoria_app.keys argv) in
  let reporter = if reporter == no_reporter then None else Some reporter in
  let qubes_init = Some [qrexec_init; gui_init] in
  let init = qubes_init ++ argv ++ reporter ++ tracing in
  register ?keys ~packages ?init name jobs
