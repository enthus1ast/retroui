# Makes the JPEG XL test files of tests/test_jxl.nim with libjxl 0.12 (the
# copy the imagecodecs wheel carries, reached through ctypes: lj.py), and
# prints each file's reference as libjxl decodes it: for a lossless file the
# CRC-32 of its pixels (R G B A bytes, row by row; each frame of an animation
# as libjxl coalesces it) and the frame's duration in milliseconds; for a
# lossy file the same, and its pixels as <name>.png (the frames one under the
# other), for the test measures how far it is from them rather than asking
# for the same bytes (libjxl's float arithmetic and ours differ in the last
# bit now and then).
#
#   python3 make.py OUTDIR               (the files libjxl writes)
#   python3 make.py --refs FILES...      (the references of other files, e.g.
#                                         the retro-*.jxl this module wrote)
#
# Pictures: crops of tests/data/webp/astronaut-q75.png (scikit-image's
# astronaut, public domain) and drawn ones. splines.jxl and
# splines-first-frame.jxl (spline_on_first_frame.jxl there) come from
# libjxl's test data (https://github.com/libjxl/testdata, CC BY 4.0, the
# JPEG XL Project Authors): no encoder writes splines.
import io, os, struct, sys, zlib
sys.dont_write_bytecode = True            # (nothing left beside the data)
import numpy as np
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lj


def frames_of(data, bits=8):
    r = lj.decode(data, bits)
    return r, [(fr, d) for fr, d in r['frames']]


def ms(r, ticks):
    a = r['info'].animation
    if not r['info'].have_animation or a.tps_numerator == 0:
        return 0
    return int(round(ticks * 1000.0 * a.tps_denominator / a.tps_numerator))


def ref_line(name, data, lossy=False):
    r, frames = frames_of(data)
    fs = ', '.join("(0x%08x'u32, %d)" % (zlib.crc32(f.tobytes()) & 0xffffffff, ms(r, d))
                   for f, d in frames)
    return '  ("%s", %d, %d, %s, @[%s]),' % (name, r['w'], r['h'], 'true' if lossy else 'false', fs)


if sys.argv[1] == '--refs':
    for f in sys.argv[2:]:
        print(ref_line(os.path.basename(f), open(f, 'rb').read()))
    sys.exit(0)

OUT = sys.argv[1]
lines = []


def save(name, data, lossy=False, what=''):
    open(os.path.join(OUT, name), 'wb').write(data)
    if lossy:
        r, frames = frames_of(data)
        strip = np.concatenate([f for f, _ in frames], axis=0)
        Image.fromarray(strip, 'RGBA').save(os.path.join(OUT, name[:-4] + '.png'), optimize=True)
    lines.append('  # ' + what)
    lines.append(ref_line(name, data, lossy))


