/* A stand-in for glob() on Android before 9 (see androidglob.h): it finds
   nothing. A real one (Android 9 and later, Termux's libandroid-glob) is
   used instead when there is one.

   Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net */
#include "androidglob.h"
#if defined(__ANDROID_API__) && __ANDROID_API__ < 28
__attribute__((weak)) int glob(const char* pattern, int flags,
                               int (*errfunc)(const char*, int), glob_t* pglob) {
  (void)pattern; (void)flags; (void)errfunc;
  if (pglob) { pglob->gl_pathc = 0; pglob->gl_pathv = 0; }
  return GLOB_NOMATCH;
}
__attribute__((weak)) void globfree(glob_t* pglob) { (void)pglob; }
#endif
