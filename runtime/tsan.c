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

void caml_tsan_func_entry_on_resume(uintnat pc, char* sp, struct stack_info* stack)
{
  caml_frame_descrs fds = caml_get_frame_descrs();

  caml_next_frame_descriptor(fds, &pc, &sp, stack);
  if (pc == 0) {
    stack = stack->handler->parent;
    if (!stack)
      return;
    pc = *(uintnat*)stack->sp;
    sp = stack->sp + 8;
  }

  caml_tsan_func_entry_on_resume(pc, sp, stack);
  __tsan_func_entry((void*)pc);
}
