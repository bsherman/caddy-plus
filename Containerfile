# syntax=docker/dockerfile:1.7

ARG XCADDY_VERSION=0.4.7
ARG XCADDY_DIGEST=sha256:f92da420ffdcf8eb7c771c2257d63976b866c12a6fc98097efc69b553d8e6b2b
ARG CORE_RUNTIME_VERSION=2.43
ARG CORE_RUNTIME_DIGEST=sha256:114d1b0ba3e2a1fc4ef42f8c1a388c6a7a2f8dca42a38a433464d0edb15bd56b
ARG CADDY_VERSION=2.11.4
ARG CLOUDFLARE_VERSION=0.2.4
ARG PORKBUN_VERSION=0.3.1
ARG LAYER4_VERSION=0.1.2
ARG X_CRYPTO_VERSION=0.56.0

FROM quay.io/hummingbird/xcaddy:${XCADDY_VERSION}@${XCADDY_DIGEST} AS builder

ARG CADDY_VERSION
ARG CLOUDFLARE_VERSION
ARG PORKBUN_VERSION
ARG LAYER4_VERSION
ARG X_CRYPTO_VERSION
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
    --with "github.com/caddy-dns/porkbun@v${PORKBUN_VERSION}" \
    --with "github.com/mholt/caddy-l4@v${LAYER4_VERSION}" \
    --replace "golang.org/x/crypto=golang.org/x/crypto@v${X_CRYPTO_VERSION}"

FROM quay.io/hummingbird/core-runtime:${CORE_RUNTIME_VERSION}@${CORE_RUNTIME_DIGEST}

ARG CADDY_VERSION
ARG IMAGE_SOURCE=https://github.com/bsherman/caddy-plus
ARG IMAGE_REVISION=unknown
ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="caddy-plus" \
      org.opencontainers.image.description="Caddy with Cloudflare and Porkbun DNS providers and Layer 4 proxy support" \
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
