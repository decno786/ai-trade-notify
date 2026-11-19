"""Draws the AI Trade Notify launcher icon into the Android project (needs Pillow)."""
import sys
from PIL import Image, ImageDraw

res = sys.argv[1]  # android/app/src/main/res
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}


def icon(s):
    big = s * 4
    grad = Image.new("RGB", (2, 2))
    grad.putdata([(0x5B, 0x7C, 0xFF), (0x7F, 0x6C, 0xFF), (0x7F, 0x6C, 0xFF), (0xA3, 0x5C, 0xFF)])
    grad = grad.resize((big, big), Image.BILINEAR).convert("RGBA")
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.28), fill=255)
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    im.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(im)
    w = int(big * 0.075)
    pts = [(big * .20, big * .66), (big * .40, big * .46), (big * .55, big * .58), (big * .78, big * .33)]
    d.line(pts, fill="white", width=w, joint="curve")
    for x, y in pts[:-1]:
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill="white")
    a = big * .10
    d.polygon([(big * .83, big * .26), (big * .84, big * .26 + a * 1.25), (big * .83 - a * 1.25, big * .27)], fill="white")
    return im.resize((s, s), Image.LANCZOS)


for name, s in SIZES.items():
    icon(s).save(f"{res}/mipmap-{name}/ic_launcher.png")
print("icons written")
