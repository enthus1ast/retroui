#!/usr/bin/env python3
"""Build the kit's text fonts: GNU FreeFont (FreeSans, FreeSerif, FreeMono,
each in four styles), cut down to what an app needs.

Maintainers only: users of the library never run this, the outputs are
checked in. Needs Python 3 with fontTools (`pip install fonttools`) and the
twelve TrueType files of GNU FreeFont (release 0412, 2012:
https://ftp.gnu.org/gnu/freefont/freefont-ttf-20120503.zip, or Debian's
`fonts-freefont-ttf`) in the folder given as argument:

    python3 tools/genfreefont.py /usr/share/fonts/truetype/freefont

Writes src/retroui/fonts/Free*.ttf (the subsets, the sources of record) and
Free*.ttf.z (the same, zlib-compressed: what typeset.nim builds into every
app and unpacks the first time a face is used).

What is kept:

* the regular of each family (the faces every style falls back to):
  Latin (Basic, Latin-1, Extended-A and -B, IPA, the spacing modifiers and
  combining marks), Greek, Cyrillic, Hebrew, the punctuation, super- and
  subscripts, currency signs, letterlike symbols, number forms, arrows,
  mathematical operators, the technical symbols, box drawing, blocks,
  geometric shapes, the miscellaneous symbols the kit's own text uses, a
  few dingbats (check marks, crosses), the Latin ligatures and the
  replacement character; FreeSerif and FreeMono also their Arabic, with
  the presentation forms A and B (the kit joins Arabic into them);
* bold: the same letters without IPA and the symbol blocks (a symbol in
  bold text comes from the regular); FreeSerif Bold its Arabic too
  (FreeSans and FreeMono Bold draw Arabic with it);
* italic and oblique: the Latin, Greek and Cyrillic letters, the marks,
  the punctuation and currency signs (Hebrew and Arabic have no italic:
  they come from the upright faces);
* the tables the kit reads: cmap, glyf/loca, hmtx/hhea, head, maxp, OS/2,
  post (without glyph names), name (the family, style, copyright, licence
  and URL, in English), and the OpenType layout (GSUB, GPOS, GDEF) for the
  features that matter to text -- kerning, marks, ligatures, the Arabic
  forms -- which the kit's kerning (GPOS pairs) and its OpenType shaper
  (documents, `textengine`) read. The legacy `kern` table goes: GPOS has
  the same pairs, as classes, in a fraction of the room.

The TrueType hinting (fpgm, prep, cvt, the glyph programs) is dropped: the
kit does not run it, it fits outlines to the pixels itself (ttf.nim).
Outlines, advances, kerning and line metrics are the fonts' own.

GNU FreeFont is free software under the GNU GPL v3 or later with the font
exception (see src/retroui/fonts/LICENSE-FreeFont.txt): an app that embeds
these files is not made a derivative of them.
"""
import io, os, sys, zlib
from fontTools.ttLib import TTFont
from fontTools import subset

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTS = os.path.join(ROOT, "src", "retro", "fonts")

# (the Unicode blocks, as code point ranges)
LATIN = [(0x0020, 0x007E), (0x00A0, 0x024F)]
IPA = [(0x0250, 0x02AF)]
MARKS = [(0x02B0, 0x036F)]             # spacing modifier letters, combining marks
GREEK = [(0x0370, 0x03FF)]
CYRILLIC = [(0x0400, 0x04FF)]
HEBREW = [(0x0590, 0x05FF), (0xFB1D, 0xFB4F)]
ARABIC = [(0x0600, 0x06FF), (0x0750, 0x077F), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF)]
PUNCT = [(0x2000, 0x206F), (0x20A0, 0x20CF), (0xFB00, 0xFB06), (0xFFFD, 0xFFFD)]
LETTERLIKE = [(0x2103, 0x2103), (0x2109, 0x2109), (0x2116, 0x2117), (0x2122, 0x2122),
              (0x2153, 0x215E)]       # (in bold and italic: the ones text uses)
SYMBOLS = [(0x2070, 0x209F), (0x2100, 0x218F), (0x2190, 0x21FF), (0x2200, 0x22FF),
           (0x2300, 0x23FF), (0x2500, 0x259F), (0x25A0, 0x25FF),
           (0x2600, 0x2603), (0x2605, 0x2606), (0x260E, 0x260E), (0x2610, 0x2612),
           (0x2639, 0x263A), (0x2640, 0x2642), (0x2660, 0x2667), (0x266A, 0x266F),
           (0x2713, 0x2718), (0x27E8, 0x27E9)]

REGULAR = LATIN + IPA + MARKS + GREEK + CYRILLIC + HEBREW + PUNCT + SYMBOLS
BOLD = LATIN + MARKS + GREEK + CYRILLIC + HEBREW + PUNCT + LETTERLIKE
ITALIC = LATIN + MARKS + GREEK + CYRILLIC + PUNCT + LETTERLIKE

FACES = [  # (file, what it keeps)
    ("FreeSans", REGULAR), ("FreeSansBold", BOLD),
    ("FreeSansOblique", ITALIC), ("FreeSansBoldOblique", ITALIC),
    ("FreeSerif", REGULAR + ARABIC), ("FreeSerifBold", BOLD + ARABIC),
    ("FreeSerifItalic", ITALIC), ("FreeSerifBoldItalic", ITALIC),
    ("FreeMono", REGULAR + ARABIC), ("FreeMonoBold", BOLD),
    ("FreeMonoOblique", ITALIC), ("FreeMonoBoldOblique", ITALIC),
]

FEATURES = ["kern", "mark", "mkmk", "curs", "ccmp", "locl", "liga", "clig", "rlig", "calt",
            "isol", "init", "medi", "fina"]


def cut(src, ranges, dst):
    font = TTFont(src)
    opt = subset.Options()
    opt.layout_features = FEATURES
    opt.hinting = False                 # (fpgm, prep, cvt, gasp and the glyph programs)
    opt.legacy_kern = False             # (GPOS has the pairs)
    opt.glyph_names = False
    opt.notdef_outline = True
    opt.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14, 16, 17]
    opt.name_languages = [0x409]
    opt.drop_tables += ["FFTM", "gasp"]
    sub = subset.Subsetter(opt)
    sub.populate(unicodes=[c for a, b in ranges for c in range(a, b + 1)])
    sub.subset(font)
    out = io.BytesIO()
    font.save(out)
    data = out.getvalue()
    with open(dst, "wb") as f:
        f.write(data)
    packed = zlib.compress(data, 9)
    with open(dst + ".z", "wb") as f:
        f.write(packed)
    return len(data), len(packed), font["maxp"].numGlyphs


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    total = [0, 0]
    for name, ranges in FACES:
        n, z, g = cut(os.path.join(src, name + ".ttf"), ranges, os.path.join(FONTS, name + ".ttf"))
        total[0] += n
        total[1] += z
        print("%-24s %5d glyphs %8d bytes, %7d compressed" % (name, g, n, z))
    print("%-24s %21d bytes, %7d compressed" % ("all", total[0], total[1]))


main()
