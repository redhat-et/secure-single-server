# OpenShell Three-Harness Demonstrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add standalone OpenShell sandboxing demos (OpenCode, OpenClaw, Codex) and an integrated `openshell-praxis` scenario to `secure-single-server`, with pinned Red Hat quay images, four policy profiles per harness, and a no-secrets validation workflow.

**Architecture:** A self-contained `openshell/` tree runs an OpenShell gateway as a rootless Podman quadlet from digest-pinned odh quay images (`quay.io/opendatahub/odh-openshell-{gateway,supervisor,cli}`). Each harness runs in a sandbox created `--from` a digest-pinned Red Hat AI "aipcc" agentic workload image (`quay.io/aipcc/base-images/agentic/{opencode,openclaw,codex}`) in which the harness CLI is already pre-installed; OpenShell injects the odh supervisor runtime as a companion container and enforces one of four capability-graded OpenShell `policy.yaml` files applied at create time. (Ground truth: the `odh-openshell-sandbox` image is the injected runtime, not an agent base; the aipcc agentic images — labeled `io.openshell.harness.version` — are the workload bases and are the Red Hat equivalent of NVIDIA's community `sandboxes/base`.) A separate `openshell-praxis` scenario plugs into the PR #2 installer framework and locks sandbox model egress to the Praxis all-in-one loopback gateway. CI boots the pinned images and proves policy enforcement without provider credentials.

**Tech Stack:** RHEL 9, rootless Podman + quadlet (systemd user units), OpenShell (odh quay images), Bash, YAML policies, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-24-openshell-harness-demos-design.md`

## Global Constraints

- Base branch: `feat/gateway-scenarios` (PR #2). Branch: `openshell-harness-demos`.
- All images pinned by `@sha256:` digest, declared once in `openshell/configs/images.env`. Rendered templates use `Pull=never`.
- No provider credentials in the repo or in CI. Provider keys come from environment/OS keyring only.
- OpenShell control plane is consumed only via odh quay images (`quay.io/opendatahub/odh-openshell-{supervisor,gateway,cli,sandbox}`); no host RPM install. Harness workload images are the public Red Hat `quay.io/aipcc/base-images/agentic/*` images (pinned by digest); no custom image builds.
- Harnesses are OpenCode, OpenClaw, Codex — each pre-installed in its aipcc workload image. Claude Code is out of scope (no public aipcc image; `agentic/claude-code` is private → unusable in no-secrets CI).
- OpenClaw means the standalone `openclaw` npm package (`github.com/openclaw/openclaw`, verified `name: openclaw` in the aipcc image). NemoClaw is NOT used.
- Sandboxes are created `--from <aipcc image@sha256> --policy <host-path profile.yaml>` (harness pre-installed; NO create-time npm install, NO `--no-auto-providers`). Connect via `ssh -o ProxyCommand="openshell ssh-proxy --gateway-name local --name <n>" sandbox@<n>`.
- Reuse `scripts/common/lib.sh` helpers (`die`, `note`, `require_command`, `oci_architecture`) rather than reimplementing them.
- OpenShell sandbox policies live at `profiles/<profile>/policy.yaml`, never named bare `policy.yaml` at a scenario root (that name is a Praxis JWT plugin policy).
- Gateway binds loopback only: gRPC/control `127.0.0.1:8080`, health `127.0.0.1:8081`.
- Every shell script passes `shellcheck`; every policy YAML validates against the schema check in Task 2.
- Do not modify existing Praxis configs, quadlets, scripts, or `.github/workflows/validate.yml`.

---

## File Structure

- `openshell/configs/images.env.in` + `images.env` — the odh control-plane digests + the three aipcc harness workload digests (single source of truth).
- `openshell/configs/quadlet/openshell.network`, `openshell-gateway.container.in` — gateway quadlet.
- `openshell/configs/gateway/gateway.toml` — podman driver, deny-by-default, pinned sandbox/supervisor images.
- `openshell/scripts/lib.sh` — OpenShell-specific helpers + `openshell` CLI wrapper (sources `scripts/common/lib.sh`).
- `openshell/scripts/install.sh`, `uninstall.sh` — render + start/stop the gateway quadlet.
- `openshell/scripts/harness-lib.sh` — shared single-phase create (`--from`+`--policy`)/ssh/connect/destroy used by all harness scripts (harness pre-installed in the workload image).
- `openshell/harnesses/<h>/create.sh`, `connect.sh`, `README.md`, `profiles/<p>/policy.yaml` — per harness.
- `openshell/docs/*` — quickstarts, teaching walkthrough, threat model.
- `openshell/tests/openshell-static.sh`, `openshell-image.sh`, `openshell-policy.sh` — standalone tests.
- `configs/openshell-praxis/*`, `scripts/openshell-praxis/install`, `docs/quickstarts/openshell-praxis/*`, `tests/openshell-praxis/*` — integrated scenario.
- `.github/workflows/openshell-validate.yml` — CI.
- Top-level `README.md` — add scenario rows.

Each task ends with an independently testable deliverable and a commit.

---

### Task 1: Scaffolding, pinned digests, and static test harness

**Files:**
- Create: `openshell/configs/images.env.in`
- Create: `openshell/configs/images.env`
- Create: `openshell/scripts/lib.sh`
- Create: `openshell/tests/openshell-static.sh`

**Interfaces:**
- Produces: `openshell/scripts/lib.sh` exporting `OPENSHELL_DIR`, `render_template <in> <out>`, `openshell_cli <args...>`, and sourcing `scripts/common/lib.sh` for `die`/`note`/`require_command`/`oci_architecture`.
- Produces: `openshell/configs/images.env` defining the four odh control-plane images `ODH_GATEWAY_IMAGE`, `ODH_SUPERVISOR_IMAGE`, `ODH_SANDBOX_IMAGE`, `ODH_CLI_IMAGE` (all `quay.io/opendatahub/odh-openshell-*@sha256:...`) plus the three public aipcc harness workload images `ODH_OPENCODE_IMAGE`, `ODH_OPENCLAW_IMAGE`, `ODH_CODEX_IMAGE` (all `quay.io/aipcc/base-images/agentic/*@sha256:...`).

- [ ] **Step 1: Write the failing static test**

Create `openshell/tests/openshell-static.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1a. images.env must define four @sha256-pinned odh control-plane images.
# shellcheck source=/dev/null
source "${OS_DIR}/configs/images.env"
for var in ODH_GATEWAY_IMAGE ODH_SUPERVISOR_IMAGE ODH_SANDBOX_IMAGE ODH_CLI_IMAGE; do
  val="${!var:-}"
  [[ -n "${val}" ]] || fail "${var} unset"
  [[ "${val}" == quay.io/opendatahub/odh-openshell-*@sha256:* ]] \
    || fail "${var} not a digest-pinned odh image: ${val}"
done

# 1b. images.env must define three @sha256-pinned public aipcc harness images.
for var in ODH_OPENCODE_IMAGE ODH_OPENCLAW_IMAGE ODH_CODEX_IMAGE; do
  val="${!var:-}"
  [[ -n "${val}" ]] || fail "${var} unset"
  [[ "${val}" == quay.io/aipcc/base-images/agentic/*@sha256:* ]] \
    || fail "${var} not a digest-pinned aipcc image: ${val}"
done

# 2. All shell scripts under openshell/ pass shellcheck.
if command -v shellcheck >/dev/null 2>&1; then
  mapfile -t scripts < <(find "${OS_DIR}" -name '*.sh' -type f)
  shellcheck -S style "${scripts[@]}" || fail "shellcheck failed"
fi
printf 'openshell-static: OK\n'
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash openshell/tests/openshell-static.sh`
Expected: FAIL — `configs/images.env` does not exist yet.

- [ ] **Step 3: Resolve all seven digests and write `images.env`**

Resolve each digest against quay (requires network; do NOT invent a digest). Prefer `skopeo`; fall back to `podman`:

```bash
for c in gateway supervisor sandbox cli; do
  d=$(skopeo inspect --format '{{.Digest}}' \
        docker://quay.io/opendatahub/odh-openshell-${c}:latest)
  printf 'odh %s -> %s\n' "$c" "$d"
done
for h in opencode openclaw codex; do
  d=$(skopeo inspect --format '{{.Digest}}' \
        docker://quay.io/aipcc/base-images/agentic/${h}:latest)
  printf 'aipcc %s -> %s\n' "$h" "$d"
done
```

Write `openshell/configs/images.env` with the resolved digests. The values below were resolved on 2026-09-24 and validated end-to-end on the host — use them verbatim unless a refresh is explicitly requested:

```bash
# Pinned odh OpenShell control-plane images. Refresh with openshell/tests/refresh-digests.sh.
ODH_GATEWAY_IMAGE="quay.io/opendatahub/odh-openshell-gateway@sha256:d75a99a58d80214c9f01f9daa1e4bd50c7991fd8d33e1c4274116b8aacb1434b"
ODH_SUPERVISOR_IMAGE="quay.io/opendatahub/odh-openshell-supervisor@sha256:33263cd17b697e7a09d53fe2d3ab0e630175f469b9bfc749f08e1a20057bf371"
ODH_SANDBOX_IMAGE="quay.io/opendatahub/odh-openshell-sandbox@sha256:2aec9ff5af204028a4310f083cbb76f20e64fab893a21666a5696e9e93906974"
ODH_CLI_IMAGE="quay.io/opendatahub/odh-openshell-cli@sha256:114e6e5fa6609a2b4577aea12ca49af7239f2937c55d687c7f2b4737fd0f1f0e"
# Public aipcc agentic harness workload images (harness CLI pre-installed).
ODH_OPENCODE_IMAGE="quay.io/aipcc/base-images/agentic/opencode@sha256:5743452ce2dde8d91d3d8998d8667efa45da27e53c170dbd614516603a44d7d3"
ODH_OPENCLAW_IMAGE="quay.io/aipcc/base-images/agentic/openclaw@sha256:de12000bc8c251e868519bb86ed975458bf3f2ff63c6ebc2eece4bc769f14b69"
ODH_CODEX_IMAGE="quay.io/aipcc/base-images/agentic/codex@sha256:f62cb7aa71cb145daf843b5e11c5efc255e19bb44d41c4eab5b1dba912b2342e"
```

Create `openshell/configs/images.env.in` identical but with `@@ODH_*@@` / `@@ODH_OPENCODE_IMAGE@@` etc. placeholders, documenting that `images.env` is the rendered, digest-pinned copy committed to the repo.

- [ ] **Step 4: Write `openshell/scripts/lib.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
OPENSHELL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd -- "${OPENSHELL_DIR}/.." && pwd)"
# shellcheck source=../../scripts/common/lib.sh
source "${REPO_ROOT}/scripts/common/lib.sh"
# shellcheck source=../configs/images.env
source "${OPENSHELL_DIR}/configs/images.env"

CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

render_template() {  # <template.in> <output>
  local in="$1" out="$2"
  sed \
    -e "s#@@ODH_GATEWAY_IMAGE@@#${ODH_GATEWAY_IMAGE}#g" \
    -e "s#@@ODH_SUPERVISOR_IMAGE@@#${ODH_SUPERVISOR_IMAGE}#g" \
    -e "s#@@ODH_SANDBOX_IMAGE@@#${ODH_SANDBOX_IMAGE}#g" \
    -e "s#@@ODH_CLI_IMAGE@@#${ODH_CLI_IMAGE}#g" \
    -e "s#@@ODH_OPENCODE_IMAGE@@#${ODH_OPENCODE_IMAGE}#g" \
    -e "s#@@ODH_OPENCLAW_IMAGE@@#${ODH_OPENCLAW_IMAGE}#g" \
    -e "s#@@ODH_CODEX_IMAGE@@#${ODH_CODEX_IMAGE}#g" \
    "${in}" > "${out}"
}

# Run the openshell CLI from the pinned odh CLI image against the local gateway.
openshell_cli() {
  "${CONTAINER_ENGINE}" run --rm --network host \
    -v "${HOME}/.config/openshell:/home/openshell/.config/openshell:z" \
    "${ODH_CLI_IMAGE}" "$@"
}
```

- [ ] **Step 5: Run the static test to verify it passes**

Run: `bash openshell/tests/openshell-static.sh`
Expected: PASS — `openshell-static: OK`.

- [ ] **Step 6: Commit**

```bash
git add openshell/configs/images.env openshell/configs/images.env.in \
        openshell/scripts/lib.sh openshell/tests/openshell-static.sh
git commit -m "feat(openshell): scaffold pinned images, lib, and static test"
```

---

### Task 2: Gateway quadlet, gateway.toml, and policy-schema check

**Files:**
- Create: `openshell/configs/quadlet/openshell-gateway.container.in`
- Create: `openshell/configs/gateway/gateway.toml.in`
- Modify: `openshell/tests/openshell-static.sh` (add template-render + toml checks)

(Note: with `Network=host` no `openshell.network` file is needed.)

**Interfaces:**
- Produces: a rendered `openshell-gateway.container` quadlet unit named container `openshell-gateway`, using host networking and mounting the rootless Podman socket; the gateway binds `127.0.0.1:8080` (grpc) and `127.0.0.1:8081` (health) inside the shared host netns.
- Produces: `gateway.toml.in` (v2 schema) with `compute_driver = "podman"`, JWT auth blocks, `socket_path`, `default_image = @@ODH_OPENCODE_IMAGE@@` (a real node-bearing aipcc workload so a bare `sandbox create` succeeds; per-harness `create.sh` overrides via `--from`), and `supervisor_image = @@ODH_SUPERVISOR_IMAGE@@` (the odh runtime injected as a companion container).

- [ ] **Step 1: Add failing render/toml assertions to the static test**

Append to `openshell/tests/openshell-static.sh` before the final `printf`:

```bash
# 3. Gateway quadlet template renders with no leftover placeholders.
tmp="$(mktemp)"
# shellcheck source=../scripts/lib.sh
source "${OS_DIR}/scripts/lib.sh"
render_template "${OS_DIR}/configs/quadlet/openshell-gateway.container.in" "${tmp}"
grep -q '@@' "${tmp}" && fail "unrendered placeholder in gateway quadlet"
grep -q "Image=${ODH_GATEWAY_IMAGE}" "${tmp}" || fail "gateway image not pinned in unit"
grep -q 'Pull=never' "${tmp}" || fail "gateway unit must set Pull=never"
rm -f "${tmp}"

# 4. gateway.toml.in uses the podman driver, JWT auth, and pins workload/supervisor images.
gt="${OS_DIR}/configs/gateway/gateway.toml.in"
grep -q 'compute_driver *= *"podman"' "${gt}" || fail "gateway.toml not podman driver"
grep -q '\[openshell.gateway.gateway_jwt\]' "${gt}" || fail "gateway.toml missing JWT auth block"
grep -q 'supervisor_image *= *"@@ODH_SUPERVISOR_IMAGE@@"' "${gt}" || fail "supervisor image placeholder missing"
grep -q 'default_image *= *"@@ODH_OPENCODE_IMAGE@@"' "${gt}" || fail "default_image must be an aipcc workload image (@@ODH_OPENCODE_IMAGE@@)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash openshell/tests/openshell-static.sh`
Expected: FAIL — quadlet/toml files do not exist.

- [ ] **Step 3: (no network file)** — with `Network=host` there is no `openshell.network` to write; proceed to the quadlet.

- [ ] **Step 4: Write `openshell-gateway.container.in`**

Host networking is REQUIRED: with bridge networking the gateway's in-container loopback is isolated from the host loopback, so `127.0.0.1:8081/healthz` is unreachable from the host (validated in earlier rounds — bridge + `PublishPort` gave "Connection reset by peer"). `Network=host` makes the container's `127.0.0.1` equal the host's, preserving loopback-only exposure. The gateway also needs the rootless Podman socket to spawn sibling sandbox/supervisor containers.

```ini
[Unit]
Description=OpenShell sandbox gateway (odh, pinned)
After=network-online.target
Wants=network-online.target

# The gateway needs the rootless Podman socket to spawn sibling sandbox containers.
# install.sh (Task 3) enables podman.socket for the user.
# /var/lib/openshell is bind-mounted at the same absolute path inside and out
# so sandbox bind-mount sources resolve on the host.
[Container]
Image=@@ODH_GATEWAY_IMAGE@@
ContainerName=openshell-gateway
Pull=never
Network=host
Volume=%h/.config/openshell/gateway.toml:/etc/openshell/gateway.toml:ro
Volume=/var/lib/openshell:/var/lib/openshell
Volume=%t/podman/podman.sock:/run/podman/podman.sock
SecurityLabelDisable=true
PodmanArgs=--userns=keep-id
Environment=OPENSHELL_GATEWAY_CONFIG=/etc/openshell/gateway.toml
Environment=OPENSHELL_DB_URL=sqlite:/var/lib/openshell/gateway.db?mode=rwc
Environment=XDG_DATA_HOME=/var/lib/openshell
Environment=HOME=/var/lib/openshell
Exec=

[Service]
Restart=on-failure
RestartSec=5s
TimeoutStartSec=900
TimeoutStopSec=30

[Install]
WantedBy=default.target
```

- [ ] **Step 5: Write `gateway.toml.in`** (odh v2 schema; rendered to `gateway.toml` by `install.sh` at install time)

```toml
[openshell]
version = 2

[openshell.gateway]
bind_address        = "127.0.0.1:8080"
health_bind_address = "127.0.0.1:8081"
log_level           = "info"
compute_driver      = "podman"
disable_tls         = true

[openshell.gateway.auth]
allow_unauthenticated_users = true

[openshell.gateway.gateway_jwt]
signing_key_path = "/var/lib/openshell/tls/jwt/signing.pem"
public_key_path  = "/var/lib/openshell/tls/jwt/public.pem"
kid_path         = "/var/lib/openshell/tls/jwt/kid"
gateway_id       = "openshell"
ttl_secs         = 3600

[openshell.drivers.podman]
socket_path       = "/run/podman/podman.sock"
default_image     = "@@ODH_OPENCODE_IMAGE@@"
supervisor_image  = "@@ODH_SUPERVISOR_IMAGE@@"
image_pull_policy = "if_not_present"
grpc_endpoint     = "http://127.0.0.1:8080"
enable_bind_mounts = true
```

Notes:
- `version = 2`, singular `compute_driver`, and `socket_path`/`image_pull_policy = "if_not_present"` are the validated odh schema — do NOT revert to the v1 spellings.
- The JWT signing keys are generated by `install.sh` (Task 3) via `generate-certs` into `/var/lib/openshell/tls`; the gateway will not start without them.
- `default_image` is `@@ODH_OPENCODE_IMAGE@@` (a real node-bearing aipcc workload) so a bare `sandbox create` with no `--from` still yields a usable sandbox. Per-harness `create.sh` always passes `--from`, so this default is only a fallback. `supervisor_image` stays the odh supervisor — that is the runtime injected as a companion container, NOT the workload.
- `grpc_endpoint` is `127.0.0.1:8080`: with host networking the container loopback equals the host loopback, so this reaches the gateway.

Commit `gateway.toml.in` with placeholders; `install.sh` renders `gateway.toml` at `%h/.config/openshell/gateway.toml`. The static test (Step 1) reads the `.in` template directly, so no committed rendered copy is required.

- [ ] **Step 6: Run the static test to verify it passes**

Run: `bash openshell/tests/openshell-static.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add openshell/configs/quadlet openshell/configs/gateway openshell/tests/openshell-static.sh
git commit -m "feat(openshell): add gateway quadlet and gateway.toml"
```

---

### Task 3: install/uninstall scripts and image-boot test

**Files:**
- Create: `openshell/scripts/install.sh`
- Create: `openshell/scripts/uninstall.sh`
- Create: `openshell/tests/openshell-image.sh`

**Interfaces:**
- Consumes: `render_template`, `openshell_cli`, `images.env` from Task 1; quadlet/toml from Task 2.
- Produces: a running gateway reachable at `http://127.0.0.1:8081/healthz`; a registered CLI gateway named `local`.

- [ ] **Step 1: Write the failing image test**

Create `openshell/tests/openshell-image.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
CE="${CONTAINER_ENGINE:-podman}"
# shellcheck source=../scripts/lib.sh
source "${OS_DIR}/scripts/lib.sh"
NAME=openshell-gateway-citest
cleanup() { "${CE}" rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

td="$(mktemp -d)"
render_template "${OS_DIR}/configs/gateway/gateway.toml.in" "${td}/gateway.toml"
"${CE}" run -d --name "${NAME}" --network host \
  -v "${td}/gateway.toml:/etc/openshell/gateway.toml:ro,z" \
  -v /var/lib/openshell:/var/lib/openshell:z \
  -e OPENSHELL_GATEWAY_CONFIG=/etc/openshell/gateway.toml \
  -e OPENSHELL_DB_URL="sqlite:/var/lib/openshell/gateway.db?mode=rwc" \
  -e XDG_DATA_HOME=/var/lib/openshell -e HOME=/var/lib/openshell \
  "${ODH_GATEWAY_IMAGE}"

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8081/healthz >/dev/null 2>&1; then
    printf 'openshell-image: healthz OK\n'; exit 0
  fi
  sleep 2
done
printf 'FAIL: gateway never became healthy\n' >&2; exit 1
```

- [ ] **Step 2: Run it to verify it fails**

Run: `sudo install -d -o "$(id -u)" /var/lib/openshell && bash openshell/tests/openshell-image.sh`
Expected: FAIL — `gateway.toml.in` render path / gateway not yet wired (or image not pulled).

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/lib.sh"
require_command podman

note "Enabling rootless podman socket for the gateway"
systemctl --user enable --now podman.socket

note "Configuring cgroup delegation for nested containers"
if [[ ! -f /etc/systemd/system/user@.service.d/delegate.conf ]]; then
  sudo mkdir -p /etc/systemd/system/user@.service.d
  sudo tee /etc/systemd/system/user@.service.d/delegate.conf > /dev/null << 'DELEGATE_EOF'
[Service]
Delegate=cpu cpuset io memory pids
DELEGATE_EOF
  sudo systemctl daemon-reload
  note "Cgroup delegation configured; restarting user session"
  sudo systemctl restart "user@$(id -u).service"
  sleep 2
else
  note "Cgroup delegation already configured"
fi

note "Preparing /var/lib/openshell (source==target bind path)"
sudo install -d -o "$(id -u)" -g "$(id -g)" /var/lib/openshell

note "Generating JWT signing keys for sandbox auth"
if [[ ! -f /var/lib/openshell/tls/jwt/signing.pem ]]; then
  podman run --rm --userns=keep-id \
    -e HOME=/var/lib/openshell -e XDG_DATA_HOME=/var/lib/openshell \
    -v /var/lib/openshell:/var/lib/openshell:z \
    "${ODH_GATEWAY_IMAGE}" generate-certs \
      --output-dir /var/lib/openshell/tls \
      --server-san 127.0.0.1 --server-san localhost --server-san host.openshell.internal
else
  note "JWT keys already exist, skipping generation"
fi

note "Rendering gateway config and quadlet"
install -d "${HOME}/.config/openshell" "${HOME}/.config/containers/systemd"
render_template "${OS_DIR}/configs/gateway/gateway.toml.in" "${HOME}/.config/openshell/gateway.toml"
render_template "${OS_DIR}/configs/quadlet/openshell-gateway.container.in" \
  "${HOME}/.config/containers/systemd/openshell-gateway.container"
# No openshell.network file: the gateway quadlet uses Network=host.

note "Pulling pinned images (odh control plane + aipcc harness workloads)"
for img in "${ODH_GATEWAY_IMAGE}" "${ODH_SUPERVISOR_IMAGE}" "${ODH_SANDBOX_IMAGE}" "${ODH_CLI_IMAGE}" \
           "${ODH_OPENCODE_IMAGE}" "${ODH_OPENCLAW_IMAGE}" "${ODH_CODEX_IMAGE}"; do
  podman pull "${img}"
done

note "Installing openshell CLI binary for SSH proxy"
if [[ ! -f /usr/local/bin/openshell ]]; then
  _cli_cid="$(podman create "${ODH_CLI_IMAGE}")"
  podman cp "${_cli_cid}:/usr/local/bin/openshell" /tmp/openshell
  podman rm "${_cli_cid}"
  sudo install -m 755 /tmp/openshell /usr/local/bin/openshell
  rm /tmp/openshell
else
  note "openshell CLI binary already installed"
fi

note "Starting gateway"
systemctl --user daemon-reload
systemctl --user start openshell-gateway.service

note "Waiting for gateway health"
sleep 2

note "Registering CLI gateway 'local'"
openshell_cli gateway add http://127.0.0.1:8080 --name local
openshell_cli gateway select local
note "OpenShell gateway installed. Health: http://127.0.0.1:8081/healthz"
```

Notes:
- JWT keys MUST be generated before the gateway starts (the v2 `gateway.toml` references them; the gateway will not start otherwise). Idempotent: skips if `signing.pem` exists.
- Cgroup delegation lets the rootless gateway spawn sibling sandbox + supervisor containers.
- The native `openshell` CLI binary is extracted to `/usr/local/bin/openshell` for the SSH `ProxyCommand` used by the harness library (Task 4). Idempotent.
- All seven pinned images are pre-pulled (`if_not_present` in the toml means create-time won't re-pull), so `sandbox create --from <aipcc image>` has the workload locally.
- No `|| true` on `gateway add`/`gateway select`: install must abort if CLI registration fails (do not mask errors).

- [ ] **Step 4: Write `uninstall.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib.sh
source "${OS_DIR}/scripts/lib.sh"
systemctl --user stop openshell-gateway.service 2>/dev/null || true
rm -f "${HOME}/.config/containers/systemd/openshell-gateway.container" \
      "${HOME}/.config/containers/systemd/openshell.network"
systemctl --user daemon-reload
note "OpenShell gateway removed. /var/lib/openshell left intact (contains caches)."
```

- [ ] **Step 5: Run the image test to verify it passes**

Run: `bash openshell/tests/openshell-image.sh`
Expected: PASS — `openshell-image: healthz OK`.

- [ ] **Step 6: Commit**

```bash
git add openshell/scripts/install.sh openshell/scripts/uninstall.sh openshell/tests/openshell-image.sh
git commit -m "feat(openshell): add install/uninstall and gateway boot test"
```

---

### Task 4: Shared harness library (single-phase create from pre-built image)

**Design note (validated on host 2026-09-24):** The harness CLI is already pre-installed in the aipcc workload image, so there is NO create-time install and NO temporary npm-egress window. `harness_create` simply creates the sandbox `--from` the pinned image with the profile policy applied at birth, then waits for phase `Ready`. Connect uses the native `openshell ssh-proxy` binary (installed by `install.sh` at `/usr/local/bin/openshell`) as an SSH `ProxyCommand`. All policy paths passed to the native CLI are HOST filesystem paths.

**Files:**
- Create: `openshell/scripts/harness-lib.sh`

**Interfaces:**
- Consumes: `note`, `die`, `require_command` from Task 1's `lib.sh`; `OPENSHELL_BIN` (defaults to `/usr/local/bin/openshell`) and `OPENSHELL_GATEWAY_NAME` (defaults to `local`).
- Produces: functions used by every harness `create.sh`/`connect.sh`:
  - `harness_create <sandbox_name> <image_ref> <policy_file>` — creates a sandbox from `<image_ref>` with `<policy_file>` (host path) and waits for phase `Ready`.
  - `harness_ssh <sandbox_name> <cmd...>` — non-interactive exec via ssh-proxy ProxyCommand.
  - `harness_connect_tty <sandbox_name> [cmd...]` — interactive attach (allocates a TTY).
  - `harness_forward <sandbox_name> <port>` — local port-forward (OpenClaw web UI).
  - `harness_destroy <sandbox_name>`.

- [ ] **Step 1: Write the failing unit test**

Create a temporary test `openshell/tests/harness-lib-unit.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/harness-lib.sh
source "${OS_DIR}/scripts/harness-lib.sh"
for fn in harness_create harness_ssh harness_connect_tty harness_forward harness_destroy; do
  declare -F "${fn}" >/dev/null || { echo "FAIL: ${fn} missing"; exit 1; }
done
echo "harness-lib-unit: OK"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash openshell/tests/harness-lib-unit.sh`
Expected: FAIL — `harness-lib.sh` not found.

- [ ] **Step 3: Write `harness-lib.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
_HL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${_HL_DIR}/lib.sh"

: "${OPENSHELL_BIN:=/usr/local/bin/openshell}"
: "${OPENSHELL_GATEWAY_NAME:=local}"
: "${OPENSHELL_SANDBOX_USER:=sandbox}"

_os() { "${OPENSHELL_BIN}" "$@"; }

# Build the ssh ProxyCommand for a sandbox (native ssh-proxy, name mode).
_proxy_cmd() {  # <sandbox>
  printf '%s ssh-proxy --gateway-name %s --name %s' \
    "${OPENSHELL_BIN}" "${OPENSHELL_GATEWAY_NAME}" "$1"
}

harness_ssh() {  # <sandbox> <cmd...>
  local name="$1"; shift
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o "ProxyCommand=$(_proxy_cmd "${name}")" \
    "${OPENSHELL_SANDBOX_USER}@${name}" "$@"
}

harness_connect_tty() {  # <sandbox> [cmd...]
  local name="$1"; shift || true
  ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o "ProxyCommand=$(_proxy_cmd "${name}")" \
    "${OPENSHELL_SANDBOX_USER}@${name}" "$@"
}

harness_forward() {  # <sandbox> <port>
  local name="$1" port="$2"
  note "Forwarding 127.0.0.1:${port} -> sandbox ${name}:${port} (Ctrl-C to stop)"
  ssh -N -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o "ProxyCommand=$(_proxy_cmd "${name}")" \
    -L "127.0.0.1:${port}:127.0.0.1:${port}" \
    "${OPENSHELL_SANDBOX_USER}@${name}"
}

harness_destroy() { _os sandbox delete "$1" >/dev/null 2>&1 || true; }

# Wait until the sandbox reports phase Ready (or fail on Error/timeout).
_wait_ready() {  # <sandbox>
  local name="$1" i ph
  for i in $(seq 1 40); do
    ph="$(_os sandbox list 2>/dev/null | awk -v n="${name}" '$1==n{print $NF}')"
    case "${ph}" in
      Ready) return 0;;
      Error) die "sandbox ${name} entered Error phase";;
    esac
    sleep 15
  done
  die "sandbox ${name} did not reach Ready in time"
}

# Single-phase create: harness is pre-installed in <image_ref>.
harness_create() {  # <name> <image_ref> <policy_file>
  local name="$1" image="$2" policy="$3"
  require_command ssh
  [[ -f "${policy}" ]] || die "policy file not found: ${policy}"
  note "Creating sandbox ${name} from ${image##*/}"
  _os sandbox create --name "${name}" --from "${image}" --policy "${policy}"
  _wait_ready "${name}"
  note "Sandbox ${name} ready"
}
```

- [ ] **Step 4: Run the unit test to verify it passes**

Run: `bash openshell/tests/harness-lib-unit.sh`
Expected: PASS. Then delete the temp test: `rm openshell/tests/harness-lib-unit.sh` (its assertions are structural; the behavior is exercised by Task 8).

- [ ] **Step 5: Commit**

```bash
git add openshell/scripts/harness-lib.sh
git commit -m "feat(openshell): add shared single-phase harness library"
```

---

### Task 5: OpenCode harness (scripts + four profiles) — canonical harness task

**Design note:** The harness is pre-installed in the aipcc image (`ODH_OPENCODE_IMAGE`). No bootstrap policy, no create-time install. Verified binary paths inside the aipcc images: `node`/`npm`/`git` at `/usr/sbin/`, the harness CLI at `/usr/local/sbin/<harness>`. `curl` and `python3` are NOT present — do not reference them in policies. Do NOT include a `process:` block (sandbox uid varies 1000/1001). This task is the canonical shape; Tasks 6 (OpenClaw) and 7 (Codex) repeat it with the per-harness deltas called out there.

**Files:**
- Create: `openshell/harnesses/opencode/create.sh`, `connect.sh`, `README.md`
- Create: `openshell/harnesses/opencode/profiles/{review,dev,automation,interactive}/policy.yaml`

**Interfaces:**
- Consumes: `harness_create`, `harness_connect_tty` from Task 4; `ODH_OPENCODE_IMAGE` from `images.env`.
- Produces: `create.sh --profile <p> [--name N]` and `connect.sh [--name N]` for OpenCode.

- [ ] **Step 1: Write `profiles/review/policy.yaml`** (workspace read-only, model API only)

```yaml
version: 1
filesystem_policy:
  include_workdir: false
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /opt, /sandbox]
  read_write: [/tmp, /dev/null, /home]
