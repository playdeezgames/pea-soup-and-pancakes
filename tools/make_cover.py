#!/usr/bin/env python3
"""Draws assets/cover.png (630x500) from two of the game's own frames: the title lettering from
assets/screenshots/01-title.png over the board of assets/screenshots/03-bowl-two.png (the ?demo scene).
Both screenshots are the 144x176 canvas at 4x. Needs Pillow. Run from the repo root: python3 -I tools/make_cover.py"""
from PIL import Image, ImageFilter

def scale(im, k):
    # Whole-pixel enlarge by an affine transform (Pillow's resize fails to enlarge on this machine; see the vault's Gotchas).
    return im.transform((im.width * k, im.height * k), Image.AFFINE, (1 / k, 0, 0, 0, 1 / k, 0), Image.NEAREST)

def native(path):
    im = Image.open(path).convert("RGB")
    return im.reduce(4)  # the shots are exact 4x blocks

BG = (26, 17, 11)
title, demo = native("assets/screenshots/01-title.png"), native("assets/screenshots/03-bowl-two.png")
cols = {(134, 184, 74), (245, 197, 66)}  # the title's green and gold
pts = [(x, y) for y in range(20, 80) for x in range(title.width) if title.getpixel((x, y)) in cols]
x0, y0 = min(p[0] for p in pts), min(p[1] for p in pts)
x1, y1 = max(p[0] for p in pts), max(p[1] for p in pts)
txt = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
for x, y in pts:
    txt.putpixel((x - x0, y - y0), title.getpixel((x, y)) + (255,))
T = scale(txt, 4)
outline = Image.new("RGBA", T.size, BG + (255,))
outline.putalpha(T.getchannel("A").filter(ImageFilter.MaxFilter(13)))

cover = Image.new("RGB", (630, 500), BG)
cover.paste(scale(demo.crop((8, 24, 136, 152)), 4), (59, 500 - 512 + 60))  # the 8x8 board
band = Image.new("RGBA", (630, T.height + 48), BG + (215,))
cover.paste(band, (0, 14), band)
px = (630 - T.width) // 2
cover.paste(outline, (px, 38), outline)
cover.paste(T, (px, 38), T)
cover.save("assets/cover.png")
print("assets/cover.png", cover.size)
