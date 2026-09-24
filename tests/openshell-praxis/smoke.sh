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
