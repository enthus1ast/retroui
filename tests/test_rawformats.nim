## Tests of retroui/rawformats: cameras' own raw files (NEF, ARW, CR2, CR3,
## ORF, RW2, PEF, RAF) told apart, read number for number as LibRaw reads
## them, and developed as LibRaw develops them.
##
## Real camera files are big, so they are not kept here: each is looked for
## (by name) under tests/data/raw and under $RETRO_RAW_SAMPLES, and its test
## is skipped when it is not found. They are genuine files from GitHub:
## drewnoakes/metadata-extractor-images ("arw/Sony NEX-7.arw" is kept as
## "arw_Sony_NEX-7.arw", "cr3/_MG_0039.CR3" as "cr3__MG_0039.CR3", and so
## on), letmaik/rawpy's test/ (iss*.NEF, RAW_CANON_5DMARK2_PREPROD.CR2),
## AcademySoftwareFoundation/OpenImageIO-images' raw/ (RAW_*) and
## lclevy/canon_cr3's samples/ ("IMG_0482_raw.CR3" kept as
## "cr3_lclevy_IMG_0482_raw.CR3"). The numbers they are checked against
## come from LibRaw 0.22 (rawpy): the raw sensor values' sums, the white
## balance as shot, and the developed light's mean (linear sRGB, white
## balance as shot, bilinear demosaic) over the same part of the picture.
## The CR3s (EOS R8 lossless and C-RAW, EOS R3 C-RAW, EOS M50 lossless and
## C-RAW in two tiles) were also compared with LibRaw's raw_image whole:
## every number the same; their black, white and picture's part are checked
## here too.

import std/[unittest, os, times, strutils, strformat, math]
import retroui/[rawformats, photodevelop]


proc w16(o: var string; v: int) = (o.add char(v and 255); o.add char((v shr 8) and 255))
proc w32(o: var string; v: int) =
  o.add char(v and 255); o.add char((v shr 8) and 255); o.add char((v shr 16) and 255); o.add char((v shr 24) and 255)

proc tiff(make, model: string; w, h, bps, comp: int; data: string; extra: seq[(int, int, int, int)] = @[]): string =
  ## A small little-endian TIFF the way cameras write raws: IFD0 with the
  ## maker and model, a SubIFD with the mosaic (RGGB).
  var o = "II*\0"
  o.w32(0)
  let dataAt = o.len
  o.add data
  while (o.len and 3) != 0: o.add '\0'
  let makeAt = o.len
  o.add make & "\0"
  let modelAt = o.len
  o.add model & "\0"
  while (o.len and 3) != 0: o.add '\0'
  # the raw directory
  let raw = o.len
  var tags = @[(254, 4, 1, 0), (256, 4, 1, w), (257, 4, 1, h), (258, 3, 1, bps), (259, 3, 1, comp),
               (262, 3, 1, 32803), (273, 4, 1, dataAt), (277, 3, 1, 1), (278, 4, 1, h), (279, 4, 1, data.len),
               (33421, 3, 2, 2 or (2 shl 16)), (33422, 1, 4, 0 or (1 shl 8) or (1 shl 16) or (2 shl 24))] & extra
  o.w16(tags.len)
  for (tag, kind, cnt, v) in tags:
    o.w16(tag); o.w16(kind); o.w32(cnt); o.w32(v)
  o.w32(0)
  let ifd0 = o.len
  let t0 = @[(271, 2, make.len + 1, makeAt), (272, 2, model.len + 1, modelAt), (274, 3, 1, 1), (330, 4, 1, raw)]
  o.w16(t0.len)
  for (tag, kind, cnt, v) in t0:
    o.w16(tag); o.w16(kind); o.w32(cnt); o.w32(v)
  o.w32(0)
  o[4] = char(ifd0 and 255); o[5] = char((ifd0 shr 8) and 255); o[6] = char((ifd0 shr 16) and 255); o[7] = char(ifd0 shr 24)
  o

proc sample(w, h: int; x, y: int): int =
  ## Smooth numbers with a few edges, as a sensor might give.
  600 + (x * 37 + y * 23) mod 900 + (if (x div 8 + y div 8) mod 2 == 0: 200 else: 0)

