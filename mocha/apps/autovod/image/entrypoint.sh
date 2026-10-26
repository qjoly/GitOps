#!/bin/bash
set -euo pipefail

: "${STREAMER_NAME:?STREAMER_NAME must be set}"

# AutoVOD sources its config from the cwd, and youtubeuploader rewrites
# request.token in place, so both need a writable copy of the mounts.
cp "/config/${STREAMER_NAME}.config" /workdir/
cp /secrets/client_secrets.json /secrets/request.token /workdir/
chmod 600 /workdir/client_secrets.json /workdir/request.token

exec /usr/local/bin/AutoVOD.sh -n "${STREAMER_NAME}"
