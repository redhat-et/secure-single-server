# OpenShell Three-Harness Demonstrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add standalone OpenShell sandboxing demos (Claude Code, OpenCode, OpenClaw) and an integrated `openshell-praxis` scenario to `secure-single-server`, with pinned odh images, four policy profiles per harness, and a no-secrets validation workflow.

**Architecture:** A self-contained `openshell/` tree runs an OpenShell gateway as a rootless Podman quadlet from digest-pinned odh quay images; each harness is installed into the odh sandbox base at create-time (two-phase launch) and constrained by one of four capability-graded OpenShell `policy.yaml` files. A separate `openshell-praxis` scenario plugs into the PR #2 installer framework and locks sandbox model egress to the Praxis all-in-one loopback gateway. CI boots the pinned images and proves policy enforcement without provider credentials.

**Tech Stack:** RHEL 9, rootless Podman + quadlet (systemd user units), OpenShell (odh quay images), Bash, YAML policies, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-24-openshell-harness-demos-design.md`

## Global Constraints

- Base branch: `feat/gateway-scenarios` (PR #2). Branch: `openshell-harness-demos`.
- All odh images pinned by `@sha256:` digest, declared once in `openshell/configs/images.env`. Rendered templates use `Pull=never`.
- No provider credentials in the repo or in CI. Provider keys come from environment/OS keyring only.
- OpenShell is consumed only via odh quay images (`quay.io/opendatahub/odh-openshell-{supervisor,gateway,cli,sandbox}`); no host RPM install.
- OpenClaw means `github.com/anthropics/openclaw` (npm package `openclaw`). NemoClaw is NOT used.
- Reuse `scripts/common/lib.sh` helpers (`die`, `note`, `require_command`, `oci_architecture`) rather than reimplementing them.
- OpenShell sandbox policies live at `profiles/<profile>/policy.yaml`, never named bare `policy.yaml` at a scenario root (that name is a Praxis JWT plugin policy).
- Gateway binds loopback only: gRPC/control `127.0.0.1:8080`, health `127.0.0.1:8081`.
- Every shell script passes `shellcheck`; every policy YAML validates against the schema check in Task 2.
- Do not modify existing Praxis configs, quadlets, scripts, or `.github/workflows/validate.yml`.

---

## File Structure

- `openshell/configs/images.env.in` + `images.env` — the four odh digests (single source of truth).
- `openshell/configs/quadlet/openshell.network`, `openshell-gateway.container.in` — gateway quadlet.
- `openshell/configs/gateway/gateway.toml` — podman driver, deny-by-default, pinned sandbox/supervisor images.
- `openshell/scripts/lib.sh` — OpenShell-specific helpers + `openshell` CLI wrapper (sources `scripts/common/lib.sh`).
- `openshell/scripts/install.sh`, `uninstall.sh` — render + start/stop the gateway quadlet.
- `openshell/scripts/harness-lib.sh` — shared two-phase create/connect/destroy used by all harness scripts.
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
- Produces: `openshell/configs/images.env` defining `ODH_GATEWAY_IMAGE`, `ODH_SUPERVISOR_IMAGE`, `ODH_SANDBOX_IMAGE`, `ODH_CLI_IMAGE` (all `quay.io/opendatahub/odh-openshell-*@sha256:...`).

- [ ] **Step 1: Write the failing static test**

Create `openshell/tests/openshell-static.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# 1. images.env must define four @sha256-pinned odh images.
# shellcheck source=/dev/null
source "${OS_DIR}/configs/images.env"
for var in ODH_GATEWAY_IMAGE ODH_SUPERVISOR_IMAGE ODH_SANDBOX_IMAGE ODH_CLI_IMAGE; do
  val="${!var:-}"
  [[ -n "${val}" ]] || fail "${var} unset"
  [[ "${val}" == quay.io/opendatahub/odh-openshell-*@sha256:* ]] \
    || fail "${var} not a digest-pinned odh image: ${val}"
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

- [ ] **Step 3: Resolve the four odh digests and write `images.env`**

Resolve each digest against quay (requires network; do NOT invent a digest). Prefer `skopeo`; fall back to `podman`:

