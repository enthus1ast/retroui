"""libjxl (the copy the imagecodecs wheel carries, 0.12) through ctypes, for
make.py: it writes the JPEG XL test files and decodes them for the references.
Test tooling only -- retroui/jxl does not use it.

encode(frames, ...) -> bytes, encode_jpeg(jpeg) -> bytes, decode(data, bits) -> dict
"""
import ctypes as C
import glob
import os

import numpy as np

_libdir = os.path.join(os.path.dirname(__import__('imagecodecs').__file__) + '.libs')
_cands = sorted(glob.glob(os.path.join(_libdir, 'libjxl-*.so*')))
_cands = [c for c in _cands if 'threads' not in c and 'cms' not in c]
lib = C.CDLL(_cands[0])
_cms = C.CDLL(sorted(glob.glob(os.path.join(_libdir, 'libjxl_cms-*.so*')))[0])

B = C.c_int
u32 = C.c_uint32


class PreviewHeader(C.Structure):
    _fields_ = [('xsize', u32), ('ysize', u32)]


class AnimationHeader(C.Structure):
    _fields_ = [('tps_numerator', u32), ('tps_denominator', u32), ('num_loops', u32),
                ('have_timecodes', B)]


class BasicInfo(C.Structure):
    _fields_ = [('have_container', B), ('xsize', u32), ('ysize', u32),
                ('bits_per_sample', u32), ('exponent_bits_per_sample', u32),
                ('intensity_target', C.c_float), ('min_nits', C.c_float),
                ('relative_to_max_display', B), ('linear_below', C.c_float),
                ('uses_original_profile', B), ('have_preview', B), ('have_animation', B),
                ('orientation', C.c_int), ('num_color_channels', u32),
                ('num_extra_channels', u32), ('alpha_bits', u32), ('alpha_exponent_bits', u32),
                ('alpha_premultiplied', B), ('preview', PreviewHeader),
                ('animation', AnimationHeader), ('intrinsic_xsize', u32),
                ('intrinsic_ysize', u32), ('padding', C.c_uint8 * 100)]


class PixelFormat(C.Structure):
    _fields_ = [('num_channels', u32), ('data_type', C.c_int), ('endianness', C.c_int),
                ('align', C.c_size_t)]


class BlendInfo(C.Structure):
    _fields_ = [('blendmode', C.c_int), ('source', u32), ('alpha', u32), ('clamp', B)]


class LayerInfo(C.Structure):
    _fields_ = [('have_crop', B), ('crop_x0', C.c_int32), ('crop_y0', C.c_int32),
                ('xsize', u32), ('ysize', u32), ('blend_info', BlendInfo),
                ('save_as_reference', u32)]


class FrameHeader(C.Structure):
    _fields_ = [('duration', u32), ('timecode', u32), ('name_length', u32), ('is_last', B),
                ('layer_info', LayerInfo)]


class ExtraChannelInfo(C.Structure):
    _fields_ = [('type', C.c_int), ('bits_per_sample', u32), ('exponent_bits_per_sample', u32),
                ('dim_shift', u32), ('name_length', u32), ('alpha_premultiplied', B),
                ('spot_color', C.c_float * 4), ('cfa_channel', u32)]


class ColorEncoding(C.Structure):
    _fields_ = [('color_space', C.c_int), ('white_point', C.c_int),
                ('white_point_xy', C.c_double * 2), ('primaries', C.c_int),
                ('primaries_red_xy', C.c_double * 2), ('primaries_green_xy', C.c_double * 2),
                ('primaries_blue_xy', C.c_double * 2), ('transfer_function', C.c_int),
                ('gamma', C.c_double), ('rendering_intent', C.c_int)]


