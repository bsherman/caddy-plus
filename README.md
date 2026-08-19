# caddy-plus

An OCI image for running Caddy as an unprivileged, Podman-managed reverse proxy. It adds only the Cloudflare and Porkbun DNS providers to the standard Caddy modules.

The image does not contain a Caddyfile, credentials, a management UI, container socket tooling, `caddy-docker-proxy`, or Layer 4 proxy extensions.

## Image

Published images use this name:

```text
ghcr.io/bsherman/caddy-plus
```

Revision tags use `<Caddy version>-<image revision>`, for example `2.11.4-1`, and are immutable. Every later dependency rebuild with the same Caddy version receives the next unused revision, such as `2.11.4-2`.

The workflow also updates these compatibility aliases to the newest successful revision:

| Tag | Policy |
| --- | --- |
| `2.11.4-1` | Immutable build revision |
| `2.11.4` | Moving patch alias |
| `2.11` | Moving minor alias |
| `2` | Moving major alias |

The project does not publish `latest` or date tags. Deployments requiring reproducibility must use a revision tag plus digest, or preferably the digest itself.

For reproducible deployments, use the multi-architecture index digest reported by the release workflow:

```text
ghcr.io/bsherman/caddy-plus:2.11.4-1@sha256:...
```

The supported platforms are:

- `linux/amd64`
- `linux/arm64`

## Runtime conventions

The image follows the Hummingbird Caddy image conventions where they apply to a custom binary on `core-runtime`:

| Setting | Value |
| --- | --- |
| User | UID `65532` |
| Working directory | `/srv` |
| Data directory | `/data` |
| Config state directory | `/config` |
| Caddyfile | `/etc/caddy/Caddyfile` |
| Exposed ports | `8080/tcp`, `8443/tcp`, `2019/tcp` |
| Stop signal | `SIGQUIT` |
| Default command | `caddy run --config /etc/caddy/Caddyfile --adapter caddyfile` |

Mount these paths:

- `/data`: persistent, read-write Caddy data including certificates and keys.
- `/config`: persistent, read-write Caddy autosave and configuration state.
- `/etc/caddy`: deployment-owned configuration, normally mounted read-only and containing `Caddyfile`.

The image intentionally contains no `/etc/caddy/Caddyfile`; it will not start successfully until one is mounted.

Because Caddy runs without root privileges, configure `http_port 8080` and `https_port 8443`. Map privileged host ports separately if the Podman host permits it.

## Credentials

Pass credentials at runtime. Never put them in a Caddyfile, Containerfile, image layer, or committed environment file.

### Cloudflare

Set `CF_API_TOKEN` to a scoped Cloudflare API token with:

- `Zone.Zone:Read`
- `Zone.DNS:Edit`
- Zone resources restricted to only the zones Caddy manages

### Porkbun

Set both:

- `PORKBUN_API_KEY`
- `PORKBUN_API_SECRET_KEY`

Porkbun API keys do not provide a Cloudflare-style DNS-only permission selection. Enable API access only for the required domains in Porkbun Domain Management, and apply per-key domain or source-IP restrictions when available. Do not reuse a general-purpose account API key.

## DNS-01 examples

Cloudflare:

```caddyfile
{
	http_port 8080
	https_port 8443
}

cloudflare.example.com {
	tls {
		dns cloudflare {env.CF_API_TOKEN}
	}
	reverse_proxy app:8080
}
```

Porkbun:

```caddyfile
{
	http_port 8080
	https_port 8443
}

porkbun.example.com {
	tls {
		dns porkbun {
			api_key {env.PORKBUN_API_KEY}
			api_secret_key {env.PORKBUN_API_SECRET_KEY}
		}
	}
	reverse_proxy app:8080
}
```

`caddy validate` provisions these providers but does not start Caddy or make an ACME request. CI uses syntactically valid dummy values to test both configurations without real credentials.

## Podman

Create rootless-Podman volumes and a deployment-specific Caddyfile directory outside this repository:

```bash
podman volume create caddy-data
podman volume create caddy-config
mkdir -p caddy
```

Run on unprivileged host ports:

```bash
podman run --rm --name caddy \
  --publish 8080:8080/tcp \
  --publish 8443:8443/tcp \
  --publish 8443:8443/udp \
  --env-file ./caddy.env \
  --volume caddy-data:/data \
  --volume caddy-config:/config \
  --volume ./caddy:/etc/caddy:ro,Z \
  ghcr.io/bsherman/caddy-plus:2.11.4-1@sha256:...
```

