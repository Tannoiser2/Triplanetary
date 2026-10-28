#!/usr/bin/env python3
"""Trascrive le mappe ampliate di Mike Rowles in data/xmap.json (sistema interno, 76 x 53 esagoni)
e data/xmap_full.json (da Mercurio a Plutone, 152 x 53).

Fonti (tools/reference/xmap/): inner_map.pdf e full_map.pdf (mappe vettoriali con le etichette CCRR degli
esagoni), inner_planets.pdf, jupiter.pdf, saturn.pdf e outer_planets.pdf (sovrapposizioni dei pianeti e
delle lune), map_notes.pdf (raggi e periodi).

- I centri degli esagoni si ricavano dalle etichette (4 cifre) nell'SVG prodotto da pdftocairo.
- Gli asteroidi sono gli esagoni con la trama a puntini: si contano i pixel scuri nella metà bassa
  dell'esagono (sotto l'etichetta) su un'immagine a 72 dpi.
- La mappa è a esagoni con il lato in alto ("flat-top"); il motore usa esagoni a punta in alto e la
  plancia ruota la vista di 90 gradi, quindi un punto (X, Y) del PDF diventa (Y, -X) nel motore.
Uso: python3 tools/build_xmap.py
"""
import json, math, os, re, subprocess, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "reference", "xmap")
DATA = os.path.join(HERE, "..", "data")
SQRT3 = math.sqrt(3.0)
NEIGHBOR_PT = 45.0          # distanza fra centri di esagoni vicini nel PDF (lato 26 pt)
K = SQRT3 / NEIGHBOR_PT     # da punti PDF a unità del motore

def axial(px, py):
    """Punto del motore -> coordinate assiali (come Hex.from_point)."""
    r = py / 1.5
    q = px / SQRT3 - r * 0.5
    s = -q - r
    rq, rr, rs = round(q), round(r), round(s)
    dq, dr, ds = abs(rq - q), abs(rr - r), abs(rs - s)
    if dq > dr and dq > ds: rq = -rr - rs
    elif dr > ds: rr = -rq - rs
    return (int(rq), int(rr))

def to_engine(dx, dy):
    return (dy * K, -dx * K)

