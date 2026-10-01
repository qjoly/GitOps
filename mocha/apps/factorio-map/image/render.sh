#!/usr/bin/env bash
set -euo pipefail

# ---- required env ----
: "${FA_USERNAME:?factorio account username}"
: "${FA_TOKEN:?factorio account token}"
: "${AWS_ACCESS_KEY_ID:?s3 access key}"
: "${AWS_SECRET_ACCESS_KEY:?s3 secret key}"

# ---- config (with defaults) ----
S3_ENDPOINT="${S3_ENDPOINT:-https://rustfs.thoughtless.eu}"
S3_BUCKET="${S3_BUCKET:-factorio}"
S3_PREFIX="${S3_PREFIX:-}"                  # empty = bucket root (dedicated bucket)
S3_PROVIDER="${S3_PROVIDER:-Minio}"
S3_REGION="${S3_REGION:-us-east-1}"
FACTORIO_NS="${FACTORIO_NS:-factorio-lucca}"
FACTORIO_SELECTOR="${FACTORIO_SELECTOR:-app=factorio}"
FACTORIO_VERSION="${FACTORIO_VERSION:-2.0.77}"
MAP_ZOOM="${MAP_ZOOM:-1.0}"                 # 1.0 = 32 px/tile (native)
CELL_PX="${CELL_PX:-16384}"                 # max px per screenshot (grid cell)
JPEG_Q="${JPEG_Q:-90}"
KEEP="${KEEP:-14}"
RENDER_TIMEOUT="${RENDER_TIMEOUT:-1800}"    # cap on the FMAP_DONE wait; flush is separate
CACHE="${CACHE_DIR:-/cache}"
WORK="${WORK_DIR:-/work}"
FDIR="$CACHE/factorio"
DEST="s3:${S3_BUCKET}${S3_PREFIX:+/$S3_PREFIX}"

# rclone S3 remote "s3", configured via env
export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER="$S3_PROVIDER"
export RCLONE_CONFIG_S3_ENV_AUTH=false
export RCLONE_CONFIG_S3_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_S3_ENDPOINT="$S3_ENDPOINT"
export RCLONE_CONFIG_S3_REGION="$S3_REGION"

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# ---- 1. factorio client (cached on PVC) ----
if [ ! -x "$FDIR/bin/x64/factorio" ] || [ "$("$FDIR/bin/x64/factorio" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" != "$FACTORIO_VERSION" ]; then
  log "downloading factorio $FACTORIO_VERSION (expansion/linux64)"
  rm -rf "$FDIR"; mkdir -p "$CACHE"
  curl -fsSL -o /tmp/fa.tar.xz "https://factorio.com/get-download/${FACTORIO_VERSION}/expansion/linux64?username=${FA_USERNAME}&token=${FA_TOKEN}"
  tar xf /tmp/fa.tar.xz -C "$CACHE"; rm -f /tmp/fa.tar.xz
fi
log "factorio: $("$FDIR/bin/x64/factorio" --version | head -1)"

# ---- 2. fetch latest save + mods from the running server ----
POD="$(kubectl get pods -n "$FACTORIO_NS" -l "$FACTORIO_SELECTOR" -o jsonpath='{.items[0].metadata.name}')"
[ -n "$POD" ] || { log "no factorio pod running; nothing to render"; exit 0; }
log "factorio pod: $POD"
LATEST="$(kubectl exec -n "$FACTORIO_NS" "$POD" -- sh -c 'ls -t /factorio/saves/*.zip 2>/dev/null | head -1')"
[ -n "$LATEST" ] || { log "no save found on server"; exit 0; }
log "latest save: $LATEST"
rm -rf "$WORK/saves" "$WORK/mods" "$WORK/out" "$WORK/.factorio"
mkdir -p "$WORK/saves" "$WORK/mods" "$WORK/.factorio"
kubectl exec -n "$FACTORIO_NS" "$POD" -- cat "$LATEST" > "$WORK/saves/current.zip"
kubectl exec -n "$FACTORIO_NS" "$POD" -- tar cf - -C /factorio mods 2>/dev/null | tar xf - -C "$WORK" 2>/dev/null || true
rm -f "$WORK/mods/mod-list.json" "$WORK/mods/mod-settings.dat"

