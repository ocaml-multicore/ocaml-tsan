/**************************************************************************/
/*                                                                        */
/*                                 OCaml                                  */
/*   TODO                                                                 */
/*                                                                        */
/*   All rights reserved.  This file is distributed under the terms of    */
/*   the GNU Lesser General Public License version 2.1, with the          */
/*   special exception on linking described in the file LICENSE.          */
/*                                                                        */
/**************************************************************************/

#define CAML_INTERNALS
#include "caml/fiber.h"
#include "caml/frame_descriptors.h"

#include <stdio.h>    // XXX
#include <execinfo.h> // XXX

void caml_tsan_func_exit_on_perform(uintnat pc, char* sp)
{
  //fprintf(stderr, "caml_tsan_func_exit_on_perform(pc = %p, sp = %p\n", (void*)pc, sp); // XXX

  struct stack_info* stack = Caml_state->current_stack;
  caml_frame_descrs fds = caml_get_frame_descrs();

  /* iterate on each frame  */
  while (1) {
    //uintnat old_pc = pc; // XXX
    //fprintf(stderr, "feop: in fn called by: "); backtrace_symbols_fd((void**)&pc, 1, 2);

    frame_descr* descr = caml_next_frame_descriptor(fds, &pc, &sp, stack);

    //fprintf(stderr, "next_fd(pc = %p, sp = %p)\n", (void*)pc, sp); // XXX

    //fprintf(stderr, "func_exit for "); backtrace_symbols_fd((void**)&old_pc, 1, 2); // XXX
    __tsan_func_exit(NULL);

    if (descr == NULL) {
      //fprintf(stderr, "Oh noes, no descriptor!!\n"); // XXX
      break;
    }

  }

  //fprintf(stderr, "I'm leaving caml_tsan_func_entry_on_perform\n"); // XXX
}

void caml_tsan_func_entry_on_resume(uintnat pc, char* sp, struct stack_info* stack)
{
  //fprintf(stderr, "caml_tsan_func_entry_on_resume(pc = %p, sp = %p\n", (void*)pc, sp); // XXX

  caml_frame_descrs fds = caml_get_frame_descrs();

  //fprintf(stderr, "feor: in fn called by: "); backtrace_symbols_fd((void**)&pc, 1, 2);

  caml_next_frame_descriptor(fds, &pc, &sp, stack);

  //fprintf(stderr, "next_fd(pc = %p, sp = %p)\n", (void*)pc, sp); // XXX

  if (pc == 0) {
    stack = stack->handler->parent;
    if (!stack)
      return;
    pc = *(uintnat*)stack->sp;
    sp = stack->sp + 8;
  }

  caml_tsan_func_entry_on_resume(pc, sp, stack);

  //fprintf(stderr, "func_entry for "); backtrace_symbols_fd((void**)&pc, 1, 2); // XXX
  __tsan_func_entry((void*)pc);
}
