#!/usr/bin/env bash
# Run on a disposable RHEL host with an installed OpenShell service owner.
# Exercises actual OpenShell enforcement and pinned OpenCode with a synthetic model.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/common/lib.sh
# shellcheck disable=SC1091
source "${ROOT}/scripts/common/lib.sh"
require_root
owner="${OPENSHELL_TEST_OWNER:-openshell-svc}"
uid="$(id -u "${owner}")"
name="code-runtime-$$"
praxis="opencode-runtime-praxis-$$"
td="$(mktemp -d /var/tmp/opencode-runtime.XXXXXX)"
fixture_pid=""
os_run() {
  runuser -u "${owner}" -- env HOME="/var/lib/${owner}" \
    XDG_RUNTIME_DIR="/run/user/${uid}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
    OPENSHELL_MODEL_ID=fixture-model PRAXIS_PORT=18080 "$@"
}
cleanup() {
  os_run "${OPENSHELL_BIN:-/usr/local/bin/openshell}" sandbox delete "${name}" >/dev/null 2>&1 || true
  podman rm -f "${praxis}" >/dev/null 2>&1 || true
  if [[ -n "${fixture_pid}" ]]; then kill "${fixture_pid}" 2>/dev/null || true; wait "${fixture_pid}" 2>/dev/null || true; fi
  rm -rf "${td}"
}
on_exit() {
  result=$?
  if (( result != 0 )); then os_run "${OPENSHELL_BIN:-/usr/local/bin/openshell}" logs "${name}" --since 5m 2>/dev/null | tail -40 || true; fi
  cleanup
}
trap on_exit EXIT
chmod 0755 "${td}"
python3 "${ROOT}/tests/openshell-praxis/opencode-provider.py" >"${td}/fixture.log" 2>&1 &
fixture_pid=$!
# Require readiness from this process, rather than accidentally using an old fixture.
for ((attempt=0; attempt<30; attempt++)); do
  if grep -q '^fixture ready$' "${td}/fixture.log"; then break; fi
  if ! kill -0 "${fixture_pid}" 2>/dev/null; then cat "${td}/fixture.log" >&2; exit 1; fi
  sleep 1
done
grep -q '^fixture ready$' "${td}/fixture.log" || { cat "${td}/fixture.log" >&2; exit 1; }
sed -e 's/127.0.0.1:8080/127.0.0.1:18080/g' -e 's/127.0.0.1:8000/127.0.0.1:18000/g' \
  "${ROOT}/configs/vllm/praxis.yaml" >"${td}/praxis.yaml"
chmod 0644 "${td}/praxis.yaml"
podman run -d --name "${praxis}" --network=host --user=1001:1001 \
  --read-only --cap-drop=all --security-opt=no-new-privileges \
  -v "${td}/praxis.yaml:/etc/praxis/runtime.yaml:ro,Z" \
  "${DEFAULT_PRAXIS_IMAGE}" -c /etc/praxis/runtime.yaml >/dev/null
curl --fail --silent --retry 30 --retry-connrefused --retry-delay 1 \
  http://127.0.0.1:18080/v1/models >/dev/null
os_run "${ROOT}/openshell/harnesses/opencode/create.sh" --profile dev \
  --name "${name}" --config "${ROOT}/configs/vllm/harness"
# shellcheck disable=SC2016
os_run timeout 180 bash -c 'source "$1/openshell/scripts/harness-lib.sh"; harness_ssh "$2" "cd /sandbox && opencode run --format json --model praxis/fixture-model \"Write the proof script, run it with bash, then confirm completion.\""' \
  test "${ROOT}" "${name}" >"${td}/result.jsonl"
python3 - "${td}/result.jsonl" <<'PYVERIFY'
import json, sys
items = [json.loads(line) for line in open(sys.argv[1]) if line.strip().startswith('{')]
if any(item.get('type') == 'error' for item in items):
    raise SystemExit('OpenCode reported an error')
if not any(item.get('type') == 'text' and 'OPENCODE_TOOL_OK' in item.get('part', {}).get('text', '') for item in items):
    raise SystemExit('OpenCode did not report successful tool continuation')
PYVERIFY
# Independent readback proves the model's write and command tools both ran.
# shellcheck disable=SC2016
os_run bash -c 'source "$1/openshell/scripts/harness-lib.sh"; harness_ssh "$2" "cat /sandbox/opencode-exec-proof.txt"' \
  test "${ROOT}" "${name}" | grep -Fx OPENCODE_TOOL_OK
# Prove an allowed Praxis request and explicit cloud/direct-fixture denials.
# shellcheck disable=SC2016
os_run bash -c 'source "$1/openshell/scripts/harness-lib.sh"; harness_ssh "$2" node --input-type=module' \
  test "${ROOT}" "${name}" <<'JS'
if (process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY) throw new Error('Unexpected provider key in sandbox');
const allowed = await fetch('http://host.openshell.internal:18080/v1/models');
if (!allowed.ok) throw new Error('Praxis positive control failed');
for (const url of ['http://host.openshell.internal:18000/v1/models', 'https://api.openai.com/v1/models']) {
  try { await fetch(url); throw new Error('Direct endpoint reachable: ' + url); }
  catch (error) { if (error.cause?.code !== 'EACCES') throw error; }
}
console.log('Praxis positive control, direct-route denials, credential isolation passed');
JS
printf 'OpenCode OpenShell runtime: real streamed write and bash tools, continuation, and policy controls passed\n'
