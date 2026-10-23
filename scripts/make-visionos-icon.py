#!/usr/bin/env python3
"""Generate GalaxyVision layered app icon (needs Pillow). Usage: make-visionos-icon.py <AppIcon.solidimagestack dir> [preview.png]"""
import json, math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter
S = 1024
root = sys.argv[1]
random.seed(64)

# Back: opaque navy -> black radial gradient
back = Image.new("RGB", (S, S))
px = back.load()
for y in range(S):
    for x in range(S):
        d = min(1.0, math.hypot(x - S*0.5, y - S*0.45) / (S*0.75))
        t = d ** 0.9
        px[x, y] = (int(14*(1-t)), int(22*(1-t)+1*t), int(58*(1-t)+3*t))

# Middle: tiny dots + soft glow behind star
mid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([S*0.2, S*0.2, S*0.8, S*0.8], fill=(255, 190, 60, 120))
glow = glow.filter(ImageFilter.GaussianBlur(90))
mid = Image.alpha_composite(mid, glow)
dd = ImageDraw.Draw(mid)
for _ in range(34):
    x, y = random.randint(40, S-40), random.randint(40, S-40)
    if math.hypot(x-S/2, y-S/2) < 300: continue
    r = random.choice([2, 2, 3, 3, 4]); a = random.randint(150, 255)
    dd.ellipse([x-r, y-r, x+r, y+r], fill=(255, 255, 255, a))

# Front: gold five-point star, transparent bg
def star(cx, cy, R, r):
    pts = []
    for i in range(10):
        ang = -math.pi/2 + i*math.pi/5
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad*math.cos(ang), cy + rad*math.sin(ang)))
    return pts
front = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cx, cy = S/2, S/2 + 18
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).polygon(star(cx, cy+14, 330, 140), fill=(0, 0, 0, 110))
front = Image.alpha_composite(front, sh.filter(ImageFilter.GaussianBlur(14)))
outer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(outer).polygon(star(cx, cy, 330, 140), fill=(245, 170, 20, 255), outline=(245, 170, 20, 255), width=10)
inner = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(inner).polygon(star(cx, cy, 285, 120), fill=(255, 224, 80, 255))
hl = Image.new("RGBA", (S, S), (255, 245, 170, 0))
ImageDraw.Draw(hl).polygon(star(cx-14, cy-16, 190, 80), fill=(255, 245, 170, 200))
hl = hl.filter(ImageFilter.GaussianBlur(26))
front = Image.alpha_composite(front, outer)
front = Image.alpha_composite(front, inner)
front = Image.alpha_composite(front, hl)
# clip highlight/inner to the star silhouette
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon(star(cx, cy, 330, 140), fill=255, outline=255, width=10)
front.putalpha(Image.composite(front.getchannel("A"), Image.new("L", (S, S), 0), mask))

def w(path, obj):
    with open(path, "w") as f: json.dump(obj, f, indent=2)
info = {"author": "xcode", "version": 1}
os.makedirs(root, exist_ok=True)
w(os.path.join(root, "..", "Contents.json"), {"info": info})
w(os.path.join(root, "Contents.json"), {"info": info, "layers": [{"filename": f"{n}.solidimagestacklayer"} for n in ("Front", "Middle", "Back")]})
for name, img in (("Front", front), ("Middle", mid), ("Back", back)):
    ld = os.path.join(root, f"{name}.solidimagestacklayer"); cd = os.path.join(ld, "Content.imageset")
    os.makedirs(cd, exist_ok=True)
    w(os.path.join(ld, "Contents.json"), {"info": info})
    w(os.path.join(cd, "Contents.json"), {"images": [{"idiom": "vision", "scale": "2x", "filename": f"{name}.png"}], "info": info})
    img.save(os.path.join(cd, f"{name}.png"))
comp = Image.alpha_composite(Image.alpha_composite(back.convert("RGBA"), mid), front)
comp.save(sys.argv[2] if len(sys.argv) > 2 else "/tmp/icon-preview.png")