for name, res, args in [
        ('JxlEncoderCreate', C.c_void_p, [C.c_void_p]),
        ('JxlEncoderDestroy', None, [C.c_void_p]),
        ('JxlEncoderUseContainer', C.c_int, [C.c_void_p, B]),
        ('JxlEncoderInitBasicInfo', None, [C.c_void_p]),
        ('JxlEncoderSetBasicInfo', C.c_int, [C.c_void_p, C.c_void_p]),
        ('JxlEncoderSetColorEncoding', C.c_int, [C.c_void_p, C.c_void_p]),
        ('JxlColorEncodingSetToSRGB', None, [C.c_void_p, B]),
        ('JxlEncoderFrameSettingsCreate', C.c_void_p, [C.c_void_p, C.c_void_p]),
        ('JxlEncoderSetFrameLossless', C.c_int, [C.c_void_p, B]),
        ('JxlEncoderSetFrameDistance', C.c_int, [C.c_void_p, C.c_float]),
        ('JxlEncoderFrameSettingsSetOption', C.c_int, [C.c_void_p, C.c_int, C.c_int64]),
        ('JxlEncoderFrameSettingsSetFloatOption', C.c_int, [C.c_void_p, C.c_int, C.c_float]),
        ('JxlEncoderInitFrameHeader', None, [C.c_void_p]),
        ('JxlEncoderSetFrameHeader', C.c_int, [C.c_void_p, C.c_void_p]),
        ('JxlEncoderInitBlendInfo', None, [C.c_void_p]),
        ('JxlEncoderSetExtraChannelBlendInfo', C.c_int, [C.c_void_p, C.c_size_t, C.c_void_p]),
        ('JxlEncoderInitExtraChannelInfo', None, [C.c_int, C.c_void_p]),
        ('JxlEncoderSetExtraChannelInfo', C.c_int, [C.c_void_p, C.c_size_t, C.c_void_p]),
        ('JxlEncoderAddImageFrame', C.c_int, [C.c_void_p, C.c_void_p, C.c_void_p, C.c_size_t]),
        ('JxlEncoderAddJPEGFrame', C.c_int, [C.c_void_p, C.c_void_p, C.c_size_t]),
        ('JxlEncoderStoreJPEGMetadata', C.c_int, [C.c_void_p, B]),
        ('JxlEncoderCloseInput', None, [C.c_void_p]),
        ('JxlEncoderProcessOutput', C.c_int, [C.c_void_p, C.c_void_p, C.c_void_p]),
        ('JxlEncoderGetError', C.c_int, [C.c_void_p]),
        ('JxlEncoderSetCodestreamLevel', C.c_int, [C.c_void_p, C.c_int]),
        ('JxlDecoderCreate', C.c_void_p, [C.c_void_p]),
        ('JxlDecoderDestroy', None, [C.c_void_p]),
        ('JxlDecoderSubscribeEvents', C.c_int, [C.c_void_p, C.c_int]),
        ('JxlDecoderSetInput', C.c_int, [C.c_void_p, C.c_void_p, C.c_size_t]),
        ('JxlDecoderCloseInput', None, [C.c_void_p]),
        ('JxlDecoderProcessInput', C.c_int, [C.c_void_p]),
        ('JxlDecoderGetBasicInfo', C.c_int, [C.c_void_p, C.c_void_p]),
        ('JxlDecoderGetFrameHeader', C.c_int, [C.c_void_p, C.c_void_p]),
        ('JxlDecoderImageOutBufferSize', C.c_int, [C.c_void_p, C.c_void_p, C.c_void_p]),
        ('JxlDecoderSetImageOutBuffer', C.c_int, [C.c_void_p, C.c_void_p, C.c_void_p, C.c_size_t]),
        ('JxlDecoderSetUnpremultiplyAlpha', C.c_int, [C.c_void_p, B]),
        ('JxlDecoderSetKeepOrientation', C.c_int, [C.c_void_p, B]),
        ('JxlDecoderSetCoalescing', C.c_int, [C.c_void_p, B]),
        ('JxlDecoderSetPreferredColorProfile', C.c_int, [C.c_void_p, C.c_void_p]),
]:
    f = getattr(lib, name)
    f.restype = res
    f.argtypes = args

EFFORT, RESAMPLING, PHOTON_NOISE, NOISE, DOTS, PATCHES, EPF, GABORISH, MODULAR = 0, 2, 5, 6, 7, 8, 9, 10, 11
RESPONSIVE, PROGRESSIVE_AC, QPROGRESSIVE_AC, PROGRESSIVE_DC = 16, 17, 18, 19
PALETTE_COLORS, COLOR_TRANSFORM, MODULAR_GROUP_SIZE, MODULAR_PREDICTOR = 22, 24, 26, 27
EC_RESAMPLING = 3