landlock: {compatibility: best_effort}
network_policies:
  model_api:
    name: model-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/opencode}]
```

- [ ] **Step 2: Write `profiles/dev/policy.yaml`** (read-write, model + GitHub + npm)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /opt]
  read_write: [/sandbox, /home, /tmp, /dev/null]
landlock: {compatibility: best_effort}
network_policies:
  model_api:
    name: model-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/opencode}]
  opencode_registry:
    name: opencode-registry
    endpoints: [{host: opencode.ai, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/opencode}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/sbin/git}]
  github_git:
    name: github-git
    endpoints: [{host: github.com, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/git}]
  npm_registry:
    name: npm-registry
    endpoints: [{host: registry.npmjs.org, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/sbin/npm}]
```

- [ ] **Step 3: Write `profiles/automation/policy.yaml`** (headless — dev minus interactive git push; model + read-only GitHub + npm)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /opt]
  read_write: [/sandbox, /home, /tmp, /dev/null]
landlock: {compatibility: best_effort}
network_policies:
  model_api:
    name: model-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/opencode}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/sbin/git}]
  npm_registry:
    name: npm-registry
    endpoints: [{host: registry.npmjs.org, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/sbin/npm}]
```

- [ ] **Step 4: Write `profiles/interactive/policy.yaml`** (dev + persistent workspace + docs sites)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /opt]
  read_write: [/sandbox, /sandbox/persist, /home, /tmp, /dev/null]
landlock: {compatibility: best_effort}
network_policies:
  model_api:
    name: model-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/opencode}]
  opencode_registry:
    name: opencode-registry
    endpoints: [{host: opencode.ai, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/opencode}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/sbin/git}]
  github_git:
    name: github-git
    endpoints: [{host: github.com, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/git}]
  npm_registry:
    name: npm-registry
    endpoints: [{host: registry.npmjs.org, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}, {path: /usr/sbin/npm}]
  docs_sites:
    name: docs-sites
    endpoints:
      - {host: docs.anthropic.com, port: 443, enforcement: enforce, access: read-only}
    binaries: [{path: /usr/sbin/node}]
```

