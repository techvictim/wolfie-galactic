#!/usr/bin/env python3
"""Builds the Wolfie Military crew as voxel characters, in the same toy style as the rest
of Wolfie Galactic: Resources/crew-<id>.vox and a portrait, Resources/crew-<id>.png.

Each .vox holds seven models in this order: head, body, left arm, right arm, left leg,
right leg, and the whole character (for the portrait). Every model uses the same grid, so
the game only needs the joint positions (see Game/Crew/Crew.swift).

Characters are drawn in "pixels": 16 per metre, like a toy figure. They face -z and stand on
y = 0, centred on x = 0, z = 0. The first shape that covers a voxel decides its colour, so
details (eyes, buttons) go before the things they sit on.

  head      y 21..29, x -4..4, z -4..4   (neck joint at y 21)
  body      y 11..21, x -4..4, z -2..2   (jetpack on the back)
  arms      x ±4..±8, y 10..21           (shoulder joints at x ±6, y 20)
  legs      x 0..±4,  y 0..11            (hip joints at x ±2, y 11)

Run:  python3 Tools/make_crew.py        (needs pillow and numpy)
"""
import math, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
sys.path.insert(0, HERE)
SHEET = sys.argv[1] if len(sys.argv) > 1 else None
sys.argv = sys.argv[:1]
from make_models import box, ell, cyl_y, cyl_z, hit
from make_critters import render

GRID_X = (-11, 11)
GRID_Y = (0, 36)
GRID_Z = (-11, 11)
PARTS = ["head", "body", "armL", "armR", "legL", "legR"]


def lr(x0, x1, y0, y1, z0, z1, color, side):
    """A box on one side: side -1 is the character's left (toward -x), +1 its right."""
    a, b = side * x0, side * x1
    return box((min(a, b), y0, z0), (max(a, b), y1, z1), color)


def both(x0, x1, y0, y1, z0, z1, color):
    return [lr(x0, x1, y0, y1, z0, z1, color, -1), lr(x0, x1, y0, y1, z0, z1, color, 1)]


# ---------- shared pieces ----------

def jetpack(z0=2, color="jet", stripe="hazard"):
    """Every crew member wears a jetpack. The flames are added by the game."""
    return (
        both(1, 3, 9, 12, z0 + 1, z0 + 3, "nozzle")
        + [box((-3, 18, z0), (3, 19, z0 + 4), stripe),
           box((-3, 12, z0), (3, 20, z0 + 4), color),
           box((-2, 20, z0 + 1), (2, 21, z0 + 3), "nozzle")]
    )


def arm(side, sleeve, hand, upper=None, upper_to=17, cuff=None, mark=None):
    """An arm, 4 px square, from the shoulder (y 21) down to the hand (y 10)."""
    parts = []
    if mark:
        parts.append(lr(7, 8, 18, 19, -2, 2, mark, side))    # chevron on the outside
    parts.append(lr(4, 8, 10, 12, -2, 2, hand, side))
    if cuff:
        parts.append(lr(4, 8, 12, 13, -2, 2, cuff, side))
    parts.append(lr(4, 8, upper_to, 21, -2, 2, upper or sleeve, side))
    parts.append(lr(4, 8, 12, upper_to, -2, 2, sleeve, side))
    return parts


def leg(side, pants, boot, toe=True, patches=()):
    parts = [lr(*p[:6], p[6], side) for p in patches]
    if toe:
        parts.append(lr(0, 4, 0, 2, -3, -2, boot, side))
    parts.append(lr(0, 4, 0, 3, -2, 2, boot, side))
    parts.append(lr(0, 4, 3, 11, -2, 2, pants, side))
    return parts


def eyes(y0, y1, white, pupil, z=-4, out=1, inner=True):
    """Two eyes on the front of the head. Pupils sit toward the middle, for a friendly look."""
    p = []
    for s in (-1, 1):
        px = (1, 2) if inner else (2, 3)
        p.append(lr(px[0], px[1], y0, y1, z - out, z + 1, pupil, s))
        p.append(lr(1, 3, y0, y1, z - out, z + 1, white, s))
    return p


# ---------- the crew ----------

