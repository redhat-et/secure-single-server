# OpenCode Quickstart

This guide walks through creating, connecting to, and tearing down an OpenCode sandbox with OpenShell.

## Prerequisites

- RHEL 9 with rootless Podman 4.6 or newer
- OpenShell gateway installed (run `openshell/scripts/install.sh` if not already installed)
- Provider API key available in your environment (see below)

## Provider Configuration

OpenCode supports multiple LLM providers via environment variables. **Never commit API keys to the repository.**

Set one of the following before connecting:

```bash
# For Anthropic Claude
export ANTHROPIC_API_KEY='your-key-here'

# For OpenAI
export OPENAI_API_KEY='your-key-here'

# For custom endpoints
export ANTHROPIC_BASE_URL='https://inference.local/v1'
export ANTHROPIC_API_KEY='your-key-here'
```

Provider credentials are injected **only from the environment** at connect time and are **never stored** in the repository or configuration files.

## Installation

Install the OpenShell gateway and pull the pinned OpenCode image:

```bash
cd openshell
./scripts/install.sh
```

The installer will:
- Enable the rootless Podman socket
- Configure cgroup delegation for nested containers
- Generate JWT signing keys for sandbox authentication
- Pull pinned images including `quay.io/aipcc/base-images/agentic/opencode@sha256:5743452ce2dde8d91d3d8998d8667efa45da27e53c170dbd614516603a44d7d3`
- Install the `openshell` CLI binary
- Start the gateway service

Verify the gateway is running:

```bash
curl http://127.0.0.1:8091/healthz
```

## Create a Sandbox

Navigate to the OpenCode harness directory:

```bash
cd harnesses/opencode
```

Create a sandbox with the `dev` profile:

```bash
./create.sh --profile dev
```

This creates a sandbox named `opencode-dev` with:
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

This establishes an SSH connection with the OpenCode CLI ready to use. Your provider credentials are injected from the environment at connection time.

## Teardown

From `openshell/scripts`, destroy the sandbox:

```bash
cd ../../scripts
source harness-lib.sh
harness_destroy opencode-dev
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
- Model API endpoints (provider-specific)
- GitHub API (read-only access)
- npm registry
- OpenCode package registry

**Landlock LSM**: Best-effort compatibility mode

See `harnesses/opencode/profiles/dev/policy.yaml` for the complete policy definition.

## Next Steps

- Review the [Policy Walkthrough](../policy-walkthrough.md) to understand deny-by-default enforcement
- Read the [Threat Model](../threat-model.md) to understand what OpenShell protects and what it does not
- Explore other profiles (`review`, `automation`, `interactive`) in `harnesses/opencode/profiles/`
