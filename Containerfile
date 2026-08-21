# syntax=docker/dockerfile:1.7

ARG XCADDY_VERSION=0.4.7
ARG XCADDY_DIGEST=sha256:861480823c2ed33d4aa6878306034df7a25d4d8004c16b1a2598884b35f9732b
ARG CORE_RUNTIME_VERSION=2.43
ARG CORE_RUNTIME_DIGEST=sha256:71993808c91eb67af437cbd08eb03e997b80c6ebb8a376693eb113165b837cec
ARG CADDY_VERSION=2.11.4
ARG CLOUDFLARE_VERSION=0.2.4
ARG PORKBUN_VERSION=0.3.1

FROM quay.io/hummingbird/xcaddy:${XCADDY_VERSION}@${XCADDY_DIGEST} AS builder

ARG CADDY_VERSION
ARG CLOUDFLARE_VERSION
ARG PORKBUN_VERSION
ARG TARGETARCH

ENV CGO_ENABLED=0 \
    GOARCH=${TARGETARCH} \
    GOOS=linux \
    GOPROXY=https://proxy.golang.org,direct \
    GOSUMDB=sum.golang.org \
    GOTOOLCHAIN=local

RUN xcaddy build "v${CADDY_VERSION}" \
    --output /caddy/caddy \
    --with "github.com/caddy-dns/cloudflare@v${CLOUDFLARE_VERSION}" \
    --with "github.com/caddy-dns/porkbun@v${PORKBUN_VERSION}"

FROM quay.io/hummingbird/core-runtime:${CORE_RUNTIME_VERSION}@${CORE_RUNTIME_DIGEST}

ARG CADDY_VERSION
ARG IMAGE_SOURCE=https://github.com/bsherman/caddy-plus
ARG IMAGE_REVISION=unknown
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="caddy-plus" \
      org.opencontainers.image.description="Caddy with Cloudflare and Porkbun DNS providers" \
      org.opencontainers.image.source="${IMAGE_SOURCE}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0"

USER 0

COPY --from=builder --chown=0:0 --chmod=0755 /caddy/caddy /usr/bin/caddy

RUN mkdir -p /config/caddy /data/caddy /etc/caddy /srv && \
    chown -R 65532:0 /config /data /srv && \
    chmod -R g+rwX /config /data /srv && \
    chmod 0755 /etc/caddy

ENV XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data \
    CADDY_VERSION=v${CADDY_VERSION}

EXPOSE 8080 8443 2019
STOPSIGNAL SIGQUIT
WORKDIR /srv

CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]

USER 65532
