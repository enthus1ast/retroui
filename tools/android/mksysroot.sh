#!/usr/bin/env bash
# mksysroot.sh -- makes tools/android/sysroot.tar.gz, the Android sysroot that
# retroapk carries inside itself: what a plain clang + lld (or zig cc) needs to
# build an app's libmain.so for Android without the NDK.
#
#   tools/android/mksysroot.sh [--src DIR] [--out FILE] [--keep DIR] [--api N]
#
#   --src DIR   the sources (fetched there when missing; default
#               $RETRO_SYSROOT_SRC or ~/.cache/retro/sysroot-src)
#   --out FILE  the archive (default: sysroot.tar.gz next to this script)
#   --keep DIR  also leave the unpacked sysroot in DIR (to look at it)
#   --api N     the API level (default 24, the kit's minSdk)
#
# For arm64-v8a (phones) and x86_64 (the emulator), API 24:
#   usr/include/                     bionic's headers, the kernel's uapi headers,
#                                    the NDK's android/*.h, log.h, jni.h
#   usr/include/<triple>/asm/        each architecture's asm headers
#   usr/lib/<triple>/24/             crtbegin_so.o crtend_so.o crtbegin_dynamic.o
#                                    crtend_android.o, and stubs of libc.so libm.so
#                                    libdl.so liblog.so libandroid.so
#   usr/lib/<triple>/libclang_rt.builtins-<arch>-android.a
#                                    LLVM's compiler-rt builtins (emutls, 128-bit
#                                    floats, outline atomics...)
#   NOTICE, licenses/                where each part comes from and its licence
# No libEGL / libGLESv2 stubs: the kit opens them at run time (android_glue.c).
#
# Needs: bash, git, curl, python3, tar, a clang with lld and llvm-ar (the
# archive in the repository is made with clang 18; $CLANG, $LLD, $AR, $PYTHON
# override them). Every source is pinned to
# a revision below, the archive is written with sorted names, zero times and
# owners: the same sources and the same clang make the same archive.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
API=24
SRC=${RETRO_SYSROOT_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/retro/sysroot-src}
OUT=$HERE/sysroot.tar.gz
KEEP=
CLANG=${CLANG:-clang}
LLD=${LLD:-ld.lld}
AR=${AR:-llvm-ar}
PY=${PYTHON:-python3}
JOBS=${JOBS:-$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 4)}

while [ $# -gt 0 ]; do
  case $1 in
    --src) SRC=$2; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    --keep) KEEP=$2; shift 2 ;;
    --api) API=$2; shift 2 ;;
    -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "mksysroot: unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
done
for t in git curl "$PY" tar "$CLANG" "$LLD" "$AR"; do
  command -v "$t" >/dev/null || { echo "mksysroot: $t is missing" >&2; exit 1; }