def wolfie():
    head = (
        [box((-1, 23, -7), (1, 24, -6), "nose"),
         box((-2, 21, -6), (-1, 22, -5), "tongue"), box((-1, 21, -6), (1, 22, -5), "mouth"),
         box((-2, 21, -6), (2, 24, -4), "muzzle")]
        + eyes(25, 27, "white", "amber")
        + both(1, 3, 27, 28, -5, -4, "furdark")
        + both(2, 3, 29, 30, -1, 0, "earpink")
        + both(1, 4, 29, 30, -1, 1, "furdark")
        + both(2, 4, 30, 31, -1, 1, "furdark")
        + both(3, 4, 31, 32, -1, 1, "furdark")
        + [box((-4, 28, -4), (4, 29, 4), "furdark"),
           box((-4, 21, -4), (4, 29, 4), "fur")]
    )
    body = (
        [box((0, 17, -4), (1, 19, -3), "tags"),
         box((-3, 13, -4), (-1, 15, -3), "pouch"), box((1, 13, -4), (3, 15, -3), "pouch"),
         box((-4, 13, -3), (4, 19, 2), "carrier"),
         box((-1, 11, -3), (1, 12, -2), "buckle"),
         box((-4, 11, -2), (4, 12, 2), "belt")]
        + jetpack(2)
        + [box((-4, 11, -2), (4, 21, 2), "olive")]
    )
    patches = [(1, 2, 7, 9, -2.5, -1, "camo1"), (2, 4, 4, 6, -2.5, 0, "camo2"),
               (0, 1, 8, 11, -1, 1, "camo2"), (3, 4, 8, 10, 0, 2, "camo1")]
    return {
        "head": head, "body": body,
        "armL": arm(-1, "fur", "paw", upper="olive", mark="hazard"),
        "armR": arm(1, "fur", "paw", upper="olive", mark="hazard"),
        "legL": leg(-1, "camo", "tan", patches=patches),
        "legR": leg(1, "camo", "tan", patches=patches),
    }


def gecko():
    head = (
        both(2, 3, 25, 28, -6, -5, "pupil")
        + both(1, 4, 25, 28, -6, -3, "geckoeye")
        + both(1, 4, 24, 29, -5, -3, "gecko")
        + [box((-3, 22, -5), (3, 23, -4), "mouth"),
           box((-4, 25, -5), (4, 27, 4), "mask"),
           box((-4, 21, -4), (4, 28, 4), "gecko"),
           box((-3, 28, -3), (3, 29, 3), "gecko")]
    )
    body = (
        [box((-1, 15, -3), (1, 19, -2), "emblem"), box((-2, 16, -3), (2, 18, -2), "emblem"),
         box((-4, 11, -2), (4, 12, 2), "emblem")]
        + [box((-1, 9, 2), (1, 11, 9), "gecko"), box((-1, 8, 7), (1, 9, 10), "gecko")]
        + jetpack(2)
        + [box((-4, 11, -2), (4, 21, 2), "hero")]
    )
    return {
        "head": head, "body": body,
        "armL": arm(-1, "hero", "gecko", cuff="emblem"),
        "armR": arm(1, "hero", "gecko", cuff="emblem"),
        "legL": leg(-1, "tights", "hero"),
        "legR": leg(1, "tights", "hero"),
    }


def bubbles():
    spikes = []
    for (x, y, z) in [(0, 31, 0), (-5, 28, 0), (5, 28, 0), (-5, 23, 1), (5, 23, 1), (-3, 30, 3),
                      (3, 30, 3), (0, 27, 5), (-4, 25, 4), (4, 25, 4), (-3, 31, -2), (3, 31, -2)]:
        spikes.append(box((x - 0.5, y - 0.5, z - 0.5), (x + 0.5, y + 1.5, z + 0.5), "spike"))
    head = (
        spikes
        + [box((-2, 27, -7), (-1, 28, -6), "glint"),
           box((-3, 25, -7), (3, 29, -5), "glass"),
           box((-4, 24, -6), (4, 30, -5), "maskrim"),
           box((-2, 22, -6), (2, 24, -5), "lips"),
           box((-6, 27, -2), (6, 28, 2), "maskrim"),
           ell((0, 26, 0), (5.6, 5.4, 5.6), "puffer")]
    )
    body = (
        [box((-4, 16, -3), (4, 17, -2), "yellow"),
         box((-1, 12, -3), (1, 15, -2), "yellow")]
        + jetpack(2, color="tank", stripe="tankband")
        + [box((-4, 11, -2), (4, 21, 2), "wetsuit")]
    )
    flipper = lambda s: [lr(0, 4, 0, 1, -6, 2, "flipper", s), lr(0, 4, 1, 3, -2, 2, "wetsuitdark", s),
                         lr(0, 4, 3, 11, -2, 2, "wetsuit", s)]
    return {
        "head": head, "body": body,
        "armL": arm(-1, "wetsuit", "puffer", cuff="yellow"),
        "armR": arm(1, "wetsuit", "puffer", cuff="yellow"),
        "legL": flipper(-1), "legR": flipper(1),
    }