Named volumes preserve the image's UID `65532` ownership. If bind mounts are required for `/data` or `/config`, prepare them for that UID or use Podman's `:U,Z` options with care; `:U` recursively changes host ownership.

For a persistent deployment, manage the container with a Podman Quadlet or generated systemd unit. Preserve the same mounts, environment variables, ports, and immutable digest reference.

## Local build and verification

Build the native architecture with Podman:

```bash
podman build \
  --build-arg IMAGE_REVISION="$(git rev-parse HEAD)" \
  --build-arg IMAGE_VERSION=dev \
  --tag localhost/caddy-plus:dev \
  --file Containerfile .
```

Run all native verification checks:

```bash
ENGINE=podman tests/verify-image.sh localhost/caddy-plus:dev amd64
```

Use the matching architecture argument (`amd64` or `arm64`) on a native host. CI uses native `ubuntu-24.04` and `ubuntu-24.04-arm` runners. Buildx can optionally reproduce the other architecture locally when binfmt/QEMU is installed:

```bash
docker buildx build --platform linux/amd64 --load --tag caddy-plus:test-amd64 .
ENGINE=docker tests/verify-image.sh caddy-plus:test-amd64 amd64

docker buildx build --platform linux/arm64 --load --tag caddy-plus:test-arm64 .
ENGINE=docker tests/verify-image.sh caddy-plus:test-arm64 arm64
```

The verification script checks:

- Caddy and plugin versions from the compiled binary
- Binary target architecture
- Both required DNS module names
- Absence of prohibited custom modules
- Offline Cloudflare and Porkbun configuration validation
- Non-root runtime metadata and Hummingbird-compatible command
- Absence of embedded credentials, a Caddyfile, and build tools

## Supply-chain artifacts

Each published multi-architecture image has:

- OCI source, revision, version, title, and Apache-2.0 license labels
- A manifest-list digest and per-architecture child digests
- BuildKit `mode=max` provenance
- Per-platform SBOM attestations
- Per-platform Trivy vulnerability and secret reports
- Per-platform vulnerability attestations
- A keyless Cosign signature on the index digest

Verify a signature using the digest printed by the release workflow:

```bash
cosign verify \
  --certificate-identity 'https://github.com/bsherman/caddy-plus/.github/workflows/build.yml@refs/heads/main' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/bsherman/caddy-plus@sha256:...
```

Inspect attached SBOM and provenance attestations with `docker buildx imagetools inspect` or an OCI referrer-aware tool. Download the human-readable Trivy JSON/SARIF reports from the release workflow run; the digest-bound vulnerability attestations remain attached to each architecture image.

## Updates and releases

Renovate tracks Caddy, Cloudflare, Porkbun, the Hummingbird XCaddy and core-runtime tag/digest pairs, Trivy, Cosign, and GitHub Action commit pins. Automerge is disabled.

The official hosted Renovate GitHub app must have access to this repository. The release workflow intentionally authorizes automatic publication only for merged pull requests whose author is exactly `renovate[bot]`; other dependency-bot or self-hosted Renovate identities require a manual release.

Image builds run only in these cases:

- A Renovate pull request changes component pins in `Containerfile`.
- A maintainer starts the workflow manually.

There are no scheduled, push, ordinary pull-request, or Git-tag builds. Renovate opens component pull requests without automerge. Those pull requests build and test both architectures but do not publish.

When a Renovate component pull request is reviewed and merged into `main`, the closed pull request triggers a native build of both architectures. After verification succeeds, the workflow automatically selects the next unused immutable revision, publishes it, updates the patch/minor/major aliases, scans it, and signs its index digest.

To release a Renovate update:

1. Review and merge the relevant Renovate component update.
2. Confirm the automatic release workflow succeeds.
3. Confirm the immutable revision, moving aliases, child digests, index digest, security reports, SBOM/provenance, vulnerability attestations, and keyless signature.
4. Record the index digest in deployment configuration.

For an initial release or an explicitly requested rebuild, run **Build and publish image** manually from `main` and enable **Publish after successful verification**. Manual publication follows the same automatic revision and alias policy.

## Scope

Read-only UI work is intentionally out of scope. The stock `zackwag/caddy-ui` application can write and reload Caddyfiles, edit routes and log settings, and delete certificates, so it is not an inspection-only interface and is not included.

The previous image's `caddy-docker-proxy`, Layer 4 module, socket integration, `latest` tag, and `docker-proxy` default command have been removed intentionally.
