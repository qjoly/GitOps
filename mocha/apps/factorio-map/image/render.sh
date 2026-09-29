#!/usr/bin/env bash
set -euo pipefail

# ---- required env ----
: "${FA_USERNAME:?factorio account username}"
: "${FA_TOKEN:?factorio account token}"
: "${AWS_ACCESS_KEY_ID:?bunny s3 key}"
: "${AWS_SECRET_ACCESS_KEY:?bunny s3 secret}"

# ---- config (with defaults) ----
BUNNY_ENDPOINT="${BUNNY_ENDPOINT:-https://de-s3.storage.bunnycdn.com}"
BUNNY_BUCKET="${BUNNY_BUCKET:-mocha-coffee}"
BUNNY_PREFIX="${BUNNY_PREFIX:-factorio-map}"
FACTORIO_NS="${FACTORIO_NS:-factorio-lucca}"
FACTORIO_SELECTOR="${FACTORIO_SELECTOR:-app=factorio}"
FACTORIO_VERSION="${FACTORIO_VERSION:-2.0.77}"
RESOLUTION="${RESOLUTION:-8192}"
KEEP="${KEEP:-30}"
CACHE="${CACHE_DIR:-/cache}"
WORK="${WORK_DIR:-/work}"
FDIR="$CACHE/factorio"
DEST="bunny:$BUNNY_BUCKET/$BUNNY_PREFIX"

# rclone S3 remote "bunny" (BunnyCDN S3 gateway), configured via env
export RCLONE_CONFIG_BUNNY_TYPE=s3
export RCLONE_CONFIG_BUNNY_PROVIDER=Other
export RCLONE_CONFIG_BUNNY_ENV_AUTH=false
export RCLONE_CONFIG_BUNNY_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export RCLONE_CONFIG_BUNNY_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_BUNNY_ENDPOINT="$BUNNY_ENDPOINT"
export RCLONE_CONFIG_BUNNY_REGION=de

log(){ echo "[$(date -u +%H:%M:%S)] $*"; }

# ---- 1. factorio client (cached on PVC) ----
if [ ! -x "$FDIR/bin/x64/factorio" ] || [ "$("$FDIR/bin/x64/factorio" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" != "$FACTORIO_VERSION" ]; then
  log "downloading factorio $FACTORIO_VERSION (expansion/linux64)"
  rm -rf "$FDIR"
  mkdir -p "$CACHE"
  curl -fsSL -o /tmp/fa.tar.xz "https://factorio.com/get-download/${FACTORIO_VERSION}/expansion/linux64?username=${FA_USERNAME}&token=${FA_TOKEN}"
  tar xf /tmp/fa.tar.xz -C "$CACHE"
  rm -f /tmp/fa.tar.xz
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

# ---- 3. mods + auth setup ----
cp -r /opt/factorio-map/mod "$WORK/mods/factorio-map-shot"
sed -i "s/__RESOLUTION__/$RESOLUTION/" "$WORK/mods/factorio-map-shot/control.lua"
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

# ---- 4. render every surface under Xvfb + llvmpipe ----
export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe HOME="$WORK"
pkill -f Xvfb 2>/dev/null || true; sleep 1
Xvfb :99 -screen 0 1920x1080x24 +extension GLX +render -noreset >/tmp/xvfb.log 2>&1 &
sleep 3
# keep transient render output in the RAM workspace, not on the cache PVC
rm -rf "$FDIR/script-output" "$WORK/script-output"
mkdir -p "$WORK/script-output"
ln -sfn "$WORK/script-output" "$FDIR/script-output"
log "rendering surfaces (res=$RESOLUTION)..."
timeout "${RENDER_TIMEOUT:-1200}" "$FDIR/bin/x64/factorio" \
  --load-game "$WORK/saves/current.zip" --mod-directory "$WORK/mods" >/tmp/factorio.log 2>&1 || true
grep -E 'FMAP_OK|FMAP_SKIP|FMAP_DONE' /tmp/factorio.log || { log "render produced no markers; log tail:"; tail -30 /tmp/factorio.log; exit 1; }

# ---- 5. tile each surface (deep-zoom) ----
TS="$(date -u +%Y%m%d-%H%M%S)"
OUT="$WORK/out/$TS"
mkdir -p "$OUT"
SURFS=()
for png in "$FDIR"/script-output/map/*.png; do
  [ -s "$png" ] || continue
  name="$(basename "$png" .png)"
  vips dzsave "$png" "$OUT/$name" --suffix ".jpg[Q=82]" --tile-size 256 --overlap 1
  cp "$FDIR/script-output/map/$name.stations.json" "$OUT/" 2>/dev/null || true
  SURFS+=("$name")
done
[ "${#SURFS[@]}" -gt 0 ] || { log "no surfaces rendered"; exit 1; }
log "tiled surfaces: ${SURFS[*]}"

# ---- 6. upload + timelapse index (BunnyCDN via rclone S3) ----
surf_json="$(printf '"%s",' "${SURFS[@]}" | sed 's/,$//')"
printf '{"timestamp":"%s","surfaces":[%s]}\n' "$TS" "$surf_json" > "$OUT/render.json"
rclone copy "$OUT" "$DEST/renders/$TS" --transfers 24 --checkers 24 --s3-no-check-bucket

# global index.json (append + sort + retain last KEEP)
rclone cat "$DEST/index.json" > "$WORK/index.json" 2>/dev/null || echo '{"renders":[]}' > "$WORK/index.json"
[ -s "$WORK/index.json" ] || echo '{"renders":[]}' > "$WORK/index.json"
jq --arg ts "$TS" --argjson surf "[$surf_json]" --argjson keep "$KEEP" \
  '.renders = ((.renders + [{"timestamp":$ts,"surfaces":$surf}]) | sort_by(.timestamp)) | .dropped = (.renders[0:([0, (.renders|length) - $keep]|max)] | map(.timestamp)) | .renders = .renders[-$keep:]' \
  "$WORK/index.json" > "$WORK/index.new.json"
# prune dropped render dirs from bunny
for old in $(jq -r '.dropped[]?' "$WORK/index.new.json"); do
  log "pruning old render $old"
  rclone purge "$DEST/renders/$old" 2>/dev/null || true
done
jq 'del(.dropped)' "$WORK/index.new.json" > "$WORK/index.final.json"
rclone copyto "$WORK/index.final.json" "$DEST/index.json" --s3-no-check-bucket

# static frontend (idempotent)
rclone copyto /opt/factorio-map/web/index.html "$DEST/index.html" --s3-no-check-bucket

log "DONE render=$TS surfaces=${SURFS[*]}"
