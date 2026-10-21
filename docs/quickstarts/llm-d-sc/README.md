# llm-d-sc semantic-routing quickstart

This experimental quickstart runs the [llm-d-sc semantic-routing
demonstration](https://github.com/RMalone8/llm-d-sc-demo) with explicit Podman
networking. It does **not** use OpenShift, RHOAI, KServe, Routes, or `podman
compose`.

The deterministic test uses synthetic OpenAI-compatible backends. GitHub-hosted
CI proves image pins, container hardening, classifier readiness, prompt
extraction, Praxis routing, backend selection, Open WebUI integration, and the
trace API without downloading the Qwen weights or requiring a GPU. A separate
manual AWS scenario validates the same routing with real CPU and GPU vLLM
instances.

## Architecture

The optional browser path adds Open WebUI and a repository-owned trace relay:

```text
Open WebUI
  -> trace-ui :8080
  -> Praxis :8080
  -> llm-d-sc classifier :50051
  -> trace-ui backend relay :8081 or :8082
  -> synthetic vllm-cpu or vllm-gpu backend
```

The front relay records each request in SQLite, forwards it to Praxis, and
adds `X-Demo-Route` and `X-Demo-Classification` response headers. The two
backend relays record backend attempts with their timing, including failovers. The dashboard is at `/`, and the redacted JSON trace API is at `/_trace/api/traces`.

The validated AWS topology splits CPU and GPU work across two hosts:

```text
CPU host (m7i.4xlarge)
  Open WebUI + trace-ui + Praxis + llm-d-sc + vllm-cpu
        |
        | private VPC TCP/8000
        v
GPU host (g6.8xlarge)
  vllm-gpu only
```

This split is required for the selected AWS GPU shape: the G6 instance does
not provide the AVX-512 or AMX CPU instructions required by the pinned CPU
vLLM image. The CPU and GPU instances both serve the pinned
`RedHatAI/Qwen3.8-27B-INT4` model; llm-d-sc chooses the backend from prompt
complexity.

## Run the deterministic test

From an amd64 Linux host with Podman running:

```bash
python3 -B tests/llm-d-sc/unit.py
CONTAINER_ENGINE=podman python3 tests/llm-d-sc/integration.py
```

The integration test pulls immutable image digests, creates a temporary Podman
network and model volume, waits for the classifier to report `READY`, sends
one simple and one reasoning prompt through Open WebUI and the gateway, checks
the trace records, and removes the resources it created. The synthetic
backends also return OpenAI-compatible server-sent events so OpenCode's
streaming client follows the same path as non-streaming clients.

A successful run reports:

- `SIMPLE` with `x-llm-d-sc-status: OK`, routed to `vllm-cpu`.
- `REASONING` with `x-llm-d-sc-status: OK`, routed to `vllm-gpu`.
- Open WebUI health, model discovery, chat, and trace API checks passed.

On GitHub-hosted CI, the same path runs with Docker. It does not exercise real
vLLM generation, GPU scheduling, model quality, throughput, or latency.

## Run OpenCode through the routed backend

After the integration test prints the trace relay port, create an OpenShell
OpenCode workload that uses that relay as its only model gateway:

```bash
os_run env PRAXIS_PORT=PRINTED_TRACE_PORT \
  openshell/harnesses/opencode/create.sh \
  --profile dev \
  --name opencode-llm-d-sc \
  --config "$PWD/configs/llm-d-sc"
```

The template catalog supplies the `Semantic-Qwen` model ID. The sandbox can
contact only `host.openshell.internal:<trace-port>`, and the strict policy
permits only model discovery and chat completion. The trace relay records the
request and forwards it to Praxis. The provider marks the model as reasoning
but intentionally does not replay interleaved reasoning; Qwen's reasoning
parser can otherwise emit malformed content after tool calls.

## Run the AWS split-host scenario

This is a manual, billable scenario. Use two amd64 RHEL 9 hosts in the same
VPC with rootless Podman and at least 200 GiB of root disk on the CPU host and
300 GiB on the GPU host. The CPU host must expose AVX-512 or AMX. The GPU host
used for validation was a `g6.8xlarge` with one NVIDIA L4, the NVIDIA driver,
and a working CDI device (`nvidia.com/gpu=0`).

The sizing presets are:

- `configs/aws/llm-d-sc-webui-cpu.json`: `m7i.4xlarge`, 64 GiB RAM.
- `configs/aws/llm-d-sc-webui.json`: `g6.8xlarge`, one L4 GPU, 128 GiB RAM.

Grant only the CPU host's security group access to TCP/8000 on the GPU host's
security group. Do not expose the GPU port to the internet. Enable user
lingering on both hosts before starting detached rootless containers over
SSH:

```bash
sudo loginctl enable-linger "$USER"
```

On the GPU host, start only the GPU backend and publish it on its private VPC
address. Replace `GPU_PRIVATE_IP` with the GPU host's private IPv4 address:

```bash
CONTAINER_ENGINE=podman \
LLM_D_SC_BACKEND_TIMEOUT=720 \
python3 tests/llm-d-sc/integration.py \
  --real --gpu-only --gpu-publish-host GPU_PRIVATE_IP --keep
```

On the CPU host, run the complete stack against that endpoint:

```bash
CONTAINER_ENGINE=podman \
LLM_D_SC_BACKEND_TIMEOUT=720 \
python3 tests/llm-d-sc/integration.py \
  --real --remote-gpu GPU_PRIVATE_IP --keep
```

The successful test prints a loopback Open WebUI URL. Use an SSH tunnel from
your workstation to reach it, substituting the port from the result:

```bash
ssh -L 8080:127.0.0.1:PRINTED_WEBUI_PORT USER@CPU_PUBLIC_IP
```

Then open `http://127.0.0.1:8080` in a browser. The trace dashboard uses the
printed trace relay port in the same way.

Add `--cache-volume NAME` to either real command to reuse a named Podman
cache volume. This avoids downloading the approximately 18 GiB model weights
again after the first qualification run. A named cache is not removed by the
test's cleanup path.

## AWS validation record

The split-host scenario was validated on 2026-10-20 in `us-east-1`:

| Check | Result |
| --- | --- |
| CPU host | `m7i.4xlarge`, AVX-512 available, 64 GiB RAM |
| GPU host | `g6.8xlarge`, NVIDIA L4, driver 580.178.04 |
| Model | `RedHatAI/Qwen3.8-27B-INT4`, 18.12 GiB weights |
| Simple prompt | `SIMPLE` -> `vllm-cpu`, HTTP 200, 19.342 s |
| Reasoning prompt | `REASONING` -> `vllm-gpu`, HTTP 200, 10.086 s |
| Open WebUI | health, model list, and chat passed |
| Trace API | CPU and GPU routes both recorded |

These durations are single-request validation measurements, not a throughput
or latency benchmark. The GPU model load used about 16.84 GiB of VRAM and
steady serving used about 20.5 GiB. The real-mode requests explicitly disable
Qwen thinking for short validation prompts so the test receives final content
instead of consuming the token budget on hidden reasoning.

The OpenCode harness was separately validated on a disposable AWS
`m7i.2xlarge` RHEL 9.6 host with OpenShell v0.1.4 and the mocked CPU/GPU
backends. A simple prompt completed in one OpenCode turn and routed to
`vllm-cpu`; a reasoning prompt also completed in one turn and routed to
`vllm-gpu`.

## Security boundary

The shipped configuration keeps every host-published listener on loopback.
Praxis and the backends communicate over a private container network, while
the split-host GPU connection uses private VPC addressing and an exact
source-security-group rule.

The configuration sets `insecure_options.allow_private_upstreams: true`
because those backends have private addresses. This disables upstream SSRF
protection, so do not expose the listener publicly without an additional
reviewed network and authorization boundary.

`WEBUI_AUTH=false` is only for a disposable, loopback-only demonstration. A
shared deployment must enable authentication and place the UI behind an
appropriate HTTPS and authorization boundary. The trace relay stores recent
request prompts and model responses (capped at 16,000 characters) in a temporary SQLite database for observability;
treat its output as sensitive and do not expose it publicly.

## Temporary image

The first integration uses the upstream filter-enabled Praxis image by digest:

```text
quay.io/rmalone/praxis-llm-d-sc@sha256:5a72648501df1f414745442ca0e79ba5bff5c1d6b9238727f5f994755bc367d8
```

This is a temporary unblock. Issue
[#74](https://github.com/redhat-et/secure-single-server/issues/74) tracks
consolidating `llm_d_sc` into the repository's reviewed Praxis image. Do not
replace the digest with the upstream mutable `latest` tag.
