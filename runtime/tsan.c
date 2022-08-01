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
  fprintf(stderr, "Just a simple hello!\n"); // XXX
  fprintf(stderr, "caml_tsan_on_perform(pc = %ld, sp = %p\n", pc, sp); // XXX

  struct stack_info* stack = Caml_state->current_stack;
  caml_frame_descrs fds = caml_get_frame_descrs();

  /* iterate on each frame  */
  while (1) {
    void *p = (void*)pc; // XXX
    fprintf(stderr, "I'm at : ");
    backtrace_symbols_fd(&p, 1, 2);
    fprintf(stderr, "\n");

    frame_descr* descr = caml_next_frame_descriptor(fds, &pc, &sp, stack);
    if (descr == NULL) {
      fprintf(stderr, "Oh noes, no descriptor!!\n"); // XXX
      return;
    }

    fprintf(stderr, "next_fd(pc = %ld, sp = %p)\n", pc, sp); // XXX
  }

  fprintf(stderr, "I'm leaving caml_tsan_on_perform\n"); // XXX
}
