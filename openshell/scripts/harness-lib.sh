#!/usr/bin/env bash
set -euo pipefail
_HL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
# shellcheck source=./lib.sh
source "${_HL_DIR}/lib.sh"

_ssh_config() {  # <sandbox> -> prints a temp ssh config path
  local name="$1" cfg; cfg="$(mktemp)"
  openshell_cli sandbox ssh-config "${name}" > "${cfg}"
  printf '%s\n' "${cfg}"
}

harness_ssh() {  # <sandbox> <cmd...>
  local name="$1"; shift
  local cfg host; cfg="$(_ssh_config "${name}")"
  host="$(awk '/^Host /{print $2; exit}' "${cfg}")"
  ssh -F "${cfg}" "${host}" "$@"
  rm -f "${cfg}"
}

harness_connect_tty() {  # <sandbox> [cmd]
  local name="$1"; shift || true
  local cfg host; cfg="$(_ssh_config "${name}")"
  host="$(awk '/^Host /{print $2; exit}' "${cfg}")"
  ssh -tF "${cfg}" "${host}" "$@"
  rm -f "${cfg}"
}

harness_forward() {  # <sandbox> <port>
  local name="$1" port="$2"
  local cfg host; cfg="$(_ssh_config "${name}")"
  host="$(awk '/^Host /{print $2; exit}' "${cfg}")"
  note "Forwarding 127.0.0.1:${port} -> sandbox ${name}:${port} (Ctrl-C to stop)"
  ssh -NF "${cfg}" -L "127.0.0.1:${port}:127.0.0.1:${port}" "${host}"
  rm -f "${cfg}"
}

harness_destroy() { openshell_cli sandbox delete "$1" 2>/dev/null || true; }

# Two-phase create with policy update:
# 1. Create sandbox with profile policy (filesystem immutable from birth)
# 2. Add temporary npm network egress for install
# 3. Run install (npm needs registry.npmjs.org)
# 4. Remove npm network egress (lock to profile)
harness_create() {  # <name> <profile_dir> <install_cmd>
  local name="$1" profile_dir="$2" install_cmd="$3"
  require_command ssh

  # Copy profile policy to CLI-accessible location
  install -d "${HOME}/.config/openshell/policies"
  cp "${profile_dir}/policy.yaml" "${HOME}/.config/openshell/policies/${name}-profile.yaml"

  note "Creating sandbox ${name} with ${profile_dir##*/} profile policy"
  openshell_cli sandbox create --name "${name}" --no-auto-providers \
    --policy "/home/openshell/.config/openshell/policies/${name}-profile.yaml"

  note "Bootstrap phase: adding npm registry egress for install"
  openshell_cli policy update "${name}" \
    --add-endpoint "registry.npmjs.org:443:read-only:rest:enforce" \
    --binary /usr/bin/node --binary /usr/bin/npm --binary /usr/bin/curl

  note "Installing pinned harness"
  harness_ssh "${name}" "${install_cmd}"

  note "Locking to profile: removing npm registry egress"
  openshell_cli policy update "${name}" --remove-endpoint "registry.npmjs.org:443"

  note "Sandbox ${name} ready under ${profile_dir##*/} profile"
}
