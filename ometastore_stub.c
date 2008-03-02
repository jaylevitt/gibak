/* Copyright (C) 2007 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <fnmatch.h>
#include <sys/types.h>
#include <utime.h>


CAMLprim value perform_fnmatch(value fnm_pathname, value pattern, value string)
{
 char *patt = String_val(pattern);

 if(*patt == '/') patt++;

 return Val_bool(!fnmatch(patt, String_val(string),
	                  Bool_val(fnm_pathname) ? FNM_PATHNAME : 0));
}

CAMLprim value perform_utime(value file, value time)
{
  struct utimbuf tbuf;

	tbuf.actime = Int_val(time);
	tbuf.modtime = Int_val(time);
	if(utime(String_val(file), &tbuf))
		caml_failwith("utime");

	return(Val_int(0));
}
