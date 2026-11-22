# Hermes Agent with the Bot Desktop packages baked in, so the Hermes Desktop
# "Screen" pane works on hermes-carolyn.
#
# The upstream image runs every service as the unprivileged `hermes` user and
# ships no sudo, so the pane's "Install on host" button cannot work there
# (tools/bot_desktop/runtime.py installable() says so): the packages have to be
# in the image. The list is PACKAGES["apt"] from that same file; check it again
# when bumping the base tag.
#
# The base tag is also the tag of the built image (see
# .github/workflows/hermes-agent-desktop-image.yaml).
FROM docker.io/nousresearch/hermes-agent:v0.23.3

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      tigervnc-standalone-server \
      xfce4-panel \
      xfwm4 \
      xfdesktop4 \
      xfce4-settings \
      xfce4-terminal \
      dbus-x11 \
      x11-xserver-utils \
      x11-utils \
      x11-xkb-utils \
      xauth \
      fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*
