#!/usr/bin/env python3
"""Paints the weapon pictures for the backpack and hotbar as colourful toy-block models:
Resources/item-weapon-<id>.png (and item-laser.png). Air strikes that use a ship show the
ship itself.

Shapes are in toy pixels: guns point along +x, y is up. The first shape that covers a voxel
decides its colour, so details go before the things they sit on.

Run:  python3 Tools/make_weapon_models.py      (needs pillow and numpy)
"""
import math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
sys.path.insert(0, HERE)
sys.argv = sys.argv[:1]
from make_critters import render
from make_item_pictures import load_vox

C = {
    "dark": "#2b2f36", "steel": "#8a94a3", "light": "#c3cbd6", "wood": "#9a6a3c", "olive": "#5f6f34",
    "olived": "#46522a", "tan": "#c2a46e", "red": "#d8382f", "hazard": "#ffc21a", "black": "#1b1d22",
    "orange": "#ff8a2a", "green": "#4c7a32", "purple": "#8a4dff", "cyan": "#4ff0ff", "pink": "#ff6fd2",
    "gold": "#ffcc44", "white": "#eef2f8", "rock": "#6b5a4a", "rockd": "#4b3d33", "fire": "#ff6a1a",
    "yellow": "#ffe14d", "ecyan": "#5ff0ff", "eamber": "#ffb13d", "egreen": "#7dff6a", "eviolet": "#b98cff", "epink": "#ff6fd2", "brass": "#d9a94a", "lava": "#ff4d1a", "orb": "#120a1e", "glass": "#9fe8ff",
}


def box(a, b, c): return ("box", a, b, c)
def ell(ctr, r, c): return ("ell", ctr, r, c)
def cylx(y, z, r, x0, x1, c): return ("cylx", (y, z), r, (x0, x1), c)
def cyly(x, z, r, y0, y1, c): return ("cyly", (x, z), r, (y0, y1), c)
def cylz(x, y, r, z0, z1, c): return ("cylz", (x, y), r, (z0, z1), c)
def stripes(shape, every, c2):
    """The same shape with every other band (along x) in a second colour."""
    return ("stripe", shape, every, c2)