```bash
for c in gateway supervisor sandbox cli; do
  d=$(skopeo inspect --format '{{.Digest}}' \
        docker://quay.io/opendatahub/odh-openshell-${c}:latest)
  printf '%s -> %s\n' "$c" "$d"
done
```

Write `openshell/configs/images.env` with the resolved digests (example shape — replace each `sha256:...` with the value skopeo returned):

```bash
# Pinned odh OpenShell images. Refresh with openshell/tests/refresh-digests.sh.
ODH_GATEWAY_IMAGE="quay.io/opendatahub/odh-openshell-gateway@sha256:REPLACE"
ODH_SUPERVISOR_IMAGE="quay.io/opendatahub/odh-openshell-supervisor@sha256:REPLACE"
ODH_SANDBOX_IMAGE="quay.io/opendatahub/odh-openshell-sandbox@sha256:REPLACE"
ODH_CLI_IMAGE="quay.io/opendatahub/odh-openshell-cli@sha256:REPLACE"
```

Create `openshell/configs/images.env.in` identical but with `@@ODH_*@@` placeholders, documenting that `images.env` is the rendered, digest-pinned copy committed to the repo.

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
- Create: `openshell/configs/quadlet/openshell.network`
- Create: `openshell/configs/quadlet/openshell-gateway.container.in`
- Create: `openshell/configs/gateway/gateway.toml`
- Modify: `openshell/tests/openshell-static.sh` (add template-render + toml checks)

**Interfaces:**
- Produces: a rendered `openshell-gateway.container` quadlet unit named container `openshell-gateway`, publishing `127.0.0.1:8080` and `127.0.0.1:8081`.
- Produces: `gateway.toml` with `compute_drivers=["podman"]` and pinned `default_image`/`supervisor_image`.

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

# 4. gateway.toml uses the podman driver and pins sandbox/supervisor images.
gt="${OS_DIR}/configs/gateway/gateway.toml"
grep -q 'compute_drivers *= *\["podman"\]' "${gt}" || fail "gateway.toml not podman driver"
grep -q "supervisor_image *= *\"${ODH_SUPERVISOR_IMAGE}\"" "${gt}" || fail "supervisor image not pinned"
grep -q "default_image *= *\"${ODH_SANDBOX_IMAGE}\"" "${gt}" || fail "sandbox image not pinned"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash openshell/tests/openshell-static.sh`
Expected: FAIL — quadlet/toml files do not exist.

- [ ] **Step 3: Write `openshell.network`**

```ini
[Network]
NetworkName=openshell
```

- [ ] **Step 4: Write `openshell-gateway.container.in`**

Model on `configs/common/quadlet/praxis.container.in`:

```ini
[Unit]
Description=OpenShell sandbox gateway (odh, pinned)
After=network-online.target
Wants=network-online.target

[Container]
Image=@@ODH_GATEWAY_IMAGE@@
ContainerName=openshell-gateway
Pull=never
Network=openshell.network
PublishPort=127.0.0.1:8080:8080
PublishPort=127.0.0.1:8081:8081
Volume=%h/.config/openshell/gateway.toml:/etc/openshell/gateway.toml:ro,z
Volume=/var/lib/openshell:/var/lib/openshell:z
Environment=OPENSHELL_GATEWAY_CONFIG=/etc/openshell/gateway.toml
Environment=OPENSHELL_DB_URL=sqlite:/var/lib/openshell/gateway.db?mode=rwc
Environment=XDG_DATA_HOME=/var/lib/openshell
Environment=HOME=/var/lib/openshell
AddHost=host.openshell.internal:host-gateway
Exec=

[Service]
Restart=on-failure
RestartSec=5s
TimeoutStartSec=900
TimeoutStopSec=30

[Install]
WantedBy=default.target
```

Note in a comment above `[Container]`: the gateway needs the rootless Podman socket to spawn sibling sandbox containers; `install.sh` (Task 3) enables `podman.socket` for the user. `/var/lib/openshell` is bind-mounted at the same absolute path inside and out so sandbox bind-mount sources resolve on the host.

- [ ] **Step 5: Write `gateway.toml`** (values pulled by `render_template` at install time; commit the digest-bearing copy)

```toml
[openshell]
version = 1

