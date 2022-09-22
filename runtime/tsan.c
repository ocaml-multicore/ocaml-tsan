/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*                                                                        */
/* TODO                                                                   */
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
#include <execinfo.h> // XXX
#include <stdio.h>    // XXX

#include "caml/misc.h"
#include "caml/mlvalues.h"
#include "caml/frame_descriptors.h"
#include "caml/domain_state.h"

extern void __tsan_func_exit(void*);

void caml_tsan_exn_func_exit(uintnat pc, char* sp, char* trapsp)
{
  //fprintf(stderr, "caml_tsan_exn_func_exit(pc = %ld, sp = %p, trapsp = %p)\n",
  //    pc, sp, trapsp); // XXX

  caml_domain_state* domain_state = Caml_state;
  caml_frame_descrs fds = caml_get_frame_descrs();

  /* iterate on each frame  */
  while (1) {
    //fprintf(stderr, "I'm at : ");
    //backtrace_symbols_fd((void*)&pc, 1, 2);
    //fprintf(stderr, "\n");

    frame_descr* descr = caml_next_frame_descriptor(fds, &pc, &sp,
        domain_state->current_stack);

    if (descr == NULL) {
      //fprintf(stderr, "Oh noes, no descriptor!!\n");
      return;
    }

    //fprintf(stderr, "next_fd(pc = %ld, sp = %p)\n", pc, sp); // XXX

    /* Stop when we reach the current exception handler */
    if (sp > trapsp)
      break;

    //fprintf(stderr, "Doing a tsan_func_exit\n");
    __tsan_func_exit(NULL);
  }

  //fprintf(stderr, "I'm leaving caml_tsan_exn_func_exit\n");
}

void caml_tsan_exn_func_exit_c(char* limit)
{
  unw_context_t uc;
  unw_cursor_t cursor;
  unw_word_t sp;
  unw_word_t ip; // XXX

  unw_getcontext(&uc);
  unw_init_local(&cursor, &uc);
  while (1) {
    int ret = unw_step(&cursor);
    CAMLassert(ret >= 0);
    if (ret == 0) {
      break;
    }

    unw_get_reg(&cursor, UNW_REG_IP, &ip); // XXX
    unw_get_reg(&cursor, UNW_REG_SP, &sp);

    //fprintf(stderr, "ip = %lx, sp = %lx, for ", (long)ip, (long)sp); // XXX
    //backtrace_symbols_fd((void*)&ip, 1, 2);
    //fprintf(stderr, "\n");

    //fprintf(stderr, "Doing a tsan_func_exit\n");
    __tsan_func_exit(NULL);

    if ((char*)sp >= limit) {
      break;
    }
  }
}

#endif // WITH_THREAD_SANITIZER
