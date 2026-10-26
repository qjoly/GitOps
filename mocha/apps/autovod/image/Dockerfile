FROM alpine:3.22

ARG AUTOVOD_REF=9b185a1a46338847c9a0220c2d19956a37783642
ARG YOUTUBEUPLOADER_VERSION=1.25.5

RUN apk add --no-cache bash curl jq tzdata streamlink

RUN curl -fsSL "https://github.com/porjo/youtubeuploader/releases/download/v${YOUTUBEUPLOADER_VERSION}/youtubeuploader_${YOUTUBEUPLOADER_VERSION}_Linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin youtubeuploader \
    && chmod 755 /usr/local/bin/youtubeuploader

ADD --chmod=755 "https://raw.githubusercontent.com/jenslys/autovod/${AUTOVOD_REF}/AutoVOD.sh" /usr/local/bin/AutoVOD.sh

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

RUN adduser -D -u 1000 autovod && install -d -o autovod -g autovod /workdir

ENV HOME=/workdir \
    XDG_CACHE_HOME=/tmp \
    XDG_CONFIG_HOME=/tmp

USER 1000
WORKDIR /workdir
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
