#!/usr/bin/env python3
"""Paints the block textures, like Minecraft's: Resources/block-textures.png.

Every block gets three 16 x 16 tiles (top, side, bottom), in its colour from blocks.json with a
pattern for what it is: grass with soil sides, bark and tree rings, planks, stone, metal panels
with rivets, glass with a frame, crates, crystals, glowing Glitch veins and so on. The game adds
the light and shade for each side itself.

Tiles are laid out 16 to a row: tile number = block id * 3 + (0 top, 1 side, 2 bottom).

Run:  python3 Tools/make_block_textures.py      (needs pillow and numpy)
"""
import json, math, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
T = 16
COLS = 16
MAX_BLOCKS = 64


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def rng(seed):
    return np.random.default_rng(seed)


def speckle(base, seed, amount=0.07, scale=1):
    """The colour with gentle per-pixel variation (kept soft so it doesn't shimmer far away)."""
    r = rng(seed)
    n = r.uniform(-amount, amount, (T // scale, T // scale))
    n = np.kron(n, np.ones((scale, scale)))
    return np.clip(base[None, None, :] * (1 + n[:, :, None]), 0, 255)


def shade(tile, mask, factor):
    tile = tile.copy()
    tile[mask] = np.clip(tile[mask] * factor, 0, 255)
    return tile


def blobs(seed, count, size=2):
    r = rng(seed)
    m = np.zeros((T, T), bool)
    for _ in range(count):
        x, y = r.integers(0, T, 2)
        for dy in range(size):
            for dx in range(size):
                if r.random() < 0.8:
                    m[(y + dy) % T, (x + dx) % T] = True
    return m


def border(width=1):
    m = np.zeros((T, T), bool)
    m[:width, :] = m[-width:, :] = m[:, :width] = m[:, -width:] = True
    return m


# ---------- patterns ----------

def dirt(c, seed):
    t = speckle(c, seed, 0.08)
    t = shade(t, blobs(seed + 1, 10, 1), 0.8)
    return shade(t, blobs(seed + 2, 6, 1), 1.15)


def grass_top(c, seed):
    t = speckle(c, seed, 0.1)
    t = shade(t, blobs(seed + 3, 14, 1), 0.85)
    return shade(t, blobs(seed + 4, 10, 1), 1.12)


def grass_side(grass, soil, seed):
    t = dirt(soil, seed)
    g = grass_top(grass, seed + 9)
    r = rng(seed)
    for x in range(T):
        depth = 3 + int(r.integers(0, 3))
        t[:depth, x] = g[:depth, x]
    return t


def stone(c, seed):
    t = speckle(c, seed, 0.06)
    t = shade(t, blobs(seed + 5, 7, 3), 0.85)
    return shade(t, blobs(seed + 6, 5, 2), 1.1)


def sand(c, seed):
    t = speckle(c, seed, 0.05)
    return shade(t, blobs(seed + 7, 18, 1), 0.92)


def bark(c, seed):
    t = speckle(c, seed, 0.05)
    r = rng(seed)
    for x in range(T):
        if r.random() < 0.35:
            t[:, x] *= 0.8
    for _ in range(6):
        x, y = r.integers(0, T, 2)
        t[y:y + 3, x] *= 0.75
    return np.clip(t, 0, 255)


def rings(c, seed):
    t = np.zeros((T, T, 3))
    for y in range(T):
        for x in range(T):
            d = math.hypot(x - 7.5, y - 7.5)
            t[y, x] = c * (0.85 if int(d) % 3 == 0 else 1.05)
    t[border(1)] = c * 0.7
    return np.clip(t, 0, 255)


def leaves(c, seed):
    t = speckle(c, seed, 0.12)
    t = shade(t, blobs(seed + 8, 16, 2), 0.72)
    return shade(t, blobs(seed + 9, 10, 1), 1.18)


def planks(c, seed):
    t = speckle(c, seed, 0.04)
    r = rng(seed)
    for row in range(4):
        y = row * 4
        t[y, :] *= 0.72                       # gaps between boards
        cut = int(r.integers(2, 14))
        t[y:y + 4, cut] *= 0.8                # board ends
        for _ in range(3):                    # grain
            gx = int(r.integers(0, T))
            t[y + 1 + int(r.integers(0, 3)), gx:gx + 4] *= 0.9
    return np.clip(t, 0, 255)


def glass(c, seed, frame=1.25):
    t = np.tile(c, (T, T, 1)).astype(float)
    t[border(1)] = np.clip(c * frame, 0, 255)
    for k in range(3, 7):                     # a little glint
        t[k, k + 2] = np.clip(c * 1.35, 0, 255)
        t[k + 1, k + 2] = np.clip(c * 1.2, 0, 255)
    return t


def metal(c, seed):
    t = speckle(c, seed, 0.03)
    t[border(1)] *= 0.78
    t[7:9, :] *= 0.9
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        t[y, x] = np.clip(c * 1.3, 0, 255)
        t[y + 1, x + 1] *= 0.7
    return np.clip(t, 0, 255)


def crystal(c, seed):
    t = np.zeros((T, T, 3))
    for y in range(T):
        for x in range(T):
            facet = (x + y) // 5 + (x - y + 16) // 6
            t[y, x] = c * (0.85 + 0.12 * (facet % 3))
    t[border(1)] *= 0.8
    for k in range(4, 9):
        t[k, 15 - k] = np.clip(c * 1.4, 0, 255)
    return np.clip(t, 0, 255)


def lamp(c, seed):
    t = np.zeros((T, T, 3))
    for y in range(T):
        for x in range(T):
            d = math.hypot(x - 7.5, y - 7.5)
            t[y, x] = np.clip(c * (1.25 - d / 16), 0, 255)
    t[border(1)] = c * 0.55
    return t


def crate(c, seed):
    t = planks(c, seed)
    t[border(2)] = np.clip(c * 0.7, 0, 255)
    for k in range(2, 14):
        t[k, k] = c * 0.7
        t[k, 15 - k] = c * 0.7
    return np.clip(t, 0, 255)


def ice(c, seed):
    t = speckle(c, seed, 0.03)
    r = rng(seed)
    for _ in range(3):
        x, y = r.integers(0, T, 2)
        for k in range(6):
            t[(y + k) % T, (x + (k // 2)) % T] = np.clip(c * 1.12, 0, 255)
    return np.clip(t, 0, 255)


def panels(c, seed):
    t = speckle(c, seed, 0.02)
    t[7, :] *= 0.9
    t[:, 7] *= 0.9
    t[border(1)] *= 0.92
    return np.clip(t, 0, 255)


def neon(c, seed):
    t = np.zeros((T, T, 3))
    for y in range(T):
        k = 1 - abs(y - 7.5) / 8
        t[y, :] = np.clip(c * (0.75 + 0.45 * k), 0, 255)
    return t


def shingles(c, seed):
    t = speckle(c, seed, 0.04)
    for row in range(4):
        y = row * 4 + 3
        t[y, :] *= 0.75
        off = 2 if row % 2 else 6
        for x in range(off, T, 8):
            t[row * 4:row * 4 + 3, x] *= 0.85
    return np.clip(t, 0, 255)


def road(c, seed):
    t = speckle(c, seed, 0.1)
    return shade(t, blobs(seed + 11, 10, 1), 1.2)


def solar(c, seed):
    t = np.tile(c, (T, T, 1)).astype(float)
    for k in (0, 5, 10, 15):
        t[k, :] = c * 1.6
        t[:, k] = c * 1.6
    return np.clip(t, 0, 255)


def machine_top(c, seed, symbol):
    t = metal(hexrgb("#8d98a6"), seed)
    inner = np.zeros((T, T), bool)
    inner[3:13, 3:13] = True
    t[inner] = c
    ink = np.clip(c * 0.45, 0, 255)
    if symbol == "up":
        for k in range(4):
            t[5 + k, 7 - k:9 + k] = ink
        t[9:12, 7:9] = ink
    elif symbol == "swirl":
        for a in np.linspace(0, 4 * math.pi, 60):
            r = 0.5 + a / 2.8
            t[int(7.5 + r * math.sin(a)) % T, int(7.5 + r * math.cos(a)) % T] = ink
    elif symbol == "fast":
        for off in (4, 8):
            for k in range(3):
                t[5 + k, off + k] = ink
                t[10 - k, off + k] = ink
    elif symbol == "gem":
        for y in range(5, 11):
            w = 3 - abs(y - 7)
            t[y, 7 - w:9 + w] = np.clip(c * 1.35, 0, 255)
    return t


def machine_side(c, seed):
    t = metal(hexrgb("#8d98a6"), seed)
    t[6:10, :] = c
    return t


def glitch(c, seed, glow):
    """Dark red with bright circuit veins crawling over it."""
    t = speckle(c, seed, 0.06)
    r = rng(seed)
    vein = hexrgb("#ffd6da") if glow else hexrgb("#ff6a78")
    for _ in range(5):
        x, y = int(r.integers(0, T)), int(r.integers(0, T))
        for _ in range(14):
            t[y % T, x % T] = vein
            if r.random() < 0.5:
                x += int(r.choice([-1, 1]))
            else:
                y += int(r.choice([-1, 1]))
    if glow:
        t = np.clip(t * 1.1, 0, 255)
    return t


def make_tiles(bid, color, blocks):
    c = hexrgb(color)
    s = bid * 101
    soil = hexrgb(blocks.get(2, "#8a5a3c"))
    violet = hexrgb(blocks.get(14, "#6a4a9c"))
    if bid == 1:   return grass_top(c, s), grass_side(c, soil, s), dirt(soil, s + 1)
    if bid == 13:  return grass_top(c, s), grass_side(c, violet, s), dirt(violet, s + 1)
    if bid in (2, 14): t = dirt(c, s); return t, t, t
    if bid in (3, 15, 19): t = stone(c, s); return t, stone(c, s + 1), t
    if bid in (4, 18, 20): t = sand(c, s); return t, sand(c, s + 1), t
    if bid in (5, 16): return rings(c, s), bark(c, s), rings(c, s)
    if bid in (6, 17): t = leaves(c, s); return t, leaves(c, s + 1), t
    if bid == 7:   t = planks(c, s); return t, t, t
    if bid in (8, 23, 29): t = glass(c, s); return t, t, t
    if bid == 9:   t = metal(c, s); return t, t, t
    if bid == 10:  t = crystal(c, s); return t, t, t
    if bid == 11:  t = lamp(c, s); return t, t, t
    if bid == 12:  t = crate(c, s); return t, t, t
    if bid == 21:  t = ice(c, s); return t, t, t
    if bid == 22:  t = panels(c, s); return t, t, t
    if bid in (24, 25): t = neon(c, s); return glass(c, s, 1.1), t, glass(c, s, 1.1)
    if bid == 26:  return shingles(c, s), shingles(c, s + 1), panels(c * 0.8, s)
    if bid == 27:  t = road(c, s); return t, t, t
    if bid == 28:  t = road(c, s); return t, t, t
    if bid == 30:  return solar(c, s), metal(hexrgb("#8d98a6"), s), metal(hexrgb("#8d98a6"), s)
    if bid == 31:  return machine_top(c, s, "up"), machine_side(c, s), metal(hexrgb("#8d98a6"), s)
    if bid == 32:  return machine_top(c, s, "swirl"), machine_side(c, s), metal(hexrgb("#8d98a6"), s)
    if bid == 33:  return machine_top(c, s, "fast"), machine_side(c, s), metal(hexrgb("#8d98a6"), s)
    if bid == 34:  return machine_top(c, s, "gem"), machine_side(c, s), metal(hexrgb("#8d98a6"), s)
    if bid in (35, 36): t = glitch(c, s, bid == 36); return t, glitch(c, s + 1, bid == 36), t
    t = speckle(c, s, 0.06)
    return t, t, t


if __name__ == "__main__":
    data = json.load(open(os.path.join(RES, "blocks.json")))
    blocks = {b["id"]: b["color"] for b in data["blocks"]}
    rows = (MAX_BLOCKS * 3 + COLS - 1) // COLS
    atlas = np.full((rows * T, COLS * T, 3), 255.0)
    for bid in range(MAX_BLOCKS):
        if bid not in blocks:
            continue
        for kind, tile in enumerate(make_tiles(bid, blocks[bid], blocks)):
            index = bid * 3 + kind
            x, y = (index % COLS) * T, (index // COLS) * T
            atlas[y:y + T, x:x + T] = tile
    Image.fromarray(atlas.astype(np.uint8), "RGB").save(os.path.join(RES, "block-textures.png"))
    print("block-textures.png", atlas.shape[1], "x", atlas.shape[0])
