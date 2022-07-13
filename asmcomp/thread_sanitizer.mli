(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*                      Anmol Sahoo, Purdue University                    *)
(*                                                                        *)
(*   Copyright 2022 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)

(** Instrumentation of memory accesses using ThreadSanitizer for data race
    detection. This module contains an instrumentation pass on Cmm, where most
    of the instrumentation happens.
    Only, the function prologues and epilogues are instrumented at the assembly
    level (architecture-specific, due to the need to pass the return address)
    where calls are emitted to [__tsan_func_entry] and [__tsan_func_exit]. *)

(** Instrumentation of a {!Cmm.expression}. *)
val instrument : string -> Cmm.expression -> Cmm.expression

(** Call to [__tsan_init], which should be called at least once in the compiled
    program, before other [__tsan_*] API functions. Idempotent, i.e. can be
    called more than once without consequences. *)
val init_code : unit -> Cmm.expression
