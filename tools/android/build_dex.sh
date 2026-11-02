#!/bin/sh
# Rebuilds classes.dex from tools/android/*.java and writes it into
# src/retro/androiddex.nim, which retroapk puts in every APK.
# Needs javac, an android.jar (API 23+) and dx (Debian: dalvik-exchange).
set -e
here=$(cd "$(dirname "$0")" && pwd)
jar=${ANDROID_JAR:-$(ls /usr/lib/android-sdk/platforms/*/android.jar | head -1)}
dx=$(command -v dx || command -v dalvik-exchange)
work=$(mktemp -d)
javac -source 8 -target 8 -nowarn -bootclasspath "$jar" -d "$work" "$here"/*.java
"$dx" --dex --min-sdk-version=24 --output="$work/classes.dex" "$work"
python3 - "$work/classes.dex" "$here/../../src/retro/androiddex.nim" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
lines = []
for i in range(0, len(data), 36):
    lines.append('  "' + ''.join('\\x%02x' % b for b in data[i:i+36]) + '"')
open(sys.argv[2], 'w').write(
    "## classes.dex of tools/android/*.java (made by\n"
    "## tools/android/build_dex.sh): the Java part of every retro APK.\n\n"
    "const classesDex* =\n" + " &\n".join(lines) + "\n")
PY
rm -rf "$work"
echo "wrote src/retro/androiddex.nim"
