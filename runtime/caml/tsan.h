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

#ifndef CAML_TSAN_H
#define CAML_TSAN_H

#ifdef CAML_INTERNALS

#include "mlvalues.h"

CAMLextern void caml_tsan_func_exit_on_perform(uintnat pc, char* sp);

#endif /* CAML_INTERNALS */

#endif /* CAML_FIBER_H */
