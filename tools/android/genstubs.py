#!/usr/bin/env python3
"""Stub shared libraries (libc.so, libm.so, ...) for linking Android apps
without the NDK, made from AOSP's *.map.txt symbol files -- what the NDK's
own stubs are made from (build/soong/cc/ndkstubgen). A stub has every
function and variable of its library at the chosen API level, empty, with
the library's symbol versions: enough to link against; the phone has the
real library.

The rules of ndkstubgen / symbolfile:
  * versions named *_PRIVATE / *_PLATFORM, or tagged platform-only, are dropped
  * arch tags (arm arm64 x86 x86_64 riscv64): if any present, ours must be one
  * introduced=N / introduced-<arch>=N (version-level and symbol-level): N <= API
  * codenames (Tiramisu, ...) and 'future' count as later than any API
  * mode tags (apex, llndk, systemapi) without an NDK meaning: symbol dropped
  * 'var' -> data object, 'weak' -> weak definition
  * versioned=N with N > API: symbol defined but left out of the version script
  * extern "C++" blocks are skipped (C only)

Usage: genstubs.py <map.txt> <soname> <outdir> <api> <arch> <srcdir>
  arch: arm64 or x86_64 (the sysroot's; arm and x86 follow the same rules)
Writes <srcdir>/<stem>.c and <stem>.map, and compiles them into <outdir>/<soname>.
$CLANG is the compiler (default clang; it needs lld).
"""
import os
import re
import subprocess
import sys

ARCHES = {"arm", "arm64", "x86", "x86_64", "riscv64", "mips", "mips64"}
TRIPLES = {"arm64": "aarch64-linux-android", "arm": "armv7a-linux-androideabi",
           "x86_64": "x86_64-linux-android", "x86": "i686-linux-android"}
CODENAMES = {"Q": 29, "R": 30, "S": 31, "Sv2": 32, "Tiramisu": 33,
             "UpsideDownCake": 34, "VanillaIceCream": 35, "Baklava": 36}
MODE_TAGS = {"apex", "llndk", "systemapi"}


def api_of(v):
    if v.isdigit():
        return int(v)
    return CODENAMES.get(v, 10 ** 6)


def in_arch(tags, arch):
    arch_tags = [t for t in tags if t in ARCHES]
    return not arch_tags or arch in arch_tags


def in_api(tags, arch, api):
    introduced = None
    arch_introduced = None
    for t in tags:
        if t == "future":
            return False
        if t.startswith("introduced="):
            introduced = api_of(t.split("=", 1)[1])
        elif t.startswith("introduced-%s=" % arch):
            arch_introduced = api_of(t.split("=", 1)[1])
    eff = arch_introduced if arch_introduced is not None else introduced
    return eff is None or eff <= api


def versioned_ok(tags, api):
    for t in tags:
        if t.startswith("versioned="):
            return api_of(t.split("=", 1)[1]) <= api
    return True


def omit(tags, arch, api):
    if any(t in MODE_TAGS for t in tags):
        return True
    return not in_arch(tags, arch) or not in_api(tags, arch, api)


def parse(path):
    versions = []
    cur = None
    cxx_depth = 0
    with open(path) as f:
        for raw in f:
            line, _, comment = raw.partition("#")
            line = line.strip()
            tags = comment.split() if comment else []
            if not line:
                continue
            if cxx_depth:
                if "{" in line:
                    cxx_depth += 1
                if line.startswith("}"):
                    cxx_depth -= 1
                continue
            if line.startswith('extern "C++"'):
                cxx_depth = 1
                continue
            m = re.match(r"^([A-Za-z0-9_]+)\s*\{$", line)
            if m and cur is None:
                cur = {"name": m.group(1), "tags": tags, "syms": [], "base": None}
                continue
            m = re.match(r"^\}\s*([A-Za-z0-9_]*)\s*;$", line)
            if m and cur is not None:
                cur["base"] = m.group(1) or None
                versions.append(cur)
                cur = None
                continue
            if line in ("global:", "local:", "*;"):
                continue
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*;$", line)
            if m and cur is not None:
                cur["syms"].append((m.group(1), tags))
                continue
            sys.stderr.write("genstubs: ignoring line in %s: %s" % (path, raw))
    return versions


def main():
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    mapfile, soname, outdir, api, arch, srcdir = sys.argv[1:7]
    api = int(api)
    if arch not in TRIPLES:
        sys.exit("genstubs: unknown arch " + arch)
    stem = soname[:-3] if soname.endswith(".so") else soname
    os.makedirs(srcdir, exist_ok=True)

    c_lines = ["/* genstubs.py: %s, %s, API %d */" % (os.path.basename(mapfile), arch, api)]
    vs_blocks = []
    kept = set()
    seen = set()
    nfunc = nvar = 0
    for v in parse(mapfile):
        name = v["name"]
        if name.endswith("_PRIVATE") or name.endswith("_PLATFORM"):
            continue
        if "platform-only" in v["tags"] or omit(v["tags"], arch, api):
            continue
        vsyms = []
        for sym, tags in v["syms"]:
            if "platform-only" in tags or omit(tags, arch, api) or sym in seen:
                continue
            seen.add(sym)
            weak = "__attribute__((weak)) " if "weak" in tags else ""
            if "var" in tags:
                c_lines.append("%sint %s = 0;" % (weak, sym))
                nvar += 1
            else:
                c_lines.append("%svoid %s(void) {}" % (weak, sym))
                nfunc += 1
            if versioned_ok(tags, api):
                vsyms.append(sym)
        if vsyms:
            base = v["base"] if v["base"] in kept else None
            body = "".join("    %s;\n" % s for s in vsyms)
            vs_blocks.append("%s {\n  global:\n%s}%s;\n" %
                             (name, body, (" " + base) if base else ""))
            kept.add(name)

    cfile = os.path.join(srcdir, stem + ".c")
    vfile = os.path.join(srcdir, stem + ".map")
    with open(cfile, "w") as f:
        f.write("\n".join(c_lines) + "\n")
    with open(vfile, "w") as f:
        f.write("\n".join(vs_blocks))
    out = os.path.join(outdir, soname)
    cmd = [os.environ.get("CLANG", "clang"), "--target=%s%d" % (TRIPLES[arch], api),
           "-fPIC", "-O0", "-fno-builtin", "-w", "-shared", "-nostdlib",
           "-fuse-ld=lld", "-Wl,-s", "-Wl,--build-id=none",
           "-Wl,-soname," + soname, "-Wl,--version-script=" + vfile,
           "-o", out, cfile]
    subprocess.check_call(cmd)
    print("  %s (%s): %d functions, %d variables, versions: %s" %
          (soname, arch, nfunc, nvar, " ".join(b.split()[0] for b in vs_blocks)))


if __name__ == "__main__":
    main()
