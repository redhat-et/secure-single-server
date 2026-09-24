#!/usr/bin/env bash
set -euo pipefail
_HL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
# shellcheck source=./lib.sh
source "${_HL_DIR}/lib.sh"

: "${OPENSHELL_BIN:=/usr/local/bin/openshell}"
: "${OPENSHELL_GATEWAY_NAME:=local}"
: "${OPENSHELL_SANDBOX_USER:=sandbox}"

_os() { "${OPENSHELL_BIN}" "$@"; }

# Build the ssh ProxyCommand for a sandbox (native ssh-proxy, name mode).
_proxy_cmd() {  # <sandbox>
  printf '%s ssh-proxy --gateway-name %s --name %s' \
    "${OPENSHELL_BIN}" "${OPENSHELL_GATEWAY_NAME}" "$1"
}

harness_ssh() {  # <sandbox> <cmd...>
  local name="$1"; shift
  # SendEnv forwards the provider credentials that are set in the caller's
  # environment; unset vars are silently skipped. The sandbox sshd must
  # AcceptEnv them (see threat model / quickstart host-validation note).
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o SendEnv=OPENAI_API_KEY -o SendEnv=ANTHROPIC_API_KEY \
    -o "ProxyCommand=$(_proxy_cmd "${name}")" \
    "${OPENSHELL_SANDBOX_USER}@${name}" "$@"
}

harness_connect_tty() {  # <sandbox> [cmd...]
  local name="$1"; shift || true
  # SendEnv forwards the provider credentials that are set in the caller's
  # environment; unset vars are silently skipped. The sandbox sshd must
  # AcceptEnv them (see threat model / quickstart host-validation note).
  ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o SendEnv=OPENAI_API_KEY -o SendEnv=ANTHROPIC_API_KEY \
    -o "ProxyCommand=$(_proxy_cmd "${name}")" \
    "${OPENSHELL_SANDBOX_USER}@${name}" "$@"
}

harness_forward() {  # <sandbox> <port>
  local name="$1" port="$2"
  note "Forwarding 127.0.0.1:${port} -> sandbox ${name}:${port} (Ctrl-C to stop)"
  ssh -N -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o "ProxyCommand=$(_proxy_cmd "${name}")" \
    -L "127.0.0.1:${port}:127.0.0.1:${port}" \
    "${OPENSHELL_SANDBOX_USER}@${name}"
}

harness_destroy() { _os sandbox delete "$1" >/dev/null 2>&1 || true; }

# Wait until the sandbox reports phase Ready (or fail on Error/timeout).
_wait_ready() {  # <sandbox>
  local name="$1" ph _
  for _ in $(seq 1 40); do
    ph="$(_os sandbox list 2>/dev/null | awk -v n="${name}" '$1==n{print $NF}')"
    case "${ph}" in
      Ready) return 0;;
      Error) die "sandbox ${name} entered Error phase";;
    esac
    sleep 15
  done
  die "sandbox ${name} did not reach Ready in time"
}

# Single-phase create: harness is pre-installed in <image_ref>.
harness_create() {  # <name> <image_ref> <policy_file>
  local name="$1" image="$2" policy="$3"
  require_command ssh
  [[ -f "${policy}" ]] || die "policy file not found: ${policy}"
  note "Creating sandbox ${name} from ${image##*/}"
  _os sandbox create --name "${name}" --from "${image}" --policy "${policy}"
  _wait_ready "${name}"
  note "Sandbox ${name} ready"
}
