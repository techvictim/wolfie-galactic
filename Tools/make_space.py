#!/usr/bin/env python3
"""Builds the space models in Resources:

  space-wolfie-world.vox, space-pup-moon.vox, space-glimmer.vox
      Each planet as a ball of big blocks, seen from orbit. Wolfie World is the same
      wolf-face planet as the title screen (from make_title_planet.py).
  spaceport.vox
      The space station orbiting Wolfie World (4 small voxels per big-block edge).
  ship-comet.vox, ship-hauler.vox, ship-zoomer.vox
      Ships waiting at the spaceport. Like the starship, their noses point to +z.

Run:  python3 Tools/make_space.py      (needs pillow and numpy)
"""
import math, os, runpy, struct, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
sys.path.insert(0, HERE)
import make_models as mm
from make_models import box, ell, cyl_y, cyl_z, torus_z


def write_vox_rgb(path, voxels):
    """voxels: {(x, y, z) game axes, y up: (r, g, b)} with any coordinates."""
    xs = [p[0] for p in voxels]; ys = [p[1] for p in voxels]; zs = [p[2] for p in voxels]
    mn = (min(xs), min(ys), min(zs))
    size = (max(xs) - mn[0] + 1, max(ys) - mn[1] + 1, max(zs) - mn[2] + 1)
    assert max(size) <= 256, size
    colours = []
    index = {}
    for c in voxels.values():
        c = tuple(int(v) for v in c)
        if c not in index:
            assert len(colours) < 255, "too many colours"
            colours.append(c)
            index[c] = len(colours)
    gx, gy, gz = size
    body = b"".join(
        struct.pack("<BBBB", x - mn[0], gz - 1 - (z - mn[2]), y - mn[1], index[tuple(int(v) for v in c)])
        for (x, y, z), c in sorted(voxels.items())
    )
    chunk = mm.chunk
    size_chunk = chunk(b"SIZE", struct.pack("<iii", gx, gz, gy))
    xyzi = chunk(b"XYZI", struct.pack("<i", len(voxels)) + body)
    palette = bytearray()
    for i in range(256):
        c = colours[i] if i < len(colours) else (180, 180, 180)
        palette += bytes([c[0], c[1], c[2], 255])
    main = chunk(b"MAIN", b"", size_chunk + xyzi + chunk(b"RGBA", bytes(palette)))
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + main)
    print(f"{os.path.basename(path)}: {len(voxels)} voxels, size {size}")


def hollow(voxels):
    """Keep only voxels you could see: ones with an empty neighbour."""
    out = {}
    for (x, y, z), c in voxels.items():
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            if (x + d[0], y + d[1], z + d[2]) not in voxels:
                out[(x, y, z)] = c
                break
    return out


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def ball(radius):
    r = int(math.ceil(radius)) + 1
    return [(x, y, z) for x in range(-r, r + 1) for y in range(-r, r + 1) for z in range(-r, r + 1)
            if (x + 0.5) ** 2 + (y + 0.5) ** 2 + (z + 0.5) ** 2 <= radius * radius]


# ---------- planets ----------

def wolfie_world():
    title = runpy.run_path(os.path.join(HERE, "make_title_planet.py"))
    return hollow({k: tuple(int(v) for v in c) for k, c in title["voxels"].items()})


