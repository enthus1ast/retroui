#!/bin/sh
# src/retroui/uirelays and the `uirelays` branch hold the same code: the
# branch is nim-lang/uirelays with my commits on top, ready for a pull
# request; retroui uses it from src/retroui/uirelays.
#
#   tools/uirelays.sh push "message"  src/retroui/uirelays -> a commit on the branch
#   tools/uirelays.sh pull            the branch's src/uirelays -> src/retroui/uirelays
#   tools/uirelays.sh diff            what differs between the two
#   tools/uirelays.sh merge           nim-lang/uirelays master merged into the branch
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
  merge)
    upstream=${UIRELAYS_UPSTREAM:-https://github.com/nim-lang/uirelays.git}
    git -C "$root" fetch -q "$upstream" master
    new=$(git -C "$root" rev-parse FETCH_HEAD)
    if git -C "$root" merge-base --is-ancestor "$new" "$branch"; then
      echo "the branch has upstream's $new already"; exit 0
    fi
    git -C "$root" log --oneline "$branch..$new"
    # (a worktree of its own that stays when the merge stops on a conflict)
    tree=$root/../uirelays-merge
    git -C "$root" worktree add -q "$tree" "$branch"
    cd "$tree"
    if git merge --no-ff -q -m "Merge nim-lang/uirelays master ($(git rev-parse --short "$new"))" "$new"; then
      cd "$root" && git worktree remove "$tree"
      echo "merged; now: tools/uirelays.sh pull, and $new in VERSION"
    else
      echo "conflicts in $tree: fix them, git add, git commit there; then"
      echo "git worktree remove $tree && tools/uirelays.sh pull"
      exit 1
    fi
    ;;
  *)
    sed -n '2,10p' "$0"
    exit 2
    ;;
esac
