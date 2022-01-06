open Cmm

let select_function read_or_write size =
  let acc_string = if read_or_write then "read" else "write" in
  match size with
  | Byte_unsigned
  | Byte_signed -> Printf.sprintf "__tsan_%s1" acc_string
  | Sixteen_unsigned
  | Sixteen_signed -> Printf.sprintf "__tsan_%s4" acc_string
  | Thirtytwo_unsigned
  | Thirtytwo_signed -> Printf.sprintf "__tsan_%s8" acc_string
  | Word_int
  | Word_val -> Printf.sprintf "__tsan_%s16" acc_string
  | Single -> Printf.sprintf "__tsan_%s8" acc_string
  | Double -> Printf.sprintf "__tsan_%s16" acc_string

let instrument label body =
  let dbg = Debuginfo.none in
  let rec aux = function
    | Cop (Cload {memory_chunk; }, args, _) as c ->
        Csequence(Cop(Cextcall(select_function true memory_chunk, typ_void, [], false),
        [List.hd args], dbg), c)
    | Cop (Cstore(memory_chunk, init_or_assn), args, _) as c ->
        begin match init_or_assn with
        | Assignment -> 
            Csequence(Cop(Cextcall(select_function false memory_chunk, typ_void, [], false),
            [List.hd args], dbg), c)
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
    | Cconst_symbol _ | Cvar _ as c -> c in
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
