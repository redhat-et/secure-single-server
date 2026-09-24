#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
# shellcheck disable=SC1091
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""; CONFIG_DIR=""
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  --config) CONFIG_DIR="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <review|dev|automation|interactive> [--name N] [--config <dir>]"

if [[ -n "${CONFIG_DIR}" ]]; then
  # Integrated openshell-praxis flow: profile + provider config come from
  # <CONFIG_DIR> (e.g. configs/openshell-praxis) instead of this harness dir.
  [[ -d "${CONFIG_DIR}" ]] || die "no such config dir: ${CONFIG_DIR}"
  POLICY_SRC="${CONFIG_DIR}/profiles/${PROFILE}/policy.yaml"
  [[ -f "${POLICY_SRC}" ]] || die "no such profile in config dir: ${POLICY_SRC}"
  PROVIDER_SRC="${CONFIG_DIR}/harness-provider.json.in"
  [[ -f "${PROVIDER_SRC}" ]] || die "provider template not found: ${PROVIDER_SRC}"
  NAME="${NAME:-opencode-${PROFILE}}"
  PRAXIS_PORT="${PRAXIS_PORT:-8080}"
  : "${OPENSHELL_MODEL_ID:?set OPENSHELL_MODEL_ID to the administrator-approved model id}"
  # Render @@PRAXIS_PORT@@ in the policy (mirrors tests/openshell-praxis/smoke.sh).
  POL="$(mktemp)"; PROV="$(mktemp)"
  # shellcheck disable=SC2329
  cleanup() { rm -f "${POL}" "${PROV}"; }
  trap cleanup EXIT
  sed "s#@@PRAXIS_PORT@@#${PRAXIS_PORT}#g" "${POLICY_SRC}" > "${POL}"
  sed -e "s#@@PRAXIS_PORT@@#${PRAXIS_PORT}#g" \
      -e "s#@@MODEL_ID@@#${OPENSHELL_MODEL_ID}#g" "${PROVIDER_SRC}" > "${PROV}"
  harness_create "${NAME}" "${ODH_OPENCODE_IMAGE}" "${POL}"
  # OpenCode reads global provider config from ~/.config/opencode/opencode.json
  # (see https://opencode.ai/docs/config/); push the rendered file there.
  harness_ssh "${NAME}" 'mkdir -p ~/.config/opencode && cat > ~/.config/opencode/opencode.json' < "${PROV}"
  note "Provider config installed at ~/.config/opencode/opencode.json (Praxis loopback :${PRAXIS_PORT}, model ${OPENSHELL_MODEL_ID})"
  note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
  exit 0
fi

PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-opencode-${PROFILE}}"
harness_create "${NAME}" "${ODH_OPENCODE_IMAGE}" "${PROFILE_DIR}/policy.yaml"
note "Connect with: ${H_DIR}/connect.sh --name ${NAME}"