- [ ] **Step 5: Write `create.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <review|dev|automation|interactive> [--name N]"
PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-opencode-${PROFILE}}"
harness_create "${NAME}" "${ODH_OPENCODE_IMAGE}" "${PROFILE_DIR}/policy.yaml"
note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
```

- [ ] **Step 6: Write `connect.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="opencode-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
harness_connect_tty "${NAME}" "opencode"
```

- [ ] **Step 7: Write `README.md`** documenting: prerequisites (gateway installed via `openshell/scripts/install.sh`); that OpenCode is pre-installed in the pinned aipcc image (`ODH_OPENCODE_IMAGE`, pinned by digest — record the version 1.18.31); the provider key is supplied via env (`ANTHROPIC_API_KEY`/`OPENAI_API_KEY` or `ANTHROPIC_BASE_URL=https://inference.local/v1`), never in the repo; the four profiles table; and `create.sh`/`connect.sh` usage.

- [ ] **Step 8: Validate policy YAML shape**

Run: `for f in openshell/harnesses/opencode/profiles/*/policy.yaml; do python3 -c "import yaml,sys; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d"; done && echo OK`
Expected: `OK`.

- [ ] **Step 9: Commit**

```bash
git add openshell/harnesses/opencode
git commit -m "feat(openshell): add OpenCode harness with four profiles"
```