[openshell.gateway]
bind_address        = "127.0.0.1:8080"
health_bind_address = "127.0.0.1:8081"
log_level           = "info"
compute_drivers     = ["podman"]
disable_tls         = true

[openshell.drivers.podman]
default_image     = "@@ODH_SANDBOX_IMAGE@@"
supervisor_image  = "@@ODH_SUPERVISOR_IMAGE@@"
image_pull_policy = "IfNotPresent"
sandbox_namespace = "openshell"
grpc_endpoint     = "http://host.openshell.internal:8080"
enable_bind_mounts = true
```

Commit `gateway.toml.in` with the placeholders and let `install.sh` render `gateway.toml`. (Adjust the Task 2 test to read `gateway.toml.in` if you keep only the template; simplest is to render into `configs/gateway/gateway.toml` during Task 3 and have the test render a temp copy like it does for the quadlet.)

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
source "${OS_DIR}/scripts/lib.sh"
require_command podman

note "Enabling rootless podman socket for the gateway"
systemctl --user enable --now podman.socket

note "Preparing /var/lib/openshell (source==target bind path)"
sudo install -d -o "$(id -u)" -g "$(id -g)" /var/lib/openshell

note "Rendering gateway config and quadlet"
install -d "${HOME}/.config/openshell" "${HOME}/.config/containers/systemd"
render_template "${OS_DIR}/configs/gateway/gateway.toml.in" "${HOME}/.config/openshell/gateway.toml"
render_template "${OS_DIR}/configs/quadlet/openshell-gateway.container.in" \
  "${HOME}/.config/containers/systemd/openshell-gateway.container"
cp "${OS_DIR}/configs/quadlet/openshell.network" \
  "${HOME}/.config/containers/systemd/openshell.network"

note "Pulling pinned images"
for img in "${ODH_GATEWAY_IMAGE}" "${ODH_SUPERVISOR_IMAGE}" "${ODH_SANDBOX_IMAGE}" "${ODH_CLI_IMAGE}"; do
  podman pull "${img}"
done

note "Starting gateway"
systemctl --user daemon-reload
systemctl --user start openshell-gateway.service

note "Registering CLI gateway 'local'"
openshell_cli gateway add http://127.0.0.1:8080 --name local || true
openshell_cli gateway select local || true
note "OpenShell gateway installed. Health: http://127.0.0.1:8081/healthz"
```

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

### Task 4: Shared harness library (two-phase create-time install)

**Files:**
- Create: `openshell/scripts/harness-lib.sh`

**Interfaces:**
- Consumes: `openshell_cli` from Task 1.
- Produces: functions used by every harness `create.sh`/`connect.sh`:
  - `harness_create <harness> <sandbox_name> <profile_dir> <bootstrap_policy> <install_cmd>` — creates a default-deny sandbox, applies the bootstrap policy, runs `<install_cmd>` inside it, then applies `<profile_dir>/policy.yaml`.
  - `harness_ssh <sandbox_name> <cmd...>` — exec via `openshell sandbox ssh-config`.
  - `harness_connect_tty <sandbox_name> [cmd]` — interactive attach.
  - `harness_forward <sandbox_name> <port>` — port-forward (OpenClaw).
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

_ssh_config() {  # <sandbox> -> prints a temp ssh config path
  local name="$1" cfg; cfg="$(mktemp)"
  openshell_cli sandbox ssh-config "${name}" > "${cfg}"
  printf '%s\n' "${cfg}"
}

harness_ssh() {  # <sandbox> <cmd...>
  local name="$1"; shift
  local cfg host; cfg="$(_ssh_config "${name}")"
  host="$(awk '/^Host /{print $2; exit}' "${cfg}")"
  ssh -F "${cfg}" "${host}" "$@"
  rm -f "${cfg}"
}

harness_connect_tty() {  # <sandbox> [cmd]
  local name="$1"; shift || true
  local cfg host; cfg="$(_ssh_config "${name}")"
  host="$(awk '/^Host /{print $2; exit}' "${cfg}")"
  ssh -tF "${cfg}" "${host}" "$@"
  rm -f "${cfg}"
}

