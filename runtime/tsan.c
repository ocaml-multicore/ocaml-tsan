/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/*               Fabrice Buoro and Olivier Nicole, Tarides                */
/*                                                                        */
/*   Copyright 2022 Tarides                                               */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#if defined(WITH_THREAD_SANITIZER)
#define CAML_INTERNALS

#define UNW_LOCAL_ONLY
#include <libunwind.h>

#include "caml/mlvalues.h"
#include "caml/misc.h"
#include "caml/frame_descriptors.h"
#include "caml/fiber.h"
#include "caml/domain_state.h"
#include "caml/stack.h"

extern void __tsan_func_exit(void*);

const char * __tsan_default_suppressions() {
  return "deadlock:caml_plat_lock\n"
         "race:create_domain\n"
    ;
}

void caml_tsan_exn_func_exit(uintnat pc, char* sp, char* trapsp)
{
  caml_domain_state* domain_state = Caml_state;
  caml_frame_descrs fds = caml_get_frame_descrs();

  /* iterate on each frame  */
  while (1) {
    frame_descr* descr = caml_next_frame_descriptor(fds, &pc, &sp,
        domain_state->current_stack);

    if (descr == NULL) {
      return;
    }

    /* Stop when we reach the current exception handler */
    if (sp > trapsp) {
      break;
    }

    __tsan_func_exit(NULL);
  }
}

void caml_tsan_exn_func_exit_c(char* limit)
{
  unw_context_t uc;
  unw_cursor_t cursor;
  unw_word_t sp;

  unw_getcontext(&uc);
  unw_init_local(&cursor, &uc);

  while (1) {
    const int ret = unw_step(&cursor);
    CAMLassert(ret >= 0);
    if (ret == 0) {
      break;
    }

    unw_get_reg(&cursor, UNW_REG_SP, &sp);
    __tsan_func_exit(NULL);

    if ((char*)sp >= limit) {
      break;
    }
  }
}

void caml_tsan_func_exit_on_perform(uintnat pc, char* sp)
{
  struct stack_info* stack = Caml_state->current_stack;
  caml_frame_descrs fds = caml_get_frame_descrs();

  /* iterate on each frame  */
  while (1) {
    frame_descr* descr = caml_next_frame_descriptor(fds, &pc, &sp, stack);

    __tsan_func_exit(NULL);

    if (descr == NULL) {
      break;
    }
  }
}

CAMLno_tsan void caml_tsan_func_entry_on_resume(uintnat pc, char* sp,
                                    struct stack_info const* stack)
{
  caml_frame_descrs fds = caml_get_frame_descrs();

  caml_next_frame_descriptor(fds, &pc, &sp, (struct stack_info*)stack);
  if (pc == 0) {
    stack = stack->handler->parent;
    if (!stack) {
      return;
    }

    char* p = (char*)stack->sp;
    Pop_frame_pointer(p);
    pc = *(uintnat*)p;
    sp = p + sizeof(value);
  }

  caml_tsan_func_entry_on_resume(pc, sp, stack);
  __tsan_func_entry((void*)pc);
}

#endif // WITH_THREAD_SANITIZER
