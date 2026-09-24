#!/usr/bin/env bash
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/lib.sh"
require_command podman

note "Enabling rootless podman socket for the gateway"
systemctl --user enable --now podman.socket

note "Configuring cgroup delegation for nested containers"
if [[ ! -f /etc/systemd/system/user@.service.d/delegate.conf ]]; then
  sudo mkdir -p /etc/systemd/system/user@.service.d
  sudo tee /etc/systemd/system/user@.service.d/delegate.conf > /dev/null << 'DELEGATE_EOF'
[Service]
Delegate=cpu cpuset io memory pids
DELEGATE_EOF
  sudo systemctl daemon-reload
  note "Cgroup delegation configured; restarting user session"
  sudo systemctl restart "user@$(id -u).service"
  sleep 2
else
  note "Cgroup delegation already configured"
fi

note "Preparing /var/lib/openshell (source==target bind path)"
sudo install -d -o "$(id -u)" -g "$(id -g)" /var/lib/openshell

note "Generating JWT signing keys for sandbox auth"
if [[ ! -f /var/lib/openshell/tls/jwt/signing.pem ]]; then
  podman run --rm --userns=keep-id \
    -e HOME=/var/lib/openshell -e XDG_DATA_HOME=/var/lib/openshell \
    -v /var/lib/openshell:/var/lib/openshell:z \
    "${ODH_GATEWAY_IMAGE}" generate-certs \
      --output-dir /var/lib/openshell/tls \
      --server-san 127.0.0.1 --server-san localhost --server-san host.openshell.internal
else
  note "JWT keys already exist, skipping generation"
fi

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

note "Installing openshell CLI binary for SSH proxy"
if [[ ! -f /usr/local/bin/openshell ]]; then
  _cli_cid="$(podman create "${ODH_CLI_IMAGE}")"
  podman cp "${_cli_cid}:/usr/local/bin/openshell" /tmp/openshell
  podman rm "${_cli_cid}"
  sudo install -m 755 /tmp/openshell /usr/local/bin/openshell
  rm /tmp/openshell
else
  note "openshell CLI binary already installed"
fi

note "Starting gateway"
systemctl --user daemon-reload
systemctl --user start openshell-gateway.service

note "Waiting for gateway health"
sleep 2

note "Registering CLI gateway 'local'"
openshell_cli gateway add http://127.0.0.1:8080 --name local
openshell_cli gateway select local
note "OpenShell gateway installed. Health: http://127.0.0.1:8081/healthz"