---

### Task 6: OpenClaw harness (gateway UI on 18789)

**Design note:** Same single-phase shape as Task 5 (canonical). Harness pre-installed in `ODH_OPENCLAW_IMAGE`; no bootstrap, no install. OpenClaw is the standalone `openclaw` project (`github.com/openclaw/openclaw`) — NOT NemoClaw, NOT `anthropics/openclaw`. The harness binary is at `/usr/local/sbin/openclaw`. The Control UI is reached via SSH port-forward of `18789`, never an exposed port, so no inbound network policy is required. Do NOT include a `process:` block; do NOT reference `curl`/`python3`.

**Files:**
- Create: `openshell/harnesses/openclaw/create.sh`, `connect.sh`, `README.md`
- Create: `openshell/harnesses/openclaw/profiles/{review,dev,automation,interactive}/policy.yaml`

**Interfaces:**
- Consumes: `harness_create`, `harness_ssh`, `harness_forward` from Task 4; `ODH_OPENCLAW_IMAGE` from `images.env`.
- Produces: `create.sh --profile <p> [--name N] [--backend openai|anthropic]` and `connect.sh [--name N]` that port-forwards `18789`.

- [ ] **Step 1: Write the four profile policies** — copy the Task 5 profile shapes (review/dev/automation/interactive) verbatim, replacing the `model_api` binaries with the OpenClaw binary set and dropping the `opencode_registry` block. Each `model_api` block becomes:

```yaml
  model_api:
    name: model-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/openclaw}]
```

Keep the Task 5 `github_api`/`github_git`/`npm_registry`/`docs_sites` blocks per profile exactly (review = model only; dev = model+github+npm; automation = model+github(read-only)+npm; interactive = dev+docs_sites). In every block that scopes to the harness binary (e.g. `docs_sites`, `github_api`), keep `/usr/sbin/node` and add `/usr/local/sbin/openclaw` where the harness itself makes the call. Write each file out in full.

- [ ] **Step 2: Write `create.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""; BACKEND="anthropic"
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  --backend) BACKEND="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <p> [--name N] [--backend openai|anthropic]"
PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-openclaw-${PROFILE}}"
harness_create "${NAME}" "${ODH_OPENCLAW_IMAGE}" "${PROFILE_DIR}/policy.yaml"
note "Backend: ${BACKEND}. Start UI + forward with: ${H_DIR}/connect.sh --name ${NAME}"
```

- [ ] **Step 3: Write `connect.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="openclaw-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
# Launch the Control UI in the background, then forward its port.
harness_ssh "${NAME}" "nohup openclaw serve --port 18789 >/tmp/openclaw.log 2>&1 &" || true
harness_forward "${NAME}" 18789
```

- [ ] **Step 4: Write `README.md`** — document: OpenClaw is the standalone `github.com/openclaw/openclaw` project, pre-installed in the pinned `ODH_OPENCLAW_IMAGE` (record the version from the image label); the browser Control UI at `http://127.0.0.1:18789` after `connect.sh`; `--backend` selection; the provider key supplied via env, never in the repo; and the four profiles table.