def _check(ok, what, enc=None):
    if ok != 0:
        err = lib.JxlEncoderGetError(enc) if enc else -1
        raise RuntimeError('%s failed (%s)' % (what, err))


def _drain(enc):
    out = bytearray()
    buf = C.create_string_buffer(1 << 20)
    while True:
        nxt = C.c_void_p(C.addressof(buf))
        avail = C.c_size_t(len(buf))
        st = lib.JxlEncoderProcessOutput(enc, C.byref(nxt), C.byref(avail))
        out += buf.raw[:len(buf) - avail.value]
        if st == 0:
            return bytes(out)
        if st != 2:
            raise RuntimeError('encode failed: %d' % lib.JxlEncoderGetError(enc))


def encode(frames, *, distance=1.0, lossless=False, effort=7, container=False,
           bits=8, tps=None, durations=None, options=None, float_options=None, layers=None,
           alpha_premultiplied=False, gray=False, level=None, orientation=1):
    """frames: list of uint8/uint16 arrays (h, w, c) with c in 1..4 (2/4 = alpha)."""
    a0 = frames[0]
    h, w = a0.shape[:2]
    nc = a0.shape[2]
    has_alpha = nc in (2, 4)
    enc = lib.JxlEncoderCreate(None)
    try:
        if level is not None:
            _check(lib.JxlEncoderSetCodestreamLevel(enc, level), 'level', enc)
        _check(lib.JxlEncoderUseContainer(enc, 1 if container else 0), 'container', enc)
        bi = BasicInfo()
        lib.JxlEncoderInitBasicInfo(C.byref(bi))
        bi.xsize, bi.ysize = w, h
        bi.bits_per_sample = bits
        bi.num_color_channels = 1 if nc <= 2 else 3
        bi.num_extra_channels = 1 if has_alpha else 0
        bi.alpha_bits = bits if has_alpha else 0
        bi.alpha_premultiplied = 1 if alpha_premultiplied else 0
        bi.uses_original_profile = 1 if lossless else 0
        bi.orientation = orientation
        if tps is not None:
            bi.have_animation = 1
            bi.animation.tps_numerator, bi.animation.tps_denominator = tps
            bi.animation.num_loops = 0
        _check(lib.JxlEncoderSetBasicInfo(enc, C.byref(bi)), 'basic info', enc)
        ce = ColorEncoding()
        lib.JxlColorEncodingSetToSRGB(C.byref(ce), 1 if nc <= 2 else 0)
        _check(lib.JxlEncoderSetColorEncoding(enc, C.byref(ce)), 'color', enc)
        fs = lib.JxlEncoderFrameSettingsCreate(enc, None)
        if lossless:
            _check(lib.JxlEncoderSetFrameLossless(fs, 1), 'lossless', enc)
        else:
            _check(lib.JxlEncoderSetFrameDistance(fs, distance), 'distance', enc)
        _check(lib.JxlEncoderFrameSettingsSetOption(fs, EFFORT, effort), 'effort', enc)
        for k, v in (options or {}).items():
            _check(lib.JxlEncoderFrameSettingsSetOption(fs, k, v), 'option %d' % k, enc)
        for k, v in (float_options or {}).items():
            _check(lib.JxlEncoderFrameSettingsSetFloatOption(fs, k, v), 'foption %d' % k, enc)
        dt = 2 if bits <= 8 else 3
        for i, a in enumerate(frames):
            a = np.ascontiguousarray(a, dtype=np.uint8 if dt == 2 else '<u2')
            if tps is not None or layers is not None:
                fh = FrameHeader()
                lib.JxlEncoderInitFrameHeader(C.byref(fh))
                if durations is not None:
                    fh.duration = durations[i]
                if layers is not None and layers[i] is not None:
                    L = layers[i]
                    if 'crop' in L:
                        fh.layer_info.have_crop = 1
                        (fh.layer_info.crop_x0, fh.layer_info.crop_y0) = L['crop']
                        fh.layer_info.xsize = a.shape[1]
                        fh.layer_info.ysize = a.shape[0]
                    if 'blend' in L:
                        fh.layer_info.blend_info.blendmode = L['blend']
                    fh.layer_info.blend_info.source = L.get('source', 0)
                    fh.layer_info.save_as_reference = L.get('save', 0)
                _check(lib.JxlEncoderSetFrameHeader(fs, C.byref(fh)), 'frame header', enc)
                if has_alpha and layers is not None and layers[i] is not None and 'blend' in layers[i]:
                    b = BlendInfo()
                    lib.JxlEncoderInitBlendInfo(C.byref(b))
                    b.blendmode = layers[i]['blend']
                    b.source = layers[i].get('source', 0)
                    _check(lib.JxlEncoderSetExtraChannelBlendInfo(fs, 0, C.byref(b)), 'ec blend', enc)
            pf = PixelFormat(a.shape[2], dt, 1, 0)
            _check(lib.JxlEncoderAddImageFrame(fs, C.byref(pf), a.ctypes.data, a.nbytes),
                   'add frame', enc)
        lib.JxlEncoderCloseInput(enc)
        return _drain(enc)
    finally:
        lib.JxlEncoderDestroy(enc)


