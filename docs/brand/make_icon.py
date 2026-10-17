import json, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
SS = 4  # supersampling

def hexrgb(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2],16), int(h[2:4],16), int(h[4:6],16), a)

def render(stroke_scale=1.0, dot=True):
    N = 1024 * SS
    img = Image.new('RGBA', (N, N), (0,0,0,0))
    # macOS grid: 824x824 body centered, transparent margin, soft shadow
    off, body = 100*SS, 824*SS
    k = body / 1024.0
    shadow = Image.new('RGBA', (N, N), (0,0,0,0))
    ImageDraw.Draw(shadow).rounded_rectangle([off, off+10*SS, off+body, off+body+10*SS], radius=int(185*SS), fill=(0,0,0,90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14*SS))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([off, off, off+body, off+body], radius=int(185*SS), fill=hexrgb('#15171C'))
    edge = Image.new('RGBA', (N, N), (0,0,0,0))
    ImageDraw.Draw(edge).rounded_rectangle([off+3*SS, off+3*SS, off+body-3*SS, off+body-3*SS], radius=int(182*SS), outline=(255,255,255,22), width=int(4*SS))
    img.alpha_composite(edge)
    def ring(cx, cy, rc, w, color):
        w = w*stroke_scale
        R = (rc + w/2)
        X, Y = off + cx*k, off + cy*k
        d.ellipse([X-R*k, Y-R*k, X+R*k, Y+R*k], outline=hexrgb(color), width=int(round(w*k)))
    ring(512, 600, 168, 64, '#FF8A4C')
    ring(512, 332, 68, 64, '#FFC09A')
    if dot:
        r = 36*k
        X, Y = off+512*k, off+600*k
        d.ellipse([X-r, Y-r, X+r, Y+r], fill=hexrgb('#FF8A4C'))
    return img

big = render()
mid = render(stroke_scale=1.15)
small = render(stroke_scale=1.4, dot=False)

sizes = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
images = []
for pt, scale in sizes:
    px = pt*scale
    src = big if px >= 128 else (mid if px >= 48 else small)
    name = f"icon_{pt}x{pt}{'@2x' if scale==2 else ''}.png"
    src.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
    images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pt}x{pt}"})

with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)
big.resize((1024,1024), Image.LANCZOS).save(os.path.join(OUT, "..", "..", "..", "..", "docs", "brand", "octava-icon-1024.png")) if os.path.isdir(os.path.join(OUT, "..", "..", "..", "..", "docs", "brand")) else None
print("ok")
