/* glob() and globfree() for Android before 9 (API 28), where bionic has
   neither -- enough for std/net's search for certificates: a folder
   without wildcards, then a last part that has them (`*`, `?`, `[...]`,
   matched by fnmatch). The paths come sorted. On Android 9 and later this
   file is empty: bionic's own are used.

   Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net */
#include "androidglob.h"
#if defined(__ANDROID__) && __ANDROID_API__ < 28
#include <dirent.h>
#include <fnmatch.h>
#include <stdlib.h>
#include <string.h>

static int cmpPaths(const void *a, const void *b) {
  return strcmp(*(char * const *)a, *(char * const *)b);
}

int glob(const char *pattern, int flags, int (*errfunc)(const char *, int), glob_t *g) {
  (void)flags; (void)errfunc;
  g->gl_pathc = 0;
  g->gl_matchc = 0;
  g->gl_pathv = NULL;
  const char *slash = strrchr(pattern, '/');
  char dir[4096];
  const char *part;
  if (slash == NULL) { strcpy(dir, "."); part = pattern; }
  else {
    size_t n = (size_t)(slash - pattern);
    if (n >= sizeof dir) return GLOB_NOSPACE;
    if (n == 0) { strcpy(dir, "/"); } else { memcpy(dir, pattern, n); dir[n] = 0; }
    part = slash + 1;
  }
  DIR *d = opendir(dir);
  if (d == NULL) return GLOB_NOMATCH;
  size_t cap = 0;
  struct dirent *e;
  while ((e = readdir(d)) != NULL) {
    if (e->d_name[0] == '.' && part[0] != '.') continue;
    if (fnmatch(part, e->d_name, 0) != 0) continue;
    if (g->gl_pathc + 2 > cap) {
      cap = cap ? cap * 2 : 32;
      char **v = realloc(g->gl_pathv, cap * sizeof(char *));
      if (v == NULL) { closedir(d); globfree(g); return GLOB_NOSPACE; }
      g->gl_pathv = v;
    }
    size_t len = strlen(dir) + 1 + strlen(e->d_name) + 1;
    char *p = malloc(len);
    if (p == NULL) { closedir(d); globfree(g); return GLOB_NOSPACE; }
    if (slash == NULL) strcpy(p, e->d_name);
    else if (strcmp(dir, "/") == 0) { strcpy(p, "/"); strcat(p, e->d_name); }
    else { strcpy(p, dir); strcat(p, "/"); strcat(p, e->d_name); }
    g->gl_pathv[g->gl_pathc++] = p;
    g->gl_pathv[g->gl_pathc] = NULL;
  }
  closedir(d);
  if (g->gl_pathc == 0) return GLOB_NOMATCH;
  qsort(g->gl_pathv, g->gl_pathc, sizeof(char *), cmpPaths);
  g->gl_matchc = g->gl_pathc;
  return 0;
}

void globfree(glob_t *g) {
  if (g->gl_pathv != NULL) {
    for (size_t i = 0; i < g->gl_pathc; i++) free(g->gl_pathv[i]);
    free(g->gl_pathv);
  }
  g->gl_pathv = NULL;
  g->gl_pathc = 0;
}
#endif
