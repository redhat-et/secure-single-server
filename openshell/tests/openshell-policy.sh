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
