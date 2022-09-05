#include <stdio.h>
#include <time.h>

#define CAML_NAME_SPACE
#include "caml/mlvalues.h"
#include "caml/fail.h"
#include "caml/memory.h"
#include "caml/callback.h"

value my_c_callback(value /* unit */)
{
  fprintf(stderr, "Hello from my_c_callback\n");
  caml_callback(*caml_named_value("ocaml_h"), Val_unit);
  fprintf(stderr, "Leaving my_c_callback\n");
  return Val_unit;
}

/*
value my_c_sleep(value delay)
{
  struct timespec ts = {
    .tv_sec = 0,
    .tv_nsec = Long_val(delay) * 1000
  };

  nanosleep(&ts, NULL);
	return Val_unit;
}
*/
