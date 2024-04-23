Configure the project for Unix:

  $ mirage configure -t unix
  $ ls . mirage/
  .:
  Makefile
  _build
  config.ml
  dist
  dune
  dune-project
  dune-workspace
  dune.build
  dune.config
  mirage
  
  mirage/:
  context
  dune-workspace.config
  main.ml
  random-unix.opam
  $ cat mirage/main.ml
  open Lwt.Infix
  let return = Lwt.return
  let run t = Unix_os.Main.run t ; exit
  0
  
  let delay__key = Mirage_runtime.register @@
  # 33 "lib/devices/runtime_arg.ml"
    Mirage_runtime.delay
  ;;
  
  let backtrace__key = Mirage_runtime.register @@
  # 34 "lib/devices/runtime_arg.ml"
    Mirage_runtime.backtrace
  ;;
  
  let randomize_hashtables__key = Mirage_runtime.register @@
  # 35 "lib/devices/runtime_arg.ml"
    Mirage_runtime.randomize_hashtables
  ;;
  
  let allocation_policy__key = Mirage_runtime.register @@
  # 36 "lib/devices/runtime_arg.ml"
    Mirage_runtime.allocation_policy
  ;;
  
  let minor_heap_size__key = Mirage_runtime.register @@
  # 37 "lib/devices/runtime_arg.ml"
    Mirage_runtime.minor_heap_size
  ;;
  
  let major_heap_increment__key = Mirage_runtime.register @@
  # 38 "lib/devices/runtime_arg.ml"
    Mirage_runtime.major_heap_increment
  ;;
  
  let space_overhead__key = Mirage_runtime.register @@
  # 39 "lib/devices/runtime_arg.ml"
    Mirage_runtime.space_overhead
  ;;
  
  let max_space_overhead__key = Mirage_runtime.register @@
  # 40 "lib/devices/runtime_arg.ml"
    Mirage_runtime.max_space_overhead
  ;;
  
  let gc_verbosity__key = Mirage_runtime.register @@
  # 41 "lib/devices/runtime_arg.ml"
    Mirage_runtime.gc_verbosity
  ;;
  
  let gc_window_size__key = Mirage_runtime.register @@
  # 42 "lib/devices/runtime_arg.ml"
    Mirage_runtime.gc_window_size
  ;;
  
  let custom_major_ratio__key = Mirage_runtime.register @@
  # 43 "lib/devices/runtime_arg.ml"
    Mirage_runtime.custom_major_ratio
  ;;
  
  let custom_minor_ratio__key = Mirage_runtime.register @@
  # 44 "lib/devices/runtime_arg.ml"
    Mirage_runtime.custom_minor_ratio
  ;;
  
  let custom_minor_max_size__key = Mirage_runtime.register @@
  # 45 "lib/devices/runtime_arg.ml"
    Mirage_runtime.custom_minor_max_size
  ;;
  
  let logs__key = Mirage_runtime.register @@
  # 158 "lib/devices/runtime_arg.ml"
    Mirage_runtime.logs
  ;;
  
  module Mirage_crypto_rng_mirage_make__10 = Mirage_crypto_rng_mirage.Make(Unix_os.Time)(Mclock)
  
  module App_make__11 = App.Make(Mirage_crypto_rng_mirage_make__10)
  
  let bootvar__1 = lazy (
  # 7 "lib/devices/argv.ml"
    Bootvar.argv ()
  );;
  # 84 "mirage/main.ml"
  
  let struct_end__2 = lazy (
    let __bootvar__1 = Lazy.force bootvar__1 in
    __bootvar__1 >>= fun _bootvar__1 ->
  # 47 "lib/functoria/job.ml"
    return Mirage_runtime.(with_argv (runtime_args ()) "random" _bootvar__1)
  );;
  # 92 "mirage/main.ml"
  
  let printexc__3 = lazy (
    let _backtrace = backtrace__key () in
  # 396 "lib/mirage.ml"
    return (Printexc.record_backtrace _backtrace)
  );;
  # 99 "mirage/main.ml"
  
  let hashtbl__4 = lazy (
    let _randomize_hashtables = randomize_hashtables__key () in
  # 405 "lib/mirage.ml"
    return (if _randomize_hashtables then Hashtbl.randomize ())
  );;
  # 106 "mirage/main.ml"
  
  let gc__5 = lazy (
    let _allocation_policy = allocation_policy__key () in
    let _minor_heap_size = minor_heap_size__key () in
    let _major_heap_increment = major_heap_increment__key () in
    let _space_overhead = space_overhead__key () in
    let _max_space_overhead = max_space_overhead__key () in
    let _gc_verbosity = gc_verbosity__key () in
    let _gc_window_size = gc_window_size__key () in
    let _custom_major_ratio = custom_major_ratio__key () in
    let _custom_minor_ratio = custom_minor_ratio__key () in
    let _custom_minor_max_size = custom_minor_max_size__key () in
  # 457 "lib/mirage.ml"
    return (
  let open Gc in
    let ctrl = get () in
    set ({ ctrl with allocation_policy = (match _allocation_policy with `Next_fit -> 0 | `First_fit -> 1 | `Best_fit -> 2);
    minor_heap_size = (match _minor_heap_size with None -> ctrl.minor_heap_size | Some x -> x);
    major_heap_increment = (match _major_heap_increment with None -> ctrl.major_heap_increment | Some x -> x);
    space_overhead = (match _space_overhead with None -> ctrl.space_overhead | Some x -> x);
    max_overhead = (match _max_space_overhead with None -> ctrl.max_overhead | Some x -> x);
    verbose = (match _gc_verbosity with None -> ctrl.verbose | Some x -> x);
    window_size = (match _gc_window_size with None -> ctrl.window_size | Some x -> x);
    custom_major_ratio = (match _custom_major_ratio with None -> ctrl.custom_major_ratio | Some x -> x);
    custom_minor_ratio = (match _custom_minor_ratio with None -> ctrl.custom_minor_ratio | Some x -> x);
    custom_minor_max_size = (match _custom_minor_max_size with None -> ctrl.custom_minor_max_size | Some x -> x) })
  )
  );;
  # 135 "mirage/main.ml"
  
  let mirage_runtime__6 = lazy (
    let _delay = delay__key () in
  # 302 "lib/mirage.ml"
    Unix_os.Time.sleep_ns (Duration.of_sec _delay)
  );;
  # 142 "mirage/main.ml"
  
  let mirage_logs__7 = lazy (
    let _logs = logs__key () in
  # 21 "lib/devices/reporter.ml"
    let reporter = Mirage_logs.create () in
    Mirage_runtime.set_level ~default:(Some Logs.Info) _logs;
    Logs.set_reporter reporter;
    Lwt.return reporter
  );;
  # 152 "mirage/main.ml"
  
  let unix_os_time__8 = lazy (
    return ()
  );;
  # 157 "mirage/main.ml"
  
  let mclock__9 = lazy (
    return ()
  );;
  # 162 "mirage/main.ml"
  
  let mirage_crypto_rng_mirage_make__10 = lazy (
    let __unix_os_time__8 = Lazy.force unix_os_time__8 in
    let __mclock__9 = Lazy.force mclock__9 in
    __unix_os_time__8 >>= fun _unix_os_time__8 ->
    __mclock__9 >>= fun _mclock__9 ->
  # 18 "lib/devices/random.ml"
    Mirage_crypto_rng_mirage_make__10.initialize (module Mirage_crypto_rng.Fortuna)
  );;
  # 172 "mirage/main.ml"
  
  let app_make__11 = lazy (
    let __mirage_crypto_rng_mirage_make__10 = Lazy.force mirage_crypto_rng_mirage_make__10 in
    __mirage_crypto_rng_mirage_make__10 >>= fun _mirage_crypto_rng_mirage_make__10 ->
  # 3 "config.ml"
    App_make__11.start _mirage_crypto_rng_mirage_make__10
  );;
  # 180 "mirage/main.ml"
  
  let mirage_runtime__12 = lazy (
    let __struct_end__2 = Lazy.force struct_end__2 in
    let __printexc__3 = Lazy.force printexc__3 in
    let __hashtbl__4 = Lazy.force hashtbl__4 in
    let __gc__5 = Lazy.force gc__5 in
    let __mirage_runtime__6 = Lazy.force mirage_runtime__6 in
    let __mirage_logs__7 = Lazy.force mirage_logs__7 in
    let __app_make__11 = Lazy.force app_make__11 in
    __struct_end__2 >>= fun _struct_end__2 ->
    __printexc__3 >>= fun _printexc__3 ->
    __hashtbl__4 >>= fun _hashtbl__4 ->
    __gc__5 >>= fun _gc__5 ->
    __mirage_runtime__6 >>= fun _mirage_runtime__6 ->
    __mirage_logs__7 >>= fun _mirage_logs__7 ->
    __app_make__11 >>= fun _app_make__11 ->
  # 384 "lib/mirage.ml"
    return ()
  );;
  # 200 "mirage/main.ml"
  
  let () =
    let t = Lazy.force struct_end__2 >>= fun _ ->
    Lazy.force printexc__3 >>= fun _ ->
    Lazy.force hashtbl__4 >>= fun _ ->
    Lazy.force gc__5 >>= fun _ ->
    Lazy.force mirage_runtime__6 >>= fun _ ->
    Lazy.force mirage_logs__7 >>= fun _ ->
    Lazy.force mirage_runtime__12 in
    run t
  ;;
  $ mirage clean


Configure the project for Xen:

  $ mirage configure -t xen
  $ ls . mirage/
  .:
  Makefile
  _build
  config.ml
  dist
  dune
  dune-project
  dune-workspace
  dune.build
  dune.config
  mirage
  
  mirage/:
  context
  dune-workspace.config
  main.ml
  manifest.json
  manifest.ml
  random-xen.opam
  random.xl
  random.xl.in
  random_libvirt.xml
  $ cat mirage/main.ml
  open Lwt.Infix
  let return = Lwt.return
  let run t = Xen_os.Main.run t ; exit
  0
  
  let delay__key = Mirage_runtime.register @@
  # 33 "lib/devices/runtime_arg.ml"
    Mirage_runtime.delay
  ;;
  
  let backtrace__key = Mirage_runtime.register @@
  # 34 "lib/devices/runtime_arg.ml"
    Mirage_runtime.backtrace
  ;;
  
  let randomize_hashtables__key = Mirage_runtime.register @@
  # 35 "lib/devices/runtime_arg.ml"
    Mirage_runtime.randomize_hashtables
  ;;
  
  let allocation_policy__key = Mirage_runtime.register @@
  # 36 "lib/devices/runtime_arg.ml"
    Mirage_runtime.allocation_policy
  ;;
  
  let minor_heap_size__key = Mirage_runtime.register @@
  # 37 "lib/devices/runtime_arg.ml"
    Mirage_runtime.minor_heap_size
  ;;
  
  let major_heap_increment__key = Mirage_runtime.register @@
  # 38 "lib/devices/runtime_arg.ml"
    Mirage_runtime.major_heap_increment
  ;;
  
  let space_overhead__key = Mirage_runtime.register @@
  # 39 "lib/devices/runtime_arg.ml"
    Mirage_runtime.space_overhead
  ;;
  
  let max_space_overhead__key = Mirage_runtime.register @@
  # 40 "lib/devices/runtime_arg.ml"
    Mirage_runtime.max_space_overhead
  ;;
  
  let gc_verbosity__key = Mirage_runtime.register @@
  # 41 "lib/devices/runtime_arg.ml"
    Mirage_runtime.gc_verbosity
  ;;
  
  let gc_window_size__key = Mirage_runtime.register @@
  # 42 "lib/devices/runtime_arg.ml"
    Mirage_runtime.gc_window_size
  ;;
  
  let custom_major_ratio__key = Mirage_runtime.register @@
  # 43 "lib/devices/runtime_arg.ml"
    Mirage_runtime.custom_major_ratio
  ;;
  
  let custom_minor_ratio__key = Mirage_runtime.register @@
  # 44 "lib/devices/runtime_arg.ml"
    Mirage_runtime.custom_minor_ratio
  ;;
  
  let custom_minor_max_size__key = Mirage_runtime.register @@
  # 45 "lib/devices/runtime_arg.ml"
    Mirage_runtime.custom_minor_max_size
  ;;
  
  let logs__key = Mirage_runtime.register @@
  # 158 "lib/devices/runtime_arg.ml"
    Mirage_runtime.logs
  ;;
  
  module Mirage_crypto_rng_mirage_make__10 = Mirage_crypto_rng_mirage.Make(Xen_os.Time)(Mclock)
  
  module App_make__11 = App.Make(Mirage_crypto_rng_mirage_make__10)
  
  let bootvar__1 = lazy (
  # 21 "lib/devices/argv.ml"
    Bootvar.argv ()
  );;
  # 84 "mirage/main.ml"
  
  let struct_end__2 = lazy (
    let __bootvar__1 = Lazy.force bootvar__1 in
    __bootvar__1 >>= fun _bootvar__1 ->
  # 47 "lib/functoria/job.ml"
    return Mirage_runtime.(with_argv (runtime_args ()) "random" _bootvar__1)
  );;
  # 92 "mirage/main.ml"
  
  let printexc__3 = lazy (
    let _backtrace = backtrace__key () in
  # 396 "lib/mirage.ml"
    return (Printexc.record_backtrace _backtrace)
  );;
  # 99 "mirage/main.ml"
  
  let hashtbl__4 = lazy (
    let _randomize_hashtables = randomize_hashtables__key () in
  # 405 "lib/mirage.ml"
    return (if _randomize_hashtables then Hashtbl.randomize ())
  );;
  # 106 "mirage/main.ml"
  
  let gc__5 = lazy (
    let _allocation_policy = allocation_policy__key () in
    let _minor_heap_size = minor_heap_size__key () in
    let _major_heap_increment = major_heap_increment__key () in
    let _space_overhead = space_overhead__key () in
    let _max_space_overhead = max_space_overhead__key () in
    let _gc_verbosity = gc_verbosity__key () in
    let _gc_window_size = gc_window_size__key () in
    let _custom_major_ratio = custom_major_ratio__key () in
    let _custom_minor_ratio = custom_minor_ratio__key () in
    let _custom_minor_max_size = custom_minor_max_size__key () in
  # 457 "lib/mirage.ml"
    return (
  let open Gc in
    let ctrl = get () in
    set ({ ctrl with allocation_policy = (match _allocation_policy with `Next_fit -> 0 | `First_fit -> 1 | `Best_fit -> 2);
    minor_heap_size = (match _minor_heap_size with None -> ctrl.minor_heap_size | Some x -> x);
    major_heap_increment = (match _major_heap_increment with None -> ctrl.major_heap_increment | Some x -> x);
    space_overhead = (match _space_overhead with None -> ctrl.space_overhead | Some x -> x);
    max_overhead = (match _max_space_overhead with None -> ctrl.max_overhead | Some x -> x);
    verbose = (match _gc_verbosity with None -> ctrl.verbose | Some x -> x);
    window_size = (match _gc_window_size with None -> ctrl.window_size | Some x -> x);
    custom_major_ratio = (match _custom_major_ratio with None -> ctrl.custom_major_ratio | Some x -> x);
    custom_minor_ratio = (match _custom_minor_ratio with None -> ctrl.custom_minor_ratio | Some x -> x);
    custom_minor_max_size = (match _custom_minor_max_size with None -> ctrl.custom_minor_max_size | Some x -> x) })
  )
  );;
  # 135 "mirage/main.ml"
  
  let mirage_runtime__6 = lazy (
    let _delay = delay__key () in
  # 302 "lib/mirage.ml"
    Xen_os.Time.sleep_ns (Duration.of_sec _delay)
  );;
  # 142 "mirage/main.ml"
  
  let mirage_logs__7 = lazy (
    let _logs = logs__key () in
  # 21 "lib/devices/reporter.ml"
    let reporter = Mirage_logs.create () in
    Mirage_runtime.set_level ~default:(Some Logs.Info) _logs;
    Logs.set_reporter reporter;
    Lwt.return reporter
  );;
  # 152 "mirage/main.ml"
  
  let xen_os_time__8 = lazy (
    return ()
  );;
  # 157 "mirage/main.ml"
  
  let mclock__9 = lazy (
    return ()
  );;
  # 162 "mirage/main.ml"
  
  let mirage_crypto_rng_mirage_make__10 = lazy (
    let __xen_os_time__8 = Lazy.force xen_os_time__8 in
    let __mclock__9 = Lazy.force mclock__9 in
    __xen_os_time__8 >>= fun _xen_os_time__8 ->
    __mclock__9 >>= fun _mclock__9 ->
  # 18 "lib/devices/random.ml"
    Mirage_crypto_rng_mirage_make__10.initialize (module Mirage_crypto_rng.Fortuna)
  );;
  # 172 "mirage/main.ml"
  
  let app_make__11 = lazy (
    let __mirage_crypto_rng_mirage_make__10 = Lazy.force mirage_crypto_rng_mirage_make__10 in
    __mirage_crypto_rng_mirage_make__10 >>= fun _mirage_crypto_rng_mirage_make__10 ->
  # 3 "config.ml"
    App_make__11.start _mirage_crypto_rng_mirage_make__10
  );;
  # 180 "mirage/main.ml"
  
  let mirage_runtime__12 = lazy (
    let __struct_end__2 = Lazy.force struct_end__2 in
    let __printexc__3 = Lazy.force printexc__3 in
    let __hashtbl__4 = Lazy.force hashtbl__4 in
    let __gc__5 = Lazy.force gc__5 in
    let __mirage_runtime__6 = Lazy.force mirage_runtime__6 in
    let __mirage_logs__7 = Lazy.force mirage_logs__7 in
    let __app_make__11 = Lazy.force app_make__11 in
    __struct_end__2 >>= fun _struct_end__2 ->
    __printexc__3 >>= fun _printexc__3 ->
    __hashtbl__4 >>= fun _hashtbl__4 ->
    __gc__5 >>= fun _gc__5 ->
    __mirage_runtime__6 >>= fun _mirage_runtime__6 ->
    __mirage_logs__7 >>= fun _mirage_logs__7 ->
    __app_make__11 >>= fun _app_make__11 ->
  # 384 "lib/mirage.ml"
    return ()
  );;
  # 200 "mirage/main.ml"
  
  let () =
    let t = Lazy.force struct_end__2 >>= fun _ ->
    Lazy.force printexc__3 >>= fun _ ->
    Lazy.force hashtbl__4 >>= fun _ ->
    Lazy.force gc__5 >>= fun _ ->
    Lazy.force mirage_runtime__6 >>= fun _ ->
    Lazy.force mirage_logs__7 >>= fun _ ->
    Lazy.force mirage_runtime__12 in
    run t
  ;;
  $ mirage clean