# ---- 3. auth + mod-list ----
cat > "$WORK/.factorio/player-data.json" <<EOF
{"service-username":"${FA_USERNAME}","service-token":"${FA_TOKEN}"}
EOF
{
  echo '{"mods":['
  echo '{"name":"base","enabled":true},{"name":"space-age","enabled":true},{"name":"quality","enabled":true},{"name":"elevated-rails","enabled":true},'
  for z in "$WORK"/mods/*.zip; do
    [ -e "$z" ] || continue
    n="$(basename "$z" .zip | sed 's/_[0-9][0-9.]*$//')"
    echo "{\"name\":\"$n\",\"enabled\":true},"
  done
  echo '{"name":"factorio-map-shot","enabled":true}'
  echo ']}'
} > "$WORK/mods/mod-list.json"

# ---- 4. render under Xvfb + llvmpipe, in BATCHES ----
# factorio buffers every queued screenshot in RAM until it shuts down, so we run
# it once per batch (NBATCH invocations): each writes ~PER_BATCH cells then quits,
# keeping peak RAM ~ PER_BATCH * cell-buffer. A PLAN pass first enumerates cells.
export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe HOME="$WORK"
pkill -f Xvfb 2>/dev/null || true; sleep 1
Xvfb :99 -screen 0 1920x1080x24 +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
sleep 3
rm -rf "$FDIR/script-output" "$WORK/script-output"; mkdir -p "$WORK/script-output"
ln -sfn "$WORK/script-output" "$FDIR/script-output"
PER_BATCH="${PER_BATCH:-16}"

run_factorio(){   # $1=plan(0/1) $2=batch $3=nbatch ; waits for FMAP_DONE then flushes via shutdown
  rm -rf "$WORK/mods/factorio-map-shot"
  cp -r /opt/factorio-map/mod "$WORK/mods/factorio-map-shot"
  sed -i "s/__MAP_ZOOM__/$MAP_ZOOM/;s/__CELL_PX__/$CELL_PX/;s/__FMAP_PLAN__/$1/;s/__FMAP_BATCH__/$2/;s/__FMAP_NBATCH__/$3/" \
    "$WORK/mods/factorio-map-shot/control.lua"
  "$FDIR/bin/x64/factorio" --load-game "$WORK/saves/current.zip" --mod-directory "$WORK/mods" >/tmp/factorio.log 2>&1 &
  local fpid=$! dl=$(( $(date +%s) + RENDER_TIMEOUT ))
  while kill -0 "$fpid" 2>/dev/null; do
    [ "$(date +%s)" -ge "$dl" ] && { log "  batch timeout"; break; }
    grep -q FMAP_DONE /tmp/factorio.log 2>/dev/null && { sleep 8; break; }  # settle the queue
    sleep 3
  done
  # shutdown re-renders the batch's queued screenshots under llvmpipe (~70s each),
  # so allow a long graceful window before the hard kill.
  kill -TERM "$fpid" 2>/dev/null || true
  for _ in $(seq 1 1200); do kill -0 "$fpid" 2>/dev/null || break; sleep 2; done
  kill -KILL "$fpid" 2>/dev/null || true; wait "$fpid" 2>/dev/null || true
}

t_render0=$(date +%s)
log "planning grid (map_zoom=$MAP_ZOOM cell=$CELL_PX)..."
run_factorio 1 0 1
grep -qE 'FMAP_OK' /tmp/factorio.log || { log "plan produced no output; log tail:"; tail -30 /tmp/factorio.log; exit 1; }
expected="$(grep -oE 'shots=[0-9]+' /tmp/factorio.log | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')"
NBATCH=$(( (expected + PER_BATCH - 1) / PER_BATCH )); [ "$NBATCH" -lt 1 ] && NBATCH=1
log "plan: $expected cells over $NBATCH batch(es) of <=$PER_BATCH"
for b in $(seq 0 $((NBATCH - 1))); do
  log "rendering batch $((b + 1))/$NBATCH..."
  run_factorio 0 "$b" "$NBATCH"
  have="$(find "$WORK/script-output/map" -name 'c_*.png' 2>/dev/null | wc -l | tr -d ' ')"
  log "  cells so far: $have / $expected"
done
have="$(find "$WORK/script-output/map" -name 'c_*.png' 2>/dev/null | wc -l | tr -d ' ')"
log "cells written: $have / $expected expected ($(($(date +%s)-t_render0))s render)"
[ "$have" -ge "$expected" ] || log "WARN: $((expected - have)) cell(s) missing; continuing with what rendered"

# ---- 5. stitch each surface (native grid -> deep-zoom pyramid), stream via pyvips ----
TS="$(date -u +%Y%m%d-%H%M%S)"; OUT="$WORK/out/$TS"; mkdir -p "$OUT"
SURFS=()
t_tile0=$(date +%s)
for d in "$WORK"/script-output/map/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  meta="$WORK/script-output/map/$name.stations.json"
  [ -f "$meta" ] || continue
  nx=$(jq -r .nx "$meta"); ny=$(jq -r .ny "$meta"); cell=$(jq -r .cell "$meta")
  MAP_DIR="$d" NX="$nx" NY="$ny" CELL="$cell" OUTBASE="$OUT/$name" JPEGQ="$JPEG_Q" \
    python3 /opt/factorio-map/stitch.py || { log "stitch failed for $name"; exit 1; }
  cp "$meta" "$OUT/$name.stations.json"
  cp "$WORK/script-output/map/$name.resources.json" "$OUT/" 2>/dev/null || true
  cp "$WORK/script-output/map/$name.rails.json" "$OUT/" 2>/dev/null || true
  rm -rf "$d"
  SURFS+=("$name")
  log "stitched $name (${nx}x${ny} cells)"
done
[ "${#SURFS[@]}" -gt 0 ] || { log "no surfaces stitched"; exit 1; }
tiles="$(find "$OUT" -name '*.jpg' | wc -l | tr -d ' ')"
log "tiled surfaces: ${SURFS[*]} ($tiles tiles, $(($(date +%s)-t_tile0))s, $(du -sh "$OUT" | cut -f1))"

# ---- 6. package as ONE tarball + timelapse index (rustfs throttles per-object PUTs) ----
surf_json="$(printf '"%s",' "${SURFS[@]}" | sed 's/,$//')"
printf '{"timestamp":"%s","surfaces":[%s]}\n' "$TS" "$surf_json" > "$OUT/render.json"
tar -C "$WORK/out" -cf "$WORK/$TS.tar" "$TS"
log "tarball: $(du -sh "$WORK/$TS.tar" | cut -f1)"
t_up0=$(date +%s)
# gentle + resilient upload: rustfs 502s under aggressive multipart concurrency,
# so few large chunks, low concurrency, and generous retries.
rclone copyto "$WORK/$TS.tar" "$DEST/renders/$TS.tar" --s3-no-check-bucket --s3-no-head \
  --s3-upload-concurrency 2 --s3-chunk-size 128M \
  --retries 8 --retries-sleep 20s --low-level-retries 20
log "uploaded tarball ($(($(date +%s)-t_up0))s)"

rclone cat "$DEST/index.json" > "$WORK/index.json" 2>/dev/null || echo '{"renders":[]}' > "$WORK/index.json"
[ -s "$WORK/index.json" ] || echo '{"renders":[]}' > "$WORK/index.json"
jq --arg ts "$TS" --argjson surf "[$surf_json]" --argjson keep "$KEEP" \
  '.renders = ((.renders + [{"timestamp":$ts,"surfaces":$surf}]) | sort_by(.timestamp)) | .dropped = (.renders[0:([0, (.renders|length) - $keep]|max)] | map(.timestamp)) | .renders = .renders[-$keep:]' \
  "$WORK/index.json" > "$WORK/index.new.json"
for old in $(jq -r '.dropped[]?' "$WORK/index.new.json"); do
  log "pruning old render $old"; rclone deletefile "$DEST/renders/$old.tar" 2>/dev/null || true
done
jq 'del(.dropped)' "$WORK/index.new.json" > "$WORK/index.final.json"
# index.json/index.html are mutable -> no-store so the serving sidecar/browser
# always see the current render list / app shell.
rclone copyto "$WORK/index.final.json" "$DEST/index.json" --s3-no-check-bucket --header-upload "Cache-Control: no-store"
rclone copyto /opt/factorio-map/web/index.html "$DEST/index.html" --s3-no-check-bucket --header-upload "Cache-Control: no-store"

rm -f "$WORK/$TS.tar"
log "DONE render=$TS surfaces=${SURFS[*]}"
