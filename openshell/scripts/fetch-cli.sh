#!/usr/bin/env bash
# Download the architecture-matched, checksum-pinned upstream CLI release.
set -euo pipefail
OS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../configs/images.env
# shellcheck disable=SC1091
source "${OS_DIR}/configs/images.env"
[[ $# == 1 && -d "$1" ]] || { echo 'usage: fetch-cli.sh OUTPUT_DIRECTORY' >&2; exit 1; }
case "$(uname -m)" in
  x86_64) architecture=x86_64; digest="${OPENSHELL_CLI_SHA256_AMD64}" ;;
  aarch64|arm64) architecture=aarch64; digest="${OPENSHELL_CLI_SHA256_ARM64}" ;;
  *) echo 'unsupported CLI architecture' >&2; exit 1 ;;
esac
[[ "$(uname -s)" == Linux ]] || { echo 'the release CLI requires Linux' >&2; exit 1; }
td="$(mktemp -d)"
trap 'rm -rf "${td}"' EXIT
asset="openshell-${architecture}-unknown-linux-musl.tar.gz"
curl --fail --show-error --silent --location --retry 3 --retry-all-errors \
  --connect-timeout 10 --max-time 120 \
  "https://github.com/NVIDIA/OpenShell/releases/download/${OPENSHELL_CLI_VERSION}/${asset}" \
  -o "${td}/cli.tar.gz"
printf '%s  %s\n' "${digest}" "${td}/cli.tar.gz" | sha256sum -c - >/dev/null
tar -xzf "${td}/cli.tar.gz" -C "${td}"
install -m 0755 "${td}/openshell" "$1/openshell"
