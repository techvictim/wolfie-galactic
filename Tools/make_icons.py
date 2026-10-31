#!/usr/bin/env python3
"""Builds the app icons from Resources/wolfie-world.png:
AppIcons/iOS.xcassets, AppIcons/macOS.xcassets and AppIcons/tvOS.xcassets
(the Apple TV's layered icon and Top Shelf images).

Run:  python3 Tools/make_icons.py      (needs: pip install pillow numpy)
"""
import json, math, os, random, shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..'))
PLANET = Image.open(os.path.join(ROOT, 'Resources', 'wolfie-world.png')).convert('RGBA')
FONT_CANDIDATES = [
    '/System/Library/Fonts/SFNSRounded.ttf',
    '/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf',
    '/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf',
]
INFO = {"author": "xcode", "version": 1}

def font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

def space(w, h, seed=3):
    """Deep violet space with a soft nebula and stars."""
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    top = np.array([28, 18, 64], float)
    bottom = np.array([9, 6, 26], float)
    t = (yy / h)[..., None]
    img = top * (1 - t) + bottom * t
    for cx, cy, r, col, a in [(0.25, 0.3, 0.55, (95, 240, 255), 0.18), (0.8, 0.7, 0.5, (255, 122, 217), 0.14)]:
        d = np.sqrt(((xx / w - cx) * w / h) ** 2 + (yy / h - cy) ** 2) / r
        k = np.clip(1 - d, 0, 1) ** 2 * a
        img = img * (1 - k[..., None]) + np.array(col, float) * k[..., None]
    im = Image.fromarray(np.clip(img, 0, 255).astype('uint8'), 'RGB').convert('RGBA')
    d = ImageDraw.Draw(im)
    rnd = random.Random(seed)
    for _ in range(int(w * h / 2600)):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        r = rnd.choice([0.6, 0.8, 1.0, 1.4]) * max(1, w / 1000)
        a = rnd.randint(120, 255)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    return im

def planet(size):
    return PLANET.resize((size, size), Image.LANCZOS)

def paste_center(base, layer, cx, cy):
    base.alpha_composite(layer, (int(cx - layer.width / 2), int(cy - layer.height / 2)))

def title_text(width):
    """WOLFIE GALACTIC with a chrome edge, sized to a width."""
    lines = [('WOLFIE', (159, 252, 255), (51, 194, 173)), ('GALACTIC', (255, 140, 224), (128, 82, 255))]
    rendered = []
    for text, c1, c2 in lines:
        size = 400
        f = font(size)
        box = f.getbbox(text)
        scale = width / (box[2] - box[0])
        if text == 'GALACTIC':
            scale *= 0.92
        f = font(max(10, int(size * scale)))
        box = f.getbbox(text)
        w, h = box[2] - box[0], box[3] - box[1]
        pad = int(h * 0.18)
        mask = Image.new('L', (w + pad * 2, h + pad * 2), 0)
        ImageDraw.Draw(mask).text((pad - box[0], pad - box[1]), text, font=f, fill=255)
        edge = mask.filter(ImageFilter.MaxFilter(max(3, int(h * 0.12) | 1)))
        outer = edge.filter(ImageFilter.MaxFilter(max(3, int(h * 0.05) | 1)))
        W, H = mask.size
        yy = np.linspace(0, 1, H)[:, None]
        chrome = np.clip(np.interp(yy, [0, 0.2, 0.45, 0.56, 0.78, 1], [255, 205, 105, 245, 145, 230]), 0, 255)
        chrome_img = np.repeat(np.repeat(chrome[..., None], 3, axis=2), W, axis=1)
        face = np.array(c1, float) * (1 - yy[..., None]) + np.array(c2, float) * yy[..., None]
        face_img = np.repeat(face, W, axis=1)
        out = np.zeros((H, W, 4))
        a_outer = np.asarray(outer, float)[..., None] / 255
        a_edge = np.asarray(edge, float)[..., None] / 255
        a_face = np.asarray(mask, float)[..., None] / 255
        out[..., :3] = np.array([18, 10, 40]) * a_outer
        out[..., 3:] = a_outer
        out[..., :3] = out[..., :3] * (1 - a_edge) + chrome_img * a_edge
        out[..., :3] = out[..., :3] * (1 - a_face) + face_img * a_face
        rendered.append(Image.fromarray(np.clip(out * [1, 1, 1, 255], 0, 255).astype('uint8'), 'RGBA'))
    gap = -int(rendered[0].height * 0.12)
    total_h = sum(r.height for r in rendered) + gap
    W = max(r.width for r in rendered)
    canvas = Image.new('RGBA', (W, total_h), (0, 0, 0, 0))
    y = 0
    for r in rendered:
        canvas.alpha_composite(r, ((W - r.width) // 2, y))
        y += r.height + gap
    return canvas

def save(img, path, opaque=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (img.convert('RGB') if opaque else img).save(path, optimize=True)

def contents(path, data):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, 'Contents.json'), 'w') as f:
        json.dump(data, f, indent=2)

out = os.path.join(ROOT, 'AppIcons')
if os.path.isdir(out):
    shutil.rmtree(out)

# ---------- iOS / iPadOS: one 1024 icon, no transparency ----------
ios = os.path.join(out, 'iOS.xcassets')
contents(ios, {"info": INFO})
icon = space(1024, 1024)
paste_center(icon, planet(1000), 512, 530)
save(icon, os.path.join(ios, 'AppIcon.appiconset', 'icon-1024.png'), opaque=True)
contents(os.path.join(ios, 'AppIcon.appiconset'), {
    "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": INFO})

# ---------- macOS: rounded square on a transparent canvas, all sizes ----------
mac = os.path.join(out, 'macOS.xcassets')
contents(mac, {"info": INFO})
full = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
tile = space(824, 824)
paste_center(tile, planet(860), 412, 425)
m = Image.new('L', (824, 824), 0)
ImageDraw.Draw(m).rounded_rectangle([0, 0, 823, 823], radius=185, fill=255)
shadow = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([100, 112, 924, 936], radius=185, fill=(0, 0, 0, 110))
full.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14)))
full.paste(tile, (100, 100), m)
images = []
for pts in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = pts * scale
        name = f'icon-{pts}@{scale}x.png'
        save(full.resize((px, px), Image.LANCZOS), os.path.join(mac, 'AppIcon.appiconset', name))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{pts}x{pts}"})
