open Mach

let cons_tsan_func_entry instr =
  let retaddr = Reg.create Cmm.Int in
    instr_cons (Iop Ireturn_addr) [| |] [| retaddr |] @@
    instr_cons
      (Iop (Iextcall
          {func = "__tsan_func_entry";
           ty_res = Cmm.typ_void;
           ty_args = [XInt];
           alloc = false;
           stack_ofs = 0 }))
      [| retaddr |]
      [| |]
      instr

let cons_tsan_func_exit instr =
  let zero = Reg.create Cmm.Int in
  instr_cons
    (Iop (Iconst_int 0n))
    [| |]
    [| zero |]
  @@ instr_cons
    (Iop (Iextcall
      { func = "__tsan_func_exit";
        ty_res = Cmm.typ_void;
        ty_args = [XInt];
        alloc = false;
        stack_ofs = 0 }))
    [| zero |]
    [| |]
    instr

let wrap_with_entry_exit (fun_body : instruction) =
  let fun_body = cons_tsan_func_entry fun_body in
  let [@tail_mod_cons] rec add_exit instr =
    match instr.desc with
    | Iop (Itailcall_ind | Itailcall_imm _) | Ireturn ->
        (cons_tsan_func_exit [@tailcall false]) instr
    | Iend -> instr
    | _ ->
        { instr with next = (add_exit instr.next) }
  in
  add_exit fun_body

let fundecl fun_ =
  { fun_ with fun_body = wrap_with_entry_exit fun_.fun_body }