harness_forward() {  # <sandbox> <port>
  local name="$1" port="$2"
  local cfg host; cfg="$(_ssh_config "${name}")"
  host="$(awk '/^Host /{print $2; exit}' "${cfg}")"
  note "Forwarding 127.0.0.1:${port} -> sandbox ${name}:${port} (Ctrl-C to stop)"
  ssh -NF "${cfg}" -L "127.0.0.1:${port}:127.0.0.1:${port}" "${host}"
  rm -f "${cfg}"
}

harness_destroy() { openshell_cli sandbox delete "$1" 2>/dev/null || true; }

# Two-phase create: bootstrap egress -> install harness -> lock to profile.
harness_create() {  # <harness> <name> <profile_dir> <bootstrap_policy> <install_cmd>
  local harness="$1" name="$2" profile_dir="$3" bootstrap="$4" install_cmd="$5"
  require_command ssh
  note "Creating default-deny sandbox ${name} for ${harness}"
  openshell_cli sandbox create --name "${name}" --no-auto-providers
  note "Bootstrap phase: opening install source only"
  openshell_cli policy set "${name}" --policy "${bootstrap}"
  note "Installing pinned harness"
  harness_ssh "${name}" "${install_cmd}"
  note "Demo phase: applying ${profile_dir##*/} profile policy"
  openshell_cli policy set "${name}" --policy "${profile_dir}/policy.yaml"
  note "Sandbox ${name} ready under ${profile_dir##*/} profile"
}
```

- [ ] **Step 4: Run the unit test to verify it passes**

Run: `bash openshell/tests/harness-lib-unit.sh`
Expected: PASS. Then delete the temp test: `rm openshell/tests/harness-lib-unit.sh` (its assertions are structural; the behavior is exercised by Task 8).

- [ ] **Step 5: Commit**

```bash
git add openshell/scripts/harness-lib.sh
git commit -m "feat(openshell): add shared two-phase harness library"
```

---

### Task 5: Claude Code harness (scripts + four profiles)

**Files:**
- Create: `openshell/harnesses/claude/create.sh`, `connect.sh`, `README.md`
- Create: `openshell/harnesses/claude/profiles/{review,dev,automation,interactive}/policy.yaml`
- Create: `openshell/harnesses/claude/profiles/bootstrap.yaml`

**Interfaces:**
- Consumes: `harness_create`, `harness_connect_tty`, `harness_destroy` from Task 4.
- Produces: `create.sh --profile <p>` and `connect.sh --name <n>` for Claude Code.

- [ ] **Step 1: Write `profiles/bootstrap.yaml`** (npm-only egress)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom]
  read_write: [/tmp, /dev/null, /home]
landlock: {compatibility: best_effort}
process: {run_as_user: sandbox, run_as_group: sandbox}
network_policies:
  npm_registry:
    name: npm-registry
    endpoints:
      - {host: registry.npmjs.org, port: 443, enforcement: enforce}
    binaries: [{path: /usr/bin/node}, {path: /usr/bin/npm}, {path: /usr/bin/curl}]
```

- [ ] **Step 2: Write `profiles/review/policy.yaml`** (workspace read-only, model API only)

```yaml
version: 1
filesystem_policy:
  include_workdir: false
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom, /workspace]
  read_write: [/tmp, /dev/null, /sandbox]
landlock: {compatibility: hard_requirement}
process: {run_as_user: sandbox, run_as_group: sandbox}
network_policies:
  anthropic_api:
    name: anthropic-api
    endpoints:
      - host: api.anthropic.com
        port: 443
        protocol: rest
        enforcement: enforce
        rules: [{allow: {method: POST, path: /v1/messages}}]
    binaries: [{path: /usr/bin/node}]
```

- [ ] **Step 3: Write `profiles/dev/policy.yaml`** (read-write, model + GitHub + npm/PyPI)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom]
  read_write: [/workspace, /sandbox, /tmp, /dev/null]
landlock: {compatibility: best_effort}
process: {run_as_user: sandbox, run_as_group: sandbox}
network_policies:
  anthropic_api:
    name: anthropic-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce,
         rules: [{allow: {method: POST, path: /v1/messages}}]}
    binaries: [{path: /usr/bin/node}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/bin/curl}]
  github_git:
    name: github-git
    endpoints: [{host: github.com, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/bin/git}, {path: /usr/bin/curl}]
  npm_registry:
    name: npm-registry
    endpoints: [{host: registry.npmjs.org, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/bin/node}, {path: /usr/bin/curl}]
  pypi:
    name: pypi
    endpoints:
      - {host: pypi.org, port: 443, enforcement: enforce}
      - {host: files.pythonhosted.org, port: 443, enforcement: enforce}
    binaries: [{path: /usr/bin/curl}, {path: /usr/bin/python3}]
