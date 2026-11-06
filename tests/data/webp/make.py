# Makes the WebP test files of tests/test_webp.nim with libwebp 1.6.0 (the
# one Pillow 12 carries, reached through ctypes for the settings Pillow does
# not offer), and prints each file's reference: the CRC-32 of its pixels as
# libwebp decodes them (R G B A bytes, row by row; for an animation, each
# frame as WebPAnimDecoder composes it, and its duration).
#
#   python3 make.py OUTDIR > manifest.txt      (the files libwebp writes)
#   python3 make.py --refs FILES...             (the references of other files,
#                                                e.g. the retro-*.webp this module wrote)
#
# Pictures: crops of scikit-image's astronaut/coffee/chelsea/rocket (public
# domain / CC0) and scikit-learn's china.jpg, and drawn ones.
import io, sys, os, struct, zlib, random
sys.dont_write_bytecode = True            # (nothing left beside the data)
from PIL import Image, ImageDraw, ImageSequence
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lw import encode

if sys.argv[1] == '--refs':
    for f in sys.argv[2:]:
        data = open(f, 'rb').read()
        im = Image.open(io.BytesIO(data))
        frames = []
        for fr in ImageSequence.Iterator(im):
            frames.append((zlib.crc32(fr.convert('RGBA').tobytes()) & 0xffffffff, fr.info.get('duration', 0)))
        fs = ', '.join('(0x%08x\'u32, %d)' % fr for fr in frames)
        print('  ("%s", %d, %d, @[%s]),  # %s: written by retroui/webp' % (os.path.basename(f), im.size[0], im.size[1], fs, data[12:16].decode('latin1').strip()))
    sys.exit(0)

OUT = sys.argv[1]
SK = '/usr/local/lib/python3.13/dist-packages/skimage/data/'
SL = '/usr/local/lib/python3.13/dist-packages/sklearn/datasets/images/'
os.makedirs(OUT, exist_ok=True)
manifest = []

def crc_frames(data):
    im = Image.open(io.BytesIO(data))
    out = []
    for fr in ImageSequence.Iterator(im):
        rgba = fr.convert('RGBA')
        out.append((zlib.crc32(rgba.tobytes()) & 0xffffffff, fr.info.get('duration', 0)))
    return im.size, out

def save(name, data, note):
    with open(os.path.join(OUT, name), 'wb') as f: f.write(data)
    size, frames = crc_frames(data)
    kind = data[12:16].decode('latin1')
    manifest.append((name, size, frames, kind, note))

def photo(path, box, size=None):
    im = Image.open(path).convert('RGB')
    im = im.crop(box)
    if size: im = im.resize(size, Image.LANCZOS)
    return im

