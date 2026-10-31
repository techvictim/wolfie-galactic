#!/usr/bin/env python3
"""Builds the critters: a .vox model each (4 small voxels per big-block edge, like every
detail model) and a picture for the critter book.

Critters face -z (the way the camera looks) and stand on y = 0. Shapes are in big-block
units; the first shape that covers a voxel decides its colour, so eyes go before heads.

Run:  python3 Tools/make_critters.py      (needs pillow and numpy)
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_models as mm
from make_models import box, ell

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))

mm.COLORS.update({
    "fluff": "#5fd6b5", "belly": "#c9f6e7", "white": "#ffffff", "pupil": "#1d1630",
    "blush": "#ff8fb8", "stalk": "#3e9c84", "glowtip": "#ffe066", "feet": "#3a8f79",
    "bugshell": "#8a5cff", "bugglow": "#fff27a", "bughead": "#3b2a6b", "bugeye": "#5ff0ff", "wing": "#cdeeff",
    "bunny": "#e9e6f6", "bunnyfeet": "#b8b3d3", "earpink": "#ffb3cf", "puff": "#ffffff",
    "crab": "#ff8a4c", "claw": "#ff6236", "crabdark": "#a8452a", "crystal": "#7af5ff", "crystal2": "#ff7ad9",
    "grumble": "#7b3fbf", "grumbledark": "#4a2370", "angryeye": "#ff4242", "brow": "#2a1240",
    "fang": "#fff6e0", "mouth": "#24102f", "spike": "#ff7a3d",
})

def pair(make):
    """The same shape on the left and the right (x mirrored)."""
    return [make(-1), make(1)]

def mirror_box(x0, x1, y0, y1, z0, z1, color):
    return pair(lambda s: box((min(s * x0, s * x1), y0, z0), (max(s * x0, s * x1), y1, z1), color))

# Fluffalump: a round, fluffy mint ball with big eyes and two glowing antennae. Wolfie World.
FLUFFALUMP = (
    mirror_box(0.25, 0.5, 1.0, 1.25, -1.0, -0.75, "pupil")
    + mirror_box(0.25, 0.75, 0.75, 1.25, -0.95, -0.7, "white")
    + mirror_box(0.5, 0.75, 0.5, 0.75, -0.9, -0.6, "blush")
    + [box((-0.25, 0.5, -0.95), (0.25, 0.75, -0.7), "pupil")]
    + mirror_box(0.25, 0.5, 2.0, 2.25, -0.25, 0.0, "glowtip")
    + mirror_box(0.25, 0.5, 1.5, 2.0, -0.25, 0.0, "stalk")
    + mirror_box(0.25, 0.75, 0.0, 0.25, -0.5, 0.0, "feet")
    + [ell((0, 0.8, -0.35), (0.55, 0.5, 0.6), "belly"),
       ell((0, 0.95, 0), (0.9, 0.82, 0.88), "fluff")]
)

# Glowbug: a little violet beetle with a glowing tail. It hovers. Wolfie World.
GLOWBUG = (
    pair(lambda s: box((min(0, s * 0.25), 0.5, -0.75), (max(0, s * 0.25), 0.75, -0.5), "bugeye"))
    + [ell((0, 0.6, -0.45), (0.3, 0.28, 0.3), "bughead"),
       ell((0, 0.55, 0.55), (0.32, 0.3, 0.32), "bugglow")]
    + mirror_box(0.25, 0.5, 0.75, 1.0, 0.0, 0.5, "wing")
    + [ell((0, 0.55, 0.1), (0.4, 0.35, 0.45), "bugshell")]
)

# Moon bunny: white with tall ears and a puff tail. Hops high in low gravity. Pup Moon.
BUNNY = (
    mirror_box(0.125, 0.375, 1.0, 1.25, -0.85, -0.6, "pupil")
    + [box((-0.125, 0.75, -0.9), (0.125, 0.95, -0.6), "earpink")]
    + mirror_box(0.125, 0.375, 1.5, 2.0, -0.45, -0.3, "earpink")
    + mirror_box(0.125, 0.375, 1.25, 2.25, -0.4, -0.125, "bunny")
    + [ell((0, 1.0, -0.4), (0.45, 0.42, 0.42), "bunny"),
       ell((0, 0.6, 0.75), (0.22, 0.22, 0.2), "puff")]
    + mirror_box(0.125, 0.5, 0.0, 0.25, -0.35, 0.35, "bunnyfeet")
    + [ell((0, 0.6, 0.1), (0.48, 0.48, 0.6), "bunny")]
)

# Crystal crab: orange, with crystals growing on its shell and eyes on stalks. Glimmer.
CRAB = (
    [box((-0.25, 0.75, 0.0), (0.0, 1.5, 0.25), "crystal"),
     box((0.25, 0.75, -0.25), (0.5, 1.25, 0.0), "crystal2"),
     box((-0.5, 0.75, 0.25), (-0.25, 1.25, 0.5), "crystal2"),
     box((0.0, 0.75, 0.25), (0.25, 1.0, 0.5), "crystal")]
    + mirror_box(0.25, 0.5, 0.75, 1.0, -0.75, -0.5, "pupil")
    + mirror_box(0.25, 0.5, 0.5, 0.75, -0.75, -0.5, "crabdark")
    + pair(lambda s: ell((s * 0.85, 0.4, -0.6), (0.3, 0.22, 0.28), "claw"))
    + [ell((0, 0.45, 0.0), (0.7, 0.38, 0.6), "crab")]
    + mirror_box(0.5, 0.875, 0.0, 0.25, -0.25, 0.0, "crabdark")
    + mirror_box(0.5, 0.875, 0.0, 0.25, 0.25, 0.5, "crabdark")
)

# Grumbler: a grumpy spiky lump. Only out when Danger is on.
GRUMBLER = (
    mirror_box(0.25, 0.5, 1.0, 1.25, -0.95, -0.7, "angryeye")
    + [box((-0.75, 1.25, -0.95), (0.75, 1.5, -0.65), "brow")]
    + mirror_box(0.25, 0.5, 0.5, 0.75, -0.95, -0.7, "fang")
    + [box((-0.5, 0.5, -0.9), (0.5, 0.75, -0.6), "mouth")]
    + [box((-0.125, 1.5, -0.25), (0.125, 2.25, 0.0), "spike"),
       box((-0.625, 1.5, 0.0), (-0.375, 2.0, 0.25), "spike"),
       box((0.375, 1.5, 0.0), (0.625, 2.0, 0.25), "spike"),
       box((-0.125, 1.25, 0.5), (0.125, 1.75, 0.75), "spike")]
    + mirror_box(0.25, 0.75, 0.0, 0.25, -0.5, 0.25, "grumbledark")
    + [ell((0, 0.85, 0), (0.85, 0.8, 0.8), "grumble")]
)

CRITTERS = {
    "fluffalump": FLUFFALUMP,
    "glowbug": GLOWBUG,
    "moon-bunny": BUNNY,
    "crystal-crab": CRAB,
    "grumbler": GRUMBLER,
}
BOUNDS = ((-1.3, 1.3), (0, 2.6), (-1.3, 1.3))


# ---------- pictures ----------

def render(voxels, palette, size=256, yaw=-28, pitch=24, scale=4):
    """Paint the voxels as little shaded cubes, seen from the front, a bit to the side and above."""
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))

    def rot(p):
        x, y, z = p
        x, z = x * cy - z * sy, x * sy + z * cy           # turn around y
        y, z = y * cp + z * sp, -y * sp + z * cp          # tip toward the viewer (who is at -z)
        return np.array([x, y, z])

    keys = list(voxels)
    centre = np.mean(np.array(keys, float), axis=0) + 0.5
    corners = [rot(np.array(k, float) + c - centre) for k in keys for c in ((0, 0, 0), (1, 1, 1), (1, 0, 1), (0, 1, 0))]
    span = max(max(abs(c[0]), abs(c[1])) for c in corners) * 2 + 1
    unit = big / span * 0.92

    faces = [((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
             ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
             ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
             ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
             ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
             ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)])]
    light = np.array([0.35, 0.85, -0.4]); light /= np.linalg.norm(light)
    polys = []
    for k in keys:
        base = np.array(k, float) - centre
        for normal, quad in faces:
            if (k[0] + normal[0], k[1] + normal[1], k[2] + normal[2]) in voxels:
                continue
            n = rot(np.array(normal, float))
            if n[2] >= 0:
                continue
            pts = [rot(base + np.array(q, float)) for q in quad]
            depth = sum(p[2] for p in pts) / 4
            shade = 0.62 + 0.38 * max(0, float(np.dot(np.array(normal, float), light)))
            color = tuple(int(min(255, c * shade)) for c in palette[voxels[k]]) + (255,)
            polys.append((depth, [(big / 2 + p[0] * unit, big / 2 - p[1] * unit) for p in pts], color))
    for _, pts, color in sorted(polys, key=lambda t: -t[0]):
        draw.polygon(pts, fill=color, outline=color)
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    sheet = Image.new("RGBA", (256 * len(CRITTERS), 256), (40, 30, 70, 255))
    for i, (name, prims) in enumerate(CRITTERS.items()):
        size, voxels, names = mm.build(prims, BOUNDS)
        mm.write_vox(os.path.join(RES, name + ".vox"), size, voxels, names)
        palette = {j + 1: tuple(int(mm.COLORS[n].lstrip("#")[a:a + 2], 16) for a in (0, 2, 4)) for j, n in enumerate(names)}
        picture = render(voxels, palette)
        picture.save(os.path.join(RES, f"critter-{name}.png"))
        sheet.alpha_composite(picture, (256 * i, 0))
        print(f"{name}: {len(voxels)} voxels, size {size}")
    if len(sys.argv) > 1:
        sheet.save(sys.argv[1])
