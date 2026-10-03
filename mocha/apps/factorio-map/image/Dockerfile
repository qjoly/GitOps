FROM debian:13-slim

ARG KUBECTL_VERSION=v1.31.3

RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb libgl1 libgl1-mesa-dri libglx-mesa0 \
      libx11-6 libxext6 libxfixes3 libxcursor1 libxrandr2 libxinerama1 libxi6 libsm6 libice6 \
      libgomp1 libpulse0 libasound2 \
      ca-certificates curl xz-utils unzip libvips-tools python3 python3-cffi python3-pip jq bash \
  && pip3 install --break-system-packages --no-cache-dir pyvips \
  && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  && curl -fsSL -o /tmp/rclone.zip "https://downloads.rclone.org/rclone-current-linux-amd64.zip" \
  && unzip -j -o /tmp/rclone.zip '*/rclone' -d /usr/local/bin \
  && chmod +x /usr/local/bin/kubectl /usr/local/bin/rclone \
  && rm -f /tmp/rclone.zip \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY render.sh /usr/local/bin/render.sh
COPY sync.sh /usr/local/bin/sync.sh
COPY stitch.py /opt/factorio-map/stitch.py
COPY mod/ /opt/factorio-map/mod/
COPY web/ /opt/factorio-map/web/
RUN chmod +x /usr/local/bin/render.sh /usr/local/bin/sync.sh

ENV CACHE_DIR=/cache WORK_DIR=/work MC_CONFIG_DIR=/tmp/.mc
ENTRYPOINT ["/usr/local/bin/render.sh"]
