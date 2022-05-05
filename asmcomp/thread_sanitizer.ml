open Cmm
module V = Backend_var
module VP = Backend_var.With_provenance

type read_or_write = Read | Write

let init_code () =
  Cop (Cextcall ("__tsan_init", typ_void, [], false), [], Debuginfo.none)

let select_function read_or_write size =
  let acc_string = match read_or_write with Read -> "read" | Write -> "write" in
  match size with
  | Byte_unsigned
  | Byte_signed -> Printf.sprintf "__tsan_%s1" acc_string
  | Sixteen_unsigned
  | Sixteen_signed -> Printf.sprintf "__tsan_%s2" acc_string
  | Thirtytwo_unsigned
  | Thirtytwo_signed -> Printf.sprintf "__tsan_%s4" acc_string
  | Word_int
  | Word_val -> Printf.sprintf "__tsan_%s%d" acc_string (Sys.word_size / 8)
  | Single -> Printf.sprintf "__tsan_%s4" acc_string
  | Double -> Printf.sprintf "__tsan_%s8" acc_string

let instrument label body =
  let dbg = Debuginfo.none in
  let rec aux = function
    | Cop (Cload {memory_chunk; _} as load_op, args, dbginfo) ->
        let loc = List.hd args in
        let loc_id = VP.create (V.create_local "loc") in
        let loc_exp = Cvar (VP.var loc_id) in
        let args = loc_exp :: List.tl args in
        Clet (loc_id, loc,
          Csequence
            (Cop
              (Cextcall
                (select_function Read memory_chunk, typ_void, [], false),
                [loc_exp], dbg),
            Cop (load_op, args, dbginfo)))
    | Cop (Cstore(memory_chunk, init_or_assn), args, dbginfo) as c ->
        begin match init_or_assn with
        | Assignment ->
            let loc = List.hd args in
            let loc_id = VP.create (V.create_local "loc") in
        let loc_exp = Cvar (VP.var loc_id) in
            let args = loc_exp :: List.tl args in
            Clet (loc_id, loc,
              Csequence
                (Cop (Cextcall
                       (select_function Write memory_chunk, typ_void, [],
                         false),
                       [loc_exp], dbg),
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
        let cases = List.map (fun (nfail, ids, e, dbg) -> (nfail, ids, aux e, dbg)) cases in
        Ccatch (isrec, cases, aux body)
    | Cexit (ex, args) -> Cexit (ex, List.map aux args)
    | Cifthenelse (cond, t_dbg, t, f_dbg, f, dbg) ->
        Cifthenelse (aux cond, t_dbg, aux t, f_dbg, aux f, dbg)
    | Ctrywith (e, ex, handler, dbg) ->
        Ctrywith (aux e, ex, aux handler, dbg)
    | Cswitch (e, cases, handlers, dbg) ->
        let handlers = Array.map (fun (handler, handler_dbg) -> (aux handler, handler_dbg)) handlers in
        Cswitch(aux e, cases, handlers, dbg)
    (* no instrumentation *)
    | Cconst_int _ | Cconst_natint _ | Cconst_float _
    | Cconst_symbol _ | Cvar _ as c -> c
  in
  let entry_instr = Cop(
    Cextcall("__tsan_func_entry", typ_void, [], false),
    [Cconst_symbol(label, dbg)],
    dbg) in
  let exit_instr = Cop(
    Cextcall("__tsan_func_exit", typ_void, [], false),
    [],
    dbg) in
  Csequence(
    entry_instr,
    Csequence(aux body, exit_instr))
