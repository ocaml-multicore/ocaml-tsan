/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*               Fabrice Buoro and Olivier Nicole, Tarides                */
/*                                                                        */
/*   Copyright 2023 Tarides                                               */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#define CAML_INTERNALS

#ifdef NATIVE_CODE

#ifndef DEBUG
#undef TSAN_DEBUG
#endif

#define UNW_LOCAL_ONLY
#include <libunwind.h>

#include "caml/tsan.h"
#include "caml/mlvalues.h"
#include "caml/misc.h"
#include "caml/frame_descriptors.h"
#include "caml/fiber.h"
#include "caml/domain_state.h"
#include "caml/stack.h"
#include "caml/config.h"
#ifdef TSAN_DEBUG
#include <execinfo.h> /* For backtrace_symbols */
#endif

extern void __tsan_func_exit(void*);
#if defined(__GNUC__) && !defined(__clang__)
/* GCC already has __tsan_func_entry declared for some reason */
#else
extern void __tsan_func_entry(void*);
#endif

Caml_inline void caml_tsan_debug_log_pc(const char* msg, uintnat pc)
{
#ifdef TSAN_DEBUG
    char **sym_names = backtrace_symbols((void **)&pc, 1);
    fprintf(stderr, "%s %s\n", msg, sym_names[0]);
    free(sym_names);
#else
    (void)msg; (void)pc;
#endif
}

void caml_tsan_exn_func_exit(uintnat pc, char* sp, char* trapsp)
{
  caml_domain_state* domain_state = Caml_state;
  caml_frame_descrs fds = caml_get_frame_descrs();
  uintnat next_pc = pc;

  /* iterate on each frame  */
  while (1) {
    frame_descr* descr = caml_next_frame_descriptor(fds, &next_pc, &sp,
        domain_state->current_stack);

    if (descr == NULL) {
      return;
    }

    /* Stop when we reach the current exception handler */
    if (sp > trapsp) {
      break;
    }

    caml_tsan_debug_log_pc("forced__tsan_func_exit for", pc);
    __tsan_func_exit(NULL);
    pc = next_pc;
  }
}

void caml_tsan_exn_func_exit_c(char* limit)
{
  unw_context_t uc;
  unw_cursor_t cursor;
  unw_word_t sp;
#ifdef TSAN_DEBUG
  unw_word_t prev_pc;
#endif
  int ret;

  ret = unw_getcontext(&uc);
  if (ret != 0)
    caml_fatal_error("unw_getcontext failed with code %d", ret);
  ret = unw_init_local(&cursor, &uc);
  if (ret != 0)
    caml_fatal_error("unw_init_local failed with code %d", ret);

  while (1) {
#ifdef TSAN_DEBUG
    if (unw_get_reg(&cursor, UNW_REG_IP, &prev_pc) < 0) {
      caml_fatal_error("unw_get_reg failed with code %d", ret);
    }
#endif

    ret = unw_step(&cursor);
    if (ret < 0) {
      caml_fatal_error("unw_step failed with code %d", ret);
    } else if (ret == 0) {
      /* No more frames */
      break;
    }

    ret = unw_get_reg(&cursor, UNW_REG_SP, &sp);
    if (ret != 0)
      caml_fatal_error("unw_get_reg failed with code %d", ret);
#ifdef TSAN_DEBUG
    caml_tsan_debug_log_pc("forced__tsan_func_exit for", prev_pc);
#endif
    __tsan_func_exit(NULL);

    if ((char*)sp >= limit) {
      break;
    }
  }
}

/* This function iterates on each stack frame of the current fiber. This is
   sufficient, since when the top of the stack is reached, the runtime switches
   to the parent fiber, and re-performs; as a consequence, this function will
   be called again. */
void caml_tsan_func_exit_on_perform(uintnat pc, char* sp)
{
  struct stack_info* stack = Caml_state->current_stack;
  caml_frame_descrs fds = caml_get_frame_descrs();
  uintnat next_pc = pc;

  /* iterate on each frame  */
  while (1) {
    frame_descr* descr = caml_next_frame_descriptor(fds, &next_pc, &sp, stack);

    caml_tsan_debug_log_pc("forced__tsan_func_exit for", pc);
    __tsan_func_exit(NULL);

    if (descr == NULL) {
      break;
    }
    pc = next_pc;
  }
}

