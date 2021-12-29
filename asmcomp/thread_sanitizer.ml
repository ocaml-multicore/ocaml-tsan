open Cmm

let instrument label body =
  let dbg = Debuginfo.none in
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
    Csequence(body, exit_instr))
