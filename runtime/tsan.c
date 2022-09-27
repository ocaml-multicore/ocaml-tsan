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

#define CAML_INTERNALS

#if defined(WITH_THREAD_SANITIZER)

#define UNW_LOCAL_ONLY
#include <libunwind.h>

#include "caml/misc.h"
#include "caml/mlvalues.h"
#include "caml/frame_descriptors.h"
#include "caml/domain_state.h"

extern void __tsan_func_exit(void*);

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
    if (sp > trapsp)
      break;

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
    int ret = unw_step(&cursor);
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

#endif // WITH_THREAD_SANITIZER
