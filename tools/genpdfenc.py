#!/usr/bin/env python3
"""Writes src/retro/pdfencodings.nim: the encodings PDF fonts use
(Standard, WinAnsi, MacRoman) as glyph names, and glyph names to
characters (the Adobe Glyph List for new fonts), from fontTools."""
import os
from fontTools import agl
from fontTools.encodings import StandardEncoding, MacRoman
from fontTools.cffLib import cffStandardStrings

here = os.path.dirname(os.path.abspath(__file__))
uv2name = {}
for n, u in agl.AGL2UV.items():
    uv2name.setdefault(u, n)

def names_of(table):
    out = []
    for n in table:
        out.append('' if n in ('.notdef', None) else n)
    return out

std = names_of(StandardEncoding.StandardEncoding)
mac = names_of(MacRoman.MacRoman)
win = []
for code in range(256):
    if code < 32:
        win.append('')
        continue
    try:
        ch = bytes([code]).decode('cp1252')
    except UnicodeDecodeError:
        win.append('bullet' if code in (127, 129, 141, 143, 144, 157) else '')
        continue
    u = ord(ch)
    win.append(uv2name.get(u, 'uni%04X' % u))
win[32] = 'space'
win[160] = 'space'
win[173] = 'hyphen'

def nimlist(name, xs):
    s = 'const %s* = [\n' % name
    line = '  '
    for x in xs:
        item = '"%s", ' % x
        if len(line) + len(item) > 110:
            s += line.rstrip() + '\n'
            line = '  '
        line += item
    s += line.rstrip().rstrip(',') + ']\n'
    return s

pairs = sorted(agl.AGL2UV.items())
out = ['## Encodings of PDF fonts and the Adobe Glyph List (for new fonts), for',
       '## pdfread. Made by tools/genpdfenc.py from fontTools -- edit that.',
       '']
out.append(nimlist('standardEncoding', std))
out.append(nimlist('macRomanEncoding', mac))
out.append(nimlist('winAnsiEncoding', win))
out.append(nimlist('cffStandardStrings', list(cffStandardStrings)))
import unicodedata
forms = []
for cp in list(range(0xFB50, 0xFE00)) + list(range(0xFE70, 0xFF00)):
    ch = chr(cp)
    if unicodedata.category(ch) == 'Cn': continue
    d = unicodedata.normalize('NFKC', ch)
    if d != ch and all(ord(c) < 0xFB50 for c in d):
        forms.append('%X=%s' % (cp, ','.join('%X' % ord(c) for c in d)))
out.append('const arabicFormsData* = "%s"\n  ## presentation form=base letters (hex)|...' % '|'.join(forms))
# the widths of the 14 standard fonts (Adobe's Core 14 AFM files, as
# reportlab carries them): fonts that are named, not embedded
try:
    from reportlab.pdfbase import _fontdata
    parts = []
    for fn in ('Helvetica', 'Helvetica-Bold', 'Times-Roman', 'Times-Bold', 'Times-Italic',
               'Times-BoldItalic', 'Symbol', 'ZapfDingbats'):
        ws = _fontdata.widthsByFontGlyph[fn]
        parts.append(fn + ':' + ','.join('%s=%d' % (g, w) for g, w in sorted(ws.items())))
    out.append('const afmWidthsData* = "%s"\n  ## font:glyph=width,...|... (1/1000 em; Courier: all 600)' % '|'.join(parts))
except ImportError:
    raise SystemExit('reportlab is needed for the standard fonts\' widths')
names = '|'.join('%s=%X' % (n, u) for n, u in pairs)
out.append('const glyphListData* = "%s"\n  ## name=hex|...' % names)
open(os.path.join(here, '..', 'src', 'retro', 'pdfencodings.nim'), 'w').write('\n'.join(out) + '\n')
print(len(pairs), 'names')
