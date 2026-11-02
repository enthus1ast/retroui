#!/bin/sh
## The C compiler of the Linux AppImage builds: zig's clang, linking against
## an older glibc (2.31: Ubuntu 20.04, Debian 11, Fedora 32, RHEL 9 and
## later; $RETRO_GLIBC for another) than the one of the computer building,
## so the AppImage runs on the systems people have. It is zig on the PATH,
## else Python's (pip install ziglang).
##
##   nim c --cc:clang --clang.exe:tools/zigcc.sh --clang.linkerexe:tools/zigcc.sh app.nim
##
## Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

target="x86_64-linux-gnu.${RETRO_GLIBC:-2.31}"
if command -v zig >/dev/null 2>&1; then
  exec zig cc -target "$target" "$@"
fi
exec python3 -m ziglang cc -target "$target" "$@"
