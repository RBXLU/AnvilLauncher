from PIL import Image, ImageDraw, ImageFilter
import sys
N, S = 32, 32          # сетка 32x32, клетка 32 px -> 1024
W = N * S
img = Image.new("RGB", (W, W))
# фон: вертикальный градиент тёмно-зелёного
top, bottom = (24, 40, 30), (8, 14, 11)
d = ImageDraw.Draw(img)
for y in range(W):
    t = y / (W - 1)
    d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))

# мягкое зелёное свечение за наковальней
glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([W*0.18, W*0.20, W*0.82, W*0.84], fill=(74, 222, 128, 70))
glow = glow.filter(ImageFilter.GaussianBlur(120))
img = Image.alpha_composite(img.convert("RGBA"), glow)

LIGHT, MID, DARK, EDGE = (196, 202, 212), (140, 146, 156), (92, 97, 106), (52, 56, 62)
G1, G2, G3 = (220, 255, 230), (74, 222, 128), (34, 160, 80)
px = {}
def row(y, x0, x1, c):
    for x in range(x0, x1 + 1): px[(x, y)] = c

# наковальня
row(12, 9, 25, LIGHT); row(13, 6, 25, MID); row(14, 8, 25, MID)
row(15, 11, 23, DARK)
for y in (16, 17, 18): row(y, 13, 21, MID)
row(19, 11, 23, DARK)
row(20, 8, 26, MID); row(21, 8, 26, DARK)
# тени и блики
for y in (13, 14): px[(25, y)] = DARK
for y in (16, 17, 18): px[(21, y)] = DARK; px[(13, y)] = LIGHT
px[(6, 13)] = LIGHT; px[(7, 13)] = LIGHT
row(22, 9, 25, EDGE)
# искры от удара
for (x, y, c) in [(17, 10, G1), (17, 9, G1), (16, 9, G2), (18, 9, G2), (17, 8, G2), (19, 7, G3), (15, 7, G3),
                  (21, 6, G2), (13, 6, G2), (22, 9, G3), (12, 9, G3), (20, 4, G3), (14, 4, G3), (17, 5, G1)]:
    px[(x, y)] = c

layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ld = ImageDraw.Draw(layer)
for (x, y), c in px.items():
    y += 2  # центрируем рисунок по вертикали
    ld.rectangle([x*S, y*S, (x+1)*S - 1, (y+1)*S - 1], fill=c + (255,))
# лёгкая тень под пикселями
shadow = layer.split()[3].point(lambda a: 110 if a else 0)
sh = Image.new("RGBA", (W, W), (0, 0, 0, 0)); sh.putalpha(shadow)
img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(10)), (0, 18))
img.alpha_composite(layer)
img.convert("RGB").save(sys.argv[1])