def nova():
    head = (
        [box((-3, 27, -7), (-2, 28, -6), "glint"),
         box((-4, 23, -7), (4, 28, -4), "visor"),
         box((5, 26, -1), (6, 31, 0), "antenna"), box((5, 31, -1), (6, 32, 0), "red"),
         ell((0, 25.5, 0), (5.6, 5.4, 5.6), "helmet")]
    )
    body = (
        [box((-2, 16, -3), (-1, 17, -2), "red"), box((0, 16, -3), (1, 17, -2), "green"),
         box((-2, 14, -3), (2, 15, -2), "yellow"),
         box((-3, 13, -3), (3, 19, -2), "panel"),
         box((-4, 11, -2), (4, 12, 2), "blue")]
        + jetpack(2, color="white", stripe="blue")
        + [box((-4, 11, -2), (4, 21, 2), "suit")]
    )
    return {
        "head": head, "body": body,
        "armL": arm(-1, "suit", "blue", cuff="blue", mark="blue"),
        "armR": arm(1, "suit", "blue", cuff="blue", mark="blue"),
        "legL": leg(-1, "suit", "boot", patches=[(0, 4, 6, 7, -2, 2, "blue")]),
        "legR": leg(1, "suit", "boot", patches=[(0, 4, 6, 7, -2, 2, "blue")]),
    }


def gizmo():
    head = (
        both(1, 3, 25, 27, -6, -4, "screeneye")
        + [box((-2, 23, -6), (-1, 24, -4), "screeneye"), box((-1, 22, -6), (1, 23, -4), "screeneye"),
           box((1, 23, -6), (2, 24, -4), "screeneye"),
           box((-3, 22, -5), (3, 28, -4), "screen"),
           box((-1, 32, -1), (1, 34, 1), "red"),
           box((-0.5, 29, -0.5), (0.5, 32, 0.5), "antenna"),
           box((-5, 24, -1), (-4, 26, 1), "bolt"), box((4, 24, -1), (5, 26, 1), "bolt"),
           box((-4, 21, -4), (4, 29, 4), "metal")]
    )
    body = (
        [box((-2, 15, -3), (2, 18, -2), "gauge"), box((-1, 16, -3.5), (1, 17, -2), "red"),
         box((-4, 11, -2), (4, 12, 2), "metaldark")]
        + jetpack(2)
        + [box((-4, 11, -2), (4, 21, 2), "robot")]
    )
    claw = lambda s: [lr(4, 5, 9, 12, -2, 2, "metaldark", s), lr(7, 8, 9, 12, -2, 2, "metaldark", s),
                      lr(4, 8, 13, 14, -2, 2, "metaldark", s), lr(4, 8, 12, 21, -2, 2, "metal", s)]
    piston = lambda s: [lr(0, 4, 0, 3, -3, 2, "metaldark", s), lr(0, 4, 6, 7, -2, 2, "metaldark", s),
                        lr(0.5, 3.5, 3, 11, -1.5, 1.5, "metal", s)]
    return {"head": head, "body": body, "armL": claw(-1), "armR": claw(1), "legL": piston(-1), "legR": piston(1)}


