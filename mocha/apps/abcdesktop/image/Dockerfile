# abcdesktop desktop image with flatpak, so users install their own
# applications into the persistent home instead of waiting for an image to be
# registered in the app list.
#
# Deliberately derived, not rewritten: oc.user's Dockerfile is 381 lines of
# apt, a custom tigervnc .deb and a node builder stage. Porting that to another
# distribution is a project of its own, and flatpak makes the base distribution
# mostly irrelevant anyway.
ARG BASE=ghcr.io/abcdesktopio/oc.user.ubuntu.sudo.24.04
ARG BASE_TAG=4.4
FROM ${BASE}:${BASE_TAG}

# dbus-x11 gives dbus-launch, which flatpak run needs to reach its session
# helper. No runtime is pulled here: flathub is added per user, in the home.
RUN apt-get update && apt-get install -y --no-install-recommends \
      flatpak \
      dbus-x11 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# flatpak run asks accountsservice for the user's locales over the system bus.
# The daemon needs root, the desktop runs as uid 4096, and dbus then answers
# "Failed to execute program org.freedesktop.Accounts: Permission denied",
# which flatpak treats as fatal. Dropping the activation file makes dbus answer
# ServiceUnknown instead, which flatpak shrugs off. The daemon could not have
# started here anyway.
RUN rm -f /usr/share/dbus-1/system-services/org.freedesktop.Accounts.service
