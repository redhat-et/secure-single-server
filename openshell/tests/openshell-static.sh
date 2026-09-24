#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
# shellcheck source=../scripts/lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/lib.sh"

# 1. images.env must define four @sha256-pinned odh images.
# (images.env already sourced by lib.sh)
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

# 3. Gateway quadlet template renders with no leftover placeholders.
tmp="$(mktemp)"
render_template "${OS_DIR}/configs/quadlet/openshell-gateway.container.in" "${tmp}"
grep -q '@@' "${tmp}" && fail "unrendered placeholder in gateway quadlet"
grep -q "Image=${ODH_GATEWAY_IMAGE}" "${tmp}" || fail "gateway image not pinned in unit"
grep -q 'Pull=never' "${tmp}" || fail "gateway unit must set Pull=never"
rm -f "${tmp}"

# 4. gateway.toml.in renders with podman driver and pinned sandbox/supervisor images.
gt="$(mktemp)"
render_template "${OS_DIR}/configs/gateway/gateway.toml.in" "${gt}"
grep -q '@@' "${gt}" && fail "unrendered placeholder in gateway.toml"
grep -q 'compute_driver *= *"podman"' "${gt}" || fail "gateway.toml not podman driver"
grep -q "supervisor_image *= *\"${ODH_SUPERVISOR_IMAGE}\"" "${gt}" || fail "supervisor image not pinned"
grep -q "default_image *= *\"${ODH_SANDBOX_IMAGE}\"" "${gt}" || fail "sandbox image not pinned"
rm -f "${gt}"

printf 'openshell-static: OK\n'
