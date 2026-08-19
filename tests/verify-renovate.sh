#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "${script_dir}/.." && pwd)
log_file=$(mktemp)
trap 'rm -f "${log_file}"' EXIT

cd "${repo_dir}"

renovate-config-validator --strict --no-global renovate.json

LOG_FORMAT=json LOG_LEVEL=debug \
    renovate --platform=local --dry-run=full --require-config=required \
    >"${log_file}" 2>&1

if jq -e 'select(
    .msg == "Manager explicitly enabled in \"enabledManagers\" config, but found no results. Possible config error?" and
    .manager == "custom.regex"
)' "${log_file}" >/dev/null; then
    echo "Renovate custom manager found no dependencies" >&2
    exit 1
fi

extraction=$(jq -c 'select(.msg == "Dependency extraction complete") | .stats.managers.regex' "${log_file}")
if [[ ${extraction} != '{"fileCount":7,"depCount":7}' ]]; then
    echo "unexpected custom.regex extraction result: ${extraction:-missing}" >&2
    exit 1
fi

file_count=$(jq -r '
    select(.msg == "packageFiles with updates") |
    [.config.regex[].packageFile] | unique | length
' "${log_file}")
if [[ ${file_count} != 2 ]]; then
    echo "expected custom.regex dependencies in 2 files, found ${file_count:-none}" >&2
    exit 1
fi

expected_dependencies=(
    quay.io/hummingbird/xcaddy
    quay.io/hummingbird/core-runtime
    caddyserver/caddy
    github.com/caddy-dns/cloudflare
    github.com/caddy-dns/porkbun
    aquasecurity/trivy
    sigstore/cosign
)

for dependency in "${expected_dependencies[@]}"; do
    if ! jq -e --arg dependency "${dependency}" '
        select(.msg == "packageFiles with updates") |
        .. | objects | select(.depName? == $dependency)
    ' "${log_file}" >/dev/null; then
        echo "Renovate did not extract ${dependency}" >&2
        exit 1
    fi
done

if ! jq -e '
    select(.msg == "Dependency extraction complete") |
    .stats.managers["github-actions"].depCount > 0
' "${log_file}" >/dev/null; then
    echo "Renovate did not extract GitHub Actions dependencies" >&2
    exit 1
fi

echo "verified Renovate extraction for 7 custom dependencies and GitHub Actions"
