#!/usr/bin/env python3
"""Paints the weapon pictures for the backpack and hotbar: Resources/item-weapon-<id>.png.

The line drawings are the same icons as Wolfie Military's arsenal, in hazard yellow on a dark
rounded square. Add an entry here for any new weapon in weapons.json.

Run:  python3 Tools/make_weapon_icons.py      (needs cairosvg: pip install cairosvg)
"""
import json, os
import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "Resources"))
SIZE = 192

ICONS = {
 "hammer": "<path d=\"M12.5 3.5h7v6h-7z\"/><path d=\"M14 9.5 4.5 20.5\"/>",
 "sledge": "<path d=\"M10 2.5h11v8H10z\"/><path d=\"M13 10.5 3.5 21\"/>",
 "flame": "<path d=\"M2.5 15h7v3h-7zM9.5 15.8h4\"/><path d=\"M4 15v-3h3v3\"/><path d=\"M14 16c2-3 5-1 7.5-4-1 3 .5 4-1 6.5-1.5 2.4-4.6 2.6-6.5.7\"/><path d=\"M17 17.3c.8-1 1.8-.8 2.4-2\"/>",
 "laser": "<path d=\"M2.5 13h9l1.5-2.5h3V17h-3L11.5 15h-9z\"/><path d=\"M16 13.7h6\"/><path d=\"M19 10l2.5-1.8M19 17.5l2.5 1.8\"/>",
 "cannon": "<circle cx=\"8\" cy=\"17\" r=\"3.6\"/><path d=\"M8.5 13.2 19 6.8l1.7 3-9.8 6.6\"/><path d=\"M3 21h10\"/>",
 "rocket": "<path d=\"M5 19l1-4 9.5-9.5C18 3 21 3 21 3s0 3-2.5 5.5L9 18z\"/><path d=\"M8 13l-4-1 2-2.5M11 16l1 4 2.5-2\"/>",
 "grenade": "<circle cx=\"11\" cy=\"14.5\" r=\"6.5\"/><path d=\"M9 8.2V5.5h4v2.7\"/><path d=\"M13 6.5l4.5-3\"/><path d=\"M8.5 14.5h5\"/>",
 "minigun": "<path d=\"M2.5 9.5h13M2.5 12.5h13M2.5 15.5h13\"/><path d=\"M15.5 7.5H20v10h-4.5z\"/><path d=\"M20 12.5h2.5M17 17.5V21\"/>",
 "blackhole": "<path d=\"M2.5 12.5 7 8l10.5.8 4 3.7-4 3.7L7 17z\"/><path d=\"M7 8l2.2 4.5L7 17M17.5 8.8 15.2 12.5l2.3 3.7M9.2 12.5h6\"/><path d=\"M10 17.5l-1.5 3.5h3.5\"/>",
 "tnt": "<rect x=\"3.5\" y=\"9\" width=\"5\" height=\"12\" rx=\"1\"/><rect x=\"9.5\" y=\"9\" width=\"5\" height=\"12\" rx=\"1\"/><rect x=\"15.5\" y=\"9\" width=\"5\" height=\"12\" rx=\"1\"/><path d=\"M12 9c0-3 2-3.5 3.5-5.5\"/><path d=\"M16.5 2.5l1 1M18 4.5h1.2\"/>",
 "remote": "<rect x=\"6\" y=\"9\" width=\"12\" height=\"12.5\" rx=\"2\"/><path d=\"M12 9V2.5\"/><circle cx=\"12\" cy=\"15.5\" r=\"2.6\"/><path d=\"M15.5 4.5c1.4 1.2 1.4 3 0 4.2M8.5 4.5c-1.4 1.2-1.4 3 0 4.2\"/>",
 "cluster": "<circle cx=\"7.5\" cy=\"9\" r=\"3.2\"/><circle cx=\"16.5\" cy=\"9\" r=\"3.2\"/><circle cx=\"12\" cy=\"16.5\" r=\"3.2\"/><path d=\"M12 2.5v2\"/>",
 "air": "<path d=\"M12 2.5c1 0 1.5 1.5 1.5 3V9l8 4.5v2l-8-2.5v5l2.5 2v1.5L12 20.5 8 21.5V20l2.5-2v-5L2.5 15.5v-2l8-4.5V5.5c0-1.5.5-3 1.5-3z\"/>",
 "bomber": "<path d=\"M12 2.5c.8 0 1.2 1 1.2 2v5l9 4.5v1.8l-9-2.3v4.6l2.4 1.7v1.4L12 20.3l-3.6.9v-1.4l2.4-1.7v-4.6l-9 2.3V14l9-4.5v-5c0-1 .4-2 1.2-2z\"/><path d=\"M6 12.5v2.2M9 11v2.2M15 11v2.2M18 12.5v2.2\"/>",
 "missiles": "<path d=\"M6 2.5v11M12 2.5v13M18 2.5v11\"/><path d=\"M4.3 13.5 6 18l1.7-4.5M10.3 15.5 12 20l1.7-4.5M16.3 13.5 18 18l1.7-4.5\"/>",
 "meteor": "<circle cx=\"15\" cy=\"15\" r=\"5.5\"/><path d=\"M11 11 3 3M12.5 8.5 7 3M8.5 12.5 3 7\"/><path d=\"M13 14l1.5 1.5\"/>",
 "hmg": "<path d=\"M2 11h12M2 14h12\"/><path d=\"M14 9h4v7h-4z\"/><path d=\"M18 12.5h4M15 16l-1.5 4.5M17 16l1 4.5\"/><path d=\"M8 9V7h3v2\"/>",
 "scope": "<circle cx=\"12\" cy=\"12\" r=\"8.5\"/><path d=\"M12 1.5v6M12 16.5v6M1.5 12h6M16.5 12h6\"/><circle cx=\"12\" cy=\"12\" r=\"1.2\"/>",
 "nuke": "<path d=\"M7 13.5a5 5 0 0 1 10 0\"/><path d=\"M4.5 12.5a7.5 4.5 0 0 1 15 0c0 1.6-3 2.4-7.5 2.4s-7.5-.8-7.5-2.4z\"/><path d=\"M10.5 14.9v5.6h3v-5.6\"/><path d=\"M6 20.5h12\"/><path d=\"M9 7.5a3 3 0 0 1 6 0\"/>",
 "sniper": "<path d=\"M1.5 12h15l2-1.5h4\"/><path d=\"M5 12l-1 4h3l1-4\"/><path d=\"M8 9.5h5v2.5H8z\"/><circle cx=\"10.5\" cy=\"7.5\" r=\"1.5\"/>",
 "shotgun": "<path d=\"M2 11.5h13l2 2h4v2.5h-5l-2-2H2z\"/><path d=\"M5 14.5l-1 4h3\"/><path d=\"M19 9l2.5-1.5M19 11l3 0\"/>",
 "bazooka": "<path d=\"M2 10.5h15v4H2z\"/><path d=\"M17 9.5l4 1v4l-4 1\"/><path d=\"M7 14.5v4h3v-4M11 10.5V8h3v2.5\"/>",
 "gl": "<path d=\"M3 10h11v5H3z\"/><circle cx=\"17.5\" cy=\"12.5\" r=\"3.5\"/><path d=\"M6 15v4h3v-4\"/>",
 "mortar": "<path d=\"M8 17 16 4.5l3 1.8-8 12.5\"/><path d=\"M4 20.5h12M7.5 17.5 6 20.5M12 17.5l1.5 3\"/>",
 "buster": "<path d=\"M12 2.5l3 4v10l-3 2-3-2v-10z\"/><path d=\"M9 16.5l-2.5 3M15 16.5l2.5 3M12 18.5v3\"/><path d=\"M10 9h4\"/>",
 "artillery": "<path d=\"M3 17h8l9-9 1.5 1.5-9 9H3z\"/><circle cx=\"6\" cy=\"19\" r=\"2\"/><circle cx=\"12\" cy=\"19\" r=\"2\"/><path d=\"M18 3v2M20.5 4l-1.5 1.5M22 7h-2\"/>",
 "cruise": "<path d=\"M2 12h16l4 0-4-2.5H5L2 12zM2 12l3 2.5h13L22 12\"/><path d=\"M9 9.5 7.5 5.5h2l3 4M9 14.5l-1.5 4h2l3-4\"/>",
 "gunship": "<path d=\"M12 3c.7 0 1 .8 1 1.8V9h8.5v2H13v6l2.5 2v1.2L12 19.5l-3.5.7V19l2.5-2v-6H2.5V9H11V4.8C11 3.8 11.3 3 12 3z\"/><path d=\"M5 7.5v3M8 7.5v3M16 7.5v3M19 7.5v3\"/>",
 "drones": "<rect x=\"9\" y=\"10\" width=\"6\" height=\"4\" rx=\"1\"/><path d=\"M9 11 5.5 7.5M15 11l3.5-3.5M9 13l-3.5 3.5M15 13l3.5 3.5\"/><path d=\"M3 7.5h5M16 7.5h5M3 16.5h5M16 16.5h5\"/>",
 "mines": "<path d=\"M4 16.5h16l-2-4H6z\"/><path d=\"M8 12.5l1-2h6l1 2\"/><path d=\"M12 10.5V8M10.5 8h3\"/>",
 "mega": "<circle cx=\"10.5\" cy=\"14\" r=\"7.5\"/><path d=\"M15.8 8.7l2.4-2.4\"/><path d=\"M18.5 3v2M21.5 6h-2M20.5 4l-1.2 1.2\"/><path d=\"M7 13.5a3.5 3.5 0 0 1 3-3\"/>",
 "harpoon": "<path d=\"M3 21 17 7\"/><path d=\"M14 4h6v6\"/><path d=\"M20 4l-4.5 4.5\"/><path d=\"M5.5 15.5l3 3M8 13l3 3\"/>",
 "torpedo": "<path d=\"M3 12c0-2 1.6-3 3.5-3H16l4 3-4 3H6.5C4.6 15 3 14 3 12z\"/><path d=\"M6 9 4.5 6.5M6 15l-1.5 2.5\"/><circle cx=\"21.5\" cy=\"7\" r=\"1\"/><circle cx=\"19\" cy=\"4.5\" r=\".8\"/>",
 "depth": "<rect x=\"6\" y=\"6\" width=\"12\" height=\"13\" rx=\"2\"/><path d=\"M6 10h12M6 15h12M10 6V3.5h4V6\"/><circle cx=\"4\" cy=\"21\" r=\"1\"/><circle cx=\"20\" cy=\"21.5\" r=\".8\"/>"
}


def svg(paths):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-3 -3 30 30" width="%d" height="%d">'
        '<rect x="-2.6" y="-2.6" width="29.2" height="29.2" rx="6" fill="#1f232b" stroke="#ffc21a" stroke-width="0.9"/>'
        '<g fill="none" stroke="#ffc21a" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">%s</g>'
        '</svg>' % (SIZE, SIZE, paths)
    )


if __name__ == "__main__":
    weapons = json.load(open(os.path.join(RES, "weapons.json")))["weapons"]
    for w in weapons:
        paths = ICONS.get(w["id"])
        if not paths:
            print("no icon for", w["id"])
            continue
        cairosvg.svg2png(bytestring=svg(paths).encode(), write_to=os.path.join(RES, f"item-weapon-{w['id']}.png"))
    print(len(weapons), "weapons")