proc arw2(vals: seq[int]; w, h: int): string =
  ## Sony's compression of 11-bit numbers whose blocks of 16 span less than
  ## 128 (so it is exact): biggest, smallest, where they are, then 7-bit steps.
  for y in 0 ..< h:
    var col = 0
    while col < w - 30:
      var blk: array[16, int]
      for i in 0 .. 15: blk[i] = vals[y * w + col + 2 * i]
      var imax, imin = 0
      for i in 0 .. 15:
        if blk[i] > blk[imax]: imax = i
        if blk[i] < blk[imin]: imin = i
      if imax == imin: imin = (imax + 1) mod 16
      var bits: array[16, uint8]
      let head = blk[imax] or (blk[imin] shl 11) or (imax shl 22) or (imin shl 26)
      for k in 0 .. 3: bits[k] = uint8((head shr (8 * k)) and 255)
      var bit = 30
      for i in 0 .. 15:
        if i == imax or i == imin: continue
        let d = blk[i] - blk[imin]
        for k in 0 .. 6:
          if ((d shr k) and 1) == 1:
            let at = bit + k
            bits[at shr 3] = bits[at shr 3] or uint8(1 shl (at and 7))
        bit += 7
      for v in bits: result.add char(v)
      col += 32
      col -= (if (col and 1) == 1: 1 else: 31)

proc findSample(name: string): string =
  for root in [currentSourcePath.parentDir / "data" / "raw", getEnv("RETRO_RAW_SAMPLES")]:
    if not dirExists(root): continue
    for f in walkDirRec(root):
      if f.extractFilename == name: return f
  ""

type Known = object
  ## What LibRaw reads in a camera file.
  name, kind: string
  rawW, rawH: int
  s1, s2: int64                 ## the raw values' sum, and their sum weighted by place mod 1009 ...
  rows: int                     ## ... of this many rows (0: all; LibRaw makes up a last row of some ORFs)
  dark: bool                    ## a frame near black (see below)
  wbR, wbB: float               ## white balance as shot: red / green, blue / green
  rect: array[4, int]           ## a part of our picture (x, y, w, h) ...
  mean: array[3, float]         ## ... and LibRaw's light there (scaled to our white level)
  black: array[4, float]        ## LibRaw's black of each place of the mosaic (all 0: not checked) ...
  white: float                  ## ... its white ...
  crop: array[4, int]           ## ... and its picture's part (left, top, w, h)