def with_alpha(im, kind=0):
    w, h = im.size
    a = Image.new('L', (w, h))
    px = a.load()
    for y in range(h):
        for x in range(w):
            if kind == 0:   # radial, a clear hole and an opaque band
                d = ((x - w * 0.4) ** 2 + (y - h * 0.5) ** 2) ** 0.5
                v = max(0, min(255, int(255 - d * 3)))
                if x > w * 0.8: v = 255
                if (x // 9 + y // 7) % 5 == 0: v = 0
            else:           # stripes and steps
                v = (x * 255 // max(1, w - 1)) if y < h // 2 else ((y * 37) % 256)
            px[x, y] = v
    im = im.convert('RGBA'); im.putalpha(a)
    return im

def graphic(w, h, colors=None, seed=1):
    rnd = random.Random(seed)
    im = Image.new('RGB', (w, h), (250, 250, 245))
    d = ImageDraw.Draw(im)
    pal = colors or [(rnd.randrange(256), rnd.randrange(256), rnd.randrange(256)) for _ in range(12)]
    for i in range(40):
        c = pal[i % len(pal)]
        x0, y0 = rnd.randrange(w), rnd.randrange(h)
        x1, y1 = x0 + rnd.randrange(4, w // 2), y0 + rnd.randrange(3, h // 2)
        if i % 3 == 0: d.rectangle([x0, y0, x1, y1], fill=c)
        elif i % 3 == 1: d.ellipse([x0, y0, x1, y1], outline=c, width=2)
        else: d.line([x0, y0, x1, y1], fill=c, width=1)
    if colors is None:
        d.text((4, 4), "WebP 1.6", fill=(10, 10, 10))
    return im

astro = SK + 'astronaut.png'; coffee = SK + 'coffee.png'; chelsea = SK + 'chelsea.png'
rocket = SK + 'rocket.jpg'; china = SL + 'china.jpg'

# ---- lossy (VP8) ----
save('astronaut-q75.webp', encode(photo(astro, (180, 60, 331, 173)), quality=75),
     'lossy 151x113, default settings: 4 segments, normal filter')
save('coffee-q30-simple.webp', encode(photo(coffee, (200, 100, 360, 197)), quality=30,
     filter_type=0, filter_sharpness=3, partitions=3), 'lossy, simple filter, sharpness 3, 8 partitions')
save('chelsea-q92-sharp.webp', encode(photo(chelsea, (100, 80, 197, 141)), quality=92,
     filter_sharpness=6, sns_strength=100, method=6, partitions=2, filter_strength=80),
     'lossy, sharpness 6, 4 partitions')
save('china-q5.webp', encode(photo(china, (0, 0, 640, 427), (128, 85)), quality=5,
     filter_strength=100, method=2), 'lossy, very low quality, strongest filter')
save('graphic-q50.webp', encode(graphic(129, 67), quality=50, segments=1, filter_strength=0,
     sns_strength=0, method=0), 'lossy graphic, one segment, no filter')
save('rocket-q60-auto.webp', encode(photo(rocket, (150, 180, 220, 291)), quality=60, autofilter=1,
     method=6, segments=3, use_sharp_yuv=1), 'lossy, autofilter, 3 segments')
save('tiny-3x1.webp', encode(photo(astro, (200, 200, 203, 201)), quality=80), 'lossy 3x1')
save('tiny-1x17.webp', encode(photo(coffee, (300, 100, 301, 117)), quality=80), 'lossy 1x17')

# ---- lossy with alpha (VP8X + ALPH + VP8) ----
save('alpha-q70.webp', encode(with_alpha(photo(astro, (150, 150, 251, 227))), quality=70),
     'lossy + alpha (lossless-coded alpha, fast filter)')
save('alpha-raw-q60.webp', encode(with_alpha(photo(chelsea, (60, 60, 151, 131)), 1), quality=60,
     alpha_compression=0, alpha_filtering=2), 'lossy + raw alpha, best filter')
save('alpha-levels-q60.webp', encode(with_alpha(photo(coffee, (50, 250, 141, 321))), quality=60,
     alpha_quality=40, alpha_filtering=2), 'lossy + alpha with reduced levels')

# raw ALPH with each filter, written by hand (libwebp's filters, filters.c)
def filt(a, w, h, mode):
    out = bytearray(w * h)
    def P(x, y): return a[y * w + x]
    for y in range(h):
        for x in range(w):
            if mode == 0: pred = 0
            elif y == 0: pred = 0 if x == 0 else P(x - 1, 0)
            elif x == 0: pred = P(0, y - 1)
            elif mode == 1: pred = P(x - 1, y)
            elif mode == 2: pred = P(x, y - 1)
            else:
                g = P(x - 1, y) + P(x, y - 1) - P(x - 1, y - 1)
                pred = 0 if g < 0 else 255 if g > 255 else g
            out[y * w + x] = (P(x, y) - pred) & 255
    return bytes(out)

def chunk(tag, body):
    return tag + struct.pack('<I', len(body)) + body + (b'\0' if len(body) & 1 else b'')

def riff(chunks):
    body = b'WEBP' + b''.join(chunks)
    return b'RIFF' + struct.pack('<I', len(body)) + body

def vp8x(flags, w, h):
    return chunk(b'VP8X', bytes([flags, 0, 0, 0]) + (w - 1).to_bytes(3, 'little') + (h - 1).to_bytes(3, 'little'))

def chunks_of(data):
    out, p = [], 12
    while p + 8 <= len(data):
        tag, n = data[p:p + 4], struct.unpack('<I', data[p + 4:p + 8])[0]
        out.append((tag, data[p + 8:p + 8 + n])); p += 8 + n + (n & 1)
    return out

src = with_alpha(photo(rocket, (100, 200, 167, 249)))
w, h = src.size
vp8 = [c for c in chunks_of(encode(src.convert('RGB'), quality=70)) if c[0] == b'VP8 '][0]
alpha = src.getchannel('A').tobytes()
for mode, nm in [(1, 'horizontal'), (2, 'vertical'), (3, 'gradient')]:
    body = bytes([0 | (mode << 2)]) + filt(alpha, w, h, mode)
    data = riff([vp8x(0x10, w, h), chunk(b'ALPH', body), chunk(*vp8), chunk(b'XYZW', b'skip me')])
    save('alpha-raw-%s.webp' % nm, data, 'hand-made raw ALPH, %s filter, unknown chunk' % nm)

# ---- lossless (VP8L) ----
save('ll-photo-m4.webp', encode(photo(chelsea, (120, 90, 240, 180)), lossless=1, exact=1),
     'lossless photo, default method 4')
save('ref-q75.webp', encode(photo(chelsea, (120, 90, 240, 180)), quality=75),
     'the picture of ll-photo-m4.webp, lossy at quality 75 (for comparing encoders)')
save('ll-photo-m6.webp', encode(photo(coffee, (300, 200, 396, 272)), lossless=1, quality=100, method=6),
     'lossless photo, method 6 quality 100')
save('ll-photo-m0.webp', encode(photo(astro, (300, 300, 396, 364)), lossless=1, quality=0, method=0),
     'lossless photo, method 0 quality 0')
pal = [(0, 0, 0), (255, 255, 255), (200, 30, 30), (30, 200, 30), (30, 30, 200), (240, 200, 0),
       (0, 160, 160), (128, 0, 128), (90, 90, 90), (250, 128, 64), (64, 128, 250), (10, 70, 10)]
save('ll-palette12.webp', encode(graphic(77, 45, pal), lossless=1), 'lossless, 12 colors (2 a byte)')
save('ll-palette4.webp', encode(graphic(63, 31, pal[:4], 2), lossless=1), 'lossless, 4 colors (4 a byte)')
save('ll-palette2.webp', encode(graphic(45, 21, pal[:2], 3), lossless=1), 'lossless, 2 colors (8 a byte)')
rn = random.Random(7)
g = Image.new('RGB', (64, 64)); gp = g.load()
for y in range(64):
    for x in range(64): gp[x, y] = (((x // 3) * 13 + (y // 2) * 7 + rn.randrange(3)) % 200, (x * 3) % 200, 60)
save('ll-palette200.webp', encode(g, lossless=1, method=5), 'lossless, ~200 colors (palette, 1 a byte)')
save('ll-alpha.webp', encode(with_alpha(photo(astro, (40, 40, 120, 100))), lossless=1, exact=1),
     'lossless with alpha')
save('ll-near60.webp', encode(photo(china, (300, 200, 380, 260)), lossless=1, near_lossless=60),
     'near-lossless 60 (a VP8L stream)')
rn = random.Random(5)
noise = Image.frombytes('RGB', (40, 30), bytes(rn.randrange(256) for _ in range(3600)))
save('ll-noise.webp', encode(noise, lossless=1, method=3), 'lossless noise')
b = io.BytesIO(); photo(rocket, (0, 0, 48, 40)).save(b, 'WEBP', lossless=True, icc_profile=b'not really a profile', exif=b'Exif\0\0junk')
save('ll-icc-exif.webp', b.getvalue(), 'VP8X with ICCP and EXIF, lossless')

# ---- animations ----
def frames_scene(n, w, h, alpha):
    out = []
    for i in range(n):
        im = Image.new('RGBA', (w, h), (30, 60, 90, 128 if alpha else 255))
        d = ImageDraw.Draw(im)
        d.ellipse([4 + i * 6, 6 + i * 2, 24 + i * 6, 26 + i * 2], fill=(250, 200, 0, 255))
        d.rectangle([40 - i * 3, 20, 52 - i * 3, 40], fill=(200, 30, 30, 160 if alpha else 255))
        if alpha and i % 2: d.rectangle([0, 0, 10, 10], fill=(0, 0, 0, 0))
        out.append(im)
    return out

fr = frames_scene(6, 64, 48, True)
b = io.BytesIO()
fr[0].save(b, 'WEBP', save_all=True, append_images=fr[1:], duration=[80, 120, 40, 200, 60, 100],
           loop=0, allow_mixed=True, quality=70, kmin=2, kmax=3)
save('anim-mixed.webp', b.getvalue(), 'animation, mixed lossy/lossless, alpha, keyframes every 3')
fr = frames_scene(5, 64, 48, False)
b = io.BytesIO()
fr[0].save(b, 'WEBP', save_all=True, append_images=fr[1:], duration=70, loop=3, quality=60, minimize_size=True)
save('anim-lossy.webp', b.getvalue(), 'animation, lossy, sub-rectangles')

# by hand: offsets, dispose to background, blending, a lossy+alpha frame
def frame_payload(im, **opts):
    return b''.join(chunk(t, c) for t, c in chunks_of(encode(im, **opts)) if t in (b'ALPH', b'VP8 ', b'VP8L'))

def anmf(x, y, im, dur, dispose, blend, **opts):
    w, h = im.size
    head = (x // 2).to_bytes(3, 'little') + (y // 2).to_bytes(3, 'little') + (w - 1).to_bytes(3, 'little') + \
        (h - 1).to_bytes(3, 'little') + dur.to_bytes(3, 'little') + bytes([(0 if blend else 2) | (1 if dispose else 0)])
    return chunk(b'ANMF', head + frame_payload(im, **opts))

W, H = 60, 40
bgim = with_alpha(photo(astro, (0, 0, 60, 40)), 1)
spr = with_alpha(photo(coffee, (100, 100, 24, 100 + 0) if False else (100, 100, 124, 118)))
spr2 = Image.new('RGBA', (20, 16), (0, 0, 0, 0)); ImageDraw.Draw(spr2).ellipse([0, 0, 19, 15], fill=(20, 220, 90, 200))
parts = [vp8x(0x02 | 0x10, W, H), chunk(b'ANIM', bytes([10, 20, 30, 40]) + struct.pack('<H', 0)),
         anmf(0, 0, bgim, 100, False, False, lossless=1, exact=1),
         anmf(10, 8, spr, 50, True, True, quality=75),
         anmf(14, 12, spr2, 70, False, True, lossless=1, exact=1),
         anmf(30, 20, spr, 90, True, True, lossless=1),
         anmf(20, 4, spr2, 60, True, False, quality=50),
         anmf(0, 0, bgim.convert('RGB').convert('RGBA'), 40, False, True, quality=80),
         anmf(36, 22, spr2, 30, False, True, lossless=1)]
save('anim-handmade.webp', riff(parts), 'hand-made animation: offsets, dispose, blend, lossy+alpha frames')

# libwebp's pixels of one lossy file, kept whole (for the difference in levels)
Image.open(os.path.join(OUT, 'astronaut-q75.webp')).convert('RGB').save(os.path.join(OUT, 'astronaut-q75.png'), optimize=True)

for name, size, frames, kind, note in manifest:
    fs = ', '.join('(0x%08x\'u32, %d)' % f for f in frames)
    print('  ("%s", %d, %d, @[%s]),  # %s: %s' % (name, size[0], size[1], fs, kind.strip(), note))
total = sum(os.path.getsize(os.path.join(OUT, n)) for n, *_ in manifest)
print('# total bytes', total, file=sys.stderr)