done
case $OUT in /*) ;; *) OUT=$PWD/$OUT ;; esac

# ---- the sources, pinned --------------------------------------------------------
GH=https://github.com
RAW=https://raw.githubusercontent.com
BIONIC=aosp-mirror/platform_bionic
BIONIC_REV=731631f300090436d7f5df80d50b6275c8c60a93         # main, 2025-03-26
# (aosp-mirror has no frameworks/native, system/logging or libnativehelper:
# LineageOS's mirrors of them)
FWNATIVE=LineageOS/android_frameworks_native
FWNATIVE_REV=46018f54b42489de960c62c3db9de131abce43ea       # lineage-24.0
LOGGING=LineageOS/android_system_logging
LOGGING_REV=336e1707c8258adf1f1c5c5511218b533f3a22e8        # lineage-24.0
NATIVEHELPER=LineageOS/android_libnativehelper
NATIVEHELPER_REV=b7a25286026b49f0f7d95b25f2d32c4f47f498ef   # cm-13.0 (newest jni.h there)
FWBASE=aosp-mirror/platform_frameworks_base
FWBASE_REV=1cdfff555f4a21f71ccc978290e2e212e2f8b168         # main
LLVM=llvm/llvm-project
LLVM_REV=c13b7485b87909fcf739f62cfa382b55407433c0           # llvmorg-18.1.3

fetch_repo() {   # dir repo rev sparse-paths...
  local dir=$1 repo=$2 rev=$3; shift 3
  if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null || true)" = "$rev" ]; then
    return
  fi
  echo "fetching $repo at ${rev:0:12} (only the parts needed)"
  rm -rf "$dir"
  git init -q "$dir"
  git -C "$dir" remote add origin "$GH/$repo"
  git -C "$dir" config core.sparseCheckout true
  git -C "$dir" sparse-checkout set --no-cone "$@"
  git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$rev"
  git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}
fetch_file() {   # file repo rev path
  [ -s "$1" ] && return
  mkdir -p "$(dirname "$1")"
  curl -sSfL --retry 3 -o "$1.part" "$RAW/$2/$3/$4"
  mv "$1.part" "$1"
}

mkdir -p "$SRC"
fetch_repo "$SRC/bionic" $BIONIC $BIONIC_REV \
  /libc/include/ /libc/kernel/uapi/ /libc/kernel/android/ /libc/arch-common/ \
  /libc/private/ /libc/platform/ /libc/bionic/libc_init_common.h \
  /libc/libc.map.txt /libm/libm.map.txt /libdl/libdl.map.txt
fetch_repo "$SRC/fwnative" $FWNATIVE $FWNATIVE_REV \
  /include/android/ /libs/arect/include/ /libs/nativewindow/include/android/
fetch_repo "$SRC/llvm" $LLVM $LLVM_REV /compiler-rt/lib/builtins/
D=$SRC/dl
fetch_file "$D/log.h" $LOGGING $LOGGING_REV liblog/include/android/log.h
fetch_file "$D/liblog.map.txt" $LOGGING $LOGGING_REV liblog/liblog.map.txt
fetch_file "$D/jni.h" $NATIVEHELPER $NATIVEHELPER_REV include/nativehelper/jni.h
fetch_file "$D/libandroid.map.txt" $FWBASE $FWBASE_REV native/android/libandroid.map.txt
N=$SRC/notices
fetch_file "$N/bionic-libc.NOTICE" $BIONIC $BIONIC_REV libc/NOTICE
fetch_file "$N/bionic-libm.NOTICE" $BIONIC $BIONIC_REV libm/NOTICE
fetch_file "$N/bionic-libdl.NOTICE" $BIONIC $BIONIC_REV libdl/NOTICE
fetch_file "$N/frameworks-native.NOTICE" $FWNATIVE $FWNATIVE_REV NOTICE
fetch_file "$N/frameworks-base.NOTICE" $FWBASE $FWBASE_REV NOTICE
fetch_file "$N/system-logging-liblog.NOTICE" $LOGGING $LOGGING_REV liblog/NOTICE
fetch_file "$N/libnativehelper.NOTICE" $NATIVEHELPER $NATIVEHELPER_REV NOTICE
fetch_file "$N/llvm-compiler-rt.LICENSE.TXT" $LLVM $LLVM_REV compiler-rt/LICENSE.TXT

B=$SRC/bionic/libc
RT=$SRC/llvm/compiler-rt/lib/builtins

# ---- the tree --------------------------------------------------------------------
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mksysroot.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
S=$TMP/sysroot
BUILD=$TMP/build
I=$S/usr/include
mkdir -p "$I" "$BUILD"

echo "headers"
cp -R "$B/include/." "$I/"
for d in "$B"/kernel/uapi/*; do
  case ${d##*/} in asm-generic) cp -R "$d" "$I/" ;; asm-*) ;; *) cp -R "$d" "$I/" ;; esac
