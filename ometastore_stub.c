/* Copyright (C) 2008 Mauricio Fernandez <mfp@acm.org> http//eigenclass.org
 * See README.txt and LICENSE for the redistribution and modification terms */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <fnmatch.h>
#include <stdio.h>
#include <sys/errno.h>
#include <sys/types.h>
#include <utime.h>

#if defined(HAVE_LINUX_XATTR) || defined(HAVE_OSX_XATTR)
#include <sys/xattr.h>
#endif

#ifdef HAVE_LINUX_XATTR

#define LLISTXATTR(f, buf, len) (llistxattr(f, buf, len))
#define LGETXATTR(f, nam, buf, len) (lgetxattr(f, nam, buf, len))
#define LSETXATTR(f, nam, v, len) lsetxattr(f, nam, v, len, 0)
#define LREMOVEXATTR(f, nam) lremovexattr(f, nam)

#elif defined(HAVE_OSX_XATTR)

#define LLISTXATTR(f, buf, len) (listxattr(f, buf, len, XATTR_NOFOLLOW))
#define LGETXATTR(f, nam, buf, len) (getxattr(f, nam, buf, len, 0, XATTR_NOFOLLOW))
#define LSETXATTR(f, nam, v, len) (setxattr(f, nam, v, len, 0, XATTR_NOFOLLOW))
#define LREMOVEXATTR(f, nam) removexattr(f, nam, XATTR_NOFOLLOW)

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

	tbuf.actime = Nativeint_val(time);
	tbuf.modtime = Nativeint_val(time);
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
 if (siz == 0 || errno == EPERM || errno == EACCES)
     CAMLreturn(Val_int(0));
 if(siz < 0) {   
     printf("Running llistxattr on %s failed, error %i\n", file, errno);
     if (errno == ENOTSUP) printf("Not supported on file system.\n");
     if (errno == ERANGE) printf("Namebuf too small.\n");    
     if (errno == EPERM) printf("Not supported on file.\n"); 
     if (errno == ENOTDIR) printf("Path not a directory.\n");
     if (errno == ENAMETOOLONG) printf("Name too long.\n");
     if (errno == EACCES) printf("Permission denied.\n");
     if (errno == ELOOP) printf("Too many symbolic links.  Loop?\n");
     if (errno == EFAULT) printf("Inavlid address.\n");
     if (errno == EIO) printf("I/O error occured.\n"); 
     if (errno == EINVAL) printf("Options invalid.\n");
     caml_failwith("llistxattr");
}

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
     ++i;
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

CAMLprim value perform_lsetxattr(value file, value name, value val)
{
 CAMLparam3(file, name, val);

 if(LSETXATTR(String_val(file), String_val(name), String_val(val), string_length(val)))
     caml_failwith("lsetxattr");

 CAMLreturn(Val_unit);
}

CAMLprim value perform_lremovexattr(value file, value name)
{
 CAMLparam2(file, name);

 if(LREMOVEXATTR(String_val(file), String_val(name)))
     caml_failwith("lremovexattr");

 CAMLreturn(Val_unit);
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

CAMLprim value perform_lsetxattr(value file, value name, value val)
{
 CAMLparam3(file, name, val);

 caml_failwith("lsetxattr");
}

CAMLprim value perform_lremovexattr(value file, value name)
{
 CAMLparam2(file, name);

 caml_failwith("lremovexattr");
}

#endif
