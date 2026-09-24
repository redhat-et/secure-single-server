#!/usr/bin/env bash
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./lib.sh
# shellcheck disable=SC1091
source "${OS_DIR}/scripts/lib.sh"
systemctl --user stop openshell-gateway.service 2>/dev/null || true
rm -f "${HOME}/.config/containers/systemd/openshell-gateway.container"
systemctl --user daemon-reload
note "OpenShell gateway removed. /var/lib/openshell left intact (contains caches)."
