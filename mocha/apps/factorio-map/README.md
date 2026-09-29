# factorio-map

Zoomable web map + timelapse of the factorio-lucca server, rendered from the
save file and served with OpenSeadragon. Supports every surface (Nauvis,
Fulgora, space platforms, …) and overlays train stations.

## How it works

A daily `CronJob` (`factorio-map-render`) runs the renderer image and produces,
per render, ONE tarball on S3. `MAP_ZOOM` sets sharpness (px/tile = 32·zoom;
0.75 = 24 px/tile, 1.0 = native 32 px/tile).

1. downloads the graphical factorio client once onto a cache PVC (build
   `expansion/linux64`, needs the account token from `factorio-secrets`);
2. pulls the latest save + mods from the running server via `kubectl exec`
   (RBAC: `pods/exec` in `factorio-lucca`);
3. renders each surface as a **grid of screenshots** under `Xvfb` + Mesa
   `llvmpipe` (software GL, no GPU): a single `take_screenshot` maxes out at
   16384², so a large base is captured in `CELL_PX` cells at the target zoom and
   stitched later. factorio buffers every queued screenshot in RAM until
   shutdown, so the render is split into **batches** (`PER_BATCH` cells per
   factorio invocation) to bound memory; a first `FMAP_PLAN` pass enumerates the
   grid + writes `<surface>.stations.json`. See `image/mod/control.lua`.
4. stitches each surface's cells into one Deep-Zoom pyramid with **pyvips**
   (`image/stitch.py`, `arrayjoin`→`dzsave`, streamed so the multi-gigapixel
   image is never materialised; missing/unexplored cells are filled black);
5. packs the whole render (all pyramids + station JSON) into **one tarball** and
   uploads it to `renders/<ts>.tar` on the `factorio` bucket
   (`rustfs.thoughtless.eu`, rclone), plus a small `index.json`. One object per
   render dodges rustfs's ~20 obj/s PUT ceiling. Keeps the last `KEEP` renders.

`factorio-map-web` serves the tiles **from a PVC**, not from S3 (rustfs throttles
per-object GETs and can't feed a deep-zoom viewer). A **`sync` sidecar** (same
image, `sync.sh`) polls `index.json`, downloads each new `<ts>.tar` and extracts
it onto an `openebs-hostpath` PVC (the LVM VG only had ~52 Gi free; hostpath uses
the node's ~397 Gi); **nginx** serves the PVC. Creds from `factorio-map-s3`
(OpenBao `kv/factorio-s3`). Published at
`https://factorio-map.mocha.thoughtless.eu` via Traefik.

The frontend (`image/web/index.html`, OpenSeadragon) has surface tabs, a
timelapse slider, train-station overlays, and **shareable deep links**
(`#s=<surface>&x=<gx>&y=<gy>&z=<zoom>&t=<render>`, in factorio game coords) with a
live cursor-coordinate readout and a 🔗 copy-link button; clicking a station
zooms to it.

> **Why grids + batches + tarball:** a single `take_screenshot` caps at 16384²
> (~6 px/tile for a big base = blurry); factorio buffers all queued screenshots
> in RAM until shutdown (many 16384² cells at once = OOM); and rustfs throttles
> per-object transfers (a native map is ~150k tiles). So: grid to beat the
> screenshot cap, batch to bound RAM, tarball to beat the object-count ceiling.

> `anti_alias` renders at 2× then downscales — at 16384² the 32768² intermediate
> blows llvmpipe's texture limit, so AA is only used when `shot_res ≤ 8192`.

> `/work` is a **disk-backed** emptyDir, not tmpfs: a `medium: Memory` scratch
> dir counts against the container memory cgroup and OOM-killed the renderer.

## Building the image (local only)

Not built in CI. Build and push manually:

```bash
cd image
docker buildx build --platform linux/amd64 \
  -t atcr.io/une-tasse-de.cafe/factorio-map:<tag> \
  -t atcr.io/une-tasse-de.cafe/factorio-map:latest --push .
```

Then bump the tag in `renderer.yaml`.

## Tunables (CronJob env)

- `MAP_ZOOM` — px/tile = 32·zoom (0.5=16, 0.75=24, 1.0=native 32). More = sharper
  but ~4× the cells/tiles/time/storage per doubling.
- `PER_BATCH` — cells per factorio invocation (RAM ≈ `PER_BATCH`·~1 GiB + game).
- `CELL_PX` (16384), `JPEG_Q` (90), `KEEP`, `RENDER_TIMEOUT`.

## Follow-ups

- station labels strip factorio rich-text tags (`[item=…]`); icon-only names
  render as a dot without a label.
- occasionally 1 cell/batch is lost to the shutdown flush (black patch); a
  post-render pass could re-shoot only the missing cells.
- render time is llvmpipe-bound (~35 s/cell, no GPU); a GPU node would slash it.

## rustfs bucket policy

The `factorio` user is scoped to its own bucket only:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": ["s3:ListBucket", "s3:GetBucketLocation"], "Resource": "arn:aws:s3:::factorio" },
    { "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], "Resource": "arn:aws:s3:::factorio/*" }
  ]
}
```
