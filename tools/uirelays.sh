#!/bin/sh
# src/retroui/uirelays and the `uirelays` branch hold the same code: the
# branch is nim-lang/uirelays with my commits on top, ready for a pull
# request; retroui uses it from src/retroui/uirelays.
#
#   tools/uirelays.sh push "message"  src/retroui/uirelays -> a commit on the branch
#   tools/uirelays.sh pull            the branch's src/uirelays -> src/retroui/uirelays
#   tools/uirelays.sh diff            what differs between the two
#
# RETRO.md, VERSION and LICENSE.md stay in retro only.
set -e
root=$(git rev-parse --show-toplevel)
here=$root/src/retroui/uirelays
branch=${UIRELAYS_BRANCH:-uirelays}
work=$(mktemp -d)
trap 'git -C "$root" worktree remove --force "$work/tree" 2>/dev/null; rm -rf "$work"' EXIT

copy() {   # copy <from> <to>: the files of uirelays, the retro notes left out
  mkdir -p "$2"
  (cd "$1" && find . -type f ! -name RETRO.md ! -name VERSION ! -name LICENSE.md) |
    while read -r f; do
      mkdir -p "$2/$(dirname "$f")"
      cp "$1/$f" "$2/$f"
    done
}

case "$1" in
  push)
    [ -n "$2" ] || { echo "usage: $0 push \"commit message\""; exit 2; }
    git -C "$root" worktree add -q "$work/tree" "$branch"
    rm -rf "$work/tree/src/uirelays"
    copy "$here" "$work/tree/src/uirelays"
    cd "$work/tree"
    git add -A src/uirelays
    if git diff --cached --quiet; then echo "the branch has these already"; exit 0; fi
    git commit -q -m "$2"
    git log --oneline -1
    ;;
  pull)
    git -C "$root" archive "$branch" src/uirelays | tar -x -C "$work"
    find "$here" -type f ! -name RETRO.md ! -name VERSION ! -name LICENSE.md -delete
    copy "$work/src/uirelays" "$here"
    echo "src/retroui/uirelays is the branch's now"
    ;;
  diff)
    git -C "$root" archive "$branch" src/uirelays | tar -x -C "$work"
    diff -ru -x RETRO.md -x VERSION -x LICENSE.md "$work/src/uirelays" "$here" && echo "the same"
    ;;
  *)
    sed -n '2,10p' "$0"
    exit 2
    ;;
esac