- [ ] **Step 5: Validate the policies**

Run: `for f in openshell/harnesses/openclaw/profiles/*/policy.yaml; do python3 -c "import yaml; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d"; done && echo OK`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add openshell/harnesses/openclaw
git commit -m "feat(openshell): add OpenClaw harness with four profiles"
```

---

### Task 7: Codex harness (scripts + four profiles)

**Design note:** Same single-phase shape as Task 5 (canonical). Harness pre-installed in `ODH_CODEX_IMAGE`; no bootstrap, no install. The harness binary is at `/usr/local/sbin/codex`. Codex talks to OpenAI: `api.openai.com` for inference and `auth.openai.com` for device/login. `OPENAI_API_KEY` is supplied via env, never in the repo. Do NOT include a `process:` block; do NOT reference `curl`/`python3`.

**Files:**
- Create: `openshell/harnesses/codex/create.sh`, `connect.sh`, `README.md`
- Create: `openshell/harnesses/codex/profiles/{review,dev,automation,interactive}/policy.yaml`

**Interfaces:**
- Consumes: `harness_create`, `harness_connect_tty` from Task 4; `ODH_CODEX_IMAGE` from `images.env`.
- Produces: `create.sh --profile <p> [--name N]` and `connect.sh [--name N]` for Codex.

- [ ] **Step 1: Write the four profile policies** — copy the Task 5 profile shapes (review/dev/automation/interactive) verbatim, replacing the `model_api` block with the Codex endpoints/binaries below and dropping the `opencode_registry` block:

```yaml
  model_api:
    name: model-api
    endpoints:
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: auth.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}, {path: /usr/local/sbin/codex}]
```

Keep the Task 5 `github_api`/`github_git`/`npm_registry`/`docs_sites` blocks per profile exactly (review = model only; dev = model+github+npm; automation = model+github(read-only)+npm; interactive = dev+docs_sites). Write each file out in full.

- [ ] **Step 2: Write `create.sh`** — copy Task 5 Step 5 verbatim, changing `ODH_OPENCODE_IMAGE` → `ODH_CODEX_IMAGE` and the default name to `codex-${PROFILE}`.

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <review|dev|automation|interactive> [--name N]"
PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-codex-${PROFILE}}"
harness_create "${NAME}" "${ODH_CODEX_IMAGE}" "${PROFILE_DIR}/policy.yaml"
note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
```

- [ ] **Step 3: Write `connect.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="codex-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
harness_connect_tty "${NAME}" "codex"
```

- [ ] **Step 4: Write `README.md`** — mirror Task 5 Step 7 for Codex: pre-installed in the pinned `ODH_CODEX_IMAGE` (record the version); `OPENAI_API_KEY` supplied via env, never in the repo; the profiles allow `api.openai.com` + `auth.openai.com`; the four profiles table; `create.sh`/`connect.sh` usage.

- [ ] **Step 5: Validate the policies**

Run: `for f in openshell/harnesses/codex/profiles/*/policy.yaml; do python3 -c "import yaml; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d"; done && echo OK`
Expected: `OK`.

- [ ] **Step 6: Commit**

```bash
git add openshell/harnesses/codex
git commit -m "feat(openshell): add Codex harness with four profiles"
```

---

### Task 8: Policy-proof test + policy linting in static test

**Files:**
- Create: `openshell/tests/openshell-policy.sh`
- Modify: `openshell/tests/openshell-static.sh` (lint all profile policies)

**Interfaces:**
- Consumes: gateway from Task 3; `openshell_cli` from Task 1; a policy file from any harness.
- Produces: a behavioral assertion that deny-by-default blocks GitHub and a github-allow policy permits reads but blocks writes.

- [ ] **Step 1: Add policy linting to the static test**

Append to `openshell/tests/openshell-static.sh`:

```bash
# 5. Every profile policy is schema-valid.
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r p; do
    python3 - "$p" <<'PY' || fail "invalid policy: $p"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
assert d.get("version") == 1, "version"
assert "network_policies" in d, "network_policies"
assert "filesystem_policy" in d, "filesystem_policy"
PY
  done < <(find "${OS_DIR}" -path '*/profiles/*/policy.yaml')
fi
```

- [ ] **Step 2: Write the failing policy-proof test**

The proof is behavioral and uses NO secrets: it hits the public `https://api.github.com/zen` endpoint. It uses the single-phase `harness_create` (create `--from <aipcc image> --policy <host-path>`, wait `Ready`) — never the broken `--no-auto-providers` path — and probes egress with `node` (the aipcc images have `node` at `/usr/sbin/node` and no `curl`). Two sandboxes are created, one per policy, because filesystem/network are applied at birth:

- **deny** sandbox: a model-only policy (GitHub NOT in `network_policies`) → GitHub fetch must fail (deny-by-default).
- **allow** sandbox: same policy plus a `github_api` endpoint scoped to `/usr/sbin/node` → GitHub fetch must succeed.

Create `openshell/tests/openshell-policy.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
# shellcheck source=../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/harness-lib.sh"
# shellcheck source=../configs/images.env
# shellcheck disable=SC1091
source "${OS_DIR}/configs/images.env"

DENY="policy-proof-deny-citest"
ALLOW="policy-proof-allow-citest"
cleanup() { harness_destroy "${DENY}" 2>/dev/null || true; harness_destroy "${ALLOW}" 2>/dev/null || true; }
trap cleanup EXIT

# node one-liner: exit 0 iff the URL is fetched successfully within 10s, else exit 1.
probe='node --input-type=module -e "const c=AbortSignal.timeout(10000);try{const r=await fetch(process.argv[1],{signal:c});process.exit(r.ok?0:1)}catch(e){process.exit(1)}" '

DENY_POL="$(mktemp)"; cat > "${DENY_POL}" <<'YAML'
version: 1
filesystem_policy: {include_workdir: false, read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /opt], read_write: [/tmp, /dev/null, /home]}
landlock: {compatibility: best_effort}
network_policies:
  model_api:
    name: model-api
    endpoints: [{host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}]
YAML

ALLOW_POL="$(mktemp)"; cat > "${ALLOW_POL}" <<'YAML'
version: 1
filesystem_policy: {include_workdir: false, read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /opt], read_write: [/tmp, /dev/null, /home]}
landlock: {compatibility: best_effort}
network_policies:
  model_api:
    name: model-api
    endpoints: [{host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}]
    binaries: [{path: /usr/sbin/node}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/sbin/node}]
YAML

harness_create "${DENY}"  "${ODH_OPENCODE_IMAGE}" "${DENY_POL}"
harness_create "${ALLOW}" "${ODH_OPENCODE_IMAGE}" "${ALLOW_POL}"
rm -f "${DENY_POL}" "${ALLOW_POL}"

# deny-by-default: GitHub not in policy → blocked.
if harness_ssh "${DENY}" "${probe} https://api.github.com/zen" >/dev/null 2>&1; then
  echo "FAIL: github reachable under default-deny"; exit 1
fi
echo "deny-by-default: github blocked (expected)"

# allow: GitHub endpoint present → reachable.
harness_ssh "${ALLOW}" "${probe} https://api.github.com/zen" >/dev/null \
  || { echo "FAIL: github blocked despite allow policy"; exit 1; }
echo "github-allow: read succeeds (expected)"

echo "openshell-policy: OK"
```

