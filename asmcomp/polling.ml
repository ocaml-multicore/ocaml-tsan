(**************************************************************************)
(*                                                                        *)
(*                                 OCaml                                  *)
(*                                                                        *)
(*             Xavier Leroy, projet Cristal, INRIA Rocquencourt           *)
(*                                                                        *)
(*   Copyright 1996 Institut National de Recherche en Informatique et     *)
(*     en Automatique.                                                    *)
(*                                                                        *)
(*   All rights reserved.  This file is distributed under the terms of    *)
(*   the GNU Lesser General Public License version 2.1, with the          *)
(*   special exception on linking described in the file LICENSE.          *)
(*                                                                        *)
(**************************************************************************)
open Mach
open Clflags

(* constants *)
let lmax = 500
let k = 6
let e = lmax/k
(* let r = lmax/k *)

let is_addr_live i = not (Reg.Set.is_empty (Reg.Set.filter (fun f -> f.typ = Cmm.Addr) i))
let _is_rax_live i = not (Reg.Set.is_empty (Reg.Set.filter (fun f -> f.loc = Reg.Reg 0) i))

let insert_poll_instr instr = 
    let poll_instr = 
        Iop (Ipoll)
    in
    { instr with desc = poll_instr ; next = instr ; res = [| |] }

let rec insert_poll_aux delta instr =
    let delta = match instr.desc with
        | Iend -> delta
        | Iop _ -> delta + 1
        | _ -> delta + 1
    in
    let next = match instr.desc with
        | Iend -> instr.next
        | _ ->
          if delta >= (lmax-1) then 
            (if (is_addr_live instr.live) then
                (insert_poll_aux delta instr.next)
            else
                (insert_poll_instr (insert_poll_aux 0 instr.next)))
          else
            insert_poll_aux delta instr.next
    in
    { instr with next }

let insert_poll fun_body =
    insert_poll_aux (lmax-e) fun_body

let fundecl f =
    let new_body =
      if !add_poll then
        insert_poll f.fun_body
      else
        f.fun_body
    in
      { f with fun_body = new_body }
