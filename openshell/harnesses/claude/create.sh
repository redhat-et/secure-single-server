#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
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
harness_create "${NAME}" "${PROFILE_DIR}" \
  "npm install -g @anthropic-ai/claude-code@2.1.281"
note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
