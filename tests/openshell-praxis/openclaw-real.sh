#!/usr/bin/env bash
# Opt-in acceptance against an already-configured real Praxis upstream.
# Run as the OpenShell service owner; credentials remain with Praxis.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${OPENSHELL_MODEL_ID:?set the real served model ID}"
: "${OPENCLAW_TEST_CONFIG:?set the reviewed OpenClaw config directory}"
# shellcheck source=../../openshell/scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${ROOT}/openshell/scripts/harness-lib.sh"
name="oc-real-$$"
td="$(mktemp -d)"
cleanup() {
  local result=0
  harness_destroy "${name}" || result=1
  rm -rf "${td}"
  return "${result}"
}
cleanup_exit_status=0
trap 'cleanup_exit_status=$?; if ! cleanup && (( cleanup_exit_status == 0 )); then cleanup_exit_status=1; fi; exit "$cleanup_exit_status"' EXIT
"${ROOT}/openshell/harnesses/openclaw/create.sh" --profile dev \
  --name "${name}" --config "${OPENCLAW_TEST_CONFIG}"
"${ROOT}/openshell/harnesses/openclaw/run.sh" --name "${name}" --timeout 600 --message \
  'Use the write tool to create /home/node/.openclaw/workspace/acceptance.cjs with exactly this CommonJS code: module.exports = (a, b) => a + b; . Then use the read tool to read that file and report its contents. Do not create tests or execute commands. You must actually call both tools.' >"${td}/result.json"
python3 - "${td}/result.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get('ok') and r.get('final'), 'No successful final model response'
summary = r.get('toolSummary', {})
assert {'read', 'write'} <= set(summary.get('tools', [])), 'Missing real read/write tool calls'
assert summary.get('failures') == 0, 'A model tool call failed'
PY
# Trusted independent tests avoid treating model-authored assertions as proof.
harness_ssh "${name}" 'cd /home/node/.openclaw/workspace && test -s acceptance.cjs && node' <<'JS'
const test = require('node:test');
const assert = require('node:assert/strict');
const add = require('./acceptance.cjs');
test('positive operands', () => assert.equal(add(2, 3), 5));
test('opposite operands', () => assert.equal(add(-2, 2), 0));
test('zero operands', () => assert.equal(add(0, 0), 0));
JS
printf 'OpenClaw real-model acceptance passed: %s\n' "${OPENSHELL_MODEL_ID}"
