# ctypes access to the libwebp that Pillow bundles (1.6.0): the full WebPConfig.
import ctypes, glob
from PIL import Image
LIB = glob.glob('/usr/local/lib/python3.13/site-packages/pillow.libs/libwebp-*.so*')[0]
lib = ctypes.CDLL(LIB)
FIELDS = ['lossless','quality','method','image_hint','target_size','target_PSNR','segments',
  'sns_strength','filter_strength','filter_sharpness','filter_type','autofilter','alpha_compression',
  'alpha_filtering','alpha_quality','pass','show_compressed','preprocessing','partitions',
  'partition_limit','emulate_jpeg_size','thread_level','low_memory','near_lossless','exact',
  'use_delta_palette','use_sharp_yuv','qmin','qmax']
class Config(ctypes.Structure):
    _fields_ = [(f, ctypes.c_float if f in ('quality','target_PSNR') else ctypes.c_int) for f in FIELDS]
class MemWriter(ctypes.Structure):
    _fields_ = [('mem', ctypes.c_void_p), ('size', ctypes.c_size_t), ('max_size', ctypes.c_size_t), ('pad', ctypes.c_uint32*1)]
ENC_ABI = 0x0210
lib.WebPConfigInitInternal.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_float, ctypes.c_int]
lib.WebPPictureInitInternal.argtypes = [ctypes.c_void_p, ctypes.c_int]
lib.WebPPictureImportRGBA.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
lib.WebPEncode.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
lib.WebPMemoryWriterInit.argtypes = [ctypes.c_void_p]
lib.WebPPictureFree.argtypes = [ctypes.c_void_p]
lib.WebPMemoryWriterClear.argtypes = [ctypes.c_void_p]
lib.WebPValidateConfig.argtypes = [ctypes.c_void_p]
WRITER = ctypes.cast(lib.WebPMemoryWrite, ctypes.c_void_p).value
# offsets inside WebPPicture (x86-64): use_argb 0, colorspace 4, width 8, height 12,
# writer 96, custom_ptr 104, error_code 136
def encode(img, **opts):
    """img: PIL image (RGB or RGBA). opts: WebPConfig fields. Returns the .webp bytes."""
    img = img.convert('RGBA')
    cfg = Config()
    assert lib.WebPConfigInitInternal(ctypes.byref(cfg), 0, 75.0, ENC_ABI)
    for k, v in opts.items(): setattr(cfg, k, v)
    assert lib.WebPValidateConfig(ctypes.byref(cfg)), opts
    pic = ctypes.create_string_buffer(512)
    assert lib.WebPPictureInitInternal(pic, ENC_ABI)
    ctypes.c_int.from_buffer(pic, 0).value = 1 if cfg.lossless else 0
    ctypes.c_int.from_buffer(pic, 8).value = img.width
    ctypes.c_int.from_buffer(pic, 12).value = img.height
    raw = img.tobytes()
    assert lib.WebPPictureImportRGBA(pic, raw, img.width * 4)
    mw = MemWriter()
    lib.WebPMemoryWriterInit(ctypes.byref(mw))
    ctypes.c_void_p.from_buffer(pic, 96).value = WRITER
    ctypes.c_void_p.from_buffer(pic, 104).value = ctypes.addressof(mw)
    ok = lib.WebPEncode(ctypes.byref(cfg), pic)
    assert ok, ctypes.c_int.from_buffer(pic, 136).value
    out = ctypes.string_at(mw.mem, mw.size)
    lib.WebPMemoryWriterClear(ctypes.byref(mw))
    lib.WebPPictureFree(pic)
    return out
if __name__ == '__main__':
    import io
    im = Image.open('/usr/local/lib/python3.13/dist-packages/skimage/data/astronaut.png').crop((100,50,231,147))
    for o in [dict(quality=30, filter_type=0, filter_sharpness=3, partitions=3), dict(lossless=1, quality=100, method=6), dict(quality=80)]:
        b = encode(im, **o)
        d = Image.open(io.BytesIO(b)); d.load()
        print(o, len(b), d.size, d.mode, b[12:16])