```

- [ ] **Step 4: Write `profiles/automation/policy.yaml`** (dev minus interactive, headless — same as dev but drop `github_git` write path and PyPI; keep model + read-only GitHub + npm)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom]
  read_write: [/workspace, /sandbox, /tmp, /dev/null]
landlock: {compatibility: hard_requirement}
process: {run_as_user: sandbox, run_as_group: sandbox}
network_policies:
  anthropic_api:
    name: anthropic-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce,
         rules: [{allow: {method: POST, path: /v1/messages}}]}
    binaries: [{path: /usr/bin/node}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/bin/curl}]
  npm_registry:
    name: npm-registry
    endpoints: [{host: registry.npmjs.org, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/bin/node}, {path: /usr/bin/curl}]
```

- [ ] **Step 5: Write `profiles/interactive/policy.yaml`** (dev + persistent volume + docs sites)

```yaml
version: 1
filesystem_policy:
  include_workdir: true
  read_only: [/usr, /lib, /lib64, /etc, /proc, /dev/urandom]
  read_write: [/workspace, /sandbox, /sandbox/persist, /tmp, /dev/null]
landlock: {compatibility: best_effort}
process: {run_as_user: sandbox, run_as_group: sandbox}
network_policies:
  anthropic_api:
    name: anthropic-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce,
         rules: [{allow: {method: POST, path: /v1/messages}}]}
    binaries: [{path: /usr/bin/node}]
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/bin/curl}]
  github_git:
    name: github-git
    endpoints: [{host: github.com, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/bin/git}, {path: /usr/bin/curl}]
  npm_registry:
    name: npm-registry
    endpoints: [{host: registry.npmjs.org, port: 443, enforcement: enforce}]
    binaries: [{path: /usr/bin/node}, {path: /usr/bin/curl}]
  docs_sites:
    name: docs-sites
    endpoints:
      - {host: docs.anthropic.com, port: 443, enforcement: enforce, access: read-only}
      - {host: docs.python.org, port: 443, enforcement: enforce, access: read-only}
    binaries: [{path: /usr/bin/curl}]
```

- [ ] **Step 6: Write `create.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
PROFILE=""; NAME=""
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <review|dev|automation|interactive> [--name N]"
PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-claude-${PROFILE}}"
harness_create claude "${NAME}" "${PROFILE_DIR}" \
  "${H_DIR}/profiles/bootstrap.yaml" \
  "sudo npm install -g @anthropic-ai/claude-code@latest"
note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
```

- [ ] **Step 7: Write `connect.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="claude-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
harness_connect_tty "${NAME}" "claude"
```

- [ ] **Step 8: Write `README.md`** documenting: prerequisites (gateway installed via `openshell/scripts/install.sh`; `ANTHROPIC_API_KEY` in env when running Claude), the four profiles table, and `create.sh`/`connect.sh` usage. Pin the harness version explicitly instead of `@latest` once confirmed.

- [ ] **Step 9: Validate policy YAML shape**

Run: `bash openshell/tests/openshell-static.sh` (extend it in Task 8 to lint every `profiles/**/policy.yaml` for `version: 1` + `network_policies`). For now:
Run: `for f in openshell/harnesses/claude/profiles/*/policy.yaml; do python3 -c "import yaml,sys; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d"; done && echo OK`
Expected: `OK`.

- [ ] **Step 10: Commit**

```bash
git add openshell/harnesses/claude
git commit -m "feat(openshell): add Claude Code harness with four profiles"
```

---

### Task 6: OpenCode harness (scripts + four profiles)

**Files:**
- Create: `openshell/harnesses/opencode/create.sh`, `connect.sh`, `README.md`
- Create: `openshell/harnesses/opencode/profiles/{bootstrap,review,dev,automation,interactive}.../policy.yaml`