- [ ] **Step 3: Run it to verify it fails without a gateway, passes with one**

Run (gateway down): `bash openshell/tests/openshell-policy.sh` → FAIL (`harness_create` cannot reach the gateway / sandbox never reaches `Ready`).
Run (after `openshell/scripts/install.sh`): `bash openshell/tests/openshell-policy.sh` → PASS ending `openshell-policy: OK`.

This test is host-dependent (needs a running gateway + outbound 443 to api.github.com); CI runs it only on the self-hosted RHEL runner, not on ephemeral GitHub-hosted runners (see Task 12).

- [ ] **Step 4: Commit**

```bash
git add openshell/tests/openshell-policy.sh openshell/tests/openshell-static.sh
git commit -m "test(openshell): add policy-proof and policy linting"
```

---

### Task 9: Standalone docs + top-level README rows

**Files:**
- Create: `openshell/docs/README.md`, `quickstarts/{opencode,openclaw,codex}.md`, `policy-walkthrough.md`, `threat-model.md`
- Modify: `README.md` (repo root)

- [ ] **Step 1: Write `openshell/docs/README.md`** — overview: architecture (gateway → injected odh supervisor → aipcc workload sandbox), the three harnesses (OpenCode/OpenClaw/Codex) as pinned public aipcc images with the harness CLI pre-installed, prerequisites (RHEL 9, rootless podman, `openshell/scripts/install.sh`), and links to the three quickstarts.

- [ ] **Step 2: Write the three quickstarts** (`opencode.md`, `openclaw.md`, `codex.md`) — each: install gateway, `create.sh --profile dev`, connect, teardown, and how the provider key is supplied from the environment (never the repo). For OpenClaw, document the `18789` port-forward and browser URL; for Codex, `OPENAI_API_KEY`.

- [ ] **Step 3: Write `policy-walkthrough.md`** — narrate the Task 8 deny → allow sequence using `openshell logs <sandbox>` output (`action=deny` → `action=allow`), referencing existing profiles (no new policy files).

- [ ] **Step 4: Write `threat-model.md`** — what OpenShell enforces (network endpoints per binary, filesystem read/write scope, landlock) and what it does not (logic inside the sandbox). Note the trust boundary: harnesses ship pre-installed in pinned public aipcc images (`@sha256`), so there is NO create-time install step and NO npm-egress window; provider credentials are injected only from the environment at connect time and never stored in the repo or CI.

- [ ] **Step 5: Modify root `README.md`** — add to the scenario/testing tables an "OpenShell sandboxing (standalone)" row pointing to `openshell/docs/README.md`.

- [ ] **Step 6: Verify links**

Run: `tests/shared-gateway-static.sh` (repo's existing Markdown-link check) — confirm it passes and covers the new files, or add the new paths to whatever link-check glob it uses.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add openshell/docs README.md
git commit -m "docs(openshell): add standalone quickstarts, walkthrough, threat model"
```

---

### Task 10: Integrated `openshell-praxis` scenario

**Files:**
- Create: `configs/openshell-praxis/gateway.toml.in`
- Create: `configs/openshell-praxis/harness-provider.json.in`
- Create: `configs/openshell-praxis/profiles/{review,dev,automation,interactive}/policy.yaml`
- Create: `scripts/openshell-praxis/install`
- Create: `docs/quickstarts/openshell-praxis/{README.md,install.md,users.md}`

**Interfaces:**
- Consumes: the PR #2 `scripts/common/install` framework; the OpenShell gateway from Task 3; the Praxis all-in-one loopback gateway (`:8080`).
- Produces: an installed scenario whose sandbox model egress is the Praxis loopback only.

- [ ] **Step 1: Write `harness-provider.json.in`** (model base URL = Praxis loopback), modeled on `configs/all-in-one/clients/opencode-shared-gateway.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "praxis": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Praxis (sandboxed)",
      "options": {"baseURL": "http://host.openshell.internal:@@PRAXIS_PORT@@/v1", "apiKey": "local-placeholder"},
      "models": {"@@MODEL_ID@@": {"name": "Administrator-approved model"}}
    }
  }
}
```

- [ ] **Step 2: Write the four integrated profile policies** — same four-profile structure as Task 5, but the model endpoint block permits ONLY the Praxis loopback and denies direct provider hosts:

```yaml
  praxis_gateway:
    name: praxis-gateway
    endpoints:
      - {host: host.openshell.internal, port: @@PRAXIS_PORT@@, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/sbin/node}]
```

No `api.anthropic.com`/`api.openai.com` endpoints appear in any integrated profile (default-deny blocks them). Keep github/npm/docs blocks graded per profile as in Task 5 (binaries `/usr/sbin/node`, `/usr/sbin/git`, `/usr/sbin/npm`; no `curl`/`python3` — absent from aipcc images). Write all four in full.

**HOST-INTEGRATION QUESTIONS to resolve during execution (validate on the RHEL host, do not guess):**
- **Port:** the OpenShell gateway grpc binds host `127.0.0.1:8080`, and the Praxis all-in-one gateway is also described on loopback `:8080` — a direct conflict on the same host. Confirm the actual Praxis all-in-one listen port from its committed config and set `@@PRAXIS_PORT@@` accordingly; if both truly want 8080, rule on which moves (prefer moving the OpenShell grpc bind, since it is ours to change, and update `gateway.toml`/quadlet/tests consistently).
- **Reachability:** sandbox containers are spawned by the gateway on bridge networking, so `host.openshell.internal` must resolve inside the sandbox to the host. Verify how the odh supervisor exposes the host alias to injected workloads; if it does not, determine the correct host-reachable address for the Praxis loopback and use that instead. Record the finding in the ledger.

- [ ] **Step 3: Write `scripts/openshell-praxis/install`** (thin wrapper, matching `scripts/all-in-one/install`):

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../common/install" --scenario openshell-praxis "$@"
```

- [ ] **Step 4: Extend `scripts/common/install` scenario handling** — add an `openshell-praxis` case that (a) asserts the Praxis all-in-one gateway is installed and healthy on loopback, (b) runs `openshell/scripts/install.sh` for the OpenShell gateway, and (c) records the scenario in `SCENARIO_FILE`. Follow the existing `--scenario` dispatch pattern already in `scripts/common/install`; read it first and mirror its structure exactly.

- [ ] **Step 5: Write the three quickstart docs** — `README.md` (architecture: harness → OpenShell sandbox → Praxis loopback → provider; credential-starved + sandboxed), `install.md` (prereq: all-in-one Praxis installed; then `scripts/openshell-praxis/install`), `users.md` (per-harness create with an integrated profile + the provider config).

- [ ] **Step 6: Validate the integrated policies**

Run: `for f in configs/openshell-praxis/profiles/*/policy.yaml; do python3 -c "import yaml; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d; assert not any('api.anthropic.com' in str(e) or 'api.openai.com' in str(e) for e in d['network_policies'].values())"; done && echo OK`
Expected: `OK` (proves no direct provider host is allowed).

- [ ] **Step 7: Commit**

```bash
git add configs/openshell-praxis scripts/openshell-praxis docs/quickstarts/openshell-praxis
git commit -m "feat(openshell-praxis): integrated sandbox-through-praxis scenario"
```

---

### Task 11: Integrated smoke test

**Files:**
- Create: `tests/openshell-praxis/smoke.sh`

**Interfaces:**
- Consumes: OpenShell gateway; an integrated profile from Task 10.
- Produces: assertion that a loopback stub is reachable and direct provider hosts are denied.

