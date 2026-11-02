"""Makes the pictures tests/test_systemimage.nim reads (run from this folder):
pip install pillow pillow-heif   (Pillow 11.2 or later reads and writes AVIF)

  ref.png         the picture, 8 bits
  ref16.png       a picture at 16 bits (for the 10-bit files)
  photo.heic      ref.png as an 8-bit HEIC (x265, 4:4:4)    + photo.heic.png: libheif's decode (pillow-heif)
  photo.avif      ref.png as an 8-bit AVIF (4:4:4)          + photo.avif.png: libavif's decode (Pillow)
  alpha.avif      ref.png with a see-through gradient        + alpha.avif.png
  deep.heic       ref16.png as a 10-bit HEIC
  deep.avif       ref16.png as a 10-bit AVIF (libavif through ctypes: Pillow writes 8 bits only)
  turned.avif     ref.png stored with a quarter turn counter-clockwise ('irot' 1) and then
                  top and bottom exchanged ('imir' axis 0): shown, it is ref.png transposed
"""
import ctypes, struct
from PIL import Image
import pillow_heif

W, H = 96, 64

def ref_pixels():
    img = Image.new("RGB", (W, H))
    px = img.load()
    for y in range(H):
        for x in range(W):
            r = int(255 * x / (W - 1))
            g = int(255 * y / (H - 1))
            b = 200 if (x - 60) ** 2 + (y - 30) ** 2 < 15 ** 2 else 40
            if 10 <= x < 30 and 40 <= y < 56:
                r, g, b = 250, 250, 250
            px[x, y] = (r, g, b)
    return img

def ref16():
    """R G B at 16 bits: smooth ramps (big-endian rows for PNG)."""
    rows = []
    for y in range(H):
        row = b""
        for x in range(W):
            r = int(65535 * x / (W - 1))
            g = int(65535 * y / (H - 1))
            b = int(65535 * ((x + y) / (W + H - 2)) ** 2)
            row += struct.pack(">HHH", r, g, b)
        rows.append(row)
    return rows

ref = ref_pixels()
ref.save("ref.png")

# 16-bit PNG by hand (Pillow cannot save 16-bit RGB)
import zlib
rows16 = ref16()
raw = b"".join(b"\x00" + r for r in rows16)
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 16, 2, 0, 0, 0)) + \
      chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
open("ref16.png", "wb").write(png)

pillow_heif.register_heif_opener()
ref.save("photo.heic", quality=95, chroma=444)
Image.open("photo.heic").convert("RGB").save("photo.heic.png")

ref.save("photo.avif", quality=95, subsampling="4:4:4")
Image.open("photo.avif").convert("RGB").save("photo.avif.png")

rgba = ref.convert("RGBA")
a = rgba.load()
for y in range(H):
    for x in range(W):
        r, g, b, _ = a[x, y]
        a[x, y] = (r, g, b, int(255 * x / (W - 1)))
rgba.save("alpha.avif", quality=95, subsampling="4:4:4")
Image.open("alpha.avif").convert("RGBA").save("alpha.avif.png")

# 10-bit HEIC from the 16-bit picture
pillow_heif.options.SAVE_HDR_TO_12_BIT = False
data16 = b"".join(struct.pack("<%dH" % (W * 3), *struct.unpack(">%dH" % (W * 3), r)) for r in rows16)
hf = pillow_heif.from_bytes(mode="RGB;16", size=(W, H), data=data16)
hf.save("deep.heic", quality=95, chroma=444)

# 10-bit AVIF through libavif itself
lib = ctypes.CDLL("libavif.so.16")
class RGB(ctypes.Structure):
    _fields_ = [("width", ctypes.c_uint32), ("height", ctypes.c_uint32), ("depth", ctypes.c_uint32),
                ("format", ctypes.c_int), ("up", ctypes.c_int), ("down", ctypes.c_int),
                ("avoidLibYUV", ctypes.c_int), ("ignoreAlpha", ctypes.c_int),
                ("premultiplied", ctypes.c_int), ("isFloat", ctypes.c_int), ("maxThreads", ctypes.c_int),
                ("pixels", ctypes.c_void_p), ("rowBytes", ctypes.c_uint32), ("spare", ctypes.c_uint64 * 16)]