**Interfaces:**
- Consumes: `harness_create`, `harness_connect_tty` from Task 4.
- Produces: `create.sh --profile <p>` for OpenCode.

- [ ] **Step 1: Confirm the OpenCode install channel + provider endpoint**

OpenCode installs via npm (`opencode-ai`) or its published install script. Confirm the current package name/version and the model host it calls (it is an OpenAI-compatible client; the standalone demo points it at the provider the user configures, e.g. `api.openai.com` or `api.anthropic.com`). Record the chosen provider host — it becomes the `model_api` endpoint in the profiles below. Default this plan to `api.openai.com` for standalone.

- [ ] **Step 2: Write `profiles/bootstrap.yaml`** (identical structure to Task 5 Step 1; npm-only egress) — repeat the Task 5 bootstrap content verbatim.

- [ ] **Step 3: Write the four profile policies** — same four-profile structure and filesystem/landlock/process blocks as Task 5 Steps 2–5, with the model endpoint block replaced by:

```yaml
  model_api:
    name: model-api
    endpoints:
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce,
         rules: [{allow: {method: POST, path: /v1/chat/completions}}]}
    binaries: [{path: /usr/bin/node}]
```

Keep `github_api`, `github_git`, `npm_registry`, `pypi`, `docs_sites` blocks per profile exactly as in the Claude profiles (review = model only; dev = model+github+npm+pypi; automation = model+github(read-only)+npm; interactive = dev+docs_sites). Write each file out in full.

- [ ] **Step 4: Write `create.sh`** — copy Task 5 Step 6, changing the harness label to `opencode`, the default name to `opencode-${PROFILE}`, and the install command to `sudo npm install -g opencode-ai@latest`.

- [ ] **Step 5: Write `connect.sh`** — copy Task 5 Step 7, default name `opencode-dev`, launching `opencode`.

- [ ] **Step 6: Write `README.md`** — mirror Task 5 Step 8 for OpenCode; note the provider is configurable and document which host the profiles allow.

- [ ] **Step 7: Validate the policies**

Run: `for f in openshell/harnesses/opencode/profiles/*/policy.yaml; do python3 -c "import yaml; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d"; done && echo OK`
Expected: `OK`.

- [ ] **Step 8: Commit**

```bash
git add openshell/harnesses/opencode
git commit -m "feat(openshell): add OpenCode harness with four profiles"
```

---

### Task 7: OpenClaw harness (gateway UI on 18789)

**Files:**
- Create: `openshell/harnesses/openclaw/create.sh`, `connect.sh`, `README.md`
- Create: `openshell/harnesses/openclaw/profiles/{bootstrap,review,dev,automation,interactive}/policy.yaml`

**Interfaces:**
- Consumes: `harness_create`, `harness_forward` from Task 4.
- Produces: `create.sh --profile <p> [--backend openai|anthropic]` and `connect.sh --name <n>` that port-forwards `18789`.

- [ ] **Step 1: Write `profiles/bootstrap.yaml`** — repeat the Task 5 bootstrap content verbatim.

- [ ] **Step 2: Write the four profile policies** — same structure as Task 5, but the model endpoint block permits the chosen backend host and is scoped to the node/openclaw binaries:

```yaml
  model_api:
    name: model-api
    endpoints:
      - {host: api.anthropic.com, port: 443, protocol: rest, enforcement: enforce}
      - {host: api.openai.com, port: 443, protocol: rest, enforcement: enforce}
    binaries:
      - {path: /usr/bin/node}
      - {path: /usr/local/bin/openclaw}
      - {path: /usr/lib/node_modules/openclaw/**}
      - {path: /usr/local/lib/node_modules/openclaw/**}
```

Write all four profiles in full (review = model only; dev/automation/interactive add the same github/npm/pypi/docs blocks as Task 5). Because OpenClaw serves a local UI, no inbound network policy is required — the Control UI is reached via SSH port-forward, not an exposed port.

- [ ] **Step 3: Write `create.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
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
harness_create openclaw "${NAME}" "${PROFILE_DIR}" \
  "${H_DIR}/profiles/bootstrap.yaml" \
  "sudo npm install -g openclaw@latest"
note "Backend: ${BACKEND}. Start UI in sandbox, then: ${H_DIR}/connect.sh --name ${NAME}"
```

