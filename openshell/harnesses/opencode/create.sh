#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
# shellcheck disable=SC1091
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <review|dev|automation|interactive> [--name N]"
PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-opencode-${PROFILE}}"
harness_create "${NAME}" "${ODH_OPENCODE_IMAGE}" "${PROFILE_DIR}/policy.yaml"
note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
