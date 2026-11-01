#!/usr/bin/env python3
"""Paints the backpack pictures for builds and vehicles:
Resources/item-build-<id>.png and Resources/item-vehicle-<kind>.png.

Builds are read from Resources/builds.json (the same shapes the game uses) and coloured with
Resources/blocks.json; vehicles are read from their .vox models.

Run after changing builds or vehicle models:  python3 Tools/make_item_pictures.py
"""
import json, math, os, struct, sys

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
sys.path.insert(0, HERE)
sys.argv = sys.argv[:1]
from make_critters import render

SIZE = 192


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def inside(shape, x, y, z, a, b):
    """The same rules as BuildDef.inside in Game/Items/Items.swift."""
    on_x = x in (a[0], b[0]); on_y = y in (a[1], b[1]); on_z = z in (a[2], b[2])
    if shape == "walls":
        return on_x or on_z
    if shape == "frame":
        return sum([on_x, on_y, on_z]) >= 2
    if shape == "roof":
        k = y - a[1]
        return a[0] + k <= x <= b[0] - k and a[2] + k <= z <= b[2] - k
    if shape == "dome":
        cx, cz = (a[0] + b[0]) / 2, (a[2] + b[2]) / 2
        rx, rz, ry = (b[0] - a[0]) / 2 + 0.5, (b[2] - a[2]) / 2 + 0.5, (b[1] - a[1]) + 0.5
        dx, dz, dy = (x - cx) / rx, (z - cz) / rz, (y - a[1]) / ry
        d = dx * dx + dy * dy + dz * dz
        inner = dx * dx * (rx / (rx - 1)) ** 2 + dy * dy * (ry / (ry - 1)) ** 2 + dz * dz * (rz / (rz - 1)) ** 2
        return d <= 1 and inner > 1
    if shape == "column":
        cx, cz = (a[0] + b[0]) / 2, (a[2] + b[2]) / 2
        r = min(b[0] - a[0], b[2] - a[2]) / 2 + 0.5
        return (x - cx) ** 2 + (z - cz) ** 2 <= r * r
    return True


def build_voxels(build):
    grid = {}
    for part in build["parts"]:
        a = [min(part["from"][i], part["to"][i]) for i in range(3)]
        b = [max(part["from"][i], part["to"][i]) for i in range(3)]
        for y in range(a[1], b[1] + 1):
            for z in range(a[2], b[2] + 1):
                for x in range(a[0], b[0] + 1):
                    if inside(part["shape"], x, y, z, a, b):
                        grid[(x, y, z)] = part["block"]
    return {k: v for k, v in grid.items() if v != 0}


def load_vox(path):
    data = open(path, "rb").read()
    off = 8 + 12 + struct.unpack("<i", data[12:16])[0]
    vox, pal, size = {}, None, None
    while off + 12 <= len(data):
        tag = data[off:off + 4]
        cs, ch = struct.unpack("<ii", data[off + 4:off + 12])
        c = off + 12
        if tag == b"SIZE":
            size = struct.unpack("<iii", data[c:c + 12])
        elif tag == b"XYZI":
            n = struct.unpack("<i", data[c:c + 4])[0]
            for i in range(n):
                x, y, z, ci = data[c + 4 + i * 4:c + 8 + i * 4]
                vox[(x, z, size[1] - 1 - y)] = ci
        elif tag == b"RGBA":
            pal = {i + 1: tuple(data[c + i * 4:c + i * 4 + 3]) for i in range(255)}
        off = c + cs + ch
    return vox, pal


if __name__ == "__main__":
    blocks = {b["id"]: hexrgb(b["color"]) for b in json.load(open(os.path.join(RES, "blocks.json")))["blocks"]}
    for build in json.load(open(os.path.join(RES, "builds.json")))["builds"]:
        vox = build_voxels(build)
        picture = render(vox, blocks, size=SIZE, yaw=-30, pitch=26)
        picture.save(os.path.join(RES, f"item-build-{build['id']}.png"))
        print("build", build["id"], len(vox))
    for kind, model, yaw in [("rover", "rover", 60), ("buggy", "buggy", 60), ("hoverbike", "hoverbike", 60),
                             ("starship", "starship", 150), ("comet", "ship-comet", 150),
                             ("hauler", "ship-hauler", 150), ("zoomer", "ship-zoomer", 150)]:
        vox, pal = load_vox(os.path.join(RES, model + ".vox"))
        render(vox, pal, size=SIZE, yaw=yaw, pitch=22).save(os.path.join(RES, f"item-vehicle-{kind}.png"))
        print("vehicle", kind)
