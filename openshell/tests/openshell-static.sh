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