astro = np.asarray(Image.open(os.path.join(HERE, '..', 'webp', 'astronaut-q75.png')).convert('RGB'))
photo = np.ascontiguousarray(astro[20:68, 40:104])          # 64x48
photo96 = np.ascontiguousarray(astro[10:82, 30:126])        # 96x72
yy, xx = np.mgrid[:48, :64]
alpha = np.clip(255 - ((xx - 32) ** 2 + (yy - 24) ** 2) // 4, 0, 255).astype(np.uint8)
alpha[:, :6] = 0                                            # (fully clear)
rgba = np.dstack([photo, alpha])


def drawn(w, h, seed):
    rng = np.random.default_rng(seed)
    img = Image.new('RGB', (w, h), (240, 236, 220))
    d = ImageDraw.Draw(img)
    cols = [(200, 40, 40), (30, 90, 200), (20, 20, 20), (250, 200, 30), (60, 160, 80)]
    for i in range(12):
        x, y = int(rng.integers(0, w)), int(rng.integers(0, h))
        s = int(rng.integers(8, max(9, w // 3)))
        c = cols[i % len(cols)]
        if i % 3 == 0:
            d.rectangle([x, y, x + s, y + s // 2], fill=c)
        elif i % 3 == 1:
            d.ellipse([x, y, x + s, y + s], outline=c, width=2)
        else:
            d.line([x, y, x + s, y + s // 3], fill=c, width=3)
    d.text((4, 4), 'retro jxl', fill=(0, 0, 0))
    return np.asarray(img)


# ---- lossless: the same pixels as libjxl, exactly
save('ll-photo-e1.jxl', lj.encode([photo], lossless=True, effort=1),
     what='modular lossless 64x48, effort 1 (libjxl\'s fast lossless writer)')
save('ll-photo-e7.jxl', lj.encode([photo], lossless=True, effort=7),
     what='modular lossless, effort 7: weighted predictor, MA tree, ANS')
save('ll-graphic-e9.jxl', lj.encode([drawn(96, 64, 1)], lossless=True, effort=9),
     what='modular lossless drawing 96x64, effort 9: palette')
save('ll-alpha.jxl', lj.encode([rgba], lossless=True, effort=3),
     what='modular lossless with alpha (some of it 0), effort 3')
save('ll-gray.jxl', lj.encode([photo[:, :, 1:2]], lossless=True, effort=7),
     what='modular lossless grayscale')
g16 = np.zeros((32, 48, 3), np.uint16)
y16, x16 = np.mgrid[:32, :48]
g16[:, :, 0] = (x16 * 1365 + y16 * 7) % 65536
g16[:, :, 1] = 65535 - y16 * 2047 - x16
g16[:, :, 2] = (x16 * y16 * 41) % 65536
save('ll-16.jxl', lj.encode([g16], lossless=True, bits=16, effort=7),
     what='modular lossless, 16 bits a sample')
save('ll-groups.jxl', lj.encode([drawn(300, 260, 2)], lossless=True, effort=2,
                                options={lj.MODULAR_GROUP_SIZE: 0}),
     what='modular lossless 300x260 in nine groups of 128x128, effort 2')
save('ll-squeeze.jxl', lj.encode([photo], lossless=True, options={lj.RESPONSIVE: 1}),
     what='modular lossless, responsive: the squeeze transform')
txt = Image.new('RGB', (160, 48), (250, 250, 245))
d = ImageDraw.Draw(txt)
for i in range(4):
    d.text((3, 2 + 11 * i), 'jxl patches jxl patches', fill=(20, 30, 90))
save('ll-patches.jxl', lj.encode([np.asarray(txt)], lossless=True, effort=7, options={lj.PATCHES: 1}),
     what='modular lossless text 160x48: patches')
save('ll-orient6.jxl', lj.encode([photo[:32, :48]], lossless=True, effort=3, orientation=6),
     what='modular lossless 48x32 with orientation 6: shown turned, 32x48')
# the container by hand: ftyp, jxll, the codestream in three jxlp boxes, Exif between
cs = lj.encode([photo[:24, :32]], lossless=True, effort=3)


def box(t, payload):
    return struct.pack('>I', 8 + len(payload)) + t + payload


parts = [cs[:20], cs[20:60], cs[60:]]
cont = (b'\0\0\0\x0cJXL \r\n\x87\n' + box(b'ftyp', b'jxl \0\0\0\0jxl ') + box(b'jxll', b'\x05') +
        box(b'jxlp', struct.pack('>I', 0) + parts[0]) + box(b'Exif', b'\0\0\0\0MM\0\x2a\0\0\0\x08\0\0') +
        box(b'jxlp', struct.pack('>I', 1) + parts[1]) +
        box(b'jxlp', struct.pack('>I', 0x80000002) + parts[2]))
save('ll-container.jxl', cont, what='container 32x24: the codestream in three jxlp boxes, an Exif box among them')
frames = []
for k in range(4):
    f = rgba[:32, :48].copy()
    f[4:20, 2 + 10 * k:18 + 10 * k] = [255, 40, 40, 200]
    frames.append(f)
lay = [None, {'crop': (10, 6), 'blend': 2}, {'crop': (0, 16), 'blend': 0}, {'crop': (30, 2), 'blend': 1}]
fr = [frames[0], frames[1][:20, :30], frames[2][:16, :48], frames[3][:24, :16] // 2]
save('anim-ll.jxl', lj.encode(fr, lossless=True, tps=(100, 1), durations=[5, 10, 20, 7], layers=lay),
     what='lossless animation 48x32: frames cropped and blended (blend, replace, add)')

# ---- lossy: near libjxl's pixels
save('vd-d1.jxl', lj.encode([photo96], distance=1.0, effort=7), True,
     what='VarDCT 96x72 at distance 1, effort 7 (what cjxl writes by default)')
save('vd-alpha.jxl', lj.encode([rgba], distance=1.5), True, what='VarDCT with alpha')
save('vd-prog.jxl', lj.encode([photo96], distance=1.0, options={lj.PROGRESSIVE_AC: 1, lj.PROGRESSIVE_DC: 1}),
     True, what='VarDCT, progressive: AC in passes, LF in a frame of its own')
save('vd-noise.jxl', lj.encode([photo], distance=2.0, options={lj.EPF: 3}, float_options={lj.PHOTON_NOISE: 6400.0}),
     True, what='VarDCT with photon noise and three passes of the edge preserving filter')
save('vd-up2.jxl', lj.encode([photo96], distance=2.0, options={lj.RESAMPLING: 2}), True,
     what='VarDCT coded at half size, upsampled')
buf = io.BytesIO()
Image.fromarray(photo).save(buf, 'JPEG', quality=85, subsampling=2)
save('jpeg-420.jxl', lj.encode_jpeg(buf.getvalue(), container=True, store=True), True,
     what='a JPEG (4:2:0) recompressed, in a container with its jbrd box')
save('md-lossy.jxl', lj.encode([photo], distance=1.0, options={lj.MODULAR: 1}), True,
     what='modular lossy (quantized squeeze, XYB)')
af = []
for k in range(3):
    f = photo[:32, :48].copy()
    f[6:22, 4 + 12 * k:20 + 12 * k] = [40, 200, 255]
    af.append(f)
save('anim-lossy.jxl', lj.encode(af, distance=1.5, tps=(1000, 1), durations=[100, 250, 40]), True,
     what='VarDCT animation 48x32, three frames')
td = os.path.join(HERE, 'libjxl-testdata')
if os.path.isdir(td):                     # (once: the two files are kept here)
    for src, dst in [('spline_on_first_frame.jxl', 'splines-first-frame.jxl'), ('splines.jxl', 'splines.jxl')]:
        open(os.path.join(OUT, dst), 'wb').write(open(os.path.join(td, src), 'rb').read())
for name in ['splines-first-frame.jxl', 'splines.jxl']:
    data = open(os.path.join(OUT, name), 'rb').read()
    r, frs = frames_of(data)
    a = frs[0][0]
    if name == 'splines.jxl':
        a = a[0:128, 1024:1152]           # (a part of 2048x2048)
    Image.fromarray(np.ascontiguousarray(a), 'RGBA').save(os.path.join(OUT, name[:-4] + '.png'), optimize=True)
    lines.append('  # libjxl test data: splines')
    lines.append(ref_line(name, data, True))
# 12 megapixels, little in them: for the speed of decoding (effort 3: 8x8 blocks throughout)
big = np.zeros((3000, 4000, 3), np.uint8)
big[:] = (70, 120, 180)
by, bx = np.mgrid[:3000, :4000]
big[((bx - 2000) ** 2 + (by - 1500) ** 2) < 900 ** 2] = (200, 160, 60)
big[1000:1100] = (250, 250, 250)
data = lj.encode([big], distance=1.0, effort=3)
open(os.path.join(OUT, 'flat-12mp.jxl'), 'wb').write(data)
r, frs = frames_of(data)
a = frs[0][0]
print('# flat-12mp.jxl', len(data), 'bytes; pixels (x, y, RGBA):',
      [(x, y, '%02x%02x%02x%02x' % tuple(a[y, x])) for x, y in [(0, 0), (2000, 1500), (2000, 1050), (1101, 1500), (3999, 2999)]])
for name in ['ll-16.jxl', 'll-alpha.jxl']:   # 16 bits a sample: R G B A, little-endian
    r = lj.decode(open(os.path.join(OUT, name), 'rb').read(), 16)
    print('# %s at 16 bits: 0x%08x' % (name, zlib.crc32(r['frames'][0][0].astype('<u2').tobytes()) & 0xffffffff))
print('\n'.join(lines))
