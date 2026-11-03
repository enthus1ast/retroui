#!/usr/bin/env python3
"""Build the embedded Open Sans (Regular and Bold), the kit's smooth modern
UI font.

Maintainers only: users of the library never run this, the outputs are
checked in. Needs Python 3 with fontTools (`pip install fonttools`) and the
Open Sans repository (SIL Open Font License 1.1); only three files of it
are needed:

    git clone --depth 1 --filter=blob:none --sparse \\
        https://github.com/googlefonts/opensans ~/opensans
    git -C ~/opensans sparse-checkout set --no-cone /OFL.txt \\
        /fonts/ttf/OpenSans-Regular.ttf /fonts/ttf/OpenSans-Bold.ttf
    python3 tools/genopensans.py ~/opensans

Writes src/retro/fonts/OpenSans.ttf, OpenSansBold.ttf (+ .ttf.z) and
OpenSans-OFL.txt. What it changes, for the kit's text engine (which reads
TrueType outlines, no OpenType layout):

* the characters kept: Latin (with Vietnamese), Greek, Cyrillic, the
  punctuation and symbols the UI uses -- nearly all the font has; Arabic
  and what else it lacks come from the kit's other faces;
* the hinting, the layout tables (GSUB, GPOS, GDEF: marks only -- the
  static fonts of Open Sans 3.003 have no kerning) and the glyph names
  dropped: the kit fits outlines to the pixels itself and places marks.

The outlines, advances and line metrics are the font's own.
"""
import os, shutil, sys, zlib
from fontTools.ttLib import TTFont
from fontTools import subset

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONTS = os.path.join(ROOT, "src", "retro", "fonts")

KEEP = ("U+0020-007E,U+00A0-024F,U+0250-02FF,U+0300-036F,U+0370-03FF,U+0400-052F,"
        "U+1E00-1EFF,U+1F00-1FFF,U+2000-206F,U+20A0-20CF,U+2100-218F,U+2190-21FF,"
        "U+2200-22FF,U+2500-25FF,U+FB00-FB06,U+FFFD")


def unicodes(spec):
    out = []
    for part in spec.split(","):
        a, _, b = part[2:].partition("-")
        out += range(int(a, 16), int(b or a, 16) + 1)
    return out


def build(src, dst):
    f = TTFont(src)
    opts = subset.Options()
    opts.layout_features = []
    opts.drop_tables += ["GSUB", "GPOS", "GDEF", "DSIG", "gasp", "FFTM"]
    opts.hinting = False
    opts.glyph_names = False
    opts.notdef_outline = True
    opts.name_IDs = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14]
    opts.name_languages = [0x409]
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=unicodes(KEEP))
    sub.subset(f)
    f.recalcTimestamp = False          # (the font's own date: the same bytes every time)
    f.save(dst)
    data = open(dst, "rb").read()
    open(dst + ".z", "wb").write(zlib.compress(data, 9))
    print("%s: %d characters, %d bytes (%d packed)" %
          (os.path.basename(dst), len(f.getBestCmap()), len(data), os.path.getsize(dst + ".z")))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    repo = sys.argv[1]
    build(os.path.join(repo, "fonts", "ttf", "OpenSans-Regular.ttf"), os.path.join(FONTS, "OpenSans.ttf"))
    build(os.path.join(repo, "fonts", "ttf", "OpenSans-Bold.ttf"), os.path.join(FONTS, "OpenSansBold.ttf"))
    shutil.copy(os.path.join(repo, "OFL.txt"), os.path.join(FONTS, "OpenSans-OFL.txt"))


if __name__ == "__main__":
    main()