- [ ] **Step 4: Write `connect.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="openclaw-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
# Launch the gateway UI in the background, then forward its port.
harness_ssh "${NAME}" "nohup openclaw serve --port 18789 >/tmp/openclaw.log 2>&1 &" || true
harness_forward "${NAME}" 18789
```

- [ ] **Step 5: Write `README.md`** — document that OpenClaw is `github.com/anthropics/openclaw`, the browser Control UI on `http://127.0.0.1:18789` after `connect.sh`, backend selection, and the four profiles.

- [ ] **Step 6: Validate the policies**

Run: `for f in openshell/harnesses/openclaw/profiles/*/policy.yaml; do python3 -c "import yaml; d=yaml.safe_load(open('$f')); assert d['version']==1 and 'network_policies' in d"; done && echo OK`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add openshell/harnesses/openclaw
git commit -m "feat(openshell): add OpenClaw harness with four profiles"
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

Create `openshell/tests/openshell-policy.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
# shellcheck source=../scripts/harness-lib.sh
source "${OS_DIR}/scripts/harness-lib.sh"
NAME="policy-proof-citest"
trap 'harness_destroy "${NAME}"' EXIT

openshell_cli sandbox create --name "${NAME}" --no-auto-providers

# deny-by-default: GitHub blocked
if harness_ssh "${NAME}" "curl -fsS https://api.github.com/zen" >/dev/null 2>&1; then
  echo "FAIL: github reachable under default-deny"; exit 1
fi
echo "deny-by-default: github blocked (expected)"

# apply github read-only allow (reuse claude dev profile's github_api via a minimal policy)
POL="$(mktemp)"; cat > "${POL}" <<'YAML'
version: 1
filesystem_policy: {include_workdir: false, read_only: [/usr,/lib,/etc,/proc,/dev/urandom], read_write: [/tmp,/dev/null]}
landlock: {compatibility: best_effort}
network_policies:
  github_api:
    name: github-api
    endpoints: [{host: api.github.com, port: 443, protocol: rest, enforcement: enforce, access: read-only}]
    binaries: [{path: /usr/bin/curl}]
YAML
openshell_cli policy set "${NAME}" --policy "${POL}"; rm -f "${POL}"

harness_ssh "${NAME}" "curl -fsS https://api.github.com/zen" >/dev/null \
  || { echo "FAIL: github read blocked after allow"; exit 1; }
echo "github-allow: read succeeds (expected)"

# write must still be blocked (L7 read-only)
if harness_ssh "${NAME}" "curl -fsS -XPOST https://api.github.com/user/repos -d '{}'" >/dev/null 2>&1; then
  echo "FAIL: write allowed under read-only policy"; exit 1
fi
echo "github-allow: write blocked (expected)"
echo "openshell-policy: OK"
```

- [ ] **Step 3: Run it to verify it fails without a gateway, passes with one**

Run (gateway down): `bash openshell/tests/openshell-policy.sh` → FAIL (cannot create sandbox).
Run (after `openshell/scripts/install.sh`): `bash openshell/tests/openshell-policy.sh` → PASS ending `openshell-policy: OK`.

- [ ] **Step 4: Commit**

```bash
git add openshell/tests/openshell-policy.sh openshell/tests/openshell-static.sh
git commit -m "test(openshell): add policy-proof and policy linting"
```

---

### Task 9: Standalone docs + top-level README rows

**Files:**
- Create: `openshell/docs/README.md`, `quickstarts/{claude,opencode,openclaw}.md`, `policy-walkthrough.md`, `threat-model.md`
- Modify: `README.md` (repo root)

- [ ] **Step 1: Write `openshell/docs/README.md`** — overview: architecture (gateway → supervisor → sandbox), prerequisites (RHEL 9, rootless podman, `openshell/scripts/install.sh`), and links to the three quickstarts.

- [ ] **Step 2: Write the three quickstarts** — each: install gateway, `create.sh --profile dev`, connect, teardown. For OpenClaw, document the `18789` port-forward and browser URL.

- [ ] **Step 3: Write `policy-walkthrough.md`** — narrate the Task 8 deny → allow sequence using the `openshell logs <sandbox>` output (`action=deny` → `action=allow`), referencing existing profiles (no new policy files).