- [ ] **Step 1: Write the failing smoke test**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../openshell/scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${ROOT}/openshell/scripts/harness-lib.sh"
# shellcheck source=../../openshell/configs/images.env
# shellcheck disable=SC1091
source "${ROOT}/openshell/configs/images.env"
NAME="ospx-smoke-citest"
cleanup() { harness_destroy "${NAME}" 2>/dev/null || true; }
trap cleanup EXIT

# Single-phase create with the integrated dev profile (Praxis-loopback only; no
# direct provider hosts). Then prove a direct provider host is denied.
# The rendered policy is produced by scripts/openshell-praxis/install; for this
# test, render @@PRAXIS_PORT@@ into a temp copy (default 8080; override via env).
PRAXIS_PORT="${PRAXIS_PORT:-8080}"
POL="$(mktemp)"
sed "s#@@PRAXIS_PORT@@#${PRAXIS_PORT}#g" \
  "${ROOT}/configs/openshell-praxis/profiles/dev/policy.yaml" > "${POL}"
harness_create "${NAME}" "${ODH_OPENCODE_IMAGE}" "${POL}"
rm -f "${POL}"

probe='node --input-type=module -e "const c=AbortSignal.timeout(10000);try{const r=await fetch(process.argv[1],{signal:c});process.exit(r.ok?0:1)}catch(e){process.exit(1)}" '

# Direct provider host must be denied (not in the integrated policy).
if harness_ssh "${NAME}" "${probe} https://api.openai.com/v1/models" >/dev/null 2>&1; then
  echo "FAIL: direct provider reachable under integrated policy"; exit 1
fi
echo "integrated: direct provider denied (expected)"
echo "openshell-praxis-smoke: OK"
```

- [ ] **Step 2: Run it** (after gateway install): `bash tests/openshell-praxis/smoke.sh`
Expected: PASS ending `openshell-praxis-smoke: OK`.
(Host-dependent — self-hosted RHEL runner only; see Task 12.)

- [ ] **Step 3: Commit**

```bash
git add tests/openshell-praxis/smoke.sh
git commit -m "test(openshell-praxis): integrated smoke denies direct providers"
```

---

### Task 12: CI workflow `openshell-validate.yml`

**Files:**
- Create: `.github/workflows/openshell-validate.yml`

**Interfaces:**
- Consumes: all tests from Tasks 1–11.
- Produces: an amd64 + arm64, no-secrets validation workflow.

- [ ] **Step 1: Write the workflow** (model on `.github/workflows/validate.yml`)

```yaml
name: Validate OpenShell demos

on:
  pull_request:
    paths: ["openshell/**", "configs/openshell-praxis/**", "scripts/openshell-praxis/**", ".github/workflows/openshell-validate.yml"]
  push:
    branches: [main]
    paths: ["openshell/**", "configs/openshell-praxis/**", "scripts/openshell-praxis/**", ".github/workflows/openshell-validate.yml"]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  openshell:
    name: OpenShell ${{ matrix.arch }}
    strategy:
      fail-fast: false
      matrix:
        include:
          - {runner: ubuntu-24.04, arch: amd64}
          - {runner: ubuntu-24.04-arm, arch: arm64}
    runs-on: ${{ matrix.runner }}
    timeout-minutes: 25
    env:
      CONTAINER_ENGINE: docker
    steps:
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
        with: {persist-credentials: false}
      - name: Install tools
        run: sudo apt-get update && sudo apt-get install -y jq ripgrep shellcheck python3-yaml
      - name: Static checks
        run: bash openshell/tests/openshell-static.sh
      - name: Native architecture check
        env: {EXPECTED_ARCH: "${{ matrix.arch }}"}
        run: |
          source scripts/common/lib.sh
          test "$(oci_architecture "$(uname -m)")" = "$EXPECTED_ARCH"
      - name: Boot pinned gateway without provider keys
        run: |
          sudo install -d -o "$(id -u)" /var/lib/openshell
          bash openshell/tests/openshell-image.sh
      - name: Policy proof (host-capable runners only)
        if: ${{ vars.OPENSHELL_SELF_HOSTED == 'true' }}
        run: bash openshell/tests/openshell-policy.sh
      - name: Integrated smoke (host-capable runners only)
        if: ${{ vars.OPENSHELL_SELF_HOSTED == 'true' }}
        run: bash tests/openshell-praxis/smoke.sh
```

Note: static checks and the gateway boot test run always on the ephemeral amd64/arm64 GitHub runners (no secrets, no sandbox spawning needed). The policy-proof and integrated-smoke steps require a running odh gateway that can spawn sibling sandbox + supervisor containers via the Podman driver and reach the network — only a self-hosted RHEL runner can do this. They are gated on the repo variable `OPENSHELL_SELF_HOSTED == 'true'` so they are skipped (not failed) on GitHub-hosted runners. Document this split in `openshell/docs/README.md`. During implementation, confirm whether a self-hosted RHEL runner is available; if so, add its label to the matrix so the gated steps actually execute there.

- [ ] **Step 2: Validate the workflow YAML**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/openshell-validate.yml'))" && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/openshell-validate.yml
git commit -m "ci(openshell): add no-secrets validation workflow"
```

---

## Self-Review

**Spec coverage:**
- Standalone OpenShell runtime (pinned odh control plane via quadlet) → Tasks 1–3. ✓
- CLI via odh image + native binary for ssh-proxy → Task 1 (`openshell_cli`) + Task 3 (extract `/usr/local/bin/openshell`). ✓
- Three harnesses × four profiles, single-phase create from pinned public aipcc images (harness pre-installed) → Tasks 4–7. ✓
- OpenClaw = standalone `github.com/openclaw/openclaw` (NOT NemoClaw), UI 18789 → Task 6. ✓
- Codex = OpenAI (`api.openai.com` + `auth.openai.com`), `OPENAI_API_KEY` from env → Task 7. ✓
- Teaching pointer → Task 9 Step 3. ✓
- Integrated `openshell-praxis` scenario (loopback-only egress) → Task 10. ✓
- CI: static + boot always-on (no secrets, amd64+arm64); policy proof + integrated smoke gated to self-hosted RHEL → Task 12. ✓
- Tests mirror existing idioms → Tasks 1,3,8,11. ✓
- Praxis untouched → enforced by Global Constraints + paths-filtered CI. ✓

**Placeholder scan:** The intentional tokens are the seven pinned digests (Task 1 Step 3, now filled with the 2026-09-24 validated values), `@@ODH_*_IMAGE@@`/`@@MODEL_ID@@`/`@@PRAXIS_PORT@@` template placeholders (resolved by `render_template`/install), all by design. No two-phase install, no `bootstrap.yaml`, no `@latest` (harness versions ship pinned in the aipcc images). No "TBD"/"handle edge cases" placeholders.

**Type consistency:** `openshell_cli`, `render_template`, and `harness_create(name,image,policy)/harness_ssh/harness_connect_tty/harness_forward/harness_destroy` are defined in Tasks 1 and 4 and used consistently in Tasks 3–11 (single-phase signature everywhere; no stale `harness_create <profile_dir> <install_cmd>` calls remain). `images.env` variables (`ODH_GATEWAY/SUPERVISOR/SANDBOX/CLI_IMAGE` + `ODH_OPENCODE/OPENCLAW/CODEX_IMAGE`) match across `lib.sh`, templates, tests. Binary paths (`/usr/sbin/node|npm|git`, `/usr/local/sbin/<harness>`; no `curl`/`python3` in-sandbox) are consistent across all policies and the node-based probes. Profile directory names (`review/dev/automation/interactive`) are consistent across harnesses and CI.

**Open confirmations for the executor (not plan gaps):** whether a self-hosted RHEL runner is available for the gated behavioral CI steps; the Praxis all-in-one listen port and host-alias reachability for the integrated scenario (Task 10 host-integration questions); refresh of the seven pinned digests if a newer image is required.
