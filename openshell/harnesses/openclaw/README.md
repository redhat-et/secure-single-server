# OpenClaw Harness

Sandboxed OpenClaw CLI demo for OpenShell.

## Prerequisites

- OpenShell gateway installed via `openshell/scripts/install.sh`
- Provider API key set in your environment (see below)

## Pre-installed Harness

OpenClaw CLI (version 2026.9.5) is pre-installed in the pinned aipcc image:
```
ODH_OPENCLAW_IMAGE=quay.io/aipcc/base-images/agentic/openclaw@sha256:de12000bc8c251e868519bb86ed975458bf3f2ff63c6ebc2eece4bc769f14b69
```

OpenClaw is the standalone `github.com/openclaw/openclaw` project.

Binary paths inside the container:
- `/usr/local/sbin/openclaw` (harness CLI)
- `/usr/sbin/node`, `/usr/sbin/npm`, `/usr/sbin/git`

## Provider Configuration

The LLM provider is configured via environment variables. **Never commit API keys to the repository.**

Set one of:
- `ANTHROPIC_API_KEY` for Anthropic Claude
- `OPENAI_API_KEY` for OpenAI

Provider selection is passed via the `--backend` flag to `create.sh`.

## Profiles

| Profile | Workspace | Network Access | Use Case |
|---------|-----------|----------------|----------|
| `review` | Read-only (no workdir) | Model API only | Code review, read-only analysis |
| `dev` | Read-write | Model + GitHub (read-only) + npm | Interactive development |
| `automation` | Read-write | Model + GitHub (read-only) + npm | Headless CI/CD, no interactive git push |
| `interactive` | Read-write + persist | Model + GitHub + npm + docs sites | Full-featured interactive sessions with persistent workspace |

## Usage

### Create a sandbox

```bash
./create.sh --profile <review|dev|automation|interactive> [--name NAME] [--backend openai|anthropic]
```

Examples:
```bash
# Create dev sandbox with default name "openclaw-dev" and Anthropic backend
./create.sh --profile dev

# Create review sandbox with custom name and OpenAI backend
./create.sh --profile review --name my-review-session --backend openai

# Create interactive sandbox
./create.sh --profile interactive
```

### Connect to a sandbox and access the Control UI

```bash
./connect.sh [--name NAME]
```

This launches the OpenClaw Control UI inside the sandbox and forwards port 18789 to your local machine.

Access the browser UI at: `http://127.0.0.1:18789`

Examples:
```bash
# Connect to default "openclaw-dev" sandbox
./connect.sh

# Connect to custom-named sandbox
./connect.sh --name my-review-session
```

### Destroy a sandbox

```bash
# From openshell/scripts
../../scripts/harness-lib.sh
harness_destroy <name>
```

## Policy Details

Each profile enforces filesystem and network policies via Landlock LSM and OpenShell's network supervisor:

- **Filesystem**: Profiles control workspace access (`include_workdir`), read-only paths, and read-write paths
- **Network**: Granular per-binary endpoint allowlists (model APIs, GitHub, npm, etc.)
- **Landlock**: Best-effort compatibility mode for LSM enforcement

See `profiles/*/policy.yaml` for full policy definitions.