def hit(p, x, y, z):
    k = p[0]
    if k == "stripe":
        _, shape, every, c2 = p
        return hit(shape, x, y, z) and int(math.floor(x / every)) % 2 == 0
    if k == "box":
        a, b = p[1], p[2]
        return a[0] <= x < b[0] and a[1] <= y < b[1] and a[2] <= z < b[2]
    if k == "ell":
        c, r = p[1], p[2]
        return ((x - c[0]) / r[0]) ** 2 + ((y - c[1]) / r[1]) ** 2 + ((z - c[2]) / r[2]) ** 2 <= 1
    if k == "cylx":
        (cy, cz), r, (x0, x1) = p[1], p[2], p[3]
        return x0 <= x < x1 and (y - cy) ** 2 + (z - cz) ** 2 <= r * r
    if k == "cyly":
        (cx, cz), r, (y0, y1) = p[1], p[2], p[3]
        return y0 <= y < y1 and (x - cx) ** 2 + (z - cz) ** 2 <= r * r
    if k == "cylz":
        (cx, cy), r, (z0, z1) = p[1], p[2], p[3]
        return z0 <= z < z1 and (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    return False


def colour(p):
    return p[3] if p[0] == "stripe" else p[-1]


def sample(prims, grid=((-22, 26), (-14, 20), (-10, 10))):
    vox = {}
    (x0, x1), (y0, y1), (z0, z1) = grid
    for x in range(x0, x1):
        for y in range(y0, y1):
            for z in range(z0, z1):
                for p in prims:
                    if hit(p, x + 0.5, y + 0.5, z + 0.5):
                        vox[(x, y, z)] = colour(p)
                        break
    return vox


def gun_body(stock, body, length):
    return [box((-14, -3, -1.5), (-4, 2, 1.5), stock), box((-4, -2, -2), (6, 3, 2), body),
            box((-2, -7, -1), (1, -2, 1), "black")]


MODELS = {
    "laser": [cylx(0.5, 0, 1, 10, 13, "pink"), cylx(0.5, 0, 1.6, 4, 10, "steel"),
              box((-6, -2, -2.5), (4, 4, 2.5), "light"), box((-4, -8, -1.5), (0, -2, 1.5), "dark"),
              box((-2, 4, -1), (2, 6, 1), "pink")],
    "hammer": [box((6, -6, -3), (12, 6, 3), "steel"), box((5, -6, -3.2), (6, 6, 3.2), "dark"),
               box((-14, -1.2, -1.2), (6, 1.2, 1.2), "wood"), box((-15, -1.6, -1.6), (-11, 1.6, 1.6), "red")],
    "sledge": [stripes(box((5, -8, -4), (15, 8, 4), "dark"), 3, "steel"), box((5, -8, -4), (15, 8, 4), "steel"),
               box((-16, -1.4, -1.4), (5, 1.4, 1.4), "wood"), box((-17, -1.8, -1.8), (-13, 1.8, 1.8), "hazard")],
    "flame": [ell((21, 1, 0), (4, 3, 3), "yellow"), ell((24, 1, 0), (5, 4, 4), "fire"),
              cylx(1, 0, 1.6, 12, 16, "orange"), cylx(1, 0, 1.2, -2, 12, "dark"),
              box((-4, -2, -2), (4, 4, 2), "steel"), box((-1, -7, -1), (2, -2, 1), "black"),
              stripes(cyly(-9, 0, 4.5, -8, 6, "hazard"), 100, "red"), cyly(-9, 0, 4.5, -8, 6, "red"),
              cyly(-9, 0, 4.6, -1, 1, "hazard")],
    "minigun": sum([[cylx(2 * math.cos(k * math.pi / 3), 2 * math.sin(k * math.pi / 3), 0.8, 2, 20, "dark")] for k in range(6)], [])
               + [cylx(0, 0, 3.2, 18, 20, "ecyan"), cylx(0, 0, 3.2, 14, 16, "ecyan"), box((-12, -5, -5), (2, 5, 5), "dark"),
                  box((-8, -3, 5), (0, 3, 9), "ecyan"), box((-6, -10, -1), (-3, -5, 1), "black"),
                  box((-14, 5, -1), (-4, 7, 1), "steel")],
    "hmg": [stripes(cylx(1, 0, 1.6, 6, 18, "dark"), 3, "eamber"), cylx(1, 0, 1.2, 4, 24, "dark"), cylx(1, 0, 2, 21, 24, "eamber"), box((-10, -3, -3), (4, 4, 3), "olive"),
            box((-6, -7, 3), (2, -1, 7), "olived"), box((10, -9, -0.5), (11, 0, 0.5), "steel"),
            box((13, -9, -0.5), (14, 0, 0.5), "steel"), box((-16, -1, -1), (-10, 3, 1), "olived")],
    "scope": [cylx(1, 0, 1.2, 22, 25, "egreen"), box((-12, 1, -1.7), (-2, 2, 1.7), "egreen"), cylx(1, 0, 0.8, 4, 25, "dark"), box((-16, -2, -1.5), (4, 3, 1.5), "tan"), box((-18, -5, -1.5), (-12, 3, 1.5), "tan"),
              cylx(6, 0, 1.8, -8, 6, "black"), cylx(6, 0, 1.8, 6, 7, "glass"), box((-4, 3, -0.8), (0, 5, 0.8), "black"),
              box((-2, -6, -1), (1, -2, 1), "black")],
    "sniper": [stripes(cylx(1, 0, 1.6, 8, 20, "dark"), 4, "eviolet"), cylx(1, 0, 1.1, 6, 23, "dark"), cylx(1, 0, 1.4, 21, 23, "eviolet"), box((-15, -3, -1.6), (-2, 3, 1.6), "wood"), box((-2, -1, -2), (7, 3, 2), "dark"),
               cylx(5.5, 0, 1.4, -2, 6, "black"), box((0, -6, -1), (3, -1, 1), "wood")],
    "shotgun": [cylx(1.5, 0, 2.2, 17, 20, "epink"), cylx(1.5, 0, 1.3, 0, 20, "dark"), cylx(-1.2, 0, 1.2, 4, 12, "wood"), box((-4, -1, -2), (2, 3, 2), "dark"),
                box((-16, -3, -1.6), (-4, 2, 1.6), "wood"), box((-3, -6, -1), (0, -1, 1), "black"), box((0, -3.5, -2.5), (2, -2.5, 2.5), "red")],
    "cannon": [cylx(2, 0, 3.4, -6, 16, "dark"), cylx(2, 0, 4.2, 14, 16, "black"), ell((-7, 2, 0), (3, 3, 3), "dark"),
               cylz(-2, -5, 5.5, 4, 6, "red"), cylz(-2, -5, 5.5, -6, -4, "red"), cylz(-2, -5, 2, -6, 6, "wood"),
               box((-14, -6, -3), (2, -2, 3), "wood")],
    "rocket": [ell((14, 1, 0), (4, 2.2, 2.2), "red"), cylx(1, 0, 2.6, -14, 12, "olive"), cylx(1, 0, 3, 9, 12, "olived"),
               cylx(1, 0, 3, -14, -11, "olived"), box((-4, -6, -1), (-1, -1, 1), "black"), box((2, -5, -1), (5, -1, 1), "black"),
               box((-2, 3.5, -1), (2, 5, 1), "dark")],
    "bazooka": [stripes(cylx(1, 0, 4, 10, 15, "hazard"), 2, "black"), cylx(1, 0, 4, 10, 15, "black"), cylx(1, 0, 3.4, -16, 10, "green"),
                cylx(1, 0, 4, -18, -14, "black"), box((-6, -8, -1.5), (-2, -2, 1.5), "black"), box((0, -7, -1), (3, -2, 1), "black"),
                box((-8, 4.5, -1.5), (-2, 7, 1.5), "dark")],
    "grenade": [cyly(0, 0, 1.6, 6, 9, "steel"), box((1, 5, -1), (6, 7, 1), "steel"), cylz(6, 4, 2, -0.6, 0.6, "gold"),
                stripes(ell((0, -1, 0), (6, 7, 6), "olive"), 2.5, "olived"), ell((0, -1, 0), (6, 7, 6), "olive"),
                cyly(0, 0, 6.2, -1.5, 0, "hazard")],
    "gl": [cylz(-2, 0, 5.5, -3, 3, "olived"), cylz(-2, 0, 5.6, -0.5, 0.5, "hazard"), cylx(1, 0, 2, 2, 18, "dark"),
           box((-16, -3, -1.5), (-6, 2, 1.5), "olive"), box((-5, -10, -1), (-2, -4, 1), "black"), box((6, -6, -1), (9, -1, 1), "black")],
    "mortar": [cyly(0, 0, 2.6, -4, 16, "olive"), cyly(0, 0, 3, 13, 16, "olived"), box((-9, -8, -9), (9, -6, 9), "dark"),
               box((-1, -6, -1), (1, -4, 1), "steel"), box((5, -6, -0.6), (6, 6, 0.6), "steel"), box((-6, -6, -0.6), (-5, 6, 0.6), "steel")],
    "buster": [stripes(ell((14, 0, 0), (6, 3.4, 3.4), "steel"), 1.5, "light"), ell((14, 0, 0), (6, 3.4, 3.4), "light"),
               stripes(cylx(0, 0, 3.4, -10, 9, "hazard"), 4, "black"), cylx(0, 0, 3.4, -10, 9, "black"),
               box((-14, -6, -0.5), (-9, 6, 0.5), "red"), box((-14, -0.5, -6), (-9, 0.5, 6), "red")],
    "tnt": [box((-2, 8, -0.6), (0, 12, 0.6), "dark"), ell((-1, 12, 0), (1, 1, 1), "orange"),
            box((-6, 0, -3.2), (6, 3, 3.2), "black"), box((-3, 1, -3.6), (3, 3, -3.2), "red"),
            cyly(-4, 0, 2.2, -8, 8, "red"), cyly(0, 0, 2.2, -8, 8, "red"), cyly(4, 0, 2.2, -8, 8, "red")],
    "remote": [box((2, 6, -0.5), (3, 16, 0.5), "dark"), ell((2.5, 16, 0), (1, 1, 1), "red"),
               box((-3, 3, -3.5), (1, 5, -2.8), "green"), box((-8, -4, -3), (8, 4, 3), "tan"),
               box((-8, -1, -3.3), (8, 1, 3.3), "olive"), box((-8, 4, -1), (-4, 6, 1), "red"), box((4, 4, -1), (8, 6, 1), "cyan")],
    "cluster": [cyly(-4, 0, 4.2, 0, 1, "hazard"), ell((-4, 0, 0), (4, 4, 4), "olive"), cyly(4, 0, 4.2, 0, 1, "hazard"),
                ell((4, 0, 0), (4, 4, 4), "olive"), cyly(0, 0, 4.2, 6.5, 7.5, "hazard"), ell((0, 7, 0), (4, 4, 4), "olived")],
    "mines": [cyly(0, 0, 2, 2, 4, "red"), cyly(0, 0, 3.5, 1, 2, "dark"), stripes(cyly(0, 0, 8, -2, 1, "olive"), 3, "olived"),
              cyly(0, 0, 8, -2, 1, "olived")],
    "artillery": [cylx(4, 0, 2, -2, 22, "olive"), cylx(4, 0, 2.6, 18, 22, "olived"), box((-6, 0, -3), (2, 7, 3), "olived"),
                  cylz(-2, -4, 5, 4, 6, "dark"), cylz(-2, -4, 5, -6, -4, "dark"), box((-18, -3, -1), (-2, 0, 1), "olive"),
                  box((-4, 7, -2), (0, 9, 2), "hazard")],
    "cruise": [ell((14, 0, 0), (5, 2.5, 2.5), "red"), cylx(0, 0, 2.6, -14, 12, "white"), box((-2, -0.4, -10), (6, 0.4, 10), "light"),
               box((-14, -0.4, -5), (-9, 0.4, 5), "light"), box((-14, 0, -0.4), (-9, 6, 0.4), "light"), cylx(0, 0, 2.7, -16, -14, "dark")],
    "missiles": sum([[ell((x, 13, 0), (2.2, 4, 2.2), "red"), cyly(x, 0, 2.2, -8, 12, "white"),
                      box((x - 4, -8, -0.4), (x + 4, -4, 0.4), "dark"), cyly(x, 0, 2.3, 2, 3, "hazard")] for x in (-7, 0, 7)], []),
    "drones": [box((-4, -1, -4), (4, 3, 4), "steel"), box((-1, 3, -1), (1, 4, 1), "red"), box((-2, -2, -5), (2, 1, -4), "hazard")]
              + sum([[box((min(0, sx * 9), 0, min(0, sz * 9)), (max(0, sx * 9) + 1, 1.5, max(0, sz * 9) + 1), "dark"),
                      cyly(sx * 9, sz * 9, 4.5, 2, 2.8, "cyan")] for sx in (-1, 1) for sz in (-1, 1)], []),
    "meteor": [stripes(ell((0, 0, 0), (7, 6.5, 6.5), "lava"), 3, "rockd"), ell((0, 0, 0), (7, 6.5, 6.5), "rock"),
               ell((-11, 4, 0), (7, 4, 4), "fire"), ell((-18, 7, 0), (5, 3, 3), "orange"), ell((-23, 9, 0), (3, 2, 2), "yellow")],
    "mega": [box((-20, -0.6, -8), (-12, 0.6, 8), "dark"), box((-20, -8, -0.6), (-12, 8, 0.6), "dark"),
             cylx(0, 0, 7.2, 4, 7, "hazard"), ell((0, 0, 0), (18, 7, 7), "steel"), ell((16, 0, 0), (4, 3, 3), "red")],
    "nuke": [box((-20, -0.6, -9), (-12, 0.6, 9), "black"), box((-20, -9, -0.6), (-12, 9, 0.6), "black"),
             stripes(cylx(0, 0, 8.2, -4, 6, "black"), 2, "hazard"), cylx(0, 0, 8.2, -4, 6, "hazard"),
             ell((0, 0, 0), (19, 8, 8), "yellow"), ell((17, 0, 0), (4, 3.5, 3.5), "red")],
    "blackhole": [ell((16, 0, 0), (3.5, 3.5, 3.5), "orb"), box((-2, 4, -0.6), (6, 8, 0.6), "gold"),
                  box((0, -1, 3), (10, 3, 5), "cyan"), box((0, -1, -5), (10, 3, -3), "pink"),
                  ell((3, 1, 0), (12, 4, 3.4), "purple"), box((-4, -8, -1.5), (0, -2, 1.5), "dark")],
}

SHIPS = {"air": "ship-zoomer", "bomber": "ship-hauler", "gunship": "ship-comet"}


def to_palette(vox):
    return {c: tuple(int(C[c][i:i + 2], 16) for i in (1, 3, 5)) for c in set(vox.values())}


if __name__ == "__main__":
    import json
    from PIL import Image
    ids = [w["id"] for w in json.load(open(os.path.join(RES, "weapons.json")))["weapons"]]
    sheet = Image.new("RGBA", (128 * 8, 128 * ((len(ids) + 8) // 8)), (40, 30, 70, 255))
    for n, wid in enumerate(["laser"] + ids):
        if wid in SHIPS:
            vox, pal = load_vox(os.path.join(RES, SHIPS[wid] + ".vox"))
            picture = render(vox, pal, size=192, yaw=-130, pitch=24)
        elif wid in MODELS:
            vox = sample(MODELS[wid])
            yaw = -20 if wid in ("grenade", "tnt", "remote", "cluster", "mines", "mortar", "missiles", "drones") else -32
            picture = render(vox, to_palette(vox), size=192, yaw=yaw, pitch=22)
        else:
            print("no model for", wid)
            continue
        name = "item-laser.png" if wid == "laser" else f"item-weapon-{wid}.png"
        picture.save(os.path.join(RES, name))
        sheet.alpha_composite(picture.resize((128, 128)), (128 * (n % 8), 128 * (n // 8)))
    sheet.save(os.path.join(os.environ.get("SHEET_DIR", "/tmp"), "weapons-sheet.png"))
    print(len(ids) + 1, "pictures")
