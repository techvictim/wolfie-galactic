#!/usr/bin/env python3
"""Builds the detail models in Resources (4 small voxels per big-block edge):
rover.vox and starship.vox.

Shapes are described in big-block units, then sampled at 4 voxels per block, the same way
the style lab built its rover. Open the results in MagicaVoxel (free) to edit them by hand.

Run:  python3 Tools/make_models.py
"""
import math, os, struct

R = 4  # small voxels per big-block edge

COLORS = {
    "tire": "#2b2d36", "metal": "#b7c3cc", "glow": "#ffe066", "glass": "#4aa3ff",
    "rover": "#ffcc33", "trim": "#ff7a2f", "blaster": "#3d4b5c", "crate": "#c98a3d",
    "hull": "#e8ecff", "violet": "#8a5cff", "energy": "#5ff0ff",
    "flag": "#ff7ad9", "seat": "#ff8a3d", "buggyblue": "#3b6fd6", "buggywhite": "#eef1fa",
    "bike": "#c040ff", "bikedark": "#5a1f86",
}

def box(a, b, t): return ("box", a, b, t)
def cyl_z(c, rad, hl, t): return ("cylz", c, rad, hl, t)
def cyl_y(c, rad, hl, t): return ("cyly", c, rad, hl, t)
def ell(c, r, t): return ("ell", c, r, t)
def frame(a, b, w, t): return ("frame", a, b, w, t)
def band(c, r, y0, y1, t): return ("band", c, r, y0, y1, t)
def torus_z(c, major, minor, t): return ("torusz", c, major, minor, t)

def hit(p, x, y, z):
    k = p[0]
    if k == "box":
        a, b = p[1], p[2]
        return a[0] <= x < b[0] and a[1] <= y < b[1] and a[2] <= z < b[2]
    if k == "frame":
        a, b, w = p[1], p[2], p[3]
        if not (a[0] <= x < b[0] and a[1] <= y < b[1] and a[2] <= z < b[2]):
            return False
        n = sum([(x - a[0] < w or b[0] - x < w), (y - a[1] < w or b[1] - y < w), (z - a[2] < w or b[2] - z < w)])
        return n >= 2
    if k == "cylz":
        c, rad, hl = p[1], p[2], p[3]
        return abs(z - c[2]) <= hl and (x - c[0]) ** 2 + (y - c[1]) ** 2 <= rad * rad
    if k == "cyly":
        c, rad, hl = p[1], p[2], p[3]
        return abs(y - c[1]) <= hl and (x - c[0]) ** 2 + (z - c[2]) ** 2 <= rad * rad
    if k == "band":
        c, r, y0, y1 = p[1], p[2], p[3], p[4]
        return y0 <= y < y1 and ((x - c[0]) / r[0]) ** 2 + ((y - c[1]) / r[1]) ** 2 + ((z - c[2]) / r[2]) ** 2 <= 1
    if k == "torusz":
        c, major, minor = p[1], p[2], p[3]
        q = math.hypot(x - c[0], y - c[1]) - major
        return q * q + (z - c[2]) ** 2 <= minor * minor
    if k == "ell":
        c, r = p[1], p[2]
        return ((x - c[0]) / r[0]) ** 2 + ((y - c[1]) / r[1]) ** 2 + ((z - c[2]) / r[2]) ** 2 <= 1
    return False

# Rover facing +x, wheels on the ground at y = 0. First matching shape wins.
def wheel(x, z):
    return [cyl_z((x, 0.55, z), 0.24, 0.32, "metal"), cyl_z((x, 0.55, z), 0.56, 0.27, "tire")]