done
cp -R "$B/kernel/android/uapi/." "$B/kernel/android/scsi/." "$I/"
for h in "$SRC"/fwnative/include/android/*.h "$SRC/fwnative/libs/arect/include/android/rect.h" \
         "$SRC"/fwnative/libs/nativewindow/include/android/*.h; do
  [ -e "$I/android/${h##*/}" ] || cp "$h" "$I/android/"     # (bionic's own win)
done
cp "$D/log.h" "$I/android/log.h"
cp "$D/jni.h" "$I/jni.h"

# arch: NDK name, clang target, multiarch folder, kernel asm, compiler-rt name
# (no 32-bit ABIs: the apps are for 64-bit phones and the x86_64 emulator)
ARCHES="arm64 x86_64"
abi_of()    { case $1 in arm64) echo arm64-v8a ;; x86_64) echo x86_64 ;; esac; }
target_of() { case $1 in arm64) echo aarch64-linux-android ;; x86_64) echo x86_64-linux-android ;; esac; }
triple_of() { case $1 in arm64) echo aarch64-linux-android ;; x86_64) echo x86_64-linux-android ;; esac; }
kasm_of()   { case $1 in arm64) echo arm64 ;; x86_64) echo x86 ;; esac; }
rtname_of() { case $1 in arm64) echo aarch64 ;; x86_64) echo x86_64 ;; esac; }

for a in $ARCHES; do
  mkdir -p "$I/$(triple_of $a)"
  cp -R "$B/kernel/uapi/asm-$(kasm_of $a)/asm" "$I/$(triple_of $a)/asm"
done

