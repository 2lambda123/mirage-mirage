(*
 * Copyright (c) 2014 David Sheets <sheets@alum.mit.edu>
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

(** Mirage run-time utilities.

    {e Release %%VERSION%%} *)

(** {2 Log thresholds} *)

type log_threshold = [ `All | `Src of string ] * Logs.level option
(** The type for log threshold. A log level of [None] disables logging. *)

val set_level : default:Logs.level option -> log_threshold list -> unit
(** [set_level ~default l] set the log levels needed to have all of the log
    sources appearing in [l] be used. *)

module Arg : sig
  (** {2 Mirage command-line arguments} *)

  (** {2 Mirage command-line argument converters} *)

  val log_threshold : log_threshold Cmdliner.Arg.conv
  (** [log_threshold] converts log reporter threshold. *)

  val allocation_policy :
    [ `Next_fit | `First_fit | `Best_fit ] Cmdliner.Arg.conv
  (** [allocation_policy] converts allocation policy. *)
end

include module type of Functoria_runtime

(** {2 Registering scheduler hooks} *)

val at_exit : (unit -> unit Lwt.t) -> unit
(** [at_exit hook] registers [hook], which will be executed before the unikernel
    exits. The first hook registered will be executed last. *)

val at_enter_iter : (unit -> unit) -> unit
(** [at_enter_iter hook] registers [hook] to be executed at the beginning of
    each event loop iteration. The first hook registered will be executed last.

    If [hook] calls {!at_enter_iter} recursively, the new hook will run only on
    the next event loop iteration. *)

val at_leave_iter : (unit -> unit) -> unit
(** [at_leave_iter hook] registers [hook] to be executed at the end of each
    event loop iteration. See {!at_enter_iter} for details. *)

(** {2 Running hooks} *)

(** This is mainly for for developers implementing new targets. *)

val run_exit_hooks : unit -> unit Lwt.t
(** [run_exit_hooks ()] calls the sequence of hooks registered with {!at_exit}
    in sequence. *)

val run_enter_iter_hooks : unit -> unit
(** [run_enter_iter_hooks ()] calls the sequence of hooks registered with
    {!at_enter_iter} in sequence. *)

val run_leave_iter_hooks : unit -> unit
(** [run_leave_iter_hooks ()] call the sequence of hooks registered with
    {!at_leave_iter} in sequence. *)
