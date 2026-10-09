#!/usr/bin/env bash
# One bounded local agent turn inside an existing OpenShell sandbox.
set -euo pipefail
H_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/harness-lib.sh
# shellcheck disable=SC1091
source "${H_DIR}/../../scripts/harness-lib.sh"
NAME=openclaw-dev
MESSAGE=""
TIMEOUT=600
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "missing value for $1"
  case "$1" in
    --name) NAME="$2" ;;
    --message) MESSAGE="$2" ;;
    --timeout) TIMEOUT="$2" ;;
    *) die "unknown arg: $1" ;;
  esac
  shift 2
done
[[ "${NAME}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]] || die 'invalid sandbox name'
[[ -n "${MESSAGE//[[:space:]]/}" ]] || die 'provide --message with a task'
if [[ ! "${TIMEOUT}" =~ ^[1-9][0-9]{0,3}$ ]] || (( TIMEOUT > 3600 )); then
  die 'timeout must be 1..3600 seconds'
fi
# The task travels through stdin, not an interpolated remote command.
printf '%s\n' "${MESSAGE}" | harness_ssh "${NAME}" \
  "mkdir -p /home/node/.openclaw/workspace && cd /home/node/.openclaw/workspace && HOME=/home/node SQLITE_TMPDIR=/tmp openclaw agent exec --config /home/node/.openclaw/openclaw.json --cwd /home/node/.openclaw/workspace --timeout ${TIMEOUT} --json --message-file -"
