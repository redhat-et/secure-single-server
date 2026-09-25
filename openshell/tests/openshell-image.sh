#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OS_DIR="${ROOT}/openshell"
CE="${CONTAINER_ENGINE:-podman}"
# shellcheck source=../scripts/lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/lib.sh"
# Default XDG_RUNTIME_DIR so the podman socket path resolves under set -u.
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
NAME=openshell-gateway-citest
# shellcheck disable=SC2329
# shellcheck disable=SC2317  # invoked via trap, not directly
cleanup() { "${CE}" rm -f "${NAME}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

td="$(mktemp -d)"
render_template "${OS_DIR}/configs/gateway/gateway.toml.in" "${td}/gateway.toml"

run_args=(run -d --name "${NAME}" --network host --security-opt label=disable)
# --userns=keep-id is a podman flag (docker rejects it as an invalid USER mode).
[[ "${CE}" == *podman* ]] && run_args+=(--userns=keep-id)
run_args+=(
  -v "${td}/gateway.toml:/etc/openshell/gateway.toml:ro"
  -v /var/lib/openshell:/var/lib/openshell
)
# Mount the rootless podman socket only when it exists; the gateway needs it to
# spawn sandboxes, but the health check below does not, so a missing socket must
# surface as a health failure rather than a container-run mount error.
sock="${XDG_RUNTIME_DIR}/podman/podman.sock"
[[ -S "${sock}" ]] && run_args+=(-v "${sock}:/run/podman/podman.sock")
run_args+=(
  -e OPENSHELL_GATEWAY_CONFIG=/etc/openshell/gateway.toml
  -e OPENSHELL_DB_URL="sqlite:/var/lib/openshell/gateway.db?mode=rwc"
  -e XDG_DATA_HOME=/var/lib/openshell -e HOME=/var/lib/openshell
  "${ODH_GATEWAY_IMAGE}"
)
"${CE}" "${run_args[@]}"

for _ in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:8091/healthz >/dev/null 2>&1; then
    printf 'openshell-image: healthz OK\n'; exit 0
  fi
  sleep 2
done
printf 'FAIL: gateway never became healthy\n' >&2; exit 1
