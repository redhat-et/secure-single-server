#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
# shellcheck disable=SC1091
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""; BACKEND="anthropic"; CONFIG_DIR=""
while [[ $# -gt 0 ]]; do case "$1" in
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  --backend) BACKEND="$2"; shift 2;;
  --config) CONFIG_DIR="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <p> [--name N] [--backend openai|anthropic] [--config <dir>]"

if [[ -n "${CONFIG_DIR}" ]]; then
  # Integrated openshell-praxis flow: profile + provider config come from
  # <CONFIG_DIR> (e.g. configs/openshell-praxis) instead of this harness dir.
  [[ -d "${CONFIG_DIR}" ]] || die "no such config dir: ${CONFIG_DIR}"
  POLICY_SRC="${CONFIG_DIR}/profiles/${PROFILE}/policy.yaml"
  [[ -f "${POLICY_SRC}" ]] || die "no such profile in config dir: ${POLICY_SRC}"
  PROVIDER_SRC="${CONFIG_DIR}/harness-provider.json.in"
  [[ -f "${PROVIDER_SRC}" ]] || die "provider template not found: ${PROVIDER_SRC}"
  NAME="${NAME:-openclaw-${PROFILE}}"
  PRAXIS_PORT="${PRAXIS_PORT:-8080}"
  : "${OPENSHELL_MODEL_ID:?set OPENSHELL_MODEL_ID to the administrator-approved model id}"
  # Render @@PRAXIS_PORT@@ in the policy (mirrors tests/openshell-praxis/smoke.sh).
  POL="$(mktemp)"
  # shellcheck disable=SC2329
  # shellcheck disable=SC2317  # invoked via trap, not directly
  cleanup() { rm -f "${POL}"; }
  trap cleanup EXIT
  sed "s#@@PRAXIS_PORT@@#${PRAXIS_PORT}#g" "${POLICY_SRC}" > "${POL}"
  # Render the provider file next to the user. The correct in-sandbox provider
  # config path for OpenClaw cannot be determined with certainty from here (and
  # harness-provider.json.in is in OpenCode config format), so we do NOT push it
  # to an invented path. Print the exact command to install it once the OpenClaw
  # provider-config path is known.
  PROV="$(mktemp -t openclaw-praxis-provider.XXXXXX.json)"
  sed -e "s#@@PRAXIS_PORT@@#${PRAXIS_PORT}#g" \
      -e "s#@@MODEL_ID@@#${OPENSHELL_MODEL_ID}#g" "${PROVIDER_SRC}" > "${PROV}"
  harness_create "${NAME}" "${ODH_OPENCLAW_IMAGE}" "${POL}"
  note "Backend: ${BACKEND}. Rendered Praxis provider config written to: ${PROV}"
  note "Install it into the sandbox at OpenClaw's provider-config path with:"
  note "  source ${H_DIR}/../../scripts/harness-lib.sh"
  note "  harness_ssh ${NAME} 'cat > <OPENCLAW_PROVIDER_CONFIG_PATH>' < ${PROV}"
  note "Start UI + forward with: ${H_DIR}/connect.sh --name ${NAME}"
  exit 0
fi

PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-openclaw-${PROFILE}}"
harness_create "${NAME}" "${ODH_OPENCLAW_IMAGE}" "${PROFILE_DIR}/policy.yaml"
note "Backend: ${BACKEND}. Start UI + forward with: ${H_DIR}/connect.sh --name ${NAME}"
