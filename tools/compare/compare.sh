#!/bin/sh
# The same Hello (a label, a text box, two buttons) made with Retro Nim UI,
# egui, iced and Slint, measured the same way on an X screen of its own
# (Xvfb, no window manager): memory idle and at 1080p, the program's size,
# its threads, the CPU it takes idle, for 60 resizes at 1080p (every pixel
# drawn again) and for 200 hovers over a button. The kit also without shared
# memory and with OpenGL; iced and Slint also with their own CPU drawing
# (tiny-skia, software).
#
#   sh tools/compare/compare.sh            (from the repository)
#
# Needs Nim, cargo, Xvfb, xdotool. The Rust programs take some minutes to
# build the first time (in build/compare). Without a graphics card OpenGL
# is Mesa's llvmpipe, drawn on the CPU too: that is what a VM, a remote
# desktop and Termux:X11 have.
#
# Developed by Sultan Al Isaiee @foxoman -- www.foxoman.net -- sultan@foxoman.net

set -e
top=$(cd "$(dirname "$0")/../.." && pwd)
work=$top/build/compare
mkdir -p "$work"
export DISPLAY=:77
Xvfb $DISPLAY -screen 0 1920x1080x24 +extension MIT-SHM >/dev/null 2>&1 &
XVFB=$!
trap 'kill $XVFB 2>/dev/null || true' EXIT
sleep 1

nim c -d:release --opt:size --hints:off -o:"$work/hello-retro" "$top/examples/hello.nim"
strip "$work/hello-retro"
export CARGO_TARGET_DIR="$work/target"
for p in egui iced slint; do
  (cd "$top/tools/compare/rust/$p" && cargo build --release -q)
  strip -o "$work/hello-$p" "$CARGO_TARGET_DIR/release/hello_$p"
done

measure() {   # measure LABEL PROGRAM
  label=$1; shift
  "$@" >/dev/null 2>&1 &
  P=$!
  W=""
  for i in $(seq 1 400); do
    W=$(xdotool search --pid $P 2>/dev/null | tail -1)
    [ -n "$W" ] && break
    sleep 0.01
  done
  sleep 3
  rss0=$(ps -o rss= -p $P)
  thr=$(grep Threads /proc/$P/status | awk '{print $2}')
  t1=$(awk '{print $14+$15}' /proc/$P/stat); sleep 10; t2=$(awk '{print $14+$15}' /proc/$P/stat)
  for i in $(seq 1 30); do
    xdotool windowsize $W 1900 1060; sleep 0.08; xdotool windowsize $W 1880 1040; sleep 0.08
  done
  sleep 1.5
  t3=$(awk '{print $14+$15}' /proc/$P/stat)
  rss1=$(ps -o rss= -p $P)
  xdotool windowsize $W 1900 1060; xdotool windowmove $W 0 0; sleep 2
  xdotool mousemove 900 600; sleep 0.5
  t4=$(awk '{print $14+$15}' /proc/$P/stat)
  for i in $(seq 1 100); do
    xdotool mousemove 40 52; sleep 0.05; xdotool mousemove 900 600; sleep 0.05
  done
  sleep 1
  t5=$(awk '{print $14+$15}' /proc/$P/stat)
  kill $P 2>/dev/null; wait $P 2>/dev/null || true
  # (ticks of 10 ms: a step's and a hover's CPU in ms)
  printf "%-24s %6.1f MB idle %6.1f MB 1080p  %2d threads  idle %4.1f%%  resize %6.2f ms  hover %6.2f ms\n" \
    "$label" "$(echo "$rss0/1024" | bc -l)" "$(echo "$rss1/1024" | bc -l)" "$thr" \
    "$(echo "($t2-$t1)/10" | bc -l)" "$(echo "($t3-$t2)*10/60" | bc -l)" "$(echo "($t5-$t4)*10/200" | bc -l)"
}

echo "sizes:"
ls -l "$work"/hello-* | awk '{printf "  %-14s %6.1f MB\n", $9, $5/1048576}' | sed "s|$work/||"
measure "Retro Nim UI" "$work/hello-retro"
measure "Retro Nim UI (no SHM)" env RETRO_SURFACE=0 "$work/hello-retro"
measure "Retro Nim UI (OpenGL)" env RETRO_GPU=gpu "$work/hello-retro"
measure "egui (OpenGL)" "$work/hello-egui"
measure "iced (wgpu)" "$work/hello-iced"
measure "iced (tiny-skia)" env ICED_BACKEND=tiny-skia "$work/hello-iced"
measure "Slint (OpenGL)" "$work/hello-slint"
measure "Slint (software)" env SLINT_BACKEND=winit-software "$work/hello-slint"
