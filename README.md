[![Build](https://github.com/OlivierNicole/ocaml-tsan/actions/workflows/build.yml/badge.svg)](https://github.com/OlivierNicole/ocaml-tsan/actions/workflows/build.yml)

ThreadSanitizer support for OCaml 5
===================================

ThreadSanitizer is an effective approach to locate data races in concurrent code bases. This is an experimental extension of the OCaml compiler to add ThreadSanitizer support to OCaml 5.0.

Trying it out
-------------

**The current prototype is experimental; in addition, its interface is subject to changes.**

Install the compiler with ThreadSanitizer instrumentation in a new opam switch.
```
opam update
opam switch create tsan --empty
eval $(opam env --switch=tsan)
opam repo add alpha git+https://github.com/kit-ty-kate/opam-alpha-repository.git
opam pin add ocaml-variants.5.1.0+tsan git+https://github.com/OlivierNicole/ocaml-tsan
```

Then, to run your programs with ThreadSanitizer instrumentation, you need to pass the `-tsan` options to `ocamlopt` to instrument the generated executables and libraries.
If you link against C files, those can be (optionally) instrumented to detect data races in them as well, by passing `-fsanitize=thread` to GCC or clang.

If you use Dune, these settings can be grouped in a Dune profile by adding the following to your `dune-workspace`:
```
(env
 (tsan
  (ocamlopt_flags (:standard -tsan))
  (c_flags -fsanitize=thread)))
```
Then you only need to select this profile, e.g. `dune exec --profile tsan myexecutable.exe` or `dune runtest --profile tsan` (or set the profile in your `dune-workspace` file).

Examples
--------

### A simple race

The simplest of data races can be created by having two accesses to the same mutable location, one of them being a write:
```ocaml
type t = { mutable x : int }

let v = { x = 0 }

let () =
  let t1 = Domain.spawn (fun () -> v.x <- 10; Unix.sleep 1) in
  let t2 = Domain.spawn (fun () -> ignore (Sys.opaque_identity v.x); Unix.sleep 1) in
  Domain.join t1;
  Domain.join t2
```
The `Sys.opaque_identity` is here to prevent the compiler from optimizing away the read of `v.x`.

Running this program with ThreadSanitizer instrumentation will output the following report:
```
WARNING: ThreadSanitizer: data race (pid=502344)
  Read of size 8 at 0x7fc0b15fe458 by thread T4 (mutexes: write M0):
    #0 camlDune__exe__Simple_race__fun_600 /workspace_root/simple_race.ml:7 (simple_race.exe+0x51e9b1)
    #1 caml_callback ??:? (simple_race.exe+0x5777f0)
    #2 domain_thread_func domain.c:? (simple_race.exe+0x57b8fc)

  Previous write of size 8 at 0x7fc0b15fe458 by thread T1 (mutexes: write M1):
    #0 camlDune__exe__Simple_race__fun_596 /workspace_root/simple_race.ml:6 (simple_race.exe+0x51e971)
    #1 caml_callback ??:? (simple_race.exe+0x5777f0)
    #2 domain_thread_func domain.c:? (simple_race.exe+0x57b8fc)

  Mutex M0 (0x0000019c9598) created at:
    #0 pthread_mutex_init ??:? (simple_race.exe+0x488344)
    #1 caml_plat_mutex_init ??:? (simple_race.exe+0x5a83e2)
    #2 caml_init_domains ??:? (simple_race.exe+0x57a6e9)
    #3 caml_init_gc ??:? (simple_race.exe+0x58da25)
    #4 caml_startup_common ??:? (simple_race.exe+0x5b9b15)
    #5 caml_main ??:? (simple_race.exe+0x5b9d0b)
    #6 main ??:? (simple_race.exe+0x59bfb9)

  Mutex M1 (0x0000019c9480) created at:
    #0 pthread_mutex_init ??:? (simple_race.exe+0x488344)
    #1 caml_plat_mutex_init ??:? (simple_race.exe+0x5a83e2)
    #2 caml_init_domains ??:? (simple_race.exe+0x57a6e9)
    #3 caml_init_gc ??:? (simple_race.exe+0x58da25)
    #4 caml_startup_common ??:? (simple_race.exe+0x5b9b15)
    #5 caml_main ??:? (simple_race.exe+0x5b9d0b)
    #6 main ??:? (simple_race.exe+0x59bfb9)

  Thread T4 (tid=502383, running) created by main thread at:
    #0 pthread_create ??:? (simple_race.exe+0x463f7f)
    #1 caml_domain_spawn ??:? (simple_race.exe+0x57b396)
    #2 caml_c_call ??:? (simple_race.exe+0x5ba27e)
    #3 caml_main ??:? (simple_race.exe+0x5b9d0b)
    #4 main ??:? (simple_race.exe+0x59bfb9)

  Thread T1 (tid=502380, running) created by main thread at:
    #0 pthread_create ??:? (simple_race.exe+0x463f7f)
    #1 caml_domain_spawn ??:? (simple_race.exe+0x57b396)
    #2 caml_c_call ??:? (simple_race.exe+0x5ba27e)
    #3 caml_main ??:? (simple_race.exe+0x5b9d0b)
    #4 main ??:? (simple_race.exe+0x59bfb9)

SUMMARY: ThreadSanitizer: data race /workspace_root/simple_race.ml:7 in camlDune__exe__Simple_race__fun_600
==================
ThreadSanitizer: reported 1 warnings
```
If the mutable field is replaced with an `Atomic` reference, the warning disappears:
```ocaml
let v = Atomic.make 0

let () =
  let t1 = Domain.spawn (fun () -> Atomic.set v 10; Unix.sleep 1) in
  let t2 = Domain.spawn (fun () ->
      ignore (Sys.opaque_identity (Atomic.get v)); Unix.sleep 1) in
  Domain.join t1;
  Domain.join t2
```

### Synchronization using an atomic variable

Synchronizing the two accesses above by busy-waiting on an atomic boolean will be detected by ThreadSanitizer and no data race will be reported:
```ocaml
type t = { mutable x : int }

let v = { x = 0 }

let v_modified = Atomic.make false

let () =
  let t1 =
    Domain.spawn (fun () ->
        v.x <- 10;
        Atomic.set v_modified true;
        Unix.sleep 1)
  in
  let t2 =
    Domain.spawn (fun () ->
        while not (Atomic.get v_modified) do () done;
        ignore (Sys.opaque_identity v.x);
        Unix.sleep 1)
  in
  Domain.join t1;
  Domain.join t2
```
More efficiently, such synchronization can be implemented using a `Mutex.t` with the same result.


Background
----------

There are two components to ThreadSanitizer (TSan):
1. **A run-time library** to track accesses to shared data and report races
2. **Compiler instrumentation** that emits calls to the run-time library

Internally the run-time library associates with each word of application memory at least 2 “shadow words”. Each shadow word contains information about a recent memory access to that word, including a “scalar clock”. Those clocks serve to establish a happens-before (HB) relation, i.e. an event orderings that we are certain of.

This information is maintained as a “shadow state” in a separate memory region, and updated at every (instrumented) memory access.
A data race is reported every time two memory accesses are made to overlapping memory regions, and:
- one of them is a write, and
- there is no established happens-before relation between them.
More information about TSan's algorithm on [their wiki](https://github.com/google/sanitizers/wiki/ThreadSanitizerAlgorithm).

The run-time library is reusable across different programming languages (C,C++,Go, ...).


Status
------

The ThreadSanitizer support in OCaml 5.0 is still an ongoing effort. For more information on the status of this work, see [the dedicated wiki page](https://github.com/OlivierNicole/ocaml-tsan/wiki/Status-of-ThreadSanitizer-for-OCaml).


Caveats
-------

- TSan investigates *a particular execution* and therefore will not detect races in code paths that are not visited.
- TSan may still report false positives in some rare cases (see section 6.4 of the WBIA '09 paper below).


Resources
---------

- Anmol's blog post: https://anmolsahoo25.github.io/blog/thread-sanitizer-ocaml/
- Clang/LLVM TSan documentation: https://clang.llvm.org/docs/ThreadSanitizer.html
- Google Sanitizer wiki:
  - TSan C/C++ Manual: https://github.com/google/sanitizers/wiki/ThreadSanitizerCppManual
  - TSan Algorithm: https://github.com/google/sanitizers/wiki/ThreadSanitizerAlgorithm
- Slides from GCC Cauldron 2012: https://gcc.gnu.org/wiki/cauldron2012?action=AttachFile&do=get&target=kcc.pdf
- Papers
  - Serebryany and Iskhodzhanov: *ThreadSanitizer – data race detection in practice*, WBIA'09 <https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/35604.pdf>. Note that the algorithm presented in this paper is not the one used in the new version of TSan.
  - Chabby and Ramanathan: *A Study of Real-World Data Races in Golang*, PLDI'22 https://arxiv.org/pdf/2204.00764.pdf
  - Ahmad et al.: *Kard: Lightweight Data Race Detection with Per-Thread
Memory Protection*, ASPLOS'21 https://web.ics.purdue.edu/~ahmad37/papers/ahmad-kard.pdf
- ThreadSanitizer Google group: https://groups.google.com/g/thread-sanitizer