# compiler-rt's source lists, read from its CMakeLists.txt: the items of the
# first set(NAME ...) block (the ${...} in it left out)
cmake_list() {
  awk -v name="$1" '
    !on && $0 ~ "^ *set\\(" name "$" { on = 1; next }
    on && /\)/ { exit }
    on { for (i = 1; i <= NF; i++) if ($i !~ /^\$\{/ && $i !~ /^#/) print $i }' "$RT/CMakeLists.txt"
}

# up to $JOBS compilations at a time (plain bash 3: macOS has no newer one)
pids=()
spawn() {
  "$@" &
  pids+=($!)
  [ ${#pids[@]} -lt "$JOBS" ] || reap
}
reap() {
  local p bad=0
  for p in ${pids[@]+"${pids[@]}"}; do wait "$p" || bad=1; done
  pids=()
  [ $bad = 0 ] || { echo "mksysroot: a compilation failed" >&2; exit 1; }
}

for a in $ARCHES; do
  T=$(target_of $a)$API
  TR=$(triple_of $a)
  L=$S/usr/lib/$TR/$API
  O=$BUILD/$a
  mkdir -p "$L" "$O/crt" "$O/rt" "$O/stubsrc"
  echo "$(abi_of $a): crt objects"
  CF=(--target=$T --sysroot="$S" -fPIC -O2 -I"$B" -I"$B/arch-common/bionic")
  AC=$B/arch-common/bionic
  "$CLANG" "${CF[@]}" -c "$AC/crtbegin_so.c" -o "$O/crt/crtbegin_so1.o"
  "$CLANG" "${CF[@]}" -D__ASSEMBLY__ -DPLATFORM_SDK_VERSION=$API -c "$AC/crtbrand.S" -o "$O/crt/crtbrand.o"
  "$CLANG" "${CF[@]}" -D__ASSEMBLY__ -c "$AC/crtend_so.S" -o "$L/crtend_so.o"
  "$LLD" -r "$O/crt/crtbegin_so1.o" "$O/crt/crtbrand.o" -o "$L/crtbegin_so.o"
  "$CLANG" "${CF[@]}" -c "$AC/crtbegin.c" -o "$O/crt/crtbegin_dynamic1.o"
  "$LLD" -r "$O/crt/crtbegin_dynamic1.o" "$O/crt/crtbrand.o" -o "$L/crtbegin_dynamic.o"
  "$CLANG" "${CF[@]}" -D__ASSEMBLY__ -c "$AC/crtend.S" -o "$L/crtend_android.o"

  echo "$(abi_of $a): stub libraries"
  for m in "$B/libc.map.txt libc.so" "$SRC/bionic/libm/libm.map.txt libm.so" \
           "$SRC/bionic/libdl/libdl.map.txt libdl.so" "$D/liblog.map.txt liblog.so" \
           "$D/libandroid.map.txt libandroid.so"; do
    set -- $m
    CLANG=$CLANG "$PY" -I "$HERE/genstubs.py" "$1" "$2" "$L" $API $a "$O/stubsrc"
  done

  echo "$(abi_of $a): compiler-rt builtins"
  # (what compiler-rt's CMake builds for the architecture on Android)
  RF=(--target=$T --sysroot="$S" -fPIC -O2 -fno-builtin -fvisibility=hidden
      -fomit-frame-pointer -DVISIBILITY_HIDDEN -I"$RT" -w)
  [ $a = arm64 ] && RF+=(-DHAS_ASM_LSE)
  probe() { printf '%s\n' "$1" | "$CLANG" "${RF[@]}" -std=c11 -x c -c - -o /dev/null 2>/dev/null; }
  probe '_Float16 foo(_Float16 x) { return x; }' && RF+=(-DCOMPILER_RT_HAS_FLOAT16)
  srcs=($(cmake_list GENERIC_SOURCES) emutls.c enable_execute_stack.c eprintf.c
        gcc_personality_v0.c clear_cache.c)
  probe '__bf16 foo(__bf16 x) { return x; }' && srcs+=($(cmake_list BF16_SOURCES))
  case $a in
    arm64)  arch_srcs=(cpu_model/aarch64.c aarch64/fp_mode.c)
            srcs+=($(cmake_list GENERIC_TF_SOURCES)) ;;
    x86_64) arch_srcs=(cpu_model/x86.c i386/fp_mode.c x86_64/floatdidf.c x86_64/floatdisf.c
                       x86_64/floatundidf.S x86_64/floatundisf.S)
            srcs+=($(cmake_list GENERIC_TF_SOURCES)) ;;
  esac
  # an architecture's own file replaces the generic one of the same name
  # (compiler-rt's filter_builtin_sources)
  drop=" "
  for s in "${arch_srcs[@]}"; do n=${s##*/}; drop+="${n%.*}.c "; done
  list=$O/rt/sources
  : > "$list"
  for s in "${srcs[@]}"; do
    case $drop in *" $s "*) continue ;; esac
    echo "$s" >> "$list"
  done
  for s in "${arch_srcs[@]}"; do echo "$s" >> "$list"; done
  for s in $(LC_ALL=C sort -u "$list"); do
    obj=$O/rt/$(echo "${s%.*}" | tr / _).o
    case $s in
      *.c) spawn "$CLANG" "${RF[@]}" -std=c11 -c "$RT/$s" -o "$obj" ;;
      *) spawn "$CLANG" "${RF[@]}" -D__ASSEMBLY__ -c "$RT/$s" -o "$obj" ;;
    esac
  done
  if [ $a = arm64 ]; then
    # the outline atomics (-moutline-atomics, clang's default on Android):
    # one object per operation, size and memory model, made from lse.S
    for pat in cas swp ldadd ldclr ldeor ldset; do
      for size in 1 2 4 8 16; do
        [ $pat != cas ] && [ $size = 16 ] && continue
        for model in 1 2 3 4 5; do
          spawn "$CLANG" "${RF[@]}" -D__ASSEMBLY__ -DL_$pat -DSIZE=$size -DMODEL=$model \
            -c "$RT/aarch64/lse.S" -o "$O/rt/outline_atomic_${pat}${size}_${model}.o"
        done
      done
    done
  fi
  reap
  rtlib=$S/usr/lib/$TR/libclang_rt.builtins-$(rtname_of $a)-android.a
  (cd "$O/rt" && LC_ALL=C ls *.o | LC_ALL=C sort | xargs "$AR" rcsD "$rtlib")
  echo "  $(basename "$rtlib"): $(cd "$O/rt" && ls *.o | wc -l | tr -d ' ') objects"
