import sys
from pathlib import Path
from PIL import Image, ImageDraw
d = Path(sys.argv[1]); names = sys.argv[2].split(","); out = sys.argv[3]; h = int(sys.argv[4]) if len(sys.argv) > 4 else 900
ims = []
for n in names:
    im = Image.open(d / n).convert("RGB"); r = h / im.height; ims.append(im.resize((int(im.width * r), h), Image.LANCZOS))
W = sum(i.width for i in ims) + 12 * (len(ims) + 1)
sheet = Image.new("RGB", (W, h + 24), (60, 60, 60)); x = 12
for i in ims: sheet.paste(i, (x, 12)); x += i.width + 12
sheet.save(out)