/* This function is executed after switching to the deeper fiber, but before
   the linked list of fibers from the current one to the handler's has been
   restored by restoring the parent link to the handler's stack. As a
   consequence, this function simply iterates on each stack frame, following
   links to parent fibers, until that link is NULL. This way, it performs a
   [__tsan_func_entry] for each stack frame between the current and the
   handler's stack.
   We use non-tail recursion to call [__tsan_func_entry] in the reverse order
   of iteration. */
CAMLno_tsan void caml_tsan_func_entry_on_resume(uintnat pc, char* sp,
    struct stack_info const* stack)
{
  caml_frame_descrs fds = caml_get_frame_descrs();
  uintnat next_pc = pc;

  caml_next_frame_descriptor(fds, &next_pc, &sp, (struct stack_info*)stack);
  if (next_pc == 0) {
    stack = stack->handler->parent;
    if (!stack) {
      return;
    }

    char* p = (char*)stack->sp;
    Pop_frame_pointer(p);
    next_pc = *(uintnat*)p;
    sp = p + sizeof(value);
  }

  caml_tsan_func_entry_on_resume(next_pc, sp, stack);
  caml_tsan_debug_log_pc("forced__tsan_func_entry for", pc);
  __tsan_func_entry((void*)next_pc);
}

#endif // NATIVE_CODE


#include "caml/mlvalues.h"
#include <stdbool.h>

Caml_inline bool is_aligned(void *ptr, size_t byte_count)
{
  return (uintptr_t)ptr % byte_count == 0;
}

#include <stdint.h>

extern uint8_t __tsan_atomic8_load(void*, int);
extern uint16_t __tsan_atomic16_load(void*, int);
extern uint32_t __tsan_atomic32_load(void*, int);
extern uint64_t __tsan_atomic64_load(void*, int);
extern unsigned __int128 __tsan_atomic128_load(void*, int);

/* In the OCaml runtime, volatile reads are used instead of relaxed atomic
   loads on values that are shared with OCaml code, for backward compatibility
   and performance reasons (see #10992). To avoid this practice causing false
   positives with TSan, we make it so that TSan consider these reads as relaxed
   atomic loads. Volatile stores are still seen as plain stores. */
#define DEFINE_TSAN_VOLATILE_READ_WRITE(size, bitsize)                         \
                                                                               \
extern void __tsan_read##size(void*);                                          \
extern void __tsan_write##size(void*);                                         \
                                                                               \
  void __tsan_volatile_read##size(void *ptr)                                   \
  {                                                                            \
    const bool is_atomic = size <= sizeof(long long) &&                        \
               is_aligned(ptr, 8);                                             \
    if (is_atomic)                                                             \
      __tsan_atomic##bitsize##_load(ptr, memory_order_relaxed);                \
    else                                                                       \
      __tsan_read##size(ptr);                                                  \
  }                                                                            \
  void __tsan_unaligned_volatile_read##size(void *ptr)                         \
  {                                                                            \
    __tsan_volatile_read##size(ptr);                                           \
  }                                                                            \
  void __tsan_volatile_write##size(void *ptr)                                  \
  {                                                                            \
    __tsan_write##size(ptr);                                                   \
  }                                                                            \
  void __tsan_unaligned_volatile_write##size(void *ptr)                        \
  {                                                                            \
    __tsan_volatile_write##size(ptr);                                          \
  }

DEFINE_TSAN_VOLATILE_READ_WRITE(1, 8);
DEFINE_TSAN_VOLATILE_READ_WRITE(2, 16);
DEFINE_TSAN_VOLATILE_READ_WRITE(4, 32);
DEFINE_TSAN_VOLATILE_READ_WRITE(8, 64);
DEFINE_TSAN_VOLATILE_READ_WRITE(16, 128);
