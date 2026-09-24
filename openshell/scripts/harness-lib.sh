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

# Two-phase create: bootstrap egress -> install harness -> lock to profile.
harness_create() {  # <harness> <name> <profile_dir> <bootstrap_policy> <install_cmd>
  local harness="$1" name="$2" profile_dir="$3" bootstrap="$4" install_cmd="$5"
  require_command ssh
  note "Creating default-deny sandbox ${name} for ${harness}"
  openshell_cli sandbox create --name "${name}" --no-auto-providers
  note "Bootstrap phase: opening install source only"
  openshell_cli policy set "${name}" --policy "${bootstrap}"
  note "Installing pinned harness"
  harness_ssh "${name}" "${install_cmd}"
  note "Demo phase: applying ${profile_dir##*/} profile policy"
  openshell_cli policy set "${name}" --policy "${profile_dir}/policy.yaml"
  note "Sandbox ${name} ready under ${profile_dir##*/} profile"
}
