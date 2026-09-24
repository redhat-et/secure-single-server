# OpenShell Threat Model

This document describes what OpenShell enforces and what it does not, helping you understand the security boundaries of sandboxed AI coding assistant workloads.

## What OpenShell Enforces

OpenShell provides sandboxed execution environments with policy enforcement at the operating system and network levels.

### 1. Per-Binary Network Endpoint Allowlists

**Enforcement**: The ODH supervisor companion container monitors all network connections and blocks access to endpoints not explicitly listed in the sandbox's policy.

**Granularity**: Policies are defined per-binary with endpoint-specific allowlists:
- Binary path (e.g., `/usr/sbin/node`, `/usr/local/sbin/opencode`)
- Destination host and port (e.g., `api.openai.com:443`)
- Protocol (e.g., `rest`, `grpc`)
- Access level (e.g., `read-only`, `read-write`)

**Example**: The `dev` profile allows `/usr/sbin/node` to access `api.openai.com:443` and `api.github.com:443` (read-only), but blocks all other endpoints.

**Logging**: All connection attempts are logged with `action=deny` (blocked) or `action=allow` (permitted) for audit and debugging.

### 2. Filesystem Read/Write Scope

**Enforcement**: Each profile defines read-only and read-write filesystem paths. The workload cannot write to paths outside the allowed scope.

