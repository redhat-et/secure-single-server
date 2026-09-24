# Codex Quickstart

This guide walks through creating, connecting to, and tearing down an OpenAI Codex sandbox with OpenShell.

## Prerequisites

- RHEL 9 with rootless Podman 4.6 or newer
- OpenShell gateway installed (run `openshell/scripts/install.sh` if not already installed)
- OpenAI API key available in your environment (see below)

## Provider Configuration

Codex requires an OpenAI API key. **Never commit API keys to the repository.**

Set your OpenAI API key before connecting:

```bash
export OPENAI_API_KEY='your-key-here'
```

Provider credentials are injected **only from the environment** at connect time and are **never stored** in the repository or configuration files.

The Codex harness is configured to access OpenAI endpoints:
- `api.openai.com` (inference)
- `auth.openai.com` (authentication)

## Installation

Install the OpenShell gateway and pull the pinned Codex image:

```bash
cd openshell
./scripts/install.sh
```

The installer will:
- Enable the rootless Podman socket
- Configure cgroup delegation for nested containers
- Generate JWT signing keys for sandbox authentication
- Pull pinned images including `quay.io/aipcc/base-images/agentic/codex@sha256:f62cb7aa71cb145daf843b5e11c5efc255e19bb44d41c4eab5b1dba912b2342e`
- Install the `openshell` CLI binary
- Start the gateway service

Verify the gateway is running:

```bash
curl http://127.0.0.1:8091/healthz
```

## Create a Sandbox

Navigate to the Codex harness directory:

```bash
cd harnesses/codex
```

Create a sandbox with the `dev` profile:

```bash
./create.sh --profile dev
```

This creates a sandbox named `codex-dev` with:
- Read-write workspace access
- Network access to the OpenAI API, GitHub (read-only), and npm registry

Other available profiles: `review` (read-only), `automation` (CI/CD), `interactive` (full-featured with persistence).

To create a sandbox with a custom name:

```bash
./create.sh --profile dev --name my-session
```

## Connect to the Sandbox

Set your OpenAI API key (see Provider Configuration above), then connect:

```bash
./connect.sh
```

Or for a custom-named sandbox:

```bash
./connect.sh --name my-session
```

This establishes an SSH connection with the Codex CLI ready to use. Your OpenAI API key is injected from the environment at connection time.

## Teardown

From `openshell/scripts`, destroy the sandbox:

```bash
cd ../../scripts
source harness-lib.sh
harness_destroy codex-dev
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
- OpenAI API endpoints (`api.openai.com`, `auth.openai.com`)
- GitHub API (read-only access)
- npm registry

**Landlock LSM**: Best-effort compatibility mode

See `harnesses/codex/profiles/dev/policy.yaml` for the complete policy definition.

## Next Steps

- Review the [Policy Walkthrough](../policy-walkthrough.md) to understand deny-by-default enforcement
- Read the [Threat Model](../threat-model.md) to understand what OpenShell protects and what it does not
- Explore other profiles (`review`, `automation`, `interactive`) in `harnesses/codex/profiles/`