done

# ---- licences --------------------------------------------------------------------
mkdir -p "$S/licenses"
cp "$N"/* "$S/licenses/"
cat > "$S/NOTICE" <<EOF
Android sysroot for building apps without the NDK (API $API: arm64-v8a and
x86_64), made by Retro Nim UI's tools/android/mksysroot.sh.
None of it is the Android NDK; it is made from the same open sources.

usr/include/ (except android/log.h and jni.h), usr/lib/*/$API/crt*.o and the
stubs libc.so, libm.so, libdl.so (made from their symbol lists):
  Android bionic, $GH/$BIONIC
  revision $BIONIC_REV
  BSD-style licences (libc, libm), Apache-2.0 (libdl); the texts:
  licenses/bionic-libc.NOTICE, licenses/bionic-libm.NOTICE,
  licenses/bionic-libdl.NOTICE.
  The Linux uapi headers in usr/include (linux/, asm/, asm-generic/...) are
  bionic's: generated from the kernel's headers, constants and structures
  only (see the note in each of them and licenses/bionic-libc.NOTICE).

usr/include/android/ (the NDK's headers from frameworks/native):
  $GH/$FWNATIVE
  revision $FWNATIVE_REV
  Apache-2.0: licenses/frameworks-native.NOTICE

usr/include/android/log.h and the stub liblog.so:
  $GH/$LOGGING (liblog)
  revision $LOGGING_REV
  Apache-2.0: licenses/system-logging-liblog.NOTICE

usr/include/jni.h:
  $GH/$NATIVEHELPER
  revision $NATIVEHELPER_REV
  Apache-2.0: licenses/libnativehelper.NOTICE

the stub libandroid.so (made from native/android/libandroid.map.txt):
  $GH/$FWBASE
  revision $FWBASE_REV
  Apache-2.0: licenses/frameworks-base.NOTICE

usr/lib/*/libclang_rt.builtins-*-android.a (compiler-rt builtins):
  $GH/$LLVM (llvmorg-18.1.3)
  revision $LLVM_REV
  Apache-2.0 WITH LLVM-exception: licenses/llvm-compiler-rt.LICENSE.TXT

Built with: $("$CLANG" --version | head -1)
EOF

# ---- the archive -----------------------------------------------------------------
if [ -n "$KEEP" ]; then
  rm -rf "$KEEP"
  mkdir -p "$KEEP"
  cp -R "$S/." "$KEEP/"
fi
"$PY" -I - "$S" "$OUT" <<'EOF'
# a ustar tar, names sorted, times and owners zeroed; gzip -9 without a name
# or a time: the same tree gives the same bytes
import gzip, io, os, sys, tarfile
root, out = sys.argv[1], sys.argv[2]
names = []
for d, dirs, files in os.walk(root):
    for f in files:
        names.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/"))
names.sort()
buf = io.BytesIO()
with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
    for n in names:
        p = os.path.join(root, n)
        ti = tarfile.TarInfo(n)
        ti.size = os.path.getsize(p)
        ti.mtime = 0
        ti.mode = 0o644
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = ""
        with open(p, "rb") as f:
            t.addfile(ti, f)
raw = buf.getvalue()
tmp = out + ".part"
with open(tmp, "wb") as f:
    with gzip.GzipFile(filename="", mode="wb", fileobj=f, compresslevel=9, mtime=0) as g:
        g.write(raw)
os.replace(tmp, out)
print("%s: %d files, %d KB (%d KB unpacked)" % (out, len(names), os.path.getsize(out) // 1024,
                                                len(raw) // 1024))
EOF