const known: seq[Known] = @[
  Known(name: "arw_Sony_DSLR-A500.arw", kind: "ARW", rawW: 4288, rawH: 2858, s1: 17863400152, s2: 9003765104708, wbR: 2.394531, wbB: 1.191406,
        rect: [8, 8, 4240, 2842], mean: [0.060553, 0.066392, 0.083025]),
  Known(name: "arw_Sony_ILCE-5000_(A5000).arw", kind: "ARW", rawW: 5504, rawH: 3656, s1: 37965352676, s2: 19134279192400, wbR: 2.750000, wbB: 1.644531,
        rect: [8, 8, 5456, 3640], mean: [0.126303, 0.121563, 0.129993]),
  Known(name: "arw_Sony_ILCE-7M3_(A7M3).arw", kind: "ARW", rawW: 6048, rawH: 4024, s1: 36633096132, s2: 18453561601740, wbR: 1.660156, wbB: 2.964844,
        rect: [8, 8, 5984, 3984], mean: [0.126755, 0.091711, 0.068095]),
  Known(name: "arw_Sony_ILCE-7M4_(A7M4).ARW", kind: "ARW", rawW: 7168, rawH: 5120, s1: 54164586261, s2: 27299562453406, wbR: 2.357422, wbB: 1.680664,
        rect: [8, 8, 6992, 4656], mean: [0.050405, 0.089874, 0.140881]),
  Known(name: "arw_Sony_NEX-5N.arw", kind: "ARW", rawW: 4928, rawH: 3276, s1: 24848396748, s2: 12524616071512, wbR: 2.550781, wbB: 1.558594,
        rect: [8, 8, 4904, 3260], mean: [0.115379, 0.096902, 0.075156]),
  Known(name: "arw_Sony_NEX-7.arw", kind: "ARW", rawW: 6048, rawH: 4024, s1: 38015558360, s2: 19163668997928, wbR: 2.429688, wbB: 1.628906,
        rect: [8, 8, 6008, 4008], mean: [0.094393, 0.093670, 0.092330]),
  Known(name: "RAW_SONY_A300.ARW", kind: "ARW", rawW: 3880, rawH: 2608, s1: 4700372904, s2: 2368945035820, wbR: 1.925781, wbB: 1.593750,
        rect: [8, 8, 3864, 2592], mean: [0.151835, 0.145733, 0.138197]),
  Known(name: "cr2_Canon_EOS_350D.CR2", kind: "CR2", rawW: 3516, rawH: 2328, s1: 4922917260, s2: 2480437639128, wbR: 2.229637, wbB: 1.583906,
        rect: [8, 8, 3458, 2298], mean: [0.139424, 0.131960, 0.088390]),
  Known(name: "cr2_Canon_EOS_600D.CR2", kind: "CR2", rawW: 5344, rawH: 3516, s1: 55419372057, s2: 27929926372081, wbR: 2.188477, wbB: 1.523438,
        rect: [8, 9, 5186, 3448], mean: [0.144331, 0.100654, 0.092717]),
  Known(name: "cr2_Canon_EOS_70D.cr2", kind: "CR2", rawW: 5568, rawH: 3708, s1: 55352221831, s2: 27897385569208, wbR: 1.946289, wbB: 1.917969,
        rect: [8, 8, 5480, 3654], mean: [0.104046, 0.064901, 0.040201]),
  Known(name: "cr2_Canon_EOS_7D.cr2", kind: "CR2", rawW: 5360, rawH: 3516, s1: 69212672708, s2: 34881168839393, wbR: 2.295898, wbB: 1.323242,
        rect: [8, 9, 5186, 3448], mean: [0.188528, 0.186734, 0.178573]),
  Known(name: "RAW_CANON_5DMARK2_PREPROD.CR2", kind: "CR2", dark: true, rawW: 5792, rawH: 3804, s1: 28311958987, s2: 14268517071762, wbR: 2.461914, wbB: 1.369141,
        rect: [8, 9, 5618, 3736], mean: [0.009132, 0.012015, 0.050527]),
  # (CR3: EOS R3 C-RAW; EOS R8 lossless (IMG_0036, _MG_0039) and C-RAW (IMG_0041,
  # _MG_0045); EOS M50 lossless (IMG_0482, m50_02) and C-RAW (IMG_0483), in two tiles)
  Known(name: "cr3_Canon_EOS_R3.cr3", kind: "CR3", rawW: 6192, rawH: 4152, s1: 66294778182, s2: 33412446117888, wbR: 1.855469, wbB: 2.056641,
        rect: [8, 8, 6016, 4016], mean: [0.052257, 0.051628, 0.052127],
        black: [2047, 2047, 2047, 2047], white: 16383, crop: [160, 120, 6032, 4032]),
  Known(name: "cr3_IMG_0036.CR3", kind: "CR3", rawW: 6188, rawH: 4120, s1: 71483652416, s2: 36027561166741, wbR: 1.383789, wbB: 2.381836,
        rect: [8, 8, 6006, 4008], mean: [0.090002, 0.069548, 0.051250],
        black: [2047, 2047, 2047, 2047], white: 16383, crop: [154, 96, 6022, 4024]),
  Known(name: "cr3_IMG_0041.CR3", kind: "CR3", rawW: 6188, rawH: 4120, s1: 70897852277, s2: 35732000634521, wbR: 1.377930, wbB: 2.365234,
        rect: [8, 8, 6006, 4008], mean: [0.086424, 0.067203, 0.050027],
        black: [2048, 2047, 2048, 2047], white: 16383, crop: [154, 96, 6022, 4024]),
  Known(name: "cr3__MG_0039.CR3", kind: "CR3", rawW: 6188, rawH: 4120, s1: 70590304360, s2: 35577511087784, wbR: 1.381836, wbB: 2.375977,
        rect: [8, 8, 6006, 4008], mean: [0.085616, 0.066114, 0.049059],
        black: [2047, 2047, 2048, 2047], white: 16383, crop: [154, 96, 6022, 4024]),
  Known(name: "cr3__MG_0045.CR3", kind: "CR3", rawW: 6188, rawH: 4120, s1: 70224902720, s2: 35393583713046, wbR: 1.377930, wbB: 2.365234,
        rect: [8, 8, 6006, 4008], mean: [0.083193, 0.064640, 0.048512],
        black: [2048, 2047, 2048, 2047], white: 16383, crop: [154, 96, 6022, 4024]),
  Known(name: "cr3_lclevy_IMG_0482_raw.CR3", kind: "CR3", rawW: 6288, rawH: 4056, s1: 35647952509, s2: 17966527847642, wbR: 1.546875, wbB: 1.252930,
        rect: [8, 8, 6008, 4004], mean: [0.047447, 0.061320, 0.091365],
        black: [510, 510, 510, 510], white: 16383, crop: [264, 36, 6024, 4020]),
  Known(name: "cr3_lclevy_IMG_0483_craw.CR3", kind: "CR3", rawW: 6288, rawH: 4056, s1: 35558636767, s2: 17921627842656, wbR: 1.546875, wbB: 1.252930,
        rect: [8, 8, 6008, 4004], mean: [0.047173, 0.060897, 0.091231],
        black: [510, 511, 511, 510], white: 16383, crop: [264, 36, 6024, 4020]),
  Known(name: "cr3_lclevy_canon_eos_m50_02.cr3", kind: "CR3", rawW: 6288, rawH: 4056, s1: 81244979359, s2: 40947349350249, wbR: 1.232422, wbB: 1.553711,
        rect: [8, 8, 6008, 4004], mean: [0.157141, 0.094053, 0.068777],
        black: [2049, 2044, 2045, 2049], white: 16383, crop: [264, 36, 6024, 4020]),
  Known(name: "iss030e122639.NEF", kind: "NEF", rawW: 4288, rawH: 2844, s1: 879609664, s2: 442849036487, wbR: 2.250000, wbB: 1.687500,
        rect: [8, 8, 4266, 2828], mean: [0.022431, 0.024708, 0.021393]),
  Known(name: "iss042e297200.NEF", kind: "NEF", rawW: 4992, rawH: 3292, s1: 2616330578, s2: 1319551141691, wbR: 2.289062, wbB: 1.230469,
        rect: [8, 8, 4922, 3276], mean: [0.035657, 0.046997, 0.053576]),
  Known(name: "nef_Nikon_800E.nef", kind: "NEF", rawW: 7424, rawH: 4924, s1: 23618494269, s2: 11903458203297, wbR: 2.000000, wbB: 1.488281,
        rect: [8, 8, 7362, 4908], mean: [0.046070, 0.053033, 0.046041]),
  Known(name: "nef_Nikon_D300.nef", kind: "NEF", rawW: 4352, rawH: 2868, s1: 3046314495, s2: 1535411963866, wbR: 1.730469, wbB: 1.187500,
        rect: [8, 8, 4304, 2852], mean: [0.092909, 0.073033, 0.056880]),
  Known(name: "nef_Nikon_D5100.nef", kind: "NEF", rawW: 4992, rawH: 3280, s1: 24755426769, s2: 12471697832131, wbR: 2.113281, wbB: 1.328125,
        rect: [8, 8, 4932, 3264], mean: [0.112635, 0.117395, 0.122361]),
  Known(name: "nef_Nikon_D70.nef", kind: "NEF", rawW: 3040, rawH: 2014, s1: 2795224329, s2: 1408028504381, wbR: 2.071661, wbB: 1.589577,
        rect: [8, 8, 3023, 1998], mean: [0.151972, 0.147461, 0.127965]),
  Known(name: "nef_Nikon_D810.nef", kind: "NEF", rawW: 7380, rawH: 4928, s1: 88837167584, s2: 44774265814048, wbR: 1.968750, wbB: 1.265625,
        rect: [8, 8, 7364, 4912], mean: [0.178308, 0.141506, 0.117365]),
  Known(name: "nef_Nikon_D90.nef", kind: "NEF", rawW: 4352, rawH: 2868, s1: 2964104230, s2: 1493888064569, wbR: 1.339844, wbB: 1.789062,
        rect: [8, 8, 4294, 2852], mean: [0.090438, 0.073708, 0.055431]),
  Known(name: "nef_NikonD200.nef", kind: "NEF", rawW: 3904, rawH: 2616, s1: 3361412712, s2: 1694038185929, wbR: 1.550781, wbB: 1.546875,
        rect: [9, 8, 3882, 2600], mean: [0.069448, 0.110973, 0.081625]),
  Known(name: "RAW_NIKON_D3X.NEF", kind: "NEF", rawW: 6080, rawH: 4044, s1: 35178868707, s2: 17723762078630, wbR: 1.808594, wbB: 1.546875,
        rect: [8, 8, 6064, 4028], mean: [0.136489, 0.110937, 0.097261]),
  Known(name: "orf_Olympus_C5050Z.orf", kind: "ORF", rawW: 2576, rawH: 1926, s1: 2599355708, s2: 1310075667437, rows: 1925, wbR: 1.367188, wbB: 1.609375,
        rect: [8, 8, 2560, 1909], mean: [0.161308, 0.149859, 0.152197]),
  Known(name: "orf_Olympus_C8080.orf", kind: "ORF", rawW: 3280, rawH: 2454, s1: 4871073181, s2: 2456813123118, rows: 2453, wbR: 2.160156, wbB: 1.722656,
        rect: [8, 8, 3264, 2437], mean: [0.211550, 0.208277, 0.141555]),
  Known(name: "orf_Olympus_E-M10.orf", kind: "ORF", rawW: 4640, rawH: 3472, s1: 7296316018, s2: 3676776976511, wbR: 2.093750, wbB: 1.617188,
        rect: [8, 8, 4592, 3440], mean: [0.059868, 0.065449, 0.072105]),
  Known(name: "orf_Olympus_E-M5.orf", kind: "ORF", rawW: 4640, rawH: 3472, s1: 8686856938, s2: 4377097792873, wbR: 2.015625, wbB: 1.890625,
        rect: [8, 8, 4592, 3440], mean: [0.100309, 0.100164, 0.096687]),
  Known(name: "orf_Olympus_E-PL7.orf", kind: "ORF", rawW: 4640, rawH: 3472, s1: 9662979335, s2: 4870617707424, wbR: 1.890625, wbB: 1.773438,
        rect: [8, 8, 4592, 3440], mean: [0.142742, 0.118520, 0.092749]),
  Known(name: "orf_Olympus_E-PM1.orf", kind: "ORF", rawW: 4080, rawH: 3040, s1: 1854882862, s2: 934111949513, wbR: 1.578125, wbB: 2.093750,
        rect: [8, 8, 4016, 3008], mean: [0.039764, 0.030590, 0.015042]),
  Known(name: "orf_Olympus_E30.orf", kind: "ORF", rawW: 4100, rawH: 3084, s1: 4209224246, s2: 2121477297779, wbR: 2.218750, wbB: 1.132812,
        rect: [8, 8, 4016, 3008], mean: [0.081646, 0.078636, 0.087486]),
  Known(name: "orf_Olympus_E410.orf", kind: "ORF", rawW: 3720, rawH: 2800, s1: 6094714674, s2: 3071604015366, wbR: 1.953125, wbB: 1.375000,
        rect: [8, 8, 3632, 2720], mean: [0.120045, 0.155917, 0.208254]),
  Known(name: "orf_Olympus_E600.orf", kind: "ORF", rawW: 4100, rawH: 3084, s1: 8847998434, s2: 4459960966880, wbR: 1.851562, wbB: 1.289062,
        rect: [8, 8, 4016, 3008], mean: [0.169926, 0.188868, 0.211267]),
  Known(name: "orf_Olympus_PEN_E-P3.orf", kind: "ORF", rawW: 4080, rawH: 3040, s1: 2735757837, s2: 1380151396480, wbR: 2.062500, wbB: 1.515625,
        rect: [8, 8, 4016, 3008], mean: [0.118242, 0.052906, 0.017524]),
  Known(name: "orf_Olympus_Pen_E-PL1.orf", kind: "ORF", rawW: 4100, rawH: 3084, s1: 4476968479, s2: 2256714147338, wbR: 1.812500, wbB: 1.281250,
        rect: [8, 8, 4016, 3008], mean: [0.098570, 0.087510, 0.077317]),
  Known(name: "orf_Olympus_SP350.orf", kind: "ORF", rawW: 3280, rawH: 2454, s1: 4454075070, s2: 2247104086114, rows: 2453, wbR: 1.664062, wbB: 1.785156,
        rect: [8, 8, 3264, 2437], mean: [0.292328, 0.165174, 0.113751]),
  Known(name: "orf_Olympus_SP500UZ.orf", kind: "ORF", rawW: 2832, rawH: 2118, s1: 3271683584, s2: 1648981876281, rows: 2117, wbR: 2.058594, wbB: 1.484375,
        rect: [8, 8, 2816, 2101], mean: [0.175365, 0.172965, 0.160318]),
  Known(name: "orf_Olympus_TG-4.orf", kind: "ORF", rawW: 4640, rawH: 3472, s1: 17094354877, s2: 8614055658473, wbR: 1.757812, wbB: 1.703125,
        rect: [8, 8, 4592, 3440], mean: [0.253956, 0.273390, 0.192126]),
  Known(name: "orf_Olympus_TG-6.ORF", kind: "ORF", rawW: 4040, rawH: 3016, s1: 8973033652, s2: 4523966694964, wbR: 2.046875, wbB: 1.421875,
        rect: [8, 8, 3984, 2984], mean: [0.157092, 0.155781, 0.163865]),
  Known(name: "orf_Olympus_XZ1.orf", kind: "ORF", rawW: 3680, rawH: 2760, s1: 7396793056, s2: 3728708614600, wbR: 1.992188, wbB: 1.851562,
        rect: [8, 8, 3632, 2720], mean: [0.264526, 0.222189, 0.167929]),
  Known(name: "orf_OM_System_TG-7.ORF", kind: "ORF", rawW: 4040, rawH: 3016, s1: 8977947438, s2: 4527999302032, wbR: 2.046875, wbB: 1.414062,
        rect: [8, 8, 3984, 2984], mean: [0.161194, 0.156658, 0.159295]),
  Known(name: "orf_OM_Sytem_OM-1.orf", kind: "ORF", rawW: 5220, rawH: 3912, s1: 14701798656, s2: 7409585901640, wbR: 2.414062, wbB: 1.531250,
        rect: [8, 8, 5168, 3872], mean: [0.160338, 0.156035, 0.149512]),
  Known(name: "RAW_OLYMPUS_E3.ORF", kind: "ORF", rawW: 3720, rawH: 2800, s1: 4716034682, s2: 2376637349210, wbR: 1.929688, wbB: 1.515625,
        rect: [8, 8, 3632, 2720], mean: [0.144254, 0.132409, 0.111075]),
  Known(name: "pef_Pentax_K-1_Mark_II.pef", kind: "PEF", rawW: 7392, rawH: 4950, s1: 44290183916, s2: 22322062787113, wbR: 2.035156, wbB: 1.687500,
        rect: [8, 8, 7360, 4916], mean: [0.017273, 0.015571, 0.015505]),
  Known(name: "RAW_PENTAX_K200D.PEF", kind: "PEF", rawW: 3936, rawH: 2624, s1: 4781698825, s2: 2409890125121, wbR: 1.992188, wbB: 1.328125,
        rect: [8, 8, 3880, 2600], mean: [0.097409, 0.122217, 0.156260]),
  Known(name: "raf_FujiFilm_EX-2.raf", kind: "RAF", rawW: 4992, rawH: 3296, s1: 43800929487, s2: 22075408976997, wbR: 1.867550, wbB: 1.576159,
        rect: [8, 8, 4880, 3248], mean: [0.135537, 0.135321, 0.129767]),
  Known(name: "raf_FujiFilm_FinePix_S5500.raf", kind: "RAF", rawW: 2304, rawH: 1740, s1: 10795389372, s2: 5437411364979, wbR: 1.612500, wbB: 1.537500,
        rect: [8, 8, 2256, 1688], mean: [0.151708, 0.194135, 0.234532]),
  Known(name: "raf_Fujifilm_X-E1.raf", kind: "RAF", rawW: 5120, rawH: 3288, s1: 8096907693, s2: 4080589845860, wbR: 1.841060, wbB: 2.221854,
        rect: [8, 8, 4880, 3248], mean: [0.129265, 0.069184, 0.074655]),
  Known(name: "RAW_PANASONIC_G1.RW2", kind: "RW2", rawW: 4060, rawH: 3016, s1: 6783292067, s2: 3418048534373, wbR: 2.220532, wbB: 1.349810,
        rect: [8, 8, 3984, 2984], mean: [0.187498, 0.167579, 0.156503]),
  Known(name: "rw2_Panasonic_DMC-GF1.rw2", kind: "RW2", rawW: 4060, rawH: 3016, s1: 7088482927, s2: 3572973366246, wbR: 1.844106, wbB: 1.536122,
        rect: [8, 8, 3984, 2984], mean: [0.240590, 0.178484, 0.149155]),
  Known(name: "rw2_Panasonic_DMC-GF3.rw2", kind: "RW2", rawW: 4088, rawH: 2688, s1: 8111587850, s2: 4089022997174, wbR: 1.996226, wbB: 1.433962,
        rect: [8, 8, 3984, 2656], mean: [0.119587, 0.159259, 0.267076]),
  Known(name: "rw2_Panasonic_DMC-GF7.rw2", kind: "RW2", rawW: 4816, rawH: 3464, s1: 15190540981, s2: 7653691243311, wbR: 2.585938, wbB: 1.445312,
        rect: [8, 8, 4576, 3432], mean: [0.178802, 0.234631, 0.296660]),
  Known(name: "rw2_Panasonic_Lumix_DMC-LX7.rw2", kind: "RW2", rawW: 3696, rawH: 2752, s1: 5148433132, s2: 2589497002755, wbR: 1.739623, wbB: 1.818868,
        rect: [8, 8, 3632, 2720], mean: [0.160110, 0.084720, 0.131314])
]

