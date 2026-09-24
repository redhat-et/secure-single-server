# Codex Harness

Sandboxed OpenAI Codex CLI demo for OpenShell.

## Prerequisites

- OpenShell gateway installed via `openshell/scripts/install.sh`
- `OPENAI_API_KEY` set in your environment (see below)

## Pre-installed Harness

OpenAI Codex CLI is pre-installed in the pinned aipcc image:
```
ODH_CODEX_IMAGE=quay.io/aipcc/base-images/agentic/codex@sha256:f62cb7aa71cb145daf843b5e11c5efc255e19bb44d41c4eab5b1dba912b2342e
```

Binary paths inside the container:
- `/usr/local/sbin/codex` (harness CLI)
- `/usr/sbin/node`, `/usr/sbin/npm`, `/usr/sbin/git`

## Provider Configuration

OpenAI Codex requires an OpenAI API key. **Never commit API keys to the repository.**

Set:
- `OPENAI_API_KEY` for OpenAI (required)

The harness is configured to access OpenAI endpoints:
- `api.openai.com` (inference)
- `auth.openai.com` (authentication)

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
./create.sh --profile <review|dev|automation|interactive> [--name NAME]
```

Examples:
```bash
# Create dev sandbox with default name "codex-dev"
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
# Connect to default "codex-dev" sandbox
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