contents(os.path.join(mac, 'AppIcon.appiconset'), {"images": images, "info": INFO})

# ---------- tvOS: layered icons and Top Shelf ----------
tv = os.path.join(out, 'tvOS.xcassets')
contents(tv, {"info": INFO})
brand = os.path.join(tv, 'App Icon & Top Shelf Image.brandassets')
contents(brand, {
    "assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ],
    "info": INFO})

def tv_layers(w, h):
    """Back: space (opaque). Front: the planet with the title beside it."""
    back = space(w, h, seed=w)
    front = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    p = planet(int(h * 0.92))
    paste_center(front, p, w * 0.26, h * 0.5)
    text = title_text(int(w * 0.48))
    paste_center(front, text, w * 0.71, h * 0.5)
    return back, front

def imagestack(name, sizes):
    stack = os.path.join(brand, name)
    contents(stack, {"info": INFO, "layers": [{"filename": "Front.imagestacklayer"}, {"filename": "Back.imagestacklayer"}]})
    for layer in ("Front", "Back"):
        imageset = os.path.join(stack, f'{layer}.imagestacklayer', 'Content.imageset')
        contents(os.path.join(stack, f'{layer}.imagestacklayer'), {"info": INFO})
        images = []
        for (w, h), scale in sizes:
            back, front = tv_layers(w, h)
            file = f'{layer.lower()}-{w}x{h}.png'
            save(back if layer == 'Back' else front, os.path.join(imageset, file), opaque=(layer == 'Back'))
            images.append({"filename": file, "idiom": "tv", "scale": scale})
        contents(imageset, {"images": images, "info": INFO})

imagestack('App Icon - App Store.imagestack', [((1280, 768), '1x')])
imagestack('App Icon.imagestack', [((400, 240), '1x'), ((800, 480), '2x')])

def top_shelf(name, sizes):
    imageset = os.path.join(brand, name)
    images = []
    for (w, h), scale in sizes:
        img = space(w, h, seed=h)
        paste_center(img, planet(int(h * 0.98)), w * 0.2, h * 0.5)
        paste_center(img, title_text(int(w * 0.42)), w * 0.64, h * 0.5)
        file = f'top-shelf-{w}x{h}.png'
        save(img, os.path.join(imageset, file), opaque=True)
        images.append({"filename": file, "idiom": "tv", "scale": scale})
    contents(imageset, {"images": images, "info": INFO})

top_shelf('Top Shelf Image.imageset', [((1920, 720), '1x'), ((3840, 1440), '2x')])
top_shelf('Top Shelf Image Wide.imageset', [((2320, 720), '1x'), ((4640, 1440), '2x')])
print('Wrote icons to', out)