ROVER = (
    wheel(0.55, 0.6) + wheel(3.05, 0.6) + wheel(0.55, 2.9) + wheel(3.05, 2.9) + [
        box((3.4, 1.2, 0.85), (3.6, 1.45, 1.2), "glow"),
        box((3.4, 1.2, 2.3), (3.6, 1.45, 2.65), "glow"),
        box((1.95, 1.6, 0.95), (3.25, 2.5, 2.55), "glass"),
        box((1.75, 1.6, 0.85), (3.35, 2.6, 2.65), "rover"),
        box((0.05, 0.95, 0.7), (3.5, 1.15, 2.8), "trim"),
        box((0.05, 0.6, 0.75), (3.45, 1.6, 2.75), "rover"),
        frame((0.25, 1.6, 1.15), (1.45, 2.5, 2.35), 0.14, "blaster"),
        box((0.25, 1.6, 1.15), (1.45, 2.5, 2.35), "crate"),
        ell((0.45, 3.15, 1.0), (0.2, 0.2, 0.2), "glow"),
        cyl_y((0.45, 2.4, 1.0), 0.2, 0.75, "metal"),
    ]
)

# Starship: nose toward +z, standing on four legs at y = 0. Wings, a violet fin and a
# glowing energy ring around the engines make it look properly alien.
CY = 2.9
STARSHIP = [
    ell((0, CY + 0.95, 2.1), (0.95, 0.85, 1.5), "glass"),
    cyl_z((0, CY, 4.5), 0.26, 0.22, "energy"),
    band((0, CY, 0), (1.82, 1.42, 4.58), CY - 0.2, CY + 0.15, "violet"),
    ell((0, CY, 0), (1.75, 1.35, 4.5), "hull"),
    torus_z((0, CY, -3.3), 2.55, 0.3, "energy"),
    cyl_z((-1.0, CY - 0.25, -4.85), 0.46, 0.12, "energy"),
    cyl_z((1.0, CY - 0.25, -4.85), 0.46, 0.12, "energy"),
    cyl_z((-1.0, CY - 0.25, -4.1), 0.6, 0.7, "metal"),
    cyl_z((1.0, CY - 0.25, -4.1), 0.6, 0.7, "metal"),
    box((-0.25, CY + 0.7, -4.3), (0.25, CY + 2.9, -2.3), "violet"),
    box((-4.95, CY - 0.45, -2.1), (-4.15, CY + 0.05, 0.6), "violet"),
    box((4.15, CY - 0.45, -2.1), (4.95, CY + 0.05, 0.6), "violet"),
    box((-4.95, CY - 0.45, -2.1), (4.95, CY + 0.05, 0.6), "hull"),
] + [
    shape
    for x in (-1.15, 1.15)
    for z in (-2.0, 2.0)
    for shape in (
        box((x - 0.35, 0.0, z - 0.35), (x + 0.35, 0.2, z + 0.35), "metal"),
        cyl_y((x, (CY - 1.1) / 2, z), 0.17, (CY - 1.1) / 2, "metal"),
    )
]

# Moon buggy facing +x: big soft wheels, an open roll cage, a seat and a little flag.
def big_wheel(x, z):
    return [cyl_z((x, 0.72, z), 0.28, 0.36, "metal"), cyl_z((x, 0.72, z), 0.72, 0.3, "tire")]

BUGGY = (
    big_wheel(0.75, 0.45) + big_wheel(3.25, 0.45) + big_wheel(0.75, 3.05) + big_wheel(3.25, 3.05) + [
        box((0.55, 2.75, 0.85), (0.7, 3.35, 1.5), "flag"),
        cyl_y((0.6, 2.3, 0.75), 0.1, 1.0, "metal"),
        ell((0.75, 2.05, 2.75), (0.38, 0.12, 0.38), "metal"),
        box((1.55, 1.25, 1.25), (2.15, 1.9, 2.25), "seat"),
        frame((1.0, 1.2, 0.75), (2.8, 2.7, 2.75), 0.16, "buggyblue"),
        box((0.2, 0.95, 0.55), (3.8, 1.25, 2.95), "buggywhite"),
        box((3.5, 1.05, 1.1), (3.85, 1.35, 1.4), "glow"),
        box((3.5, 1.05, 2.1), (3.85, 1.35, 2.4), "glow"),
    ]
)

