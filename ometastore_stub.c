/* Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <fnmatch.h>
#include <sys/types.h>
#include <utime.h>

#if defined(HAVE_LINUX_XATTR) || defined(HAVE_OSX_XATTR)
#include <sys/xattr.h>
#endif

#ifdef HAVE_LINUX_XATTR

#define LLISTXATTR(f, buf, s) (llistxattr(f, buf, s))
#define LGETXATTR(f, nam, buf, s) (lgetxattr(f, nam, buf, s))

#elif defined(HAVE_OSX_XATTR)

#define LLISTXATTR(f, buf, s) (listxattr(f, buf, s, XATTR_NOFOLLOW))
#define LGETXATTR(f, nam, buf, s) (getxattr(f, nam, buf, s, 0, XATTR_NOFOLLOW))

#endif

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

#ifdef LLISTXATTR

CAMLprim value perform_llistxattr(value file)
{
 CAMLparam1(file);
 CAMLlocal2(l, prev);
 ssize_t siz, i;
 char *p, *porig;

 siz = LLISTXATTR(String_val(file), NULL, 0);
 if(siz == 0)
     CAMLreturn(Val_int(0));
 if(siz < 0)
     caml_failwith("llistxattr");

 porig = p = malloc(siz);
 siz = LLISTXATTR(String_val(file), p, siz);
 if(siz < 0) {
     free(p);
     caml_failwith("llistxattr");
 }

 prev = Val_int(0);
 for(i = 0; i < siz;) {
     l = caml_alloc(2, 0);
     Store_field(l, 0, caml_copy_string(p));
     Store_field(l, 1, prev);
     prev = l;
     while(*p++) /* skip */ i++;
     ++p; ++i;
 }

 free(porig);
 CAMLreturn(l);
}

CAMLprim value perform_lgetxattr(value file, value name)
{
 CAMLparam2(file, name);
 CAMLlocal1(ret);
 ssize_t siz;

 siz = LGETXATTR(String_val(file), String_val(name), NULL, 0);
 if(siz < 0)
     caml_failwith("lgetxattr");

 ret = caml_alloc_string(siz);
 if(LGETXATTR(String_val(file), String_val(name), String_val(ret), siz) < 0) {
     caml_failwith("lgetxattr");
 }

 CAMLreturn(ret);
}

#else

CAMLprim value perform_llistxattr(value file)
{
 return(Val_int(0));
}

CAMLprim value perform_lgetxattr(value file, value name)
{
 CAMLparam2(file, name);

 caml_failwith("lgetxattr");
}

#endif
