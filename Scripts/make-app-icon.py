"""Generates DzzReader/AppIcon.icon (Icon Composer bundle): 藏 on a lotus throne.

usage (from the repo root): python3 -I Scripts/make-app-icon.py

Output is deterministic (fixed float formatting, fixed key order), so a rerun yields no diff.
Needs Xcode's `swift` and the system font Songti SC Bold.
"""
import json, math, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "DzzReader", "AppIcon.icon")

glyph_d = subprocess.run(
    ["swift", os.path.join(ROOT, "Scripts", "glyph-path.swift"), "STSongti-SC-Bold", "藏", "1024", "1024"],
    check=True, capture_output=True, text=True).stdout.strip()

BROWN = "#4A3426"
ROSE_DEEP, ROSE_MID, ROSE_PALE = "#B8455E", "#DE8597", "#F7D6DC"

CANG_SCALE, CANG_DY = 0.72, -105
BACK_BASE, BACK_SIZE = 905, 300
FRONT_BASE, FRONT_SIZE = 915, 270

# Tinted: 藏 solid near-white, lotus layers dimmed so 藏 is clearly the brightest element.
TINTED_CANG = "srgb:1,1,1,1"
TINTED_LOTUS_OPACITY = 0.55


def petal(bx, by, length, width, angle):
    """A pointed lotus petal growing from (bx, by), rotated `angle` degrees from straight up."""
    L, W = length, width
    pts = [(0, 0), (W * 0.95, -L * 0.22), (W * 0.62, -L * 0.78), (0, -L),
           (-W * 0.62, -L * 0.78), (-W * 0.95, -L * 0.22), (0, 0)]
    a = math.radians(angle)

    def t(p):
        x, y = p
        return (bx + x * math.cos(a) - y * math.sin(a), by + x * math.sin(a) + y * math.cos(a))
    q = [t(p) for p in pts]
    f = lambda p: "%.1f %.1f" % p
    return "M%s C%s %s %s C%s %s %s Z" % (f(q[0]), f(q[1]), f(q[2]), f(q[3]), f(q[4]), f(q[5]), f(q[6]))


def svg(body, defs=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            '<defs>%s</defs>%s</svg>\n' % (defs, body))


def gradient(gid, top, bottom, y1, y2):
    return ('<linearGradient id="%s" x1="0" y1="%d" x2="0" y2="%d" gradientUnits="userSpaceOnUse">'
            '<stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>'
            % (gid, y1, y2, top, bottom))


def lotus(cx, base, size, part):
    """Back petals (fanned out) or front petals (upright)."""
    s = size
    if part == "back":
        specs = [(-62, 0.80, 0.24), (62, 0.80, 0.24), (-38, 0.92, 0.26), (38, 0.92, 0.26), (-14, 1.0, 0.27), (14, 1.0, 0.27)]
        grad = gradient("g", ROSE_PALE, ROSE_MID, int(base - s), int(base))
    else:
        specs = [(-48, 0.62, 0.25), (48, 0.62, 0.25), (-24, 0.70, 0.27), (24, 0.70, 0.27), (0, 0.76, 0.29)]
        grad = gradient("g", ROSE_MID, ROSE_DEEP, int(base - s * 0.76), int(base))
    paths = "".join('<path d="%s" fill="url(#g)" stroke="%s" stroke-width="%.1f" stroke-opacity="0.35"/>'
                    % (petal(cx, base, s * l, s * w, a), ROSE_DEEP, s * 0.006) for a, l, w in specs)
    return svg(paths, grad)


def cang_svg(scale, dy):
    return svg('<g transform="translate(%.1f %.1f) scale(%.3f)"><path d="%s" fill="%s"/></g>'
               % (512 * (1 - scale), 512 * (1 - scale) + dy, scale, glyph_d, BROWN))


def gradient_fill(stops):
    return {"linear-gradient": stops,
            "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


SEPIA = ["srgb:0.97,0.94,0.87,1", "srgb:0.91,0.85,0.74,1"]
NIGHT = ["srgb:0.20,0.15,0.12,1", "srgb:0.10,0.08,0.07,1"]

cang_extra = {"fill-specializations": [
    {"value": {"solid": "srgb:0.29,0.20,0.15,1"}},
    {"appearance": "dark", "value": {"solid": "srgb:0.95,0.89,0.78,1"}},
    {"appearance": "tinted", "value": {"solid": TINTED_CANG}},
]}
lotus_extra = {"opacity-specializations": [{"appearance": "tinted", "value": TINTED_LOTUS_OPACITY}]}

# icon.json lists the front group first: lotus in front of 藏.
group_defs = [
    [("lotus-front", lotus(512, FRONT_BASE, FRONT_SIZE, "front"), lotus_extra),
     ("lotus-back", lotus(512, BACK_BASE, BACK_SIZE, "back"), lotus_extra)],
    [("cang", cang_svg(CANG_SCALE, CANG_DY), cang_extra)],
]

os.makedirs(os.path.join(OUT, "Assets"), exist_ok=True)
out_groups = []
for layers in group_defs:
    out_layers = []
    for name, text, extra in layers:
        with open(os.path.join(OUT, "Assets", name + ".svg"), "w") as fh:
            fh.write(text)
        layer = {"glass": True, "hidden": False, "image-name": name + ".svg", "name": name,
                 "position": {"scale": 1, "translation-in-points": [0, 0]}}
        layer.update(extra)
        out_layers.append(layer)
    out_groups.append({"layers": out_layers, "shadow": {"kind": "layer-color", "opacity": 0.5},
                       "translucency": {"enabled": True, "value": 0.25}, "specular": True})

doc = {
    "fill-specializations": [
        {"value": gradient_fill(SEPIA)},
        {"appearance": "dark", "value": gradient_fill(NIGHT)},
    ],
    "groups": out_groups,
    "supported-platforms": {"squares": "shared"},
}
with open(os.path.join(OUT, "icon.json"), "w") as fh:
    json.dump(doc, fh, indent=2)
    fh.write("\n")
print("wrote", OUT)
