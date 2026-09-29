#!/usr/bin/env python3
"""Stitch a grid of native screenshot cells into one deep-zoom pyramid.

Streams via pyvips (arrayjoin -> dzsave) so the full multi-gigapixel image is
never materialised: dzsave pulls tiles on demand and each cell PNG is decoded
sequentially. Missing cells (unexplored/void, skipped by the mod) are filled
with black. Env: MAP_DIR, NX, NY, CELL, OUTBASE, JPEGQ.
"""
import os
import pyvips

d = os.environ["MAP_DIR"]
nx = int(os.environ["NX"])
ny = int(os.environ["NY"])
cell = int(os.environ["CELL"])
q = os.environ.get("JPEGQ", "90")
outbase = os.environ["OUTBASE"]

black = pyvips.Image.black(cell, cell, bands=3)

tiles = []
for j in range(ny):
    for i in range(nx):
        p = os.path.join(d, f"c_{j}_{i}.png")
        if os.path.exists(p) and os.path.getsize(p) > 0:
            im = pyvips.Image.new_from_file(p, access="sequential")
            if im.hasalpha():
                im = im.flatten()
            if im.bands != 3:
                im = im[:3] if im.bands > 3 else im.bandjoin([im] * (3 - im.bands))
            tiles.append(im)
        else:
            tiles.append(black)

big = pyvips.Image.arrayjoin(tiles, across=nx)
big.dzsave(outbase, suffix=f".jpg[Q={q}]", tile_size=256, overlap=1)
