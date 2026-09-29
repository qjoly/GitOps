#!/usr/bin/env bash
# Serving-side sync: pull the render tarballs listed in index.json from S3 and
# extract them onto the local (PVC) webroot, so nginx serves tiles from disk.
# This decouples serving from S3 per-object throughput (rustfs throttles PUTs
# and GETs); one tarball per render is downloaded and expanded once.
set -euo pipefail

: "${AWS_ACCESS_KEY_ID:?s3 access key}"
: "${AWS_SECRET_ACCESS_KEY:?s3 secret key}"
S3_ENDPOINT="${S3_ENDPOINT:-https://rustfs.thoughtless.eu}"
S3_BUCKET="${S3_BUCKET:-factorio}"
S3_PREFIX="${S3_PREFIX:-}"
S3_PROVIDER="${S3_PROVIDER:-Minio}"
S3_REGION="${S3_REGION:-us-east-1}"
SRV="${SRV_DIR:-/srv}"
INTERVAL="${SYNC_INTERVAL:-120}"
DEST="s3:${S3_BUCKET}${S3_PREFIX:+/$S3_PREFIX}"

export RCLONE_CONFIG_S3_TYPE=s3
export RCLONE_CONFIG_S3_PROVIDER="$S3_PROVIDER"
export RCLONE_CONFIG_S3_ENV_AUTH=false
export RCLONE_CONFIG_S3_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export RCLONE_CONFIG_S3_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_S3_ENDPOINT="$S3_ENDPOINT"
export RCLONE_CONFIG_S3_REGION="$S3_REGION"

log(){ echo "[$(date -u +%H:%M:%S)] sync: $*"; }
mkdir -p "$SRV/renders"

while :; do
  if rclone copyto "$DEST/index.json" "$SRV/index.json.new" 2>/dev/null; then
    mv -f "$SRV/index.json.new" "$SRV/index.json"
  fi
  rclone copyto "$DEST/index.html" "$SRV/index.html" 2>/dev/null || true

  if [ -f "$SRV/index.json" ]; then
    wanted="$(jq -r '.renders[].timestamp' "$SRV/index.json" 2>/dev/null || true)"
    for ts in $wanted; do
      [ -d "$SRV/renders/$ts" ] && continue
      log "fetching render $ts"
      if rclone copyto "$DEST/renders/$ts.tar" "/tmp/$ts.tar" --multi-thread-streams 8 --s3-chunk-size 64M 2>/dev/null; then
        mkdir -p "$SRV/renders/.tmp-$ts"
        if tar -C "$SRV/renders/.tmp-$ts" -xf "/tmp/$ts.tar" 2>/dev/null; then
          # tarball contains a top-level "<ts>" dir
          mv "$SRV/renders/.tmp-$ts/$ts" "$SRV/renders/$ts"
          log "extracted $ts ($(find "$SRV/renders/$ts" -type f | wc -l) files)"
        fi
        rm -rf "$SRV/renders/.tmp-$ts" "/tmp/$ts.tar"
      fi
    done
    # prune local renders no longer listed
    for d in "$SRV"/renders/*/; do
      [ -d "$d" ] || continue
      b="$(basename "$d")"
      case "$b" in .tmp-*) rm -rf "$d"; continue;; esac
      echo "$wanted" | grep -qx "$b" || { log "pruning $b"; rm -rf "$d"; }
    done
  fi
  sleep "$INTERVAL"
done
