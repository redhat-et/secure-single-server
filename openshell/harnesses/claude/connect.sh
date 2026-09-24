#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
# shellcheck source=../../scripts/harness-lib.sh
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME="claude-dev"
[[ "${1:-}" == "--name" ]] && NAME="$2"
harness_connect_tty "${NAME}" "claude"
