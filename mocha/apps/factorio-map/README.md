# factorio-map

Zoomable web map + timelapse of the factorio-lucca server, rendered from the
save file and served with OpenSeadragon. Supports every surface (Nauvis,
Fulgora, space platforms, …) and overlays train stations.

## How it works

A daily `CronJob` (`factorio-map-render`) runs the renderer image:

1. downloads the graphical factorio client once onto a cache PVC (build
   `expansion/linux64`, needs the account token from `factorio-secrets`);
2. pulls the latest save + mods from the running server via `kubectl exec`
   (RBAC: `pods/exec` in `factorio-lucca`);
3. loads the save under `Xvfb` + Mesa `llvmpipe` (software GL, no GPU) and takes
   one auto-framed `take_screenshot` per surface, plus a `<surface>.stations.json`
   (train-stop names/positions) — see `image/mod/`;
4. tiles each PNG into a Deep Zoom pyramid with `libvips dzsave`;
5. uploads tiles + a timelapse `index.json` to BunnyCDN (`mocha-coffee/factorio-map/`,
   S3 via rclone), keeping the last `KEEP` renders.

`factorio-map-web` (nginx) reverse-proxies **only** the `factorio-map/` prefix
from BunnyCDN storage (the AccessKey stays server-side; restic backups in the
same zone are never exposed) and is published at
`https://factorio-map.mocha.thoughtless.eu` via Traefik.

> nginx strips the `Referer` header: BunnyCDN storage anti-hotlink returns 401
> for any request carrying one.

## Building the image (local only)

Not built in CI. Build and push manually:

```bash
cd image
docker buildx build --platform linux/amd64 \
  -t atcr.io/une-tasse-de.cafe/factorio-map:<tag> \
  -t atcr.io/une-tasse-de.cafe/factorio-map:latest --push .
```

Then bump the tag in `renderer.yaml`.

## Follow-ups

- factorio does not self-quit after screenshots; the job waits out
  `RENDER_TIMEOUT` (currently 600s). An early-exit (poll for stable PNGs then
  kill) would shorten each run.
- station labels strip factorio rich-text tags (`[item=…]`); icon-only names
  render as a dot without a label.
