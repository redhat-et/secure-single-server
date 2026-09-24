# Using OpenShell + Praxis Integration

This guide covers creating and using harness sandboxes in the openshell-praxis scenario.

## Overview

In the integrated scenario, harnesses (OpenCode, OpenClaw, Codex) run inside credential-starved OpenShell sandboxes with network policies that permit **only** the Praxis loopback gateway. Direct access to `api.anthropic.com` and `api.openai.com` is denied.

## Integrated Profiles

Four profiles are available, each with graded permissions:

| Profile       | Workdir | GitHub | npm | Docs | Use Case                   |
|---------------|---------|--------|-----|------|----------------------------|
| review        | ✗       | ✗      | ✗   | ✗    | Read-only code review      |
| dev           | ✓       | ✓ (RO) | ✓   | ✗    | Development, prototyping   |
| automation    | ✓       | ✓ (RO) | ✓   | ✗    | CI/CD, automated tasks     |
| interactive   | ✓       | ✓ (RO) | ✓   | ✓    | Full-featured, persistence |

All profiles permit **only** the Praxis loopback gateway (`host.openshell.internal:8080`). No profile permits direct provider access.

## Creating a Sandbox

Navigate to a harness directory and create a sandbox with an integrated profile.

### Example: OpenCode with dev profile

```bash
cd openshell/harnesses/opencode
./create.sh --profile dev --config /path/to/configs/openshell-praxis
```

### Example: OpenClaw with interactive profile

```bash
cd openshell/harnesses/openclaw
./create.sh --profile interactive --config /path/to/configs/openshell-praxis
```

### Example: Codex with automation profile

```bash
cd openshell/harnesses/codex
./create.sh --profile automation --config /path/to/configs/openshell-praxis
```

## Provider Configuration

The integrated harness provider configuration (`configs/openshell-praxis/harness-provider.json.in`) points to the Praxis loopback:

```json
{
  "provider": {
    "praxis": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Praxis (sandboxed)",
      "options": {
        "baseURL": "http://host.openshell.internal:8080/v1",
        "apiKey": "local-placeholder"
      },
      "models": {
        "MODEL_ID": {
          "name": "Administrator-approved model"
        }
      }
    }
  }
}
```

**No provider credentials are required** when connecting to the sandbox. The harness has no API keys — Praxis holds the credentials and proxies requests.

## Connecting to a Sandbox

Set no provider credentials (the sandbox does not need them):

```bash
cd openshell/harnesses/opencode
./connect.sh
```

Or for a custom-named sandbox:

```bash
./connect.sh --name my-session
```

You are now in a credential-starved sandbox. The harness can reach the Praxis loopback, but cannot directly contact `api.anthropic.com` or `api.openai.com`.

## Verifying Isolation

From inside the sandbox, attempt to reach a provider directly (this should fail):

```bash
curl -v https://api.anthropic.com/v1/messages
```

Expected result: **Connection refused or timeout** (network policy denies the endpoint).

Verify the Praxis loopback is reachable:

```bash
curl -v http://host.openshell.internal:8080/healthz
```

Expected result: **200 OK** (Praxis health endpoint responds).

## Policy Details

### Review Profile

- **Filesystem**: Read-only workdir, read-only system paths
- **Network**: Praxis loopback only (no GitHub, no npm, no docs)
- **Binaries with network access**: `/usr/sbin/node`

### Dev Profile

- **Filesystem**: Read-write workdir, read-only system paths
- **Network**: Praxis loopback + GitHub (read-only) + npm + OpenCode registry
- **Binaries with network access**: `/usr/sbin/node`, `/usr/sbin/git`, `/usr/sbin/npm`

### Automation Profile

- **Filesystem**: Read-write workdir, read-only system paths
- **Network**: Praxis loopback + GitHub (read-only) + npm
- **Binaries with network access**: `/usr/sbin/node`, `/usr/sbin/git`, `/usr/sbin/npm`

### Interactive Profile

- **Filesystem**: Read-write workdir with persistence, read-only system paths
- **Network**: Praxis loopback + GitHub (read-only) + npm + OpenCode registry + docs sites
- **Binaries with network access**: `/usr/sbin/node`, `/usr/sbin/git`, `/usr/sbin/npm`

**Note**: No profile permits `curl` or `python3` (these binaries are absent from aipcc harness images).

## Teardown

Destroy a sandbox:

```bash
cd openshell/scripts
source harness-lib.sh
harness_destroy opencode-dev
```

Or for a custom-named sandbox:

```bash
harness_destroy my-session
```

## Troubleshooting

### Sandbox cannot reach Praxis loopback

Verify `host.openshell.internal` resolves inside the sandbox:

```bash
# From inside the sandbox
getent hosts host.openshell.internal
```

If it does not resolve, the OpenShell supervisor may not be injecting the host alias. Check the OpenShell gateway logs:

```bash
systemctl --user status openshell-gateway.service
journalctl --user -u openshell-gateway.service -n 100
```

### Policy violations

If the harness attempts to reach a denied endpoint, the supervisor will block the connection. Check the supervisor logs for policy violations:

```bash
# From the host
openshell_cli logs opencode-dev
```

## Next Steps

- Review the [Policy Walkthrough](../../../openshell/docs/policy-walkthrough.md) to understand deny-by-default enforcement
- Read the [Threat Model](../../../openshell/docs/threat-model.md) to understand security boundaries
- Explore other profiles under `configs/openshell-praxis/profiles/`