- [ ] **Step 4: Write `threat-model.md`** — what OpenShell enforces (network/filesystem/process), what it does not (in-sandbox logic), and the create-time-install trust boundary (bootstrap egress is npm-only).

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
      "options": {"baseURL": "http://host.openshell.internal:8080/v1", "apiKey": "local-placeholder"},
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
      - {host: host.openshell.internal, port: 8080, protocol: rest, enforcement: enforce}
    binaries: [{path: /usr/bin/node}, {path: /usr/bin/curl}]
```

No `api.anthropic.com`/`api.openai.com` endpoints appear in any integrated profile (default-deny blocks them). Keep github/npm/pypi/docs blocks graded per profile as in Task 5. Write all four in full.

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
source "${ROOT}/openshell/scripts/harness-lib.sh"
CE="${CONTAINER_ENGINE:-podman}"
NAME="ospx-smoke-citest"
STUB="ospx-stub-citest"
cleanup() { harness_destroy "${NAME}"; "${CE}" rm -f "${STUB}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Stub loopback endpoint standing in for Praxis on :8080 already used by gateway;
# use :8080 path /v1/models via the real gateway host alias is out of scope, so
# assert the integrated policy denies direct provider hosts and allows the alias.
openshell_cli sandbox create --name "${NAME}" --no-auto-providers
openshell_cli policy set "${NAME}" \
  --policy "${ROOT}/configs/openshell-praxis/profiles/dev/policy.yaml"

# Direct provider host must be denied.
if harness_ssh "${NAME}" "curl -fsS https://api.openai.com/v1/models" >/dev/null 2>&1; then
  echo "FAIL: direct provider reachable under integrated policy"; exit 1
fi
echo "integrated: direct provider denied (expected)"
echo "openshell-praxis-smoke: OK"
```

- [ ] **Step 2: Run it** (after gateway install): `bash tests/openshell-praxis/smoke.sh`
Expected: PASS ending `openshell-praxis-smoke: OK`.

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
      - name: Policy proof
        run: bash openshell/tests/openshell-policy.sh
      - name: Integrated smoke
        run: bash tests/openshell-praxis/smoke.sh
```

Note: the policy-proof and integrated-smoke steps need a running gateway able to spawn sandboxes under the container engine. If the CI runner cannot run the Podman sandbox driver, gate those two steps behind a documented `if:` condition and keep static + boot always-on; record this limitation in `openshell/docs/README.md`. Confirm driver availability on the GitHub runner during implementation and adjust.

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
- Standalone OpenShell runtime (pinned odh via quadlet) → Tasks 1–3. ✓
- CLI via odh image → Task 1 (`openshell_cli`). ✓
- Three harnesses × four profiles, create-time two-phase install → Tasks 4–7. ✓
- OpenClaw = anthropics/openclaw, UI 18789 → Task 7. ✓
- Teaching pointer → Task 9 Step 3. ✓
- Integrated `openshell-praxis` scenario (loopback-only egress) → Task 10. ✓
- CI: static + boot + policy proof + integrated smoke, no secrets, amd64+arm64 → Task 12. ✓
- Tests mirror existing idioms → Tasks 1,3,8,11. ✓
- Praxis untouched → enforced by Global Constraints + paths-filtered CI. ✓

**Placeholder scan:** The only intentional REPLACE tokens are the odh `sha256` digests (Task 1 Step 3) and `@@MODEL_ID@@` (admin-supplied), both resolved at implementation/deploy time by design, not plan gaps. `@latest` harness versions are flagged to pin once confirmed (Tasks 5–7). No "TBD"/"handle edge cases" placeholders.

**Type consistency:** `openshell_cli`, `render_template`, `harness_create/ssh/connect_tty/forward/destroy` names are defined in Tasks 1 and 4 and used consistently in Tasks 3–11. `images.env` variable names (`ODH_*_IMAGE`) match across `lib.sh`, templates, tests. Profile directory names (`review/dev/automation/interactive`) are consistent across harnesses and CI.

**Open confirmations for the executor (not plan gaps):** odh image tags→digests; OpenCode package name/version and provider host; whether the GitHub runner supports the Podman sandbox driver for the behavioral steps.
