/* Android before 9 (API 28) has no glob(): Nim's compiler options, which
   Retro Designer reads files with, call it -- the designer never does.
   Its declarations here; androidglob.c has a stand-in.

   Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net */
#ifndef RETRO_ANDROID_GLOB_H
#define RETRO_ANDROID_GLOB_H
#include <glob.h>
#if defined(__ANDROID_API__) && __ANDROID_API__ < 28
int glob(const char* pattern, int flags, int (*errfunc)(const char*, int), glob_t* pglob);
void globfree(glob_t* pglob);
#endif
#endif