class RW(ctypes.Structure):
    _fields_ = [("data", ctypes.c_void_p), ("size", ctypes.c_size_t)]
lib.avifImageCreate.restype = ctypes.c_void_p
lib.avifEncoderCreate.restype = ctypes.c_void_p
img = lib.avifImageCreate(W, H, 10, 1)            # 10 bits, 4:4:4
rgb = RGB()
lib.avifRGBImageSetDefaults(ctypes.byref(rgb), ctypes.c_void_p(img))
rgba16 = b"".join(struct.pack("<%dH" % (W * 3), *struct.unpack(">%dH" % (W * 3), r)) for r in rows16)
buf16 = bytearray()
for i in range(W * H):
    buf16 += rgba16[6 * i: 6 * i + 6] + b"\xff\xff"
cbuf = (ctypes.c_uint8 * len(buf16)).from_buffer(buf16)
rgb.format, rgb.depth, rgb.ignoreAlpha = 1, 16, 1
rgb.pixels, rgb.rowBytes = ctypes.addressof(cbuf), W * 8
assert lib.avifImageRGBToYUV(ctypes.c_void_p(img), ctypes.byref(rgb)) == 0
enc = lib.avifEncoderCreate()
q = (ctypes.c_int * 10).from_address(enc)          # quality, qualityAlpha: ints 8 and 9 (libavif 1.x)
q[8] = q[9] = 95
out = RW()
assert lib.avifEncoderWrite(ctypes.c_void_p(enc), ctypes.c_void_p(img), ctypes.byref(out)) == 0
open("deep.avif", "wb").write(ctypes.string_at(out.data, out.size))
lib.avifRWDataFree(ctypes.byref(out))
lib.avifEncoderDestroy(ctypes.c_void_p(enc))
lib.avifImageDestroy(ctypes.c_void_p(img))

# turned.avif: the pixels stored so that turning them a quarter counter-clockwise and then
# exchanging top and bottom shows ref.png transposed; that is, stored as ref.png itself
# (transposing twice is nothing): what a decoder shows must be the transpose of ref.png
img = lib.avifImageCreate(W, H, 8, 1)
rgb = RGB()
lib.avifRGBImageSetDefaults(ctypes.byref(rgb), ctypes.c_void_p(img))
src = ref.convert("RGBA").tobytes()
cbuf = (ctypes.c_uint8 * len(src)).from_buffer(bytearray(src))
rgb.format, rgb.depth, rgb.ignoreAlpha = 1, 8, 1
rgb.pixels, rgb.rowBytes = ctypes.addressof(cbuf), W * 4
assert lib.avifImageRGBToYUV(ctypes.c_void_p(img), ctypes.byref(rgb)) == 0
# (libavif 1.x avifImage: transformFlags at 116, irot.angle at 160, imir.axis at 161)
ctypes.c_uint32.from_address(img + 116).value = (1 << 2) | (1 << 3)   # IROT | IMIR
ctypes.c_uint8.from_address(img + 160).value = 1
ctypes.c_uint8.from_address(img + 161).value = 0
enc = lib.avifEncoderCreate()
q = (ctypes.c_int * 10).from_address(enc)
q[8] = q[9] = 95
out = RW()
assert lib.avifEncoderWrite(ctypes.c_void_p(enc), ctypes.c_void_p(img), ctypes.byref(out)) == 0
open("turned.avif", "wb").write(ctypes.string_at(out.data, out.size))
lib.avifRWDataFree(ctypes.byref(out))
lib.avifEncoderDestroy(ctypes.c_void_p(enc))
lib.avifImageDestroy(ctypes.c_void_p(img))
print("made", W, "x", H)