def barnacle():
    head = (
        [box((-1, 31, -6), (1, 32, -5), "gold"),
         box((-5, 29, -7), (5, 30, 5), "brim"),
         box((-4, 30, -5), (4, 33, 4), "hat"),
         box((-3, 21, -6), (3, 23, -4), "beak"),
         box((-3, 23, -5), (3, 24, -4), "mouth")]
        + both(1, 3, 27, 28, -5, -4, "white")
        + eyes(25, 27, "white", "pupil")
        + [box((-4, 21, -4), (4, 29, 4), "turtle")]
    )
    shell = [box((-3, 15, 2), (-1, 17, 3), "shelldark"), box((1, 13, 2), (3, 15, 3), "shelldark"),
             box((-1, 17, 2), (1, 19, 3), "shelldark"), box((-4, 11, 2), (4, 20, 4), "shell")]
    body = (
        [box((-0.5, y, -3), (0.5, y + 1, -2), "gold") for y in (12, 14, 16)]
        + [box((-4, 18, -3), (-1, 21, -2), "white"), box((1, 18, -3), (4, 21, -2), "white"),
           box((-4, 11, -3), (4, 21, -2), "coat")]
        + jetpack(4)
        + shell
        + [box((-4, 11, -2), (4, 21, 2), "coat")]
    )
    return {
        "head": head, "body": body,
        "armL": arm(-1, "coat", "turtle", cuff="gold"),
        "armR": arm(1, "coat", "turtle", cuff="gold"),
        "legL": leg(-1, "cream", "black"),
        "legR": leg(1, "cream", "black"),
    }


def thunderhoof():
    head = (
        [box((-1, 19, -8), (1, 20, -7), "gold"), box((-2, 20, -8), (-1, 21, -7), "gold"),
         box((1, 20, -8), (2, 21, -7), "gold"),
         box((-2, 22, -8), (-1, 23, -7), "nostril"), box((1, 22, -8), (2, 23, -7), "nostril"),
         box((-3, 20, -7), (3, 24, -4), "bullnose"),
         box((1, 24, -6), (4, 25, -5), "gold"), box((1, 27, -6), (4, 28, -5), "gold"),
         box((3, 25, -6), (4, 27, -5), "gold")]
        + both(1, 3, 27, 28, -5, -4, "brow")
        + eyes(25, 27, "white", "pupil")
        + both(4, 7, 27, 28, -1, 1, "horn")
        + both(6, 7, 28, 31, -1, 1, "horn")
        + both(4, 6, 26, 28, 0, 2, "bull")
        + [box((-4, 28, -2), (4, 30, 2), "tuft"),
           box((-4, 21, -4), (4, 29, 4), "bull")]
    )
    body = (
        [box((-0.5, y, -3), (0.5, y + 1, -2), "gold") for y in (13, 15, 17)]
        + [box((-2, 12, -3), (2, 20, -2), "vest"),
           box((-4, 11, -2), (4, 12, 2), "gold")]
        + jetpack(2)
        + [box((-4, 11, -2), (4, 21, 2), "jacket")]
    )
    epaulette = lambda s: lr(4, 8, 21, 22, -2, 2, "gold", s)
    return {
        "head": head, "body": body,
        "armL": [epaulette(-1)] + arm(-1, "jacket", "hoof", cuff="vest"),
        "armR": [epaulette(1)] + arm(1, "jacket", "hoof", cuff="vest"),
        "legL": leg(-1, "trousers", "hoof", toe=False),
        "legR": leg(1, "trousers", "hoof", toe=False),
    }


