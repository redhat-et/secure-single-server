# llm-d-sc semantic-routing quickstart

This experimental quickstart runs the [llm-d-sc semantic-routing
demonstration](https://github.com/RMalone8/llm-d-sc-demo) on one amd64 Linux
host with explicit Podman networking. It does **not** use OpenShift, RHOAI,
KServe, Routes, or `podman compose`.

The deterministic integration test uses two synthetic OpenAI-compatible
backends. It proves classifier readiness, prompt extraction, Praxis routing,
and backend selection without downloading a large vLLM model or requiring a
GPU:

```text
client -> Praxis -> llm-d-sc -> vllm-cpu or vllm-gpu mock backend
```

## Run the integration test

From a reviewed checkout on an amd64 host with Podman running:

```bash
CONTAINER_ENGINE=podman python3 tests/llm-d-sc/integration.py
```

The test pulls immutable image digests, creates a temporary Podman network and
model volume, waits for the classifier to report `READY`, sends one simple and
one reasoning prompt, and removes all resources it created.

A successful run reports:

- `SIMPLE` with `x-llm-d-sc-status: OK`, routed to `vllm-cpu`.
- `REASONING` with `x-llm-d-sc-status: OK`, routed to `vllm-gpu`.

On GitHub-hosted CI, the same test runs with Docker. It does not exercise real
vLLM generation, GPU scheduling, or model quality.

## Temporary image

The first integration uses the upstream filter-enabled Praxis image by digest:

```text
quay.io/rmalone/praxis-llm-d-sc@sha256:5a72648501df1f414745442ca0e79ba5bff5c1d6b9238727f5f994755bc367d8
```

This is a temporary unblock. Issue
[#74](https://github.com/redhat-et/secure-single-server/issues/74) tracks
consolidating `llm_d_sc` into the repository's reviewed Praxis image. Do not
replace the digest with the upstream mutable `latest` tag.

## Security boundary

The shipped configuration keeps the host-published Praxis listener on loopback
and places all backends on a private container network. It sets
`insecure_options.allow_private_upstreams: true` because those backends have
private addresses. This disables upstream SSRF protection, so do not expose the
listener publicly without an additional reviewed network and authorization
boundary.

Real CPU and GPU vLLM scenarios are intentionally separate. They require pinned
vLLM images, model artifacts, GPU runtime and CDI qualification, and capacity
planning beyond this deterministic routing test.
