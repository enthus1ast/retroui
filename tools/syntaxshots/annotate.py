"""Copies the pictures to the study's folder; under those whose cells were
measured (`mark "50"`, `mark "-1"`...) it draws each cell's width in red,
in design pixels: the number asked for, and what a share or an own width
came to. Needs Pillow; the DejaVu font when it is there.

  python3 annotate.py FROM TO
"""
import json, os, re, shutil, sys
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
try:
    bold = ImageFont.truetype("DejaVuSans-Bold.ttf", 22)
except OSError:
    try:
        bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    except OSError:
        bold = ImageFont.load_default()
red = (198, 40, 40)


def dashed(d, x, y0, y1):
    y = y0
    while y < y1:
        d.line([(x, y), (x, min(y + 6, y1))], fill=red, width=2)
        y += 11


for fn in sorted(os.listdir(src)):
    if not fn.endswith(".png"):
        continue
    name = fn[:-4]
    meta = json.load(open(os.path.join(src, name + ".json")))
    k = meta["scale"]
    marks = [m for m in meta["marks"] if re.fullmatch(r"-?\d+", m["spec"])]
    if not marks:
        shutil.copy(os.path.join(src, fn), os.path.join(dst, fn))
        continue
    # (the first line of a row that wraps: its columns are the next lines' too)
    mid = marks[0]["y"] + marks[0]["h"] / 2
    marks = [m for m in marks if abs(m["y"] + m["h"] / 2 - mid) < 30]
    im = Image.open(os.path.join(src, fn)).convert("RGB")
    W, H = im.size
    out = Image.new("RGB", (W, H + 84), "white")
    out.paste(im, (0, 0))
    d = ImageDraw.Draw(out)
    dy = H + 26
    for m in marks:
        x0, x1 = m["x"], m["x"] + m["w"] - 1
        for x in (x0, x1):
            dashed(d, x, m["y"] + m["h"] + 3, dy + 10)
        d.line([(x0, dy), (x1, dy)], fill=red, width=2)
        for x, s in ((x0, 1), (x1, -1)):
            d.polygon([(x, dy), (x + 10 * s, dy - 6), (x + 10 * s, dy + 6)], fill=red)
        spec, w = m["spec"], m["w"] / k
        w = int(w) if w == int(w) else w
        text = spec if int(spec) > 0 else f"{spec} = {w}"
        tw = d.textlength(text, font=bold)
        d.text(((x0 + x1) / 2 - tw / 2, dy + 12), text, font=bold, fill=red)
    out.save(os.path.join(dst, fn), optimize=True)
