(* TEST

* tsan
** native

ocamlopt_flags = "-tsan"
include unix
set TSAN_OPTIONS="detect_deadlocks=0"

*)

(* In this test, there is in fact no data race, but TSan will report a false
   positive. This is because here, the happens-before relation between the
   write to [v] and the read of [v] comes from the fact that [t2] will only
   read after [v_modified] is true. But this information is not available to
   the TSan runtime. The only events “seen” by TSan are:
   - [t1] writes to [v.x]
   - [t1] atomically writes to [v_modified]
   - [t2] atomically reads from [v_modified]
   - [t2] reads from [v.x]
   This information alone is not sufficient to establish a happens-before
   relation between the two accesses to [v.x].
*)

type t = { mutable x : int }

let v = { x = 0 }

let v_modified = Atomic.make false

let () =
  let t1 =
    Domain.spawn (fun () ->
        v.x <- 10;
        Atomic.set v_modified true;
        Unix.sleepf 0.1)
  in
  let t2 =
    Domain.spawn (fun () ->
        while not (Atomic.get v_modified) do () done;
        ignore (Sys.opaque_identity v.x);
        Unix.sleepf 0.1)
  in
  Domain.join t1;
  Domain.join t2
