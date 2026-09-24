# OpenClaw Quickstart

This guide walks through creating, connecting to, and tearing down an OpenClaw sandbox with OpenShell. OpenClaw provides a browser-based Control UI accessible via SSH port-forward.

## Prerequisites

- RHEL 9 with rootless Podman 4.6 or newer
- OpenShell gateway installed (run `openshell/scripts/install.sh` if not already installed)
- Provider API key available in your environment (see below)

## Provider Configuration

OpenClaw supports Anthropic Claude and OpenAI via environment variables. **Never commit API keys to the repository.**

Set one of the following before connecting:

```bash
# For Anthropic Claude
export ANTHROPIC_API_KEY='your-key-here'

# For OpenAI
export OPENAI_API_KEY='your-key-here'
```

Provider credentials are injected **only from the environment** at connect time and are **never stored** in the repository or configuration files.

The provider is selected via the `--backend` flag when creating the sandbox.

## Installation

Install the OpenShell gateway and pull the pinned OpenClaw image:

```bash
cd openshell
./scripts/install.sh
```

The installer will:
- Enable the rootless Podman socket
- Configure cgroup delegation for nested containers
- Generate JWT signing keys for sandbox authentication
- Pull pinned images including `quay.io/aipcc/base-images/agentic/openclaw@sha256:de12000bc8c251e868519bb86ed975458bf3f2ff63c6ebc2eece4bc769f14b69`
- Install the `openshell` CLI binary
- Start the gateway service

Verify the gateway is running:

```bash
curl http://127.0.0.1:8091/healthz
```

## About OpenClaw

OpenClaw is the standalone `github.com/openclaw/openclaw` project. It is **not** NemoClaw. OpenClaw provides a browser-based Control UI for interactive agent sessions.

## Create a Sandbox

Navigate to the OpenClaw harness directory:

```bash
cd harnesses/openclaw
```

Create a sandbox with the `dev` profile and Anthropic backend (default):

```bash
./create.sh --profile dev
```

Or specify OpenAI as the backend:

```bash
./create.sh --profile dev --backend openai
```

This creates a sandbox named `openclaw-dev` with:
- Read-write workspace access
- Network access to the model API, GitHub (read-only), and npm registry

Other available profiles: `review` (read-only), `automation` (CI/CD), `interactive` (full-featured with persistence).

To create a sandbox with a custom name:

```bash
./create.sh --profile dev --name my-session
```

## Connect to the Sandbox

Set your provider API key (see Provider Configuration above), then connect:

```bash
./connect.sh
```

Or for a custom-named sandbox:

```bash
./connect.sh --name my-session
```

This establishes an SSH connection with the OpenClaw Control UI running inside the sandbox and forwards port 18789 to your local machine. `connect.sh` forwards `OPENAI_API_KEY`/`ANTHROPIC_API_KEY` via `ssh SendEnv` (only variables set in your environment are sent). The sandbox image must `AcceptEnv` them for the credential to reach the harness; this is confirmed on the host during the smoke run (a host-validation step, like the `host.openshell.internal` reachability caveat), not by this repository.

## Access the Control UI

While connected, open your browser to:

```
http://127.0.0.1:18789
```

The Control UI provides an interactive interface for managing agent sessions, viewing logs, and controlling the OpenClaw environment.

## Teardown

From `openshell/scripts`, destroy the sandbox:

```bash
cd ../../scripts
source harness-lib.sh
harness_destroy openclaw-dev
```

Or for a custom-named sandbox:

```bash
harness_destroy my-session
```

## Policy Details

The `dev` profile enforces:

**Filesystem**:
- Read-write workspace access
- Read-only access to `/usr`, `/lib`, `/lib64`, `/etc`, `/proc`, `/opt`
- Read-write access to `/tmp`, `/dev/null`, `/home`

**Network** (per-binary allowlists):
- Model API endpoints (Anthropic or OpenAI, depending on `--backend`)
- GitHub API (read-only access)
- npm registry

**Landlock LSM**: Best-effort compatibility mode

See `harnesses/openclaw/profiles/dev/policy.yaml` for the complete policy definition.

## Next Steps

- Review the [Policy Walkthrough](../policy-walkthrough.md) to understand deny-by-default enforcement
- Read the [Threat Model](../threat-model.md) to understand what OpenShell protects and what it does not
- Explore other profiles (`review`, `automation`, `interactive`) in `harnesses/openclaw/profiles/`