def encode_jpeg(jpeg, container=False, store=False):
    enc = lib.JxlEncoderCreate(None)
    try:
        _check(lib.JxlEncoderUseContainer(enc, 1 if container or store else 0), 'container', enc)
        if store:
            _check(lib.JxlEncoderStoreJPEGMetadata(enc, 1), 'store', enc)
        fs = lib.JxlEncoderFrameSettingsCreate(enc, None)
        buf = C.create_string_buffer(jpeg, len(jpeg))
        _check(lib.JxlEncoderAddJPEGFrame(fs, buf, len(jpeg)), 'add jpeg', enc)
        lib.JxlEncoderCloseInput(enc)
        return _drain(enc)
    finally:
        lib.JxlEncoderDestroy(enc)


def decode(data, bits=8, keep_premul=False):
    """-> dict(w, h, frames=[(rgba array, duration_ticks)], info=BasicInfo)."""
    dec = lib.JxlDecoderCreate(None)
    try:
        _check(lib.JxlDecoderSubscribeEvents(dec, 0x40 | 0x400 | 0x1000), 'subscribe')
        buf = C.create_string_buffer(data, len(data))
        _check(lib.JxlDecoderSetInput(dec, buf, len(data)), 'input')
        lib.JxlDecoderCloseInput(dec)
        if not keep_premul:
            lib.JxlDecoderSetUnpremultiplyAlpha(dec, 1)
        bi = BasicInfo()
        frames = []
        dur = 0
        out = None
        dt = 2 if bits == 8 else 3
        pf = PixelFormat(4, dt, 1, 0)
        while True:
            st = lib.JxlDecoderProcessInput(dec)
            if st == 0x40:
                lib.JxlDecoderGetBasicInfo(dec, C.byref(bi))
            elif st == 0x400:
                fh = FrameHeader()
                lib.JxlDecoderGetFrameHeader(dec, C.byref(fh))
                dur = fh.duration
            elif st == 5:
                size = C.c_size_t()
                lib.JxlDecoderImageOutBufferSize(dec, C.byref(pf), C.byref(size))
                out = np.zeros(size.value // (1 if dt == 2 else 2), np.uint8 if dt == 2 else np.uint16)
                _check(lib.JxlDecoderSetImageOutBuffer(dec, C.byref(pf), out.ctypes.data, out.nbytes),
                       'out buffer')
            elif st == 0x1000:
                frames.append((out.reshape(bi.ysize, bi.xsize, 4).copy(), dur))
            elif st == 0:
                break
            else:
                raise RuntimeError('decode failed: status %d' % st)
        return dict(w=bi.xsize, h=bi.ysize, frames=frames, info=bi)
    finally:
        lib.JxlDecoderDestroy(dec)
