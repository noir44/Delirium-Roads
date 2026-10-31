# The lettering of the asphalt mix sack label (alpha mask, 400 x 580 = the front of the sack,
# 1 px ~ 1 mm) for sack_label.py. Pillow, Windows fonts.
#   python art/sack_label_text.py
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 400, 580
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
FONT = r"C:\Windows\Fonts\impact.ttf"


def centred(text, size, top):
    f = ImageFont.truetype(FONT, size)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text(((W - (r - l)) / 2 - l, top - t), text, font=f, fill=(0, 0, 0, 255))
    return top + (b - t)


# from the top: the knot takes the upper ~20 %
y = centred("ASPHALT", 62, 160)
y = centred("MIX", 80, y + 12)
# road sign: a road narrowing to the horizon with a dashed centre line
cx, top, bot = W / 2, y + 26, y + 120
d.polygon([(cx - 26, top), (cx + 26, top), (cx + 95, bot), (cx - 95, bot)], fill=(0, 0, 0, 255))
for k in range(4):
    a, b = top + 8 + k * 24, top + 20 + k * 24
    wa, wb = 3 + k * 1.6, 3 + (k + 0.5) * 1.6
    d.polygon([(cx - wa, a), (cx + wa, a), (cx + wb, b), (cx - wb, b)], fill=(0, 0, 0, 0))
y = centred("25 kg", 56, bot + 18)
img.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sack_label_text.png"))
print("text bottom", y, "of", H)
