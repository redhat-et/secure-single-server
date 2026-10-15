#!/usr/bin/env bash
set -euo pipefail

DEMO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SANDBOX="${OPENSHELL_SANDBOX_NAME:-streamlit-demo}"
IMAGE="${STREAMLIT_DEMO_IMAGE:-openshell-streamlit-demo:safe}"
PROVIDER="${STREAMLIT_DEMO_PROVIDER:?export STREAMLIT_DEMO_PROVIDER, for example streamlit-demo-openai}"
MODEL_BASE_URL="${MODEL_BASE_URL:?export MODEL_BASE_URL, for example https://api.openai.com/v1}"
OPENAI_MODEL="${OPENAI_MODEL:?export OPENAI_MODEL, for example gpt-5.5}"

cd "${DEMO_DIR}"
podman build -t "${IMAGE}" .
openshell service delete "${SANDBOX}" streamlit >/dev/null 2>&1 || true
if openshell sandbox list --names | grep -Fx "${SANDBOX}" >/dev/null; then
  openshell sandbox delete "${SANDBOX}" >/dev/null
fi
for _ in $(seq 1 30); do
  if ! openshell sandbox list --names | grep -Fx "${SANDBOX}" >/dev/null; then
    break
  fi
  sleep 1
done
if openshell sandbox list --names | grep -Fx "${SANDBOX}" >/dev/null; then
  printf 'error: sandbox %s did not finish deleting\n' "${SANDBOX}" >&2
  exit 1
fi
openshell sandbox create \
  --name "${SANDBOX}" \
  --from "${IMAGE}" \
  --policy policy.yaml \
  --provider "${PROVIDER}" \
  --detach \
  --no-tty \
  --env DEMO_MODE=safe \
  --env MODEL_BASE_URL="${MODEL_BASE_URL}" \
  --env OPENAI_MODEL="${OPENAI_MODEL}" \
  --env DEMO_MARKER=demo-not-a-real-secret \
  --env HOME=/tmp \
  --env STREAMLIT_SERVER_FILE_WATCHER_TYPE=none \
  --env STREAMLIT_BROWSER_GATHER_USAGE_STATS=false \
  -- /usr/local/bin/python3 -m streamlit run /opt/openshell-demo/app.py \
    --server.port=8501 \
    --server.address=0.0.0.0 \
    --server.corsAllowedOrigins "http://default--${SANDBOX}--streamlit.openshell.localhost:8090" \
    --server.headless=true

openshell service expose "${SANDBOX}" 8501 streamlit
