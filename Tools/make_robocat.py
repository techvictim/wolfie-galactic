#!/usr/bin/env python3
"""Builds the robo-cat: Resources/robocat.vox (the body, head, ears, laser and tail; the game adds
the legs so they can trot) and a picture, Resources/robocat.png.

Robo-cats are Glitched machines, not real cats: silly, a bit grumpy, never scary. Drawn in toy
pixels (16 per metre, like the crew), facing -z, standing on y = 0.

Run:  python3 Tools/make_robocat.py      (needs pillow and numpy)
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
sys.path.insert(0, HERE)
sys.argv = sys.argv[:1]
from make_models import box, hit
from make_critters import render
import make_crew

GRID_X = (-12, 12)
GRID_Y = (0, 30)
GRID_Z = (-18, 16)

def both(x0, x1, y0, y1, z0, z1, c):
    return [box((-x1, y0, z0), (-x0, y1, z1), c), box((x0, y0, z0), (x1, y1, z1), c)]

CAT = (
    # Eyes glow Glitch red; slit pupils.
    both(3, 4, 17, 20, -15.5, -14, "pupil")
    + both(2, 5, 17, 20, -15, -14, "eye")
    + [box((-1, 15, -16.5), (1, 16, -15.5), "nose"),
       box((-2, 13, -16), (2, 14, -15), "mouth"),
       box((-3, 12, -16), (3, 16, -14), "muzzle")]
    # Whiskers.
    + both(6, 9, 14, 15, -15, -14, "whisker")
    # Ears, with Glitch-red insides.
    + both(3, 5, 22, 25, -11, -10, "glitch")
    + both(2, 6, 22, 24, -11, -8, "metal")
    + both(3, 6, 24, 26, -11, -8, "metal")
    + both(4, 6, 26, 27, -11, -8, "metal")
    # The little laser on its head.
    + [box((-1, 22, -13), (1, 23, -12), "laser"),
       box((-1, 22, -12), (1, 24, -6), "dark")]
    # Head.
    + [box((-6, 12, -15), (6, 22, -5), "metal"),
       box((-6, 21, -15), (6, 22, -5), "metaldark")]
    # A red Glitch stripe down the back, panel lines, and a tummy.
    + [box((-1, 15, -4), (1, 16, 9), "glitch"),
       box((-5, 11, -1), (5, 12, 0), "metaldark"),
       box((-4, 7, -4), (4, 8, 8), "belly"),
       box((-5, 7, -5), (5, 15, 10), "metal")]
    # Tail: out, then up, with a glowing tip.
    + [box((-1, 24, 12), (1, 26, 14), "glitch"),
       box((-1, 13, 9), (1, 15, 13), "metaldark"),
       box((-1, 15, 12), (1, 24, 14), "metaldark")]
)

COLORS = {
    "metal": "#a3acb9", "metaldark": "#5d6675", "belly": "#d6dbe3", "glitch": "#ff2b3a", "eye": "#ff3b3b",
    "pupil": "#2a0a10", "nose": "#ff8fb0", "mouth": "#2a1a24", "muzzle": "#d6dbe3", "whisker": "#eef2f8",
    "laser": "#ff2b3a", "dark": "#2c3038",
}


def sample(prims):
    vox = {}
    for i in range(*GRID_X):
        for j in range(*GRID_Y):
            for k in range(*GRID_Z):
                for p in prims:
                    if hit(p, i + 0.5, j + 0.5, k + 0.5):
                        vox[(i - GRID_X[0], j - GRID_Y[0], k - GRID_Z[0])] = p[-1]
                        break
    return vox


if __name__ == "__main__":
    vox = sample(CAT)
    names = sorted(set(vox.values()))
    make_crew.COLORS.update(COLORS)
    make_crew.GRID_X, make_crew.GRID_Y, make_crew.GRID_Z = GRID_X, GRID_Y, GRID_Z
    make_crew.write_vox(os.path.join(RES, "robocat.vox"), [vox], names)
    # The picture adds the legs too.
    legs = {}
    for lx in (-4, 2):
        for lz in (-4, 6):
            for x in range(lx, lx + 3):
                for y in range(0, 7):
                    for z in range(lz, lz + 3):
                        legs[(x - GRID_X[0], y, z - GRID_Z[0])] = "metaldark"
    whole = dict(legs)
    whole.update(vox)
    palette = {c: tuple(int(COLORS[c][a:a + 2], 16) for a in (1, 3, 5)) for c in set(whole.values())}
    render(whole, palette, size=256, yaw=-35, pitch=14).save(os.path.join(RES, "robocat.png"))
    print(len(vox), "voxels")
