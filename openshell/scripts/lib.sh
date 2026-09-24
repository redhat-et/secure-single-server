#!/usr/bin/env bash
set -euo pipefail
OPENSHELL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd -- "${OPENSHELL_DIR}/.." && pwd)"
# shellcheck source=../../scripts/common/lib.sh
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/common/lib.sh"
# shellcheck source=../configs/images.env
# shellcheck disable=SC1091
source "${OPENSHELL_DIR}/configs/images.env"

CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

render_template() {  # <template.in> <output>
  local in="$1" out="$2"
  sed \
    -e "s#@@ODH_GATEWAY_IMAGE@@#${ODH_GATEWAY_IMAGE}#g" \
    -e "s#@@ODH_SUPERVISOR_IMAGE@@#${ODH_SUPERVISOR_IMAGE}#g" \
    -e "s#@@ODH_SANDBOX_IMAGE@@#${ODH_SANDBOX_IMAGE}#g" \
    -e "s#@@ODH_CLI_IMAGE@@#${ODH_CLI_IMAGE}#g" \
    "${in}" > "${out}"
}

# Run the openshell CLI from the pinned odh CLI image against the local gateway.
openshell_cli() {
  "${CONTAINER_ENGINE}" run --rm --network host \
    -v "${HOME}/.config/openshell:/home/openshell/.config/openshell:z" \
    "${ODH_CLI_IMAGE}" "$@"
}
