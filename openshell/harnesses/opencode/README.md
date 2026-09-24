# OpenCode Harness

Sandboxed OpenCode CLI demo for OpenShell.

## Prerequisites

- OpenShell gateway installed via `openshell/scripts/install.sh`
- Provider API key set in your environment (see below)

## Pre-installed Harness

OpenCode CLI (version 1.18.31) is pre-installed in the pinned aipcc image:
```
ODH_OPENCODE_IMAGE=quay.io/aipcc/base-images/agentic/opencode@sha256:5743452ce2dde8d91d3d8998d8667efa45da27e53c170dbd614516603a44d7d3
```

Binary paths inside the container:
- `/usr/local/sbin/opencode` (harness CLI)
- `/usr/sbin/node`, `/usr/sbin/npm`, `/usr/sbin/git`

## Provider Configuration

The LLM provider is configured via environment variables. **Never commit API keys to the repository.**

Set one of:
- `ANTHROPIC_API_KEY` for Anthropic Claude
- `OPENAI_API_KEY` for OpenAI
- `ANTHROPIC_BASE_URL=https://inference.local/v1` for custom endpoints

## Profiles

| Profile | Workspace | Network Access | Use Case |
|---------|-----------|----------------|----------|
| `review` | Read-only (no workdir) | Model API only | Code review, read-only analysis |
| `dev` | Read-write | Model + GitHub (read-only) + npm + OpenCode registry | Interactive development |
| `automation` | Read-write | Model + GitHub (read-only) + npm | Headless CI/CD, no interactive git push |
| `interactive` | Read-write + persist | Model + GitHub + npm + docs sites + OpenCode registry | Full-featured interactive sessions with persistent workspace |

## Usage

### Create a sandbox

```bash
./create.sh --profile <review|dev|automation|interactive> [--name NAME]
```

Examples:
```bash
# Create dev sandbox with default name "opencode-dev"
./create.sh --profile dev

# Create review sandbox with custom name
./create.sh --profile review --name my-review-session

# Create interactive sandbox
./create.sh --profile interactive
```

### Connect to a sandbox

```bash
./connect.sh [--name NAME]
```

Examples:
```bash
# Connect to default "opencode-dev" sandbox
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