def build(pdf, out, outer):
    tmp = tempfile.mkdtemp()
    svg = os.path.join(tmp, "m.svg")
    subprocess.run(["pdftocairo", "-svg", os.path.join(REF, pdf), svg], check=True)
    subprocess.run(["pdftoppm", "-r", "72", "-png", os.path.join(REF, pdf), os.path.join(tmp, "m")], check=True)
    s = open(svg).read()
    uses = [(float(x), float(y)) for x, y in re.findall(r'<use xlink:href="#glyph-0-\d" x="([\d.]+)" y="([\d.]+)"', s)]
    uses.sort(key=lambda u: (round(u[1]), u[0]))
    labels, cur = [], []
    for u in uses:
        if cur and (abs(u[1] - cur[-1][1]) > 0.6 or u[0] - cur[-1][0] > 8):
            labels.append(cur); cur = []
        cur.append(u)
    labels.append(cur)
    centers = [(sum(u[0] for u in l) / 4.0 + 3.0, l[0][1] + 13.5) for l in labels if len(l) == 4]
    im = Image.open(os.path.join(tmp, "m-1.png")).convert("RGB")
    px = im.load(); W, H = im.size
    # Sole: il disco giallo
    ys = [(x, y) for y in range(0, H, 2) for x in range(0, min(W, 1600), 2) if px[x, y][0] > 180 and px[x, y][1] > 150 and px[x, y][2] < 120]
    sx = sum(p[0] for p in ys) / len(ys); sy = sum(p[1] for p in ys) / len(ys)
    sol_c = min(centers, key=lambda c: (c[0] - sx) ** 2 + (c[1] - sy) ** 2)
    def dark(x, y):
        p = px[x, y]
        return p[0] < 120 and p[1] < 120 and p[2] < 120 and abs(p[0] - p[2]) < 25
    cells, asteroids = [], []
    for cx, cy in centers:
        h = axial(*to_engine(cx - sol_c[0], cy - sol_c[1]))
        cells.append(h)
        if math.hypot(cx - sol_c[0], cy - sol_c[1]) < 2.5 * NEIGHBOR_PT: continue
        # trama a puntini: tanti piccoli gruppi di pixel scuri (una linea d'orbita ne dà uno o due)
        pts = set()
        for dy in range(-4, 15):
            for dx in range(-13, 14):
                x, y = int(cx + dx), int(cy + dy)
                if 0 <= x < W and 0 <= y < H and dark(x, y): pts.add((x, y))
        groups = 0
        seen = set()
        for p0 in pts:
            if p0 in seen: continue
            groups += 1
            stack = [p0]; seen.add(p0)
            while stack:
                a, b = stack.pop()
                for nb in ((a + 1, b), (a - 1, b), (a, b + 1), (a, b - 1), (a + 1, b + 1), (a - 1, b - 1), (a + 1, b - 1), (a - 1, b + 1)):
                    if nb in pts and nb not in seen: seen.add(nb); stack.append(nb)
        if len(pts) >= 30 and groups >= 6: asteroids.append(h)
    # sovrapposizioni: (colonna, riga) delle etichette, colonne pari spostate in basso di mezzo esagono
    def ov(c, r): return (c * 39.0, r * NEIGHBOR_PT + (22.5 if c % 2 == 0 else 0.0))
    def rel(a, b):
        ax, ay = ov(*a); bx, by = ov(*b)
        return axial(*to_engine(bx - ax, by - ay))
    data = {
        "source": "Expanded Triplanetary Map di Mike Rowles (sistema interno, 76 x 53), trascritta da tools/build_xmap.py",
        "cells": sorted(set(cells)), "sol": [0, 0], "asteroids": sorted(set(asteroids)),
        # raggio dell'orbita in esagoni e turni per avanzare di un esagono (Map Notes); periodo 0 = fermo
        "orbits": [
            {"id": "mercury", "name": "Mercurio", "radius": 6, "period": 2, "gravity": "full", "color": "#b9876a", "size": 0.36, "base_sides": [1, 4]},
            {"id": "venus", "name": "Venere", "radius": 12, "period": 3, "gravity": "full", "color": "#e9c98a", "size": 0.42, "base_sides": [0, 1, 2, 3, 4, 5]},
            {"id": "terra", "name": "Terra", "radius": 16, "period": 4, "gravity": "full", "color": "#3f86d8", "size": 0.46, "base_sides": [0, 1, 2, 3, 4, 5],
             "moons": [{"id": "luna", "name": "Luna", "offset": rel((5, 2), (7, 2)), "gravity": "weak", "color": "#c9ccd6", "size": 0.32, "base_sides": [0, 1, 2, 3, 4, 5]}]},
            {"id": "mars", "name": "Marte", "radius": 24, "period": 5, "gravity": "full", "color": "#d0573a", "size": 0.40, "base_sides": [0, 1, 2, 3, 4, 5]},
            {"id": "vesta", "name": "Vesta", "radius": 31, "period": 11, "gravity": "none", "color": "#b0a68f", "size": 0.0, "asteroid_base": True},
            {"id": "ceres", "name": "Ceres", "radius": 34, "period": 12, "gravity": "none", "color": "#a59a8a", "size": 0.0, "asteroid_base": True},
            {"id": "pallas", "name": "Pallade", "radius": 34, "period": 12, "gravity": "none", "color": "#9c9a92", "size": 0.0, "asteroid_base": True, "behind": "ceres", "lag_deg": 60},
            {"id": "jupiter", "name": "Giove", "radius": 42, "period": 42, "gravity": "full", "mult": 2, "color": "#d9b48a", "size": 0.60, "base_sides": [],
             "moons": [
                 {"id": "callisto", "name": "Callisto", "offset": rel((5, 6), (5, 2)), "gravity": "full", "color": "#7b6b5d", "size": 0.36, "base_sides": [0, 1, 2, 3, 4, 5]},
                 {"id": "europa", "name": "Europa", "offset": rel((5, 6), (7, 4)), "gravity": "weak", "color": "#d8dde6", "size": 0.30, "base_sides": []},
                 {"id": "io", "name": "Io", "offset": rel((5, 6), (3, 7)), "gravity": "weak", "color": "#e6b44a", "size": 0.32, "base_sides": [4]},
                 {"id": "ganymede", "name": "Ganimede", "offset": rel((5, 6), (7, 9)), "gravity": "full", "color": "#9a8f84", "size": 0.36, "base_sides": [0]}]},
        ],
        "sol_gravity": {"inner_mult": 3, "outer_mult": 1},
    }
    if outer:
        minor = lambda i, n, a, b, c: {"id": i, "name": n, "offset": rel(a, b), "gravity": "none", "color": c, "size": 0.26, "base_sides": []}
        data["source"] = "Expanded Triplanetary Map di Mike Rowles (da Mercurio a Plutone, 152 x 53), trascritta da tools/build_xmap.py"
        data["orbits"] += [
            {"id": "saturn", "name": "Saturno", "radius": 56, "period": 112, "gravity": "full", "color": "#e3c98f", "size": 0.56, "base_sides": [], "rings": True,
             "moons": [{"id": "titan", "name": "Titano", "offset": rel((6, 5), (5, 2)), "gravity": "weak", "color": "#d9a85a", "size": 0.32, "base_sides": [0, 3]},
                       minor("tethys", "Teti", (6, 5), (4, 5), "#d6d8dc"), minor("rhea", "Rea", (6, 5), (4, 7), "#c8c8c8"),
                       minor("dione", "Dione", (6, 5), (6, 7), "#d0d0d0"), minor("iapetus", "Giapeto", (6, 5), (5, 10), "#8a8478")]},
            {"id": "uranus", "name": "Urano", "radius": 71, "period": 159, "gravity": "full", "color": "#9fe0e0", "size": 0.5, "base_sides": [],
             "moons": [minor("titania", "Titania", (4, 2), (6, 2), "#c8a88a"), minor("oberon", "Oberon", (4, 2), (2, 3), "#a89888")]},
            {"id": "neptune", "name": "Nettuno", "radius": 89, "period": 200, "gravity": "full", "color": "#5a8fe0", "size": 0.5, "base_sides": [],
             "moons": [{"id": "triton", "name": "Tritone", "offset": rel((7, 2), (5, 3)), "gravity": "weak", "color": "#c0c4c8", "size": 0.3, "base_sides": [0]}]},
            {"id": "pluto", "name": "Plutone", "radius": 104, "period": 227, "gravity": "weak", "color": "#c9b8a0", "size": 0.3, "base_sides": [0],
             "moons": [minor("charon", "Caronte", (2, 2), (4, 3), "#9a9a9a")]},
        ]
        data["fuel_mult"] = 2
    # Clandestine: la base pirata non è sulla mappa di Rowles; la si mette su un asteroide della fascia
    # esterna (come sulla plancia classica, a destra e un po' sotto il Sole), chiusa dall'anello di
    # asteroidi speciali che solo i suoi ospiti attraversano.
    ang = math.radians(25.0)
    target = axial(*to_engine(math.cos(ang) * 37 * NEIGHBOR_PT, math.sin(ang) * 37 * NEIGHBOR_PT))
    def hd(a, b):
        dq, dr = a[0] - b[0], a[1] - b[1]
        return max(abs(dq), abs(dr), abs(dq + dr))
    cl = min(data["asteroids"], key=lambda a: hd(a, target))
    dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
    data["fixed"] = [{"id": "clandestine", "name": "Clandestine", "hex": list(cl), "color": "#8fa7c9"}]
    data["special"] = [[cl[0] + d[0], cl[1] + d[1]] for d in dirs]
    data["asteroids"] = [a for a in data["asteroids"] if tuple(a) != tuple(cl) and [a[0], a[1]] not in data["special"]]
    os.makedirs(DATA, exist_ok=True)
    json.dump(data, open(os.path.join(DATA, out), "w"), separators=(",", ":"))
    qs = [c[0] for c in data["cells"]]; rs = [c[1] for c in data["cells"]]
    print(out, "esagoni", len(data["cells"]), "asteroidi", len(data["asteroids"]), "q", min(qs), max(qs), "r", min(rs), max(rs),
          "lune", [(m["id"], m["offset"]) for o in data["orbits"] for m in o.get("moons", [])])

if __name__ == "__main__":
    build("inner_map.pdf", "xmap.json", False)
    build("full_map.pdf", "xmap_full.json", True)
