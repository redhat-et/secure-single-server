#!/usr/bin/env bash
# Run on a disposable RHEL host with an installed OpenShell service owner.
# Exercises actual OpenShell enforcement and pinned OpenClaw with a synthetic model.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../scripts/common/lib.sh
# shellcheck disable=SC1091
source "${ROOT}/scripts/common/lib.sh"
require_root
owner="${OPENSHELL_TEST_OWNER:-openshell-svc}"
uid="$(id -u "${owner}")"
name="oc-runtime-$$"
praxis="openclaw-runtime-praxis-$$"
td="$(mktemp -d /var/tmp/openclaw-runtime.XXXXXX)"
fixture_pid=""
os_run() {
  runuser -u "${owner}" -- env HOME="/var/lib/${owner}" \
    XDG_RUNTIME_DIR="/run/user/${uid}" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${uid}/bus" \
    OPENSHELL_MODEL_ID=fixture-model PRAXIS_PORT=18080 "$@"
}
cleanup() {
  local cleanup_result=0
  os_run python3 "${ROOT}/openshell/scripts/destroy-sandbox.py" \
    "${OPENSHELL_BIN:-/usr/local/bin/openshell}" "${name}" || cleanup_result=1
  podman rm -f "${praxis}" >/dev/null 2>&1 || true
  if [[ -n "${fixture_pid}" ]]; then kill "${fixture_pid}" 2>/dev/null || true; wait "${fixture_pid}" 2>/dev/null || true; fi
  rm -rf "${td}"
  return "${cleanup_result}"
}
on_exit() {
  result=$?
  if (( result != 0 )); then os_run "${OPENSHELL_BIN:-/usr/local/bin/openshell}" logs "${name}" --since 5m 2>/dev/null | tail -40 || true; fi
  if ! cleanup && (( result == 0 )); then result=1; fi
  exit "${result}"
}
trap on_exit EXIT
chmod 0755 "${td}"
python3 "${ROOT}/tests/openshell-praxis/openclaw-provider.py" --credentialless >"${td}/fixture.log" 2>&1 &
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
os_run "${ROOT}/openshell/harnesses/openclaw/create.sh" --profile dev \
  --name "${name}" --config "${ROOT}/configs/vllm/openclaw"
os_run "${ROOT}/openshell/harnesses/openclaw/run.sh" --name "${name}" \
  --timeout 120 --message 'Write the proof file with the write tool, then confirm completion.' >"${td}/result.json"
python3 - "${td}/result.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if not result.get('ok') or 'OPENCLAW_TOOL_OK' not in result.get('final', ''):
    raise SystemExit('OpenClaw did not report a successful tool continuation')
PY
# shellcheck disable=SC2016
os_run bash -c 'source "$1/openshell/scripts/harness-lib.sh"; harness_ssh "$2" "cat /home/node/.openclaw/workspace/openclaw-proof.txt"' \
  test "${ROOT}" "${name}" | grep -Fx OPENCLAW_TOOL_OK
# Prove an allowed Praxis request and explicit cloud/direct-fixture denials.
# shellcheck disable=SC2016
os_run bash -c 'source "$1/openshell/scripts/harness-lib.sh"; harness_ssh "$2" node --input-type=module' \
  test "${ROOT}" "${name}" <<'JS'
import { writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
if (process.env.OPENAI_API_KEY || process.env.ANTHROPIC_API_KEY) throw new Error('Unexpected provider key in sandbox');
try { await writeFile('/app/openshell-denied-proof.txt', 'must not write CLI code'); throw new Error('CLI application directory is writable'); }
catch (error) { if (error.code !== 'EACCES') throw error; }
const child = spawn('/bin/sleep', ['30'], { detached: true, stdio: 'ignore' });
await once(child, 'spawn');
const exited = once(child, 'exit');
try {
  process.kill(child.pid, 0);
  try { process.kill(-child.pid, 0); throw new Error('Process-group signal unexpectedly allowed'); }
  catch (error) { if (error.code !== 'EPERM') throw error; }
} finally {
  child.kill('SIGKILL');
  await exited;
}
const allowed = await fetch('http://host.openshell.internal:18080/v1/models');
if (!allowed.ok) throw new Error('Praxis positive control failed');
for (const url of ['http://host.openshell.internal:18000/v1/models', 'https://api.openai.com/v1/models']) {
  try { await fetch(url); throw new Error('Direct endpoint reachable: ' + url); }
  catch (error) { if (error.cause?.code !== 'EACCES') throw error; }
}
console.log('Praxis positive control, direct-route denials, application write denial, process-group denial, and credential isolation passed');
JS
printf 'OpenClaw OpenShell runtime: real streamed write tool, continuation, and policy controls passed\n'