**Granularity**:
- **Read-only paths**: Typically `/usr`, `/lib`, `/lib64`, `/etc`, `/proc`, `/opt`
- **Read-write paths**: Typically `/tmp`, `/dev/null`, `/home`, and optionally the workspace directory
- **Workspace isolation**: The `include_workdir` flag controls whether the workspace is mounted (and whether it's read-only or read-write)

**Example**: The `review` profile excludes the workspace entirely (read-only analysis), while `dev` and `interactive` provide read-write workspace access.

### 3. Landlock LSM

**Enforcement**: OpenShell uses the Landlock Linux Security Module to enforce filesystem access restrictions at the kernel level.

**Mode**: Best-effort compatibility mode ensures the sandbox runs even if Landlock is not fully available on the host kernel.

**Benefit**: Provides defense-in-depth beyond discretionary access controls (DAC) and SELinux.

## What OpenShell Does NOT Enforce

Understanding the limits of OpenShell's enforcement is critical for proper risk assessment.

### 1. Logic Inside the Sandbox

**Not enforced**: OpenShell does not inspect, validate, or constrain the behavior of the harness CLI or the code it executes inside the sandbox.

**Risk**: A malicious or compromised harness could:
- Exfiltrate data to allowed endpoints (e.g., send workspace contents to the model API)
- Execute arbitrary code within the allowed filesystem and network scope
- Misuse legitimate API access (e.g., make excessive model API calls)

**Mitigation**: Choose harnesses from trusted sources, review their code, and understand the network policies you enable.

### 2. Model API Side Channels

**Not enforced**: OpenShell allows the harness to communicate with the model API as defined in the policy. It does not inspect or filter the content of those communications.

**Risk**: Sensitive data in the workspace can be sent to the model provider if the harness includes it in prompts.

**Mitigation**:
- Review workspace contents before connecting to a sandbox
- Use the `review` profile (no workspace) for read-only analysis of untrusted code
- Understand your model provider's data retention and privacy policies

### 3. Time-of-Check to Time-of-Use (TOCTOU) Attacks

**Not enforced**: OpenShell's network and filesystem policies are enforced at runtime, but there is no analysis of the harness binary itself before execution.

**Risk**: A malicious actor with write access to the container image could replace the harness binary with a trojan.

**Mitigation**: Use pinned images (`@sha256`) from trusted registries (see Trust Boundary below).

## Trust Boundary: Pinned Images and Credential Handling

OpenShell establishes a clear trust boundary for harness workloads and provider credentials.

### Pinned Public Images

**Policy**: All harness images are pinned to specific `@sha256` digests and pulled from public aipcc registries:

```bash
ODH_OPENCODE_IMAGE=quay.io/aipcc/base-images/agentic/opencode@sha256:5743452ce2dde8d91d3d8998d8667efa45da27e53c170dbd614516603a44d7d3
ODH_OPENCLAW_IMAGE=quay.io/aipcc/base-images/agentic/openclaw@sha256:de12000bc8c251e868519bb86ed975458bf3f2ff63c6ebc2eece4bc769f14b69
ODH_CODEX_IMAGE=quay.io/aipcc/base-images/agentic/codex@sha256:f62cb7aa71cb145daf843b5e11c5efc255e19bb44d41c4eab5b1dba912b2342e
```

**Benefit**: The `@sha256` digest ensures:
- You pull the exact image that was reviewed and tested
- The image cannot be silently replaced by an attacker who compromises the registry tag
- The harness CLI is pre-installed in the image (see below)

**Verification**: Anyone can independently pull and inspect the same image digest.

### Pre-installed Harness CLI

**Policy**: All harness CLIs are **pre-installed** in the pinned images. There is **no create-time install step**.

**Benefit**: Eliminates the **npm-egress window** where a malicious package could be installed from the public npm registry during sandbox creation.

**Example**: OpenCode 1.18.31 is already at `/usr/local/sbin/opencode` in the image. The `create.sh` script does not run `npm install`.

### Credentials from Environment Only

**Policy**: Provider API keys (e.g., `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) are:
- Injected **only from the environment** at connect time via the `connect.sh` script
- **Never stored** in the repository, configuration files, or CI pipelines
- **Never passed** via command-line arguments (which are visible in `ps` output)

**Mechanism**: `connect.sh` (via the `harness_ssh`/`harness_connect_tty` helpers in
`openshell/scripts/harness-lib.sh`) forwards `OPENAI_API_KEY` and
`ANTHROPIC_API_KEY` to the sandbox using `ssh -o SendEnv=OPENAI_API_KEY -o
SendEnv=ANTHROPIC_API_KEY`. `SendEnv` forwards only variables that are actually
set in the connecting user's environment; unset variables are silently skipped.

**Host-validation caveat**: `SendEnv` only takes effect if the sandbox image's
sshd `AcceptEnv`s these variables. This cannot be verified from the harness
repository; it must be confirmed on the host during the smoke run (the same
host-validation posture as the `host.openshell.internal` reachability caveat).
Do not assume the credential reaches the harness until `AcceptEnv` is confirmed
on the deployed sandbox image.

**Benefit**:
- No risk of committed credentials in Git history
- No credentials at rest in sandbox configuration files
- Credentials exist only in the runtime environment of the connecting user

**Verification**: Inspect `openshell/scripts/harness-lib.sh` to confirm credentials are forwarded via `ssh -o SendEnv=OPENAI_API_KEY -o SendEnv=ANTHROPIC_API_KEY`, and confirm the sandbox sshd `AcceptEnv`s them on the host.

## Deployment Considerations

### Trust the Image Source

- Pin to specific `@sha256` digests
- Pull from trusted registries (e.g., official aipcc images)
- Inspect the image contents before use: `podman run --rm <image> cat /etc/os-release`

### Review the Policy

- Understand what network endpoints each profile allows
- Use the most restrictive profile that meets your needs (`review` for read-only, `dev` for interactive)
- Audit the policy YAML files in `openshell/harnesses/<harness>/profiles/<profile>/policy.yaml`

### Protect Credentials

- Never commit API keys to the repository
- Use environment variables for credential injection
- Rotate credentials regularly
- Understand your model provider's access controls and audit logs

### Monitor Logs

- Use `openshell logs <sandbox-name>` to audit network activity
- Look for unexpected `action=allow` entries (connections you didn't anticipate)
- Look for `action=deny` entries to identify legitimate traffic that needs policy updates

## Summary

| Aspect | OpenShell Enforces | You Must Verify |
|--------|-------------------|-----------------|
| Network endpoints | ✓ Per-binary allowlists | Trust the harness to use endpoints responsibly |
| Filesystem access | ✓ Read/write scope via Landlock | Trust the harness not to misuse allowed paths |
| Image integrity | ✓ Pinned `@sha256` digests | Trust the image source and registry |
| Credentials | ✓ Environment-only injection | Protect your environment and rotate keys |
| Harness logic | ✗ Not inspected | Review harness code and choose trusted sources |
| Model API content | ✗ Not filtered | Understand what data the harness may send to the model |

OpenShell provides a strong foundation for sandboxed AI coding assistant workloads, but it is not a complete solution for all threat vectors. Understand the boundaries, trust the right components, and layer additional controls as needed for your risk profile.
