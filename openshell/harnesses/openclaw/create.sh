#!/usr/bin/env bash
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${H_DIR}/../../scripts/harness-lib.sh"
# shellcheck source=../../configs/images.env
# shellcheck disable=SC1091
source "${OPENSHELL_DIR:-${H_DIR}/../..}/configs/images.env"
PROFILE=""; NAME=""; HARNESS_CONFIG_DIR=""; PROVIDER=""; POLICY_ADVISOR=no
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --policy-advisor ]]; then POLICY_ADVISOR=yes; shift; continue; fi
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "missing value for $1"
  case "$1" in
  --provider) PROVIDER="$2"; shift 2;;
  --profile) PROFILE="$2"; shift 2;;
  --name) NAME="$2"; shift 2;;
  --config) HARNESS_CONFIG_DIR="$2"; shift 2;;
  *) die "unknown arg: $1";;
esac; done
[[ -n "${PROFILE}" ]] || die "usage: create.sh --profile <p> [--name N] [--config <dir>] [--policy-advisor]"

case "${PROFILE}" in review|dev|automation|interactive) ;; *) die "no such profile: ${PROFILE}" ;; esac
[[ "${NAME:-sandbox}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || die "invalid sandbox name"

if [[ -n "${HARNESS_CONFIG_DIR}" ]]; then
  [[ -z "${PROVIDER}" ]] || die "integrated mode cannot attach a direct provider"
  [[ "${PROFILE}" == dev ]] || die 'OpenClaw Praxis integration supports only the dev profile'
  POLICY_SRC="${HARNESS_CONFIG_DIR}/profiles/${PROFILE}/policy.yaml"
  PROVIDER_SRC="${HARNESS_CONFIG_DIR}/harness-provider.json.in"
  [[ -f "${POLICY_SRC}" && -f "${PROVIDER_SRC}" ]] || die 'OpenClaw integration requires a policy and provider template'
  : "${OPENSHELL_MODEL_ID:?set OPENSHELL_MODEL_ID to the administrator-approved model id}"
  PRAXIS_PORT="${PRAXIS_PORT:-8080}"
  validate_praxis_port
  PRAXIS_API_PREFIX="${PRAXIS_API_PREFIX:-}"
  if [[ -n "${PRAXIS_API_PREFIX}" && "${PRAXIS_API_PREFIX}" != /vllm &&
        ! "${PRAXIS_API_PREFIX}" =~ ^/providers/[a-z][a-z0-9-]{0,31}$ ]]; then
    die 'PRAXIS_API_PREFIX must be empty, /vllm, or /providers/LOWERCASE-SLUG'
  fi
  NAME="${NAME:-openclaw-${PROFILE}}"
  POL="$(mktemp)"; PROV="$(mktemp)"
  # shellcheck disable=SC2329,SC2317 # cleanup is invoked by the EXIT trap
  cleanup() { rm -f "${POL}" "${PROV}"; }
  trap cleanup EXIT
  sed "s#@@PRAXIS_PORT@@#${PRAXIS_PORT}#g" "${POLICY_SRC}" >"${POL}"
  python3 "${H_DIR}/../../scripts/render-openclaw.py" \
    "${PROVIDER_SRC}" "${PROV}" "${PRAXIS_PORT}" "${OPENSHELL_MODEL_ID}" "${PRAXIS_API_PREFIX}"
  harness_create "${NAME}" "${ODH_OPENCLAW_IMAGE}" "${POL}" "" "${POLICY_ADVISOR}"
  # The pinned supervisor's first provider-environment poll advances its policy
  # generation even with no providers. Starting a long stream before this poll
  # causes an intentional stale-generation disconnect and uncertain client cleanup.
  initialized=no
  for (( attempt=0; attempt<30; attempt++ )); do
    settings_log="$(_os logs "${NAME}")"
    if [[ "${settings_log}" == *provider_env_changed:true* ]]; then
      initialized=yes
      break
    fi
    sleep 1
  done
  [[ "${initialized}" == yes ]] || die 'OpenShell initial settings poll did not settle; sandbox created but model configuration not installed'
  harness_ssh "${NAME}" 'umask 077; mkdir -p ~/.openclaw && cat > ~/.openclaw/openclaw.json' <"${PROV}"
  note "OpenClaw Praxis configuration installed; run with openshell/harnesses/openclaw/run.sh --name ${NAME} --message <task>"
  exit 0
fi

PROFILE_DIR="${H_DIR}/profiles/${PROFILE}"
[[ -d "${PROFILE_DIR}" ]] || die "no such profile: ${PROFILE}"
NAME="${NAME:-openclaw-${PROFILE}}"
harness_create "${NAME}" "${ODH_OPENCLAW_IMAGE}" "${PROFILE_DIR}/policy.yaml" "${PROVIDER}" "${POLICY_ADVISOR}"
note "Open a shell with: ${H_DIR}/connect.sh --name ${NAME}"
