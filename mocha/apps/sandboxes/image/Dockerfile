# Sandbox base image: buildpack-deps:trixie plus the few tools every sandbox
# needs. gVisor keeps the root filesystem in RAM, so each binary here is paid by
# every warm-pool pod: nothing gets added without earning its place (no helm, no
# yq — the sandbox skill fetches those on demand).
FROM buildpack-deps:trixie

ARG MISE_VERSION
ARG GH_VERSION=2.105.0
ARG GH_SHA256=79e7ab5db738c48777b696e374f8b428f0647debfb424f44d2f426370407fe2f
ARG KUBECTL_VERSION=v1.37.2
ARG KUBECTL_SHA256=c04487523e7aa7d1493f7808174c899db93d7a9cf57531420cd76b9bd415f8f4
ARG TARGETARCH=amd64

# jq comes from apt: one small package, nothing wrong with trixie's build.
# git and curl are already in the base image, do not reinstall them.
RUN apt-get update \
  && apt-get install -y --no-install-recommends jq ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# gh must NOT come from apt: trixie ships 2.46.0, which GitHub's maintainers
# document as broken against deprecated APIs. Official release tarball instead.
# Extract into a scratch dir first: with only that member named, --strip-components=1
# strips all three of its path components, so extracting straight into /tmp leaves
# the binary at /tmp/gh, not /tmp/bin/gh.
RUN mkdir -p /tmp/gh-extract \
  && curl -fsSL -o /tmp/gh.tgz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
  && echo "${GH_SHA256}  /tmp/gh.tgz" | sha256sum -c - \
  && tar -xzf /tmp/gh.tgz -C /tmp/gh-extract --strip-components=1 "gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" \
  && install -m 755 /tmp/gh-extract/bin/gh /usr/local/bin/gh \
  && rm -rf /tmp/gh.tgz /tmp/gh-extract

# kubectl comes straight from dl.k8s.io, pinned by version and checksum.
RUN curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
  && echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c - \
  && chmod 755 /usr/local/bin/kubectl

# mise is pinned in mise.toml ([tools] mise = "..."), read here at build time so
# the pin lives in one place. The release tarball is used rather than
# https://mise.run: no installer script to trust, and nothing can drift to
# "latest".
COPY mise.toml /etc/mise/mise.toml
RUN MISE_VERSION="${MISE_VERSION:-$(sed -n 's/^mise = "\(.*\)"$/\1/p' /etc/mise/mise.toml)}" \
  && test -n "$MISE_VERSION" \
  && mkdir -p /tmp/mise-extract \
  && curl -fsSL -o /tmp/mise.tgz \
      "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64.tar.gz" \
  && tar -xzf /tmp/mise.tgz -C /tmp/mise-extract \
  && install -m 755 /tmp/mise-extract/mise/bin/mise /usr/local/bin/mise \
  && rm -rf /tmp/mise.tgz /tmp/mise-extract

# mise installs each repo's toolchain into the shared dir: the sandbox mounts
# /root on an emptyDir, which would hide anything installed under the root home.
ENV MISE_DATA_DIR=/usr/local/share/mise \
    MISE_CACHE_DIR=/var/cache/mise \
    MISE_YES=1

WORKDIR /work
CMD ["sleep", "infinity"]
