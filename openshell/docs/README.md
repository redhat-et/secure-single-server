# OpenShell Sandboxing (Standalone)

OpenShell provides sandboxed execution environments for AI coding assistants with per-binary network and filesystem policy enforcement. This standalone variant deploys a local gateway on RHEL 9 using rootless Podman, with harness workloads pre-installed in pinned public aipcc images.

## Architecture

**Gateway → Injected ODH Supervisor → aipcc Workload Sandbox**

- **Gateway**: OpenShell control plane handles sandbox lifecycle and SSH proxy connections
- **ODH Supervisor**: Injected companion container enforces network and filesystem policies via eBPF and Landlock LSM
- **aipcc Workload Sandbox**: Pinned public container images (`@sha256`) with harness CLIs pre-installed (OpenCode, OpenClaw, Codex)

## Available Harnesses

| Harness | Description | Pre-installed Version | Provider |
|---------|-------------|----------------------|----------|
| **OpenCode** | Claude Code CLI for interactive development | 1.18.31 | Anthropic, OpenAI, or custom endpoints |
| **OpenClaw** | Standalone OpenClaw CLI with Control UI | 2026.9.5 | Anthropic or OpenAI |
| **Codex** | OpenAI Codex CLI | Latest | OpenAI |

All harnesses are pre-installed in pinned aipcc images. There is **no create-time install step** and **no npm-egress window**.

## Prerequisites

- **Operating System**: RHEL 9 (x86_64 or aarch64)
- **Runtime**: Rootless Podman 4.6 or newer
- **Installation**: Run `openshell/scripts/install.sh` to install the gateway

## Trust Boundary

Provider credentials are:
- Injected **only from the environment** at connect time
- **Never stored** in the repository or CI
- **Never passed** via command-line arguments or configuration files

Harnesses ship pre-installed in pinned public aipcc images (`@sha256`), eliminating the npm-egress window and create-time install risks.

## Quickstart Guides

Choose the harness that matches your LLM provider and workflow:

- **[OpenCode Quickstart](quickstarts/opencode.md)** — Claude Code CLI for Anthropic, OpenAI, or custom endpoints
- **[OpenClaw Quickstart](quickstarts/openclaw.md)** — Standalone OpenClaw CLI with browser-based Control UI
- **[Codex Quickstart](quickstarts/codex.md)** — OpenAI Codex CLI for OpenAI API

## Policy and Security

- **[Policy Walkthrough](policy-walkthrough.md)** — Understand deny-by-default network enforcement and policy debugging
- **[Threat Model](threat-model.md)** — What OpenShell enforces and what it does not

## Profiles

Each harness includes four profiles with different network and filesystem policies:

| Profile | Workspace | Network Access | Use Case |
|---------|-----------|----------------|----------|
| `review` | Read-only (no workdir) | Model API only | Code review, read-only analysis |
| `dev` | Read-write | Model + GitHub (read-only) + npm | Interactive development |
| `automation` | Read-write | Model + GitHub (read-only) + npm | Headless CI/CD, no interactive git push |
| `interactive` | Read-write + persist | Model + GitHub + npm + docs sites | Full-featured interactive sessions with persistent workspace |

Network policies are enforced per-binary with granular endpoint allowlists. See individual harness READMEs for profile-specific details.

## CI Validation

The `.github/workflows/openshell-validate.yml` workflow runs automated tests on a
GitHub-hosted **RHEL 9 x64 larger runner**, matching the target platform (RHEL 9 +
rootless Podman). The runner label is `openshell-rhel9-x64`; an org admin provisions
it from the RHEL 9 partner image (Linux x64, public preview). arm64 is not covered by
CI (RHEL runner images are x64-only in preview).

**Always-on tests** (no secrets required):
- Static checks (shellcheck via pinned binary, schema validation)
- Gateway boot test (pinned ODH control plane without provider credentials, under rootless Podman)

**Gated tests** (run only when the repo variable `OPENSHELL_SELF_HOSTED == 'true'`):
- Policy proof (spawns sibling supervisor/sandbox containers via the Podman driver)
- Integrated smoke test (requires a network-reachable ODH gateway and Praxis all-in-one)

The gated tests are skipped (not failed) by default; enable them once the runner is
confirmed able to spawn sibling containers and reach the host network.
