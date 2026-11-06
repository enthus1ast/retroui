/* glob() and globfree() declared on Android before 9 (API 28), where bionic
   has neither: std/net looks for the certificate authorities with them
   (walkFiles). androidglob.c has them. retroui/xmpp includes this file in
   every C file of an Android build with TLS.

   Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net */
#ifndef RETRO_ANDROIDGLOB_H
#define RETRO_ANDROIDGLOB_H
#if defined(__ANDROID__)
#include <android/api-level.h>
#if __ANDROID_API__ < 28
#include <glob.h>
#ifdef __cplusplus
extern "C" {
#endif
int glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *g);
void globfree(glob_t *g);
#ifdef __cplusplus
}
#endif
#endif
#endif
#endif