def pup_moon():
    """A grey moon with a paw print of craters on its face."""
    radius = 8.2
    dust, rock, dark, pale = hexrgb("#c9c6d6"), hexrgb("#9a97ab"), hexrgb("#6d6a80"), hexrgb("#e6e4ef")
    vox = {}
    for (x, y, z) in ball(radius):
        n = math.sin(x * 0.7 + y * 0.4) + math.cos(z * 0.8 - x * 0.3)
        vox[(x, y, z)] = pale if n > 1.1 else dust if n > -0.3 else rock
    def crater(cx, cy, r):
        for (x, y, z) in list(vox):
            if z > 0 and (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                top = max(vz for (vx, vy, vz) in vox if vx == x and vy == y)
                if z == top:
                    vox.pop((x, y, z))
                    if (x, y, z - 1) in vox:
                        vox[(x, y, z - 1)] = dark
    crater(0, -2, 3.2)                      # the pad of the paw
    for cx, cy in ((-4, 2), (-1.5, 4), (1.5, 4), (4, 2)):
        crater(cx, cy, 1.4)                 # four toes
    # Little lights: the Moon Base and its outposts.
    light, warm = hexrgb("#fff3a0"), hexrgb("#7af5ff")
    for (lx, ly) in ((5, -3), (6, -2), (-6, -4), (-5, 5), (2, -6), (-2, 7), (6, 4)):
        column = [z for (x, y, z) in vox if x == lx and y == ly]
        if column:
            vox[(lx, ly, max(column))] = light if (lx + ly) % 2 else warm
    return hollow(vox)


def glimmer():
    """A rusty planet with ice caps and crystal spires."""
    radius = 9.5
    sand, rust, deep, ice = hexrgb("#e07a4a"), hexrgb("#c65a35"), hexrgb("#8f3f2a"), hexrgb("#e8f6ff")
    crystals = [hexrgb("#7af5ff"), hexrgb("#ff7ad9"), hexrgb("#b18cff")]
    vox = {}
    for (x, y, z) in ball(radius):
        if abs(y + 0.5) > radius * 0.78:
            vox[(x, y, z)] = ice
            continue
        n = math.sin(x * 0.5 + z * 0.6) + math.cos(y * 0.9 + x * 0.2)
        vox[(x, y, z)] = sand if n > 0.4 else rust if n > -0.6 else deep
    # Crystal spires sticking out of the surface.
    rng = np.random.default_rng(3)
    for i in range(16):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        if abs(d[1]) > 0.7:
            continue
        c = crystals[i % 3]
        for k in range(0, 4):
            p = d * (radius + k - 0.3)
            vox[(int(round(p[0])), int(round(p[1])), int(round(p[2])))] = c
    return hollow(vox)


# ---------- the spaceport ----------

mm.COLORS.update({
    "hullwhite": "#e9edf7", "panel": "#c3cad9", "steel": "#8e98ab", "darksteel": "#4b5367",
    "window": "#7fe6ff", "beacon": "#ff7ad9", "pad": "#3a3f52", "padline": "#ffd23f",
    "solar": "#3156c9", "solarline": "#9bb3ff", "dish": "#dfe4ee", "glowring": "#5ff0ff",
    "comet": "#ff8a3d", "cometdark": "#b4471c", "hauler": "#ffd23f", "haulerdark": "#a8862a",
    "zoomer": "#4fd1b0", "zoomerdark": "#287a66", "canopy": "#4aa3ff", "engine": "#5ff0ff",
})

def ring_windows(major, y, every):
    """Little lit windows around the outside of the ring."""
    out = []
    for i in range(every):
        a = 2 * math.pi * i / every
        x, z = math.cos(a) * (major + 2.4), math.sin(a) * (major + 2.4)
        out.append(box((x - 0.4, y - 0.4, z - 0.4), (x + 0.4, y + 0.4, z + 0.4), "window"))
    return out

def torus_y(c, major, minor, t):
    """A ring lying flat (around the y axis)."""
    return ("torusy", c, major, minor, t)

_old_hit = mm.hit
def hit(p, x, y, z):
    if p[0] == "torusy":
        c, major, minor = p[1], p[2], p[3]
        q = math.hypot(x - c[0], z - c[2]) - major
        return q * q + (y - c[1]) ** 2 <= minor * minor
    return _old_hit(p, x, y, z)
mm.hit = hit

RING = 17
PADS = [(RING + 6, 0.0), (RING + 6, 2 * math.pi / 3), (RING + 6, 4 * math.pi / 3)]   # (distance, angle)

def spaceport():
    prims = []
    prims += ring_windows(RING, 0.0, 40)
    # Docking pads sticking out of the ring: flat decks with yellow edge lines.
    for dist, a in PADS:
        cx, cz = math.cos(a) * dist, math.sin(a) * dist
        prims.append(("frame", (cx - 5, -1.2, cz - 5), (cx + 5, -0.6, cz + 5), 0.5, "padline"))
        prims.append(box((cx - 5, -1.2, cz - 5), (cx + 5, -0.6, cz + 5), "pad"))
        # An arm joining the pad to the ring.
        ax, az = math.cos(a) * (RING + 2), math.sin(a) * (RING + 2)
        prims.append(box((min(ax, cx) - 1, -1.4, min(az, cz) - 1), (max(ax, cx) + 1, -0.4, max(az, cz) + 1), "darksteel"))
    prims += [
        # Glowing ring around the hub, and the hub itself.
        torus_y((0, 4, 0), 6.2, 0.6, "glowring"),
        torus_y((0, -4, 0), 6.2, 0.6, "glowring"),
        cyl_y((0, 0, 0), 5.5, 7, "hullwhite"),
        cyl_y((0, 0, 0), 3.5, 9, "panel"),
        # Beacon mast and dish on top.
        ell((0, 13.5, 0), (0.7, 0.7, 0.7), "beacon"),
        cyl_y((0, 11, 0), 0.4, 2.5, "steel"),
        ell((3.5, 10, 0), (2.4, 0.6, 2.4), "dish"),
        # Solar wings below.
        box((-16, -10.5, -1.5), (-6, -10, 1.5), "solar"),
        box((6, -10.5, -1.5), (16, -10, 1.5), "solar"),
        box((-6, -10.6, -0.3), (6, -9.9, 0.3), "steel"),
        cyl_y((0, -9, 0), 1.2, 2, "steel"),
        # Spokes from the hub to the ring.
        box((-RING, -0.6, -0.8), (RING, 0.6, 0.8), "steel"),
        box((-0.8, -0.6, -RING), (0.8, 0.6, RING), "steel"),
        # The big ring.
        torus_y((0, 0, 0), RING, 2.4, "hullwhite"),
    ]
    size, vox, names = mm.build(prims, ((-29, 29), (-11, 15), (-29, 29)))
    pal = {i + 1: hexrgb(mm.COLORS[n]) for i, n in enumerate(names)}
    vox = hollow({k: pal[c] for k, c in vox.items()})
    return vox


# ---------- ships (nose toward +z, standing at y = 0) ----------

def ship(prims, bounds):
    size, vox, names = mm.build(prims, bounds)
    pal = {i + 1: hexrgb(mm.COLORS[n]) for i, n in enumerate(names)}
    return hollow({k: pal[c] for k, c in vox.items()})

COMET = [   # a fast, pointy fighter
    ell((0, 1.6, 1.0), (0.55, 0.45, 1.0), "canopy"),
    cyl_z((-0.7, 1.2, -2.6), 0.35, 0.3, "engine"),
    cyl_z((0.7, 1.2, -2.6), 0.35, 0.3, "engine"),
    ell((0, 1.2, 0), (0.9, 0.6, 2.8), "comet"),
    box((-3.2, 1.0, -1.8), (3.2, 1.3, 0.2), "cometdark"),
    box((-0.15, 1.3, -2.4), (0.15, 2.6, -1.0), "cometdark"),
    box((-0.6, 0, -0.6), (0.6, 0.7, 0.6), "steel"),
]
HAULER = [  # a big, boxy cargo shuttle
    box((-1.4, 2.6, 4.2), (1.4, 3.6, 4.6), "canopy"),
    cyl_z((-1.6, 1.8, -4.6), 0.7, 0.3, "engine"),
    cyl_z((1.6, 1.8, -4.6), 0.7, 0.3, "engine"),
    box((-2.4, 0.6, -4.4), (2.4, 4.0, 4.6), "hauler"),
    ("frame", (-2.5, 0.5, -4.5), (2.5, 4.1, 4.7), 0.3, "haulerdark"),
    box((-4.0, 1.6, -2.0), (4.0, 2.0, 1.0), "haulerdark"),
    box((-2.0, 0, -3.0), (2.0, 0.6, 3.0), "steel"),
]
ZOOMER = [  # a tiny racer with huge engines
    ell((0, 1.3, 0.6), (0.4, 0.35, 0.6), "canopy"),
    cyl_z((-1.1, 1.0, -1.4), 0.55, 1.2, "zoomerdark"),
    cyl_z((1.1, 1.0, -1.4), 0.55, 1.2, "zoomerdark"),
    cyl_z((-1.1, 1.0, -2.7), 0.45, 0.15, "engine"),
    cyl_z((1.1, 1.0, -2.7), 0.45, 0.15, "engine"),
    ell((0, 1.0, 0.2), (0.7, 0.5, 2.0), "zoomer"),
    box((-0.4, 0, -0.4), (0.4, 0.6, 0.4), "steel"),
]


if __name__ == "__main__":
    write_vox_rgb(os.path.join(RES, "space-wolfie-world.vox"), wolfie_world())
    write_vox_rgb(os.path.join(RES, "space-pup-moon.vox"), pup_moon())
    write_vox_rgb(os.path.join(RES, "space-glimmer.vox"), glimmer())
    write_vox_rgb(os.path.join(RES, "spaceport.vox"), spaceport())
    write_vox_rgb(os.path.join(RES, "ship-comet.vox"), ship(COMET, ((-3.5, 3.5), (0, 3), (-3.2, 3.2))))
    write_vox_rgb(os.path.join(RES, "ship-hauler.vox"), ship(HAULER, ((-4.5, 4.5), (0, 4.5), (-5, 5))))
    write_vox_rgb(os.path.join(RES, "ship-zoomer.vox"), ship(ZOOMER, ((-2, 2), (0, 2), (-3, 2))))
