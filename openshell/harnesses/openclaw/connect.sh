#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="openclaw-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
# Launch the Control UI in the background, then forward its port.
harness_ssh "${NAME}" "nohup openclaw serve --port 18789 >/tmp/openclaw.log 2>&1 &" || true
harness_forward "${NAME}" 18789
