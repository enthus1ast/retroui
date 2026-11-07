#!/bin/sh
# The pictures of docs/syntax.md (docs/syntax/*.png), made again from the
# programs in tools/syntaxshots/ex: each runs on a fake screen at 200 %, its
# script brings it to the moment the picture shows, and the widths it
# measured are drawn under it in red. Then a check that every program's code
# is in the study as it is in ex/. Needs Python 3 with Pillow.
#
#   sh tools/syntaxshots/make.sh        (from the repository's root)
set -e
here=$(dirname "$0")
python3 "$here/gen.py"
nim c --hints:off --warnings:off -d:useMalloc --path:src \
  --nimcache:"$here/build/cache" -o:"$here/build/study" "$here/build/study.nim"
rm -rf "$here/build/out"
OUT="$here/build/out" "$here/build/study"
python3 "$here/annotate.py" "$here/build/out" docs/syntax
python3 "$here/gen.py" --check docs/syntax.md
