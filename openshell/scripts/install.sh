#!/usr/bin/env bash
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/lib.sh"
require_command podman

note "Enabling rootless podman socket for the gateway"
systemctl --user enable --now podman.socket

note "Preparing /var/lib/openshell (source==target bind path)"
sudo install -d -o "$(id -u)" -g "$(id -g)" /var/lib/openshell

note "Rendering gateway config and quadlet"
install -d "${HOME}/.config/openshell" "${HOME}/.config/containers/systemd"
render_template "${OS_DIR}/configs/gateway/gateway.toml.in" "${HOME}/.config/openshell/gateway.toml"
render_template "${OS_DIR}/configs/quadlet/openshell-gateway.container.in" \
  "${HOME}/.config/containers/systemd/openshell-gateway.container"
cp "${OS_DIR}/configs/quadlet/openshell.network" \
  "${HOME}/.config/containers/systemd/openshell.network"

note "Pulling pinned images"
for img in "${ODH_GATEWAY_IMAGE}" "${ODH_SUPERVISOR_IMAGE}" "${ODH_SANDBOX_IMAGE}" "${ODH_CLI_IMAGE}"; do
  podman pull "${img}"
done

note "Starting gateway"
systemctl --user daemon-reload
systemctl --user start openshell-gateway.service

note "Waiting for gateway health"
sleep 2

note "Registering CLI gateway 'local'"
openshell_cli gateway add http://127.0.0.1:8080 --name local
openshell_cli gateway select local
note "OpenShell gateway installed. Health: http://127.0.0.1:8081/healthz"
