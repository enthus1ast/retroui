#!/usr/bin/env python3
"""Build the embedded Kawkab Mono (the default font of the UI's text).

Maintainers only: the outputs are checked in. Kawkab Mono, by Abdullah Arif
(with the Latin of Adobe's Source Code Pro), SIL Open Font License 1.1, is
published as its Glyphs source only; this makes the fonts the kit carries
from it. Needs Python 3 with fontmake and fontTools
(`pip install fontmake`), and the source repository:

    git clone https://github.com/aiaf/kawkab-mono ~/kawkab-mono
    python3 tools/genkawkab.py ~/kawkab-mono

Writes:
    src/retro/fonts/KawkabMono.ttf, KawkabMonoBold.ttf (+ .ttf.z)
    src/retro/fonts/LICENSE-KawkabMono.txt

What it changes, for the kit's text engine (which joins Arabic letters by
their Unicode presentation forms and reads no OpenType layout):

* each Arabic letter's joined forms, which the font only reaches through its
  `init`/`medi`/`fina` substitutions (and lam-alef through its ligatures),
  also given their presentation-form characters (U+FB50..U+FEFF);
* the layout tables dropped, the glyphs kept those of Latin, Greek,
  Cyrillic, Arabic and the punctuation the UI uses;
* the line's height made one for a UI: ascent 1020, descent 380 per 1000
  (the font's own 1300 + 650 is meant for vowelled Arabic in an editor).
"""
import os, re, shutil, subprocess, sys, tempfile, unicodedata, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTS = os.path.join(ROOT, "src", "retro", "fonts")

KEEP = ("U+0020-007E,U+00A0-024F,U+0259,U+02B9-02DD,U+0300-036F,U+0370-03FF,U+0400-04FF,"
        "U+0600-06FF,U+0750-077F,U+08A0-08FF,U+2000-206F,U+20A0-20CF,U+2100-214F,"
        "U+2190-21FF,U+2200-22FF,U+2500-257F,U+25A0-25FF,U+FB50-FDFF,U+FE70-FEFF,U+FFFD")

ASCENT, DESCENT = 1020, -380


def fixed_source(src, work):
    """The .glyphs file, mended for glyphsLib: quotes inside feature code
    escaped, and the Glyphs tokens "[$]" in feature names written out."""
    data = open(src, encoding="utf-8").read()
    lines = data.split("\n")
    for i, l in enumerate(lines):
        m = re.match(r'^(\s*code = ")(.*)(";)\s*$', l)
        if m:
            lines[i] = m.group(1) + re.sub(r'(?<!\\)"', r'\\"', m.group(2)) + m.group(3)
    data = "\n".join(lines).replace("[$]", "[dollar]")
    out = os.path.join(work, "KawkabMono.glyphs")
    open(out, "w", encoding="utf-8").write(data)
    return out


def presentation_forms(font):
    """cmap entries for the Arabic presentation forms, from the font's
    joining substitutions and lam-alef ligatures."""
    cmap = font.getBestCmap()
    gsub = font["GSUB"].table
    singles = {"init": {}, "medi": {}, "fina": {}, "isol": {}}
    ligs = {}
    for fr in gsub.FeatureList.FeatureRecord:
        tag = fr.FeatureTag
        for li in fr.Feature.LookupListIndex:
            lk = gsub.LookupList.Lookup[li]
            for st in lk.SubTable:
                if lk.LookupType == 7:
                    st = st.ExtSubTable
                if tag in singles and hasattr(st, "mapping"):
                    singles[tag].update(st.mapping)
                if tag in ("rlig", "liga", "calt") and hasattr(st, "ligatures"):
                    for first, ls in st.ligatures.items():
                        for lg in ls:
                            ligs[(first,) + tuple(lg.Component)] = lg.LigGlyph
    added = {}
    kinds = {"<initial>": "init", "<medial>": "medi", "<final>": "fina", "<isolated>": "isol"}
    for cp in list(range(0xFB50, 0xFE00)) + list(range(0xFE70, 0xFF00)):
        if cp in cmap:
            continue
        d = unicodedata.decomposition(chr(cp)).split()
        if len(d) < 2 or d[0] not in kinds:
            continue
        kind = kinds[d[0]]
        bases = [int(x, 16) for x in d[1:]]
        if any(b not in cmap for b in bases):
            continue
        if len(bases) == 1:
            g = cmap[bases[0]]
            if kind == "isol":
                added[cp] = singles["isol"].get(g, g)
            elif g in singles[kind]:
                added[cp] = singles[kind][g]
        else:
            # a ligature (lam-alef): its glyph, from the joined forms of its letters
            seqs = [cmap[b] for b in bases]
            tries = [tuple(seqs)]
            if kind in ("fina", "medi"):
                tries.append((singles["medi"].get(seqs[0], seqs[0]),) +
                             tuple(singles["fina"].get(g, g) for g in seqs[1:]))
            tries.append((singles["init"].get(seqs[0], seqs[0]),) +
                         tuple(singles["fina"].get(g, g) for g in seqs[1:]))
            for t in tries:
                if t in ligs:
                    lg = ligs[t]
                    if kind == "fina" and lg + ".fina" in font.getGlyphOrder():
                        lg = lg + ".fina"
                    added[cp] = lg
                    break
    for table in font["cmap"].tables:
        if table.isUnicode():
            for cp, g in added.items():
                if cp <= 0xFFFF or table.format == 12:
                    table.cmap[cp] = g
    return len(added)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    repo = sys.argv[1]
    from fontTools.ttLib import TTFont
    from fontTools import subset
    work = tempfile.mkdtemp()
    try:
        src = fixed_source(os.path.join(repo, "src", "Kawkab Mono.glyphs"), work)
        subprocess.run(["fontmake", "-g", src, "-o", "ttf", "-i", "--output-dir", work], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for style, name in [("Regular", "KawkabMono"), ("Bold", "KawkabMonoBold")]:
            f = TTFont(os.path.join(work, "KawkabMono-%s.ttf" % style))
            n = presentation_forms(f)
            tmp = os.path.join(work, name + "-full.ttf")
            f.save(tmp)
            opts = subset.Options()
            opts.layout_features = []
            opts.drop_tables += ["GSUB", "GPOS", "GDEF", "FFTM", "gasp", "DSIG"]
            opts.hinting = False
            opts.notdef_outline = True
            opts.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
            opts.name_languages = ["*"]
            f = TTFont(tmp)
            sub = subset.Subsetter(opts)
            unicodes = []
            for part in KEEP.split(","):
                a, _, b = part[2:].partition("-")
                unicodes += list(range(int(a, 16), int(b or a, 16) + 1))
            sub.populate(unicodes=unicodes)
            sub.subset(f)
            # a UI's line
            f["hhea"].ascent, f["hhea"].descent, f["hhea"].lineGap = ASCENT, DESCENT, 0
            os2 = f["OS/2"]
            os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ASCENT, DESCENT, 0
            out = os.path.join(FONTS, name + ".ttf")
            f.save(out)
            data = open(out, "rb").read()
            open(out + ".z", "wb").write(zlib.compress(data, 9))
            print("%s: %d glyphs, %d presentation forms added, %d bytes (%d packed)" %
                  (name, len(f.getGlyphOrder()), n, len(data), os.path.getsize(out + ".z")))
        shutil.copy(os.path.join(repo, "OFL.txt"), os.path.join(FONTS, "LICENSE-KawkabMono.txt"))
    finally:
        shutil.rmtree(work, ignore_errors=True)


main()
