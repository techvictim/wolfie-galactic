#!/usr/bin/env python3
"""Paints Resources/wolfie-world.png: Wolfie World as a ball of big toy blocks.

Kept deliberately simple: a few earth tones and greys, two stepped grey mountains for ears,
two glowing cyan blocks for eyes, a dark nose block and a lighter sandy muzzle, plus a few
bright crystals.

Run:  python3 Tools/make_title_planet.py      (needs: pip install pillow numpy)
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = 1024
RADIUS = 10.6          # planet radius in blocks
YAW = math.radians(-16)
PITCH = math.radians(16)

def hexrgb(h):
    h = h.lstrip('#')
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)

MOSS, OLIVE, LOAM = hexrgb('#5f7f4b'), hexrgb('#808a4c'), hexrgb('#7a5b3e')
SAND = hexrgb('#b39c74')
ROCK, SILVER, SNOW = hexrgb('#74767e'), hexrgb('#a3a8b2'), hexrgb('#e3e7ee')
BASALT = hexrgb('#3b3743')
CYAN, PINK, VIOLET = hexrgb('#5ff0ff'), hexrgb('#ff7ad9'), hexrgb('#8a5cff')
AMBER, GOLD = hexrgb('#ffb547'), hexrgb('#ffe08a')
GLOWING = {tuple(CYAN), tuple(PINK), tuple(VIOLET), tuple(AMBER), tuple(GOLD)}

# ---------- build the voxels (x right, y up, z toward the viewer) ----------
voxels = {}
r = int(math.ceil(RADIUS)) + 4
for x in range(-r, r + 1):
    for y in range(-r, r + 1):
        for z in range(-r, r + 1):
            if (x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5) ** 2 <= RADIUS ** 2:
                voxels[(x, y, z)] = None

def surface_of(x, y):
    """Front-most voxel z in a column, or None."""
    zs = [z for (vx, vy, z) in voxels if vx == x and vy == y]
    return max(zs) if zs else None

def colour_land(x, y, z):
    n = math.sin(x * 0.55 + z * 0.3) + math.cos(y * 0.6 - z * 0.45) + math.sin((x - y) * 0.35)
    return MOSS if n > 0.6 else OLIVE if n > -0.5 else LOAM

for key in voxels:
    voxels[key] = colour_land(*key)

# Ears: two pointed grey peaks standing up from the top of the planet
for side in (-1, 1):
    for dx, h in [(-2, 1), (-1, 3), (0, 4), (1, 3), (2, 1)]:
        x = 5 * side + dx
        for z in (1, 2, 3):
            column = [vy for (vx, vy, vz) in voxels if vx == x and vz == z]
            if not column:
                continue
            top = max(column)
            for k in range(1, h + 1):
                colour = SNOW if k >= 4 else SILVER if k >= 2 else ROCK
                voxels[(x, top + k, z)] = colour

# Sandy muzzle and cheeks on the front
for (x, y, z), c in list(voxels.items()):
    if z < 6:
        continue
    if (x / 6.2) ** 2 + ((y + 3.2) / 4.6) ** 2 <= 1 and y < 1:
        voxels[(x, y, z)] = SAND

def front(x, y):
    z = surface_of(x, y)
    return (x, y, z)

# Eyes: two glowing blocks set into the surface, nose: a raised dark block
# Eyes: warm amber, three blocks wide and two tall, with a bright gold glint
for side in (-1, 1):
    for dx in (0, 1, 2):
        for y in (1, 2):
            x = (-5 + dx) if side < 0 else (2 + dx)
            glint = (y == 2 and dx == (1 if side < 0 else 1))
            voxels[front(x, y)] = GOLD if glint else AMBER
# Nose: a dark block three wide, standing two blocks proud of the muzzle
for x, y, out in [(-2, -3, 2), (-1, -3, 2), (0, -3, 2), (-1, -4, 1)]:
    fx, fy, fz = front(x, y)
    for k in range(0, out + 1):
        voxels[(fx, fy, fz + k)] = BASALT

# A few bright crystals away from the face
for x, y in [(-8, -4), (7, -5), (-6, -8), (8, 3), (-9, 3), (5, -8)]:
    fx, fy, fz = front(x, y)
    if fz is None:
        continue
    colour = [CYAN, PINK, VIOLET][(x * 3 + y) % 3]
    voxels[(fx, fy, fz + 1)] = colour

# ---------- render ----------
cy, sy = math.cos(YAW), math.sin(YAW)
cp, sp = math.cos(PITCH), math.sin(PITCH)

def view(p):
    x, y, z = p
    x, z = x * cy + z * sy, -x * sy + z * cy          # turn
    y, z = y * cp - z * sp, y * sp + z * cp            # tilt toward the viewer
    return np.array([x, y, z])

scale = OUT * 0.36 / RADIUS
centre = np.array([OUT / 2, OUT / 2 + OUT * 0.06])

def screen(p):
    v = view(p)
    return (centre[0] + v[0] * scale, centre[1] - v[1] * scale)

FACES = [
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
    ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]
light = np.array([-0.45, 0.75, 0.5])
light /= np.linalg.norm(light)

quads = []
for (x, y, z), colour in voxels.items():
    for normal, corners in FACES:
        nb = (x + normal[0], y + normal[1], z + normal[2])
        if nb in voxels:
            continue
        n_view = view(normal)
        if n_view[2] <= 0:
            continue
        pts = [screen((x + a, y + b, z + c)) for a, b, c in corners]
        depth = view((x + 0.5 + normal[0] * 0.5, y + 0.5 + normal[1] * 0.5, z + 0.5 + normal[2] * 0.5))[2]
        bright = 0.5 + 0.6 * max(0.0, float(np.dot(normal, light)))
        if tuple(colour) in GLOWING:
            bright = max(bright, 1.0)
        # Gentle darkening toward the planet's far edges
        edge = math.sqrt(x * x + y * y) / RADIUS
        bright *= 1.0 - 0.18 * max(0.0, edge - 0.6)
        quads.append((depth, pts, np.clip(colour * bright, 0, 255), tuple(colour) in GLOWING))

quads.sort(key=lambda q: q[0])

img = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))

glow = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
gr = RADIUS * scale * 1.08
ImageDraw.Draw(glow).ellipse([centre[0] - gr, centre[1] - gr, centre[0] + gr, centre[1] + gr], fill=(127, 225, 230, 110))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(OUT * 0.03)))

d = ImageDraw.Draw(img)
edge_w = max(1, int(scale * 0.06))
for _, pts, c, _ in quads:
    fill = tuple(int(v) for v in c) + (255,)
    outline = tuple(int(v * 0.72) for v in c) + (255,)
    d.polygon(pts, fill=fill, outline=outline, width=edge_w)

# Soft glow around glowing blocks
halo = Image.new('RGBA', (OUT, OUT), (0, 0, 0, 0))
hd = ImageDraw.Draw(halo)
for _, pts, c, glowing in quads:
    if glowing:
        hd.polygon(pts, fill=tuple(int(v) for v in c) + (200,))
img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(scale * 0.6)))

path = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources', 'wolfie-world.png'))
img.save(path, optimize=True)
print('Wrote', path, len(voxels), 'blocks')
