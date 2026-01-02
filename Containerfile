ARG caddyversion=2
FROM docker.io/caddy:${caddyversion}-builder AS builder

RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/caddy-dns/porkbun \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2 \
    --with github.com/mholt/caddy-l4
    #--with github.com/caddyserver/cache-handler \

FROM docker.io/caddy:${caddyversion}-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
#??RUN apk add -U --no-cache ca-certificates curl

CMD ["caddy", "docker-proxy"]
