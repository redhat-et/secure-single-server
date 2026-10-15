#!/usr/bin/env bash
set -euo pipefail

SANDBOX="${OPENSHELL_SANDBOX_NAME:-streamlit-demo}"

run_sandbox_command() {
  local command=$1
  local output
  local status

  set +e
  output="$(openshell sandbox exec \
    --name "${SANDBOX}" \
    --no-tty \
    --timeout 10 \
    -- bash -lc "${command}" 2>&1)"
  status=$?
  set -e
  SANDBOX_EXEC_STATUS=$status
  printf '%s\n' "${output}"
  return "${status}"
}

openshell sandbox provider list "${SANDBOX}"
if ! POSITIVE_OUTPUT="$(run_sandbox_command 'echo demo > /tmp/verify-write')"; then
  printf 'error: the sandbox could not perform the positive /tmp write control\n' >&2
  exit 1
fi
printf '%s\n' "${POSITIVE_OUTPUT}"
if DENIAL_OUTPUT="$(run_sandbox_command 'echo demo > /opt/openshell-demo/verify-leak')"; then
  printf 'error: the sandbox accepted a write to its application directory\n' >&2
  exit 1
fi
if ! printf '%s\n' "${DENIAL_OUTPUT}" | grep -Eq 'Permission denied|EACCES'; then
  printf 'error: the application-directory write failed without permission-denied evidence\n' >&2
  printf 'status: %s\n' "${SANDBOX_EXEC_STATUS}" >&2
  exit 1
fi
if READ_DENIAL_OUTPUT="$(run_sandbox_command 'cat /opt/openshell-demo-secret')"; then
  printf 'error: the sandbox accepted a read of the synthetic marker\n' >&2
  exit 1
fi
if ! printf '%s\n' "${READ_DENIAL_OUTPUT}" | grep -Eq 'Permission denied|EACCES'; then
  printf 'error: the synthetic-marker read failed without permission-denied evidence\n' >&2
  printf 'status: %s\n' "${SANDBOX_EXEC_STATUS}" >&2
  exit 1
fi
printf 'verified: OpenShell denied the application-directory write and synthetic-marker read\n'
