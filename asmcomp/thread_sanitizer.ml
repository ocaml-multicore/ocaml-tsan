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

open Asttypes
open Cmm
module V = Backend_var
module VP = Backend_var.With_provenance

type read_or_write = Read | Write

let init_code () =
  Cmm_helpers.return_unit Debuginfo.none @@
  Cop (Cextcall ("__tsan_init", typ_void, [], false), [], Debuginfo.none)

let bit_size memory_chunk =
  match memory_chunk with
  | Byte_unsigned
  | Byte_signed -> 8
  | Sixteen_unsigned
  | Sixteen_signed -> 16
  | Thirtytwo_unsigned
  | Thirtytwo_signed -> 32
  | Word_int
  | Word_val -> Sys.word_size
  | Single -> 32
  | Double -> 64

let select_function read_or_write memory_chunk =
  let bit_size = bit_size memory_chunk in
  let acc_string =
    match read_or_write with Read -> "read" | Write -> "write"
  in
  Printf.sprintf "__tsan_%s%d" acc_string (bit_size / 8)

module TSan_memory_order = struct
  (* Constants defined in the LLVM ABI *)
  (* TODO: Not sure whether it's an int, a nativeint or an int32 *)
  let acquire = Cconst_int (2, Debuginfo.none)
  (*let release = Cconst_int (3, Debuginfo.none)*)
end

let machtype_of_memory_chunk = function
  | Byte_unsigned
  | Byte_signed
  | Sixteen_unsigned
  | Sixteen_signed
  | Thirtytwo_unsigned
  | Thirtytwo_signed
  | Word_int -> typ_int
  | Word_val -> typ_val
  | Single
  | Double -> typ_float

let instrument label body =
  let dbg = Debuginfo.none in
  let rec aux = function
    | Cop (Cload {memory_chunk; mutability=Mutable; is_atomic=false} as load_op,
            args, dbginfo) ->
        (* Emit a call to [__tsan_readN] before the load *)
        let loc = List.hd args in
        let loc_id = VP.create (V.create_local "loc") in
        let loc_exp = Cvar (VP.var loc_id) in
        let args = loc_exp :: List.tl args in
        Clet (loc_id, loc,
          Csequence
            (Cmm_helpers.return_unit dbg (Cop
              (Cextcall (select_function Read memory_chunk, typ_void,
                          [], false),
                [loc_exp], dbg)),
            Cop (load_op, args, dbginfo)))
    | Cop (Cload {memory_chunk; mutability=Mutable; is_atomic=true},
            [loc], dbginfo) ->
        (* Replace the atomic load with a call to [__tsan_atomicN_load] *)
        (* TODO: convince myself that this is safe *)
        let ret_typ = machtype_of_memory_chunk memory_chunk in
        Cop (Cextcall
               (Printf.sprintf "__tsan_atomic%d_load" (bit_size memory_chunk),
               ret_typ, [], false),
          [loc; TSan_memory_order.acquire], dbginfo)
    | Cop (Cload {memory_chunk=_; mutability=Mutable; is_atomic=_}, _ :: _, _) ->
        invalid_arg "instrument: wrong number of arguments for operation Cload"
    | Cop (Cstore(memory_chunk, init_or_assn), args, dbginfo) as c ->
        (* Emit a call to [__tsan_writeN] before the store *)
        begin match init_or_assn with
        | Assignment ->
            let loc = List.hd args in
            let loc_id = VP.create (V.create_local "loc") in
        let loc_exp = Cvar (VP.var loc_id) in
            let args = loc_exp :: List.tl args in
            Clet (loc_id, loc,
              Csequence
                (Cmm_helpers.return_unit dbg (Cop (Cextcall
                       (select_function Write memory_chunk, typ_void, [],
                         false),
                       [loc_exp], dbg)),
                Cop (Cstore (memory_chunk, init_or_assn), args, dbginfo)))
        | _ -> c
        end
    | Cop (op, es, dbg) -> Cop (op, List.map aux es, dbg)
    | Clet (v, e, body) -> Clet (v, aux e, aux body)
    | Clet_mut (v, k, e, body) -> Clet_mut (v, k, aux e, aux body)
    | Cphantom_let (v, e, body) -> Cphantom_let (v, e, aux body)
    | Cassign (v, e) -> Cassign (v, aux e)
    | Ctuple es -> Ctuple (List.map aux es)
    | Csequence(c1,c2) -> Csequence(aux c1, aux c2)
    | Ccatch (isrec, cases, body) ->
        let cases =
          List.map (fun (nfail, ids, e, dbg) -> (nfail, ids, aux e, dbg)) cases
        in
        Ccatch (isrec, cases, aux body)
    | Cexit (ex, args) -> Cexit (ex, List.map aux args)
    | Cifthenelse (cond, t_dbg, t, f_dbg, f, dbg) ->
        Cifthenelse (aux cond, t_dbg, aux t, f_dbg, aux f, dbg)
    | Ctrywith (e, ex, handler, dbg) ->
        Ctrywith (aux e, ex, aux handler, dbg)
    | Cswitch (e, cases, handlers, dbg) ->
        let handlers =
          handlers |> Array.map (fun (handler, handler_dbg) ->
                                  (aux handler, handler_dbg))
        in
        Cswitch(aux e, cases, handlers, dbg)
    (* no instrumentation *)
    | Cconst_int _ | Cconst_natint _ | Cconst_float _
    | Cconst_symbol _ | Cvar _ as c -> c
  in
  let entry_instr = Cmm_helpers.return_unit dbg @@
    Cop(
      Cextcall("__tsan_func_entry", typ_void, [], false),
      [Cconst_symbol(label, dbg)],
      dbg)
  in
  let exit_instr = Cmm_helpers.return_unit dbg @@
    Cop(
      Cextcall("__tsan_func_exit", typ_void, [], false),
      [],
      dbg)
  in
  let res_id = VP.create (V.create_local "res") in
  Csequence(
    entry_instr,
    Clet (res_id, aux body, Csequence(exit_instr, Cvar (VP.var res_id))))
