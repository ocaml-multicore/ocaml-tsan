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

#ifndef CAML_TSAN_H
#define CAML_TSAN_H

#ifdef CAML_INTERNALS

CAMLextern void caml_tsan_exn_func_exit_c(char* limit);

CAMLextern void caml_tsan_func_exit_on_perform(uintnat pc, char* sp);
CAMLextern void caml_tsan_func_entry_on_resume(uintnat pc, char* sp);

#endif /* CAML_INTERNALS */

#endif /* CAML_TSAN_H */
