#!/usr/bin/env bash
set -euo pipefail

image=${1:?usage: verify-image.sh IMAGE [ARCH]}
expected_arch=${2:-amd64}
engine=${ENGINE:-podman}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
containerfile=${script_dir}/../Containerfile

pin() {
    local name=$1
    grep -m1 "^ARG ${name}=" "${containerfile}" | cut -d= -f2
}

expected_caddy=${CADDY_VERSION:-$(pin CADDY_VERSION)}
expected_cloudflare=${CLOUDFLARE_VERSION:-$(pin CLOUDFLARE_VERSION)}
expected_porkbun=${PORKBUN_VERSION:-$(pin PORKBUN_VERSION)}

container() {
    "${engine}" run --rm --entrypoint caddy "${image}" "$@"
}

version=$(container version)
[[ ${version} == v${expected_caddy}* ]]

build_info=$(container build-info)
grep -Fq "GOARCH=${expected_arch}" <<<"${build_info}"
grep -Eq "github.com/caddy-dns/cloudflare[[:space:]]+v${expected_cloudflare}([[:space:]]|$)" <<<"${build_info}"
grep -Eq "github.com/caddy-dns/porkbun[[:space:]]+v${expected_porkbun}([[:space:]]|$)" <<<"${build_info}"

modules=$(container list-modules)
grep -Fxq dns.providers.cloudflare <<<"${modules}"
grep -Fxq dns.providers.porkbun <<<"${modules}"
if grep -Eq 'caddy-docker-proxy|caddy\.admin|caddy\.l4|caddy-ui|docker-proxy|(^|\.)layer4(\.|$)' <<<"${modules}"; then
    echo "forbidden custom module found" >&2
    exit 1
fi
if grep -Eq 'lucaslorentz/caddy-docker-proxy|mholt/caddy-l4|zackwag/caddy-ui' <<<"${build_info}"; then
    echo "forbidden build dependency found" >&2
    exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

cat >"${tmpdir}/cloudflare.Caddyfile" <<'EOF'
cloudflare.example.invalid {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    respond "ok"
}
EOF

cat >"${tmpdir}/porkbun.Caddyfile" <<'EOF'
porkbun.example.invalid {
    tls {
        dns porkbun {
            api_key {env.PORKBUN_API_KEY}
            api_secret_key {env.PORKBUN_API_SECRET_KEY}
        }
    }
    respond "ok"
}
EOF

mount_options=ro
if [[ ${engine} == *podman* ]]; then
    mount_options=ro,Z
fi

"${engine}" run --rm \
    --entrypoint caddy \
    --env CF_API_TOKEN=0000000000000000000000000000000000000000 \
    --volume "${tmpdir}/cloudflare.Caddyfile:/tmp/Caddyfile:${mount_options}" \
    "${image}" validate --config /tmp/Caddyfile --adapter caddyfile

"${engine}" run --rm \
    --entrypoint caddy \
    --env PORKBUN_API_KEY=validation-only \
    --env PORKBUN_API_SECRET_KEY=validation-only \
    --volume "${tmpdir}/porkbun.Caddyfile:/tmp/Caddyfile:${mount_options}" \
    "${image}" validate --config /tmp/Caddyfile --adapter caddyfile

user=$("${engine}" image inspect --format '{{.Config.User}}' "${image}")
[[ ${user} == 65532 ]]

cmd=$("${engine}" image inspect --format '{{json .Config.Cmd}}' "${image}")
[[ ${cmd} == '["caddy","run","--config","/etc/caddy/Caddyfile","--adapter","caddyfile"]' ]]

env_config=$("${engine}" image inspect --format '{{json .Config.Env}}' "${image}")
grep -Fq 'XDG_CONFIG_HOME=/config' <<<"${env_config}"
grep -Fq 'XDG_DATA_HOME=/data' <<<"${env_config}"
if grep -Eq 'CF_API_TOKEN|PORKBUN_API_KEY|PORKBUN_API_SECRET_KEY|validation-only' <<<"${env_config}"; then
    echo "credential variable or value embedded in image environment" >&2
    exit 1
fi

# shellcheck disable=SC2016
"${engine}" run --rm --entrypoint /bin/bash "${image}" -ceu '
    test ! -e /etc/caddy/Caddyfile
    test -d /data/caddy
    test -d /config/caddy
    test -d /etc/caddy
    test -d /srv
    for tool in go xcaddy gcc git make dnf microdnf apk apt docker podman skopeo socat; do
        ! command -v "${tool}" >/dev/null 2>&1
    done
'

echo "verified ${image} for linux/${expected_arch}"