COLORS = {
    "white": "#ffffff", "pupil": "#1d1630", "mouth": "#3a1f28", "red": "#ff4b4b", "green": "#4be37a",
    "yellow": "#ffd23f", "blue": "#3a7bd5", "gold": "#ffc21a", "black": "#25232b", "cream": "#efe6cf",
    "jet": "#5b636e", "hazard": "#ffc21a", "nozzle": "#2c3038", "glint": "#e6fbff",
    # Wolfie
    "fur": "#9298a1", "furdark": "#6c727c", "muzzle": "#d7dbe0", "nose": "#22232a", "amber": "#ffb33c",
    "earpink": "#e8a3a8", "tongue": "#ff8a9a", "olive": "#6b7a3a", "carrier": "#87734d", "pouch": "#6e5d3d", "tags": "#dfe4ea",
    "belt": "#3b3a31", "buckle": "#c9ccd2", "paw": "#5f646d", "camo": "#857b5c", "camo1": "#5c6640",
    "camo2": "#ab9d76", "tan": "#c39b62",
    # Gecko Kid
    "gecko": "#6fd04f", "geckoeye": "#ffe14d", "mask": "#e2383c", "hero": "#e2383c", "emblem": "#ffd23f",
    "tights": "#2f5fd0",
    # Bubbles
    "puffer": "#ffcf45", "spike": "#f2992b", "glass": "#9fe8ff", "maskrim": "#2c3a4a", "lips": "#ff8a5c",
    "wetsuit": "#1fa8a0", "wetsuitdark": "#167a75", "tank": "#ffd23f", "tankband": "#2c3a4a", "flipper": "#3d6bff",
    # Nova
    "helmet": "#eef2f8", "visor": "#1d2a5c", "antenna": "#9aa4b4", "suit": "#e4e9f2", "panel": "#4a5568",
    "boot": "#7d8796",
    # Gizmo
    "metal": "#a9b4c2", "metaldark": "#5d6675", "screen": "#1b2030", "screeneye": "#5ff0ff", "bolt": "#ff8a3d",
    "robot": "#7a4fd0", "gauge": "#e8ecff",
    # Captain Barnacle
    "turtle": "#7fb36a", "beak": "#d9d58a", "hat": "#1f2f5a", "brim": "#14141c", "coat": "#22346a",
    "shell": "#8a6a3a", "shelldark": "#5f4626",
    # Baron Thunderhoof
    "bull": "#7a4a2c", "bullnose": "#d8a77a", "nostril": "#4a2a1a", "horn": "#f1e4c4", "tuft": "#4e2d1a",
    "brow": "#2a1a12", "jacket": "#2a2630", "vest": "#c3262e", "hoof": "#2b2328", "trousers": "#4a4652",
}

CREW = {
    "wolfie": wolfie(), "gecko": gecko(), "bubbles": bubbles(), "nova": nova(),
    "gizmo": gizmo(), "barnacle": barnacle(), "thunderhoof": thunderhoof(),
}


def sample(prims):
    vox = {}
    for i in range(*GRID_X):
        for j in range(*GRID_Y):
            for k in range(*GRID_Z):
                x, y, z = i + 0.5, j + 0.5, k + 0.5
                for p in prims:
                    if hit(p, x, y, z):
                        vox[(i - GRID_X[0], j - GRID_Y[0], k - GRID_Z[0])] = p[-1]
                        break
    return vox


def chunk(tag, content, children=b""):
    return tag + struct.pack("<ii", len(content), len(children)) + content + children


def write_vox(path, models, names):
    gx, gy, gz = GRID_X[1] - GRID_X[0], GRID_Y[1] - GRID_Y[0], GRID_Z[1] - GRID_Z[0]
    index = {n: i + 1 for i, n in enumerate(names)}
    children = b""
    for vox in models:
        body = b"".join(struct.pack("<BBBB", x, gz - 1 - z, y, index[c]) for (x, y, z), c in sorted(vox.items()))
        children += chunk(b"SIZE", struct.pack("<iii", gx, gz, gy))
        children += chunk(b"XYZI", struct.pack("<i", len(vox)) + body)
    palette = bytearray()
    for i in range(256):
        h = COLORS[names[i]].lstrip("#") if i < len(names) else "b4b4b4"
        palette += bytes([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255])
    children += chunk(b"RGBA", bytes(palette))
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + chunk(b"MAIN", b"", children))


if __name__ == "__main__":
    from PIL import Image
    sheet = Image.new("RGBA", (256 * len(CREW), 256), (40, 30, 70, 255))
    for n, (cid, parts) in enumerate(CREW.items()):
        models = [sample(parts[p]) for p in PARTS]
        whole = {}
        for m in models:
            whole.update(m)
        models.append(whole)
        names = sorted({c for m in models for c in m.values()})
        write_vox(os.path.join(RES, f"crew-{cid}.vox"), models, names)
        palette = {c: tuple(int(COLORS[c].lstrip("#")[a:a + 2], 16) for a in (0, 2, 4)) for c in names}
        picture = render(whole, palette, size=256, yaw=-28, pitch=14)
        picture.save(os.path.join(RES, f"crew-{cid}.png"))
        sheet.alpha_composite(picture, (256 * n, 0))
        print(f"{cid}: {len(whole)} voxels, {len(names)} colours")
    if SHEET:
        sheet.save(SHEET)
