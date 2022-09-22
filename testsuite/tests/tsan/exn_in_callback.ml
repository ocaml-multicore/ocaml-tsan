(* TEST

modules = "my_c_callback.c"

* tsan
** native

ocamlopt_flags = "-g -tsan -ccopt -fsanitize=thread -ccopt -O1 -ccopt -fno-omit-frame-pointer -ccopt -g"
include unix
set TSAN_OPTIONS="detect_deadlocks=0"

*)
exception ExnA
exception ExnB

external my_c_callback : unit -> unit = "my_c_callback"
(*external my_c_sleep : int -> unit = "my_c_sleep"*)

(*
module Printf = struct
 include Printf
 let printf fmt = Format.ikfprintf ignore Format.err_formatter fmt
end
*)

open Printf

let r = ref 0

let [@inline never] race () = ignore @@ !r

let [@inline never] i () =
  printf "entering i\n%!";
  printf "throwing Exn...\n%!";
  (*race ();*)
  ignore (raise ExnB);
  printf "leaving i\n%!"

let [@inline never] h () =
  printf "entering h\n%!";
  i ();
  (* try i () with
  | ExnA -> printf "caught an ExnA\n%!";
  *)
  printf "leaving h\n%!"

let _ = Callback.register "ocaml_h" h

let [@inline never] g () =
  printf "entering g\n%!";
  printf "calling C code\n%!";
  my_c_callback ();
  printf "back from C code\n%!";
  printf "leaving g\n%!"

let [@inline never] f () =
  printf "entering f\n%!";
  race ();
  (try g () with
  | ExnB ->
    printf "caught an ExnB\n%!";
    Printexc.print_backtrace stdout);
  printf "leaving f\n%!"

let () =
  let d = Domain.spawn (fun () -> Unix.sleep 1; r := 1) in
  f (); Unix.sleep 1;
  Domain.join d