# Hover bike facing +x: no wheels, glowing pads underneath.
HOVERBIKE = [
    box((2.75, 1.5, 0.75), (2.95, 1.95, 1.25), "glass"),
    box((2.45, 1.55, 0.35), (2.6, 1.65, 1.65), "metal"),
    ell((1.2, 1.45, 1.0), (0.6, 0.16, 0.36), "seat"),
    ell((2.9, 1.2, 1.0), (0.45, 0.38, 0.42), "bikedark"),
    cyl_y((0.7, 0.35, 1.0), 0.42, 0.12, "energy"),
    cyl_y((2.6, 0.35, 1.0), 0.42, 0.12, "energy"),
    ell((1.7, 1.0, 1.0), (1.65, 0.45, 0.55), "bike"),
    box((-0.1, 1.0, 0.85), (0.3, 1.3, 1.15), "glow"),
]

MODELS = {
    "rover": (ROVER, ((0, 4), (0, 4), (0, 4))),
    "starship": (STARSHIP, ((-5.2, 5.2), (0, 6.2), (-5.4, 5.0))),
    "buggy": (BUGGY, ((0, 4.2), (0, 3.5), (-0.4, 3.9))),
    "hoverbike": (HOVERBIKE, ((-0.2, 3.5), (0, 2.2), (0, 2))),
}

def build(prims, bounds):
    used = []
    for p in prims:
        if p[-1] not in used:
            used.append(p[-1])
    index = {n: i + 1 for i, n in enumerate(used)}
    (x0, x1), (y0, y1), (z0, z1) = bounds
    vox = {}
    for i in range(math.floor(x0 * R), math.ceil(x1 * R)):
        for j in range(math.floor(y0 * R), math.ceil(y1 * R)):
            for k in range(math.floor(z0 * R), math.ceil(z1 * R)):
                x, y, z = (i + 0.5) / R, (j + 0.5) / R, (k + 0.5) / R
                for p in prims:
                    if hit(p, x, y, z):
                        vox[(i, j, k)] = index[p[-1]]
                        break
    xs = [v[0] for v in vox]; ys = [v[1] for v in vox]; zs = [v[2] for v in vox]
    mn = (min(xs), min(ys), min(zs))
    size = (max(xs) - mn[0] + 1, max(ys) - mn[1] + 1, max(zs) - mn[2] + 1)  # game axes, y up
    voxels = {(a - mn[0], b - mn[1], c - mn[2]): col for (a, b, c), col in vox.items()}
    return size, voxels, used

def chunk(tag, content, children=b""):
    return tag + struct.pack("<ii", len(content), len(children)) + content + children

def write_vox(path, size, voxels, names):
    gx, gy, gz = size
    # MagicaVoxel is z-up: vox = (game x, gz - 1 - game z, game y)
    body = b"".join(struct.pack("<BBBB", x, gz - 1 - z, y, c) for (x, y, z), c in sorted(voxels.items()))
    size_chunk = chunk(b"SIZE", struct.pack("<iii", gx, gz, gy))
    xyzi = chunk(b"XYZI", struct.pack("<i", len(voxels)) + body)
    palette = bytearray()
    for i in range(256):
        if i < len(names):
            h = COLORS[names[i]].lstrip("#")
            palette += bytes([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255])
        else:
            palette += bytes([180, 180, 180, 255])
    rgba = chunk(b"RGBA", bytes(palette))
    main = chunk(b"MAIN", b"", size_chunk + xyzi + rgba)
    with open(path, "wb") as f:
        f.write(b"VOX " + struct.pack("<i", 150) + main)

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    for name, (prims, bounds) in MODELS.items():
        size, voxels, names = build(prims, bounds)
        out = os.path.normpath(os.path.join(here, "..", "Resources", name + ".vox"))
        write_vox(out, size, voxels, names)
        print(f"Wrote {out}: {len(voxels)} voxels, size {size} (x, y-up, z)")