suite "camera raw files":
  test "kinds told apart":
    check rawKind("FUJIFILMCCD-RAW 0201FF383501" & repeat('\0', 100)) == "RAF"
    check rawKind("\0\0\0\x18ftypcrx \0\0\0\1crx isom" & repeat('\0', 16)) == "CR3"
    check rawKind("IIRO\x08\0\0\0" & repeat('\0', 16)) == "ORF"
    check rawKind("IIU\0\x08\0\0\0" & repeat('\0', 16)) == "RW2"
    check rawKind("II*\0\x10\0\0\0CR\x02\0" & repeat('\0', 16)) == "CR2"
    check rawKind(tiff("NIKON CORPORATION", "NIKON D90", 8, 8, 16, 1, repeat('\0', 128))) == "NEF"
    check rawKind(tiff("SONY", "ILCE-7M3", 8, 8, 16, 1, repeat('\0', 128))) == "ARW"
    check rawKind(tiff("PENTAX", "PENTAX K-1", 8, 8, 16, 1, repeat('\0', 128))) == "PEF"
    check rawKind(tiff("Some Scanner", "X", 8, 8, 16, 1, repeat('\0', 128))) == ""
    check rawKind("") == "" and rawKind("not a raw photo at all") == ""
    check isRaw("IIU\0\x08\0\0\0" & repeat('\0', 16)) and not isRaw("hello, world, a text file")

  test "an uncompressed NEF, number for number":
    let (w, h) = (64, 48)
    var data = ""
    for y in 0 ..< h:
      for x in 0 ..< w: data.w16(sample(w, h, x, y))
    let nef = tiff("NIKON CORPORATION", "NIKON D810", w, h, 14, 1, data)
    check rawKind(nef) == "NEF"
    let s = readSensor(nef)
    check s.kind == "NEF" and s.rawW == w and s.rawH == h and s.w == w and s.h == h
    check s.model == "NIKON D810" and s.cfaN == 2 and s.cfa == @[0, 1, 1, 2]
    var same = true
    for y in 0 ..< h:
      for x in 0 ..< w:
        if int(s.px[y * w + x]) != sample(w, h, x, y): same = false
    check same
    check abs(s.colorMatrix[0] - 0.9369) < 1e-6        # (Adobe's matrix of the D810)
    let raw = readRaw(nef)                              # (through rawphoto's dispatch)
    check raw.w == w and raw.h == h and raw.px.len == w * h * 3
    var ok = true
    for v in raw.px:
      if v.classify in {fcNan, fcInf} or v < 0: ok = false
    check ok
    let img = developRaw(raw, Develop())
    check img.w == w and img.h == h

  test "Sony's compressed ARW, number for number":
    let (w, h) = (64, 8)
    var vals = newSeq[int](w * h)
    for y in 0 ..< h:
      for x in 0 ..< w: vals[y * w + x] = 300 + (x * 7 + y * 3) mod 120 + (x mod 2) * 500
    let arw = tiff("SONY", "ILCE-7M3", w, h, 12, 32767, arw2(vals, w, h))
    let s = readSensor(arw)
    check s.kind == "ARW" and s.rawW == w and s.rawH == h
    var same = true
    for i in 0 ..< w * h:
      if int(s.px[i]) != 2 * vals[i]: same = false      # (no curve: twice, as LibRaw keeps 14 bits)
    check same

  test "what is not one we read":
    expect RawError: discard readSensor("not a raw photo at all, no")
    expect RawError: discard readRaw("not a raw photo at all, no")
    expect RawError: discard readSensor("\0\0\0\x18ftypcrx \0\0\0\1crx isom" & repeat('\0', 64))
    expect RawError: discard readSensor(tiff("NIKON CORPORATION", "NIKON D90", 64, 48, 12, 34713, "short"))

  test "a CR3 cut short, or damaged":
    let path = findSample("cr3_lclevy_IMG_0483_craw.CR3")
    if path == "":
      echo "    (skipped: cr3_lclevy_IMG_0483_craw.CR3 not found)"
    else:
      let data = readFile(path)
      # (cut: its picture's data not all there)
      expect RawError: discard readSensor(data[0 ..< data.len * 3 div 4])
      expect RawError: discard readSensor(data[0 ..< 30000])
      # (bytes changed in the picture's data and headers: read, or a RawError, never a crash)
      var seed = 12345
      for round in 0 ..< 4:
        var d = data
        for _ in 0 ..< 40:
          seed = (seed * 1103515245 + 12345) and 0x7FFFFFFF
          let at = if round mod 2 == 0: 22000 + seed mod 400 else: data.len div 2 + seed mod (data.len div 2)
          d[at] = char((ord(d[at]) + 1 + seed mod 255) and 255)
        try:
          let s = readSensor(d)
          check s.px.len == s.rawW * s.rawH
        except RawError:
          discard

  test "real cameras, as LibRaw reads them":
    var found = 0
    for k in known:
      let path = findSample(k.name)
      if path == "":
        echo &"    (skipped: {k.name} not found)"
        continue
      inc found
      let data = readFile(path)
      check rawKind(data) == k.kind
      let t0 = epochTime()
      var s = readSensor(data)
      let t1 = epochTime()
      check s.rawW == k.rawW and s.rawH == k.rawH
      var s1, s2: int64
      let n = (if k.rows > 0: k.rows else: s.rawH) * s.rawW
      for i in 0 ..< n:
        let v = s.px[i]
        s1 += int64(v)
        s2 += int64(v) * int64(i mod 1009)
      # (the numbers exactly as LibRaw has them)
      check s1 == k.s1 and s2 == k.s2
      check abs(s.wb[0] / s.wb[1] - k.wbR) < 1e-4 and abs(s.wb[2] / s.wb[1] - k.wbB) < 1e-4
      if k.white > 0:
        check s.black == k.black and s.white == k.white
        check [s.left, s.top, s.w, s.h] == k.crop
      s.orient = 1
      let raw = develop(s)
      let t2 = epochTime()
      var mean: array[3, float]
      let (x0, y0, rw, rh) = (k.rect[0], k.rect[1], k.rect[2], k.rect[3])
      for y in y0 ..< y0 + rh:
        for x in x0 ..< x0 + rw:
          for c in 0 .. 2: mean[c] += raw.px[(y * raw.w + x) * 3 + c]
      for c in 0 .. 2: mean[c] /= float(rw * rh)
      var worst = 0.0
      for c in 0 .. 2: worst = max(worst, abs(mean[c] / k.mean[c] - 1))
      # (the light within 3% of LibRaw's: LibRaw's bilinear mosaic filling and
      # ours (Malvar-He-Cutler) differ most in noise below black, which both
      # cut at zero; in a frame near black that is several percent)
      check worst < (if k.dark: 0.10 else: 0.03)
      echo &"    {k.name}: {k.rawW}x{k.rawH} read {t1 - t0:.2f}s, developed {t2 - t1:.2f}s, light within {worst * 100:.2f}% of LibRaw's"
    if found == 0: echo "    (no camera files found: set RETRO_RAW_SAMPLES)"
