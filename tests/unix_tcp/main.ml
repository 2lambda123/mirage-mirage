module OS=Unix
module Channel=OS.Channel
module IO=Io.Channel.IO(OS.Channel)
open Lwt
open Mlnet.Types

let main () =
(*
  let connect_thread =
    let sa = Channel.TCP (ipv4_localhost, 8080) in
    lwt ic,oc = IO.open_connection sa in
    for_lwt i = 0 to 10 do
     IO.write_line oc ("foo bar " ^ (string_of_int i)) >>
     (print_endline "wrote"; return ())
    done 
  in
*)
  let lsa = Channel.TCP (ipv4_localhost, 8081) in
  let listen_thread = Channel.listen (fun c ->
    print_endline "new connection";
    OS.Time.sleep 2. >>
    let msg = "byebye" in
    lwt _ = Channel.write c msg 0 (String.length msg) in
    return ()
  ) lsa in
  join [ listen_thread ]

let _ = OS.Main.run (main ())

