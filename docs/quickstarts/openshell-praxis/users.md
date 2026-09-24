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

Each harness `create.sh` accepts `--config <dir>`. When given, the profile is
read from `<dir>/profiles/<PROFILE>/policy.yaml` (the integrated policies) instead
of the harness's own standalone profiles, and the harness is pointed at the Praxis
loopback using `<dir>/harness-provider.json.in`.

Two environment variables control the integrated create:

- `OPENSHELL_MODEL_ID` (**required**) — the administrator-approved model id. The
  create fails fast if it is unset (a placeholder model id would silently fail at
  request time).
- `PRAXIS_PORT` (optional) — the Praxis loopback port. **Defaults to `8080`.**

The default sandbox name is `<harness>-<profile>` (e.g. `opencode-dev`); override
with `--name`.

### Example: OpenCode with dev profile

```bash
cd openshell/harnesses/opencode
export OPENSHELL_MODEL_ID='administrator-approved-model-id'
./create.sh --profile dev --config /path/to/configs/openshell-praxis
```

OpenCode reads its global provider config from `~/.config/opencode/opencode.json`
(see <https://opencode.ai/docs/config/>). The integrated `create.sh` renders
`harness-provider.json.in` (substituting `PRAXIS_PORT` and `OPENSHELL_MODEL_ID`)
and installs it there inside the sandbox automatically.

### Example: OpenClaw with interactive profile

```bash
cd openshell/harnesses/openclaw
export OPENSHELL_MODEL_ID='administrator-approved-model-id'
./create.sh --profile interactive --config /path/to/configs/openshell-praxis
```

### Example: Codex with automation profile

```bash
cd openshell/harnesses/codex
export OPENSHELL_MODEL_ID='administrator-approved-model-id'
./create.sh --profile automation --config /path/to/configs/openshell-praxis
```

**OpenClaw and Codex**: these harnesses do not consume the OpenCode config
format, and their in-sandbox provider-config path is harness-specific. For them,
`create.sh --config` applies the Praxis-only **network policy** to the sandbox and
renders the provider file locally, then **prints the exact `harness_ssh ... 'cat >
<path>'` command** for you to run once you know the harness's provider-config
path. It deliberately does not push the file to an invented path. Follow the
printed instructions to install the rendered provider config.

## Provider Configuration

The integrated harness provider configuration (`configs/openshell-praxis/harness-provider.json.in`) points to the Praxis loopback. `create.sh` renders `@@PRAXIS_PORT@@` (default 8080) and `@@MODEL_ID@@` (from `OPENSHELL_MODEL_ID`) before installing it:

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
        "administrator-approved-model-id": {
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

The aipcc harness images do not ship `curl` or `python3`, so use the pre-installed
`node` runtime to probe endpoints from inside the sandbox.

Attempt to reach a provider directly (this should fail — the endpoint is not in
the integrated policy):

```bash
node --input-type=module -e "try{await fetch('https://api.anthropic.com/v1/messages',{signal:AbortSignal.timeout(10000)});console.log('reachable')}catch(e){console.log('denied')}"
```

Expected result: **denied** (network policy blocks the endpoint).

Verify the Praxis loopback host alias resolves:

```bash
getent hosts host.openshell.internal
```

Expected result: the alias resolves to the host address (Praxis is reachable on
`host.openshell.internal:8080`).

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
