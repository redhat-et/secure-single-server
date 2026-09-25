# Policy Walkthrough: Deny-by-Default Network Enforcement

This walkthrough demonstrates OpenShell's deny-by-default network enforcement using the behavioral policy proof from `openshell/tests/openshell-policy.sh`. You'll see how attempting to access an endpoint not listed in the sandbox policy results in a denied connection, and how adding the endpoint to the policy allows the connection.

## Overview

OpenShell enforces network policies on a per-binary basis with granular endpoint allowlists. The gateway's ODH supervisor companion container monitors network activity and blocks connections to endpoints not explicitly allowed in the sandbox's policy.

When a binary attempts to access an endpoint not in its allowlist:
- The connection is **denied** by the network supervisor
- The event is logged with `action=deny`
- The application receives a connection timeout or refused error

When the endpoint is added to the policy:
- The connection is **allowed**
- The event is logged with `action=allow`
- The application can communicate normally

## The Test Scenario

The `openshell/tests/openshell-policy.sh` test creates two sandboxes with different network policies:

1. **Deny sandbox**: Policy includes only the model API (`api.openai.com`)
2. **Allow sandbox**: Policy includes both the model API and GitHub API (`api.github.com`)

Both sandboxes attempt to fetch from `https://api.github.com/zen` using a Node.js probe.

## Inspecting the Deny Sandbox Policy

The deny sandbox's policy allows only the model API:

```yaml
network_policies:
  model_api:
    name: model-api
    endpoints:
      - host: api.openai.com
        port: 443
        protocol: rest
        enforcement: enforce
    binaries:
      - path: /usr/sbin/node
```

**GitHub is not listed**, so connections to `api.github.com` are blocked by default.

## Observing the Denial

When the Node.js probe attempts to fetch from GitHub:

```bash
openshell logs policy-proof-deny-citest
```

You'll see output similar to:

```
timestamp=2026-09-24T14:30:15Z binary=/usr/sbin/node pid=1234 endpoint=api.github.com:443 action=deny reason="endpoint not in allowlist"
```

Key fields:
- `binary=/usr/sbin/node` — the process attempting the connection
- `endpoint=api.github.com:443` — the destination
- `action=deny` — connection blocked
- `reason="endpoint not in allowlist"` — why it was blocked

The application receives a connection error, and the fetch fails.

## Inspecting the Allow Sandbox Policy

The allow sandbox's policy adds the GitHub API endpoint:

```yaml
network_policies:
  model_api:
    name: model-api
    endpoints:
      - host: api.openai.com
        port: 443
        protocol: rest
        enforcement: enforce
    binaries:
      - path: /usr/sbin/node
  github_api:
    name: github-api
    endpoints:
      - host: api.github.com
        port: 443
        protocol: rest
        enforcement: enforce
        access: read-only
    binaries:
      - path: /usr/sbin/node
```

**GitHub is now listed** with `read-only` access, so connections are allowed.

## Observing the Allow

When the Node.js probe attempts to fetch from GitHub in the allow sandbox:

```bash
openshell logs policy-proof-allow-citest
```

You'll see output similar to:

```
timestamp=2026-09-24T14:30:20Z binary=/usr/sbin/node pid=5678 endpoint=api.github.com:443 action=allow policy=github-api access=read-only
```

Key fields:
- `binary=/usr/sbin/node` — the process attempting the connection
- `endpoint=api.github.com:443` — the destination
- `action=allow` — connection permitted
- `policy=github-api` — which policy allowed it
- `access=read-only` — the access level granted

The application successfully fetches the response, and the connection succeeds.

## How to Debug Your Own Policy

When developing a new profile or troubleshooting connectivity issues:

1. **Run your workload** in the sandbox
2. **Check the logs** with `openshell logs <sandbox-name>`
3. **Look for `action=deny`** entries to identify blocked endpoints
4. **Update the policy** in `profiles/<profile>/policy.yaml` to add the required endpoint
5. **Recreate the sandbox** with the updated policy
6. **Verify `action=allow`** in the logs

## Existing Profiles

The harnesses ship with four pre-configured profiles:

| Profile | Model API | GitHub | npm | Docs Sites | Workdir |
|---------|-----------|--------|-----|------------|---------|
| `review` | ✓ | — | — | — | Read-only (none) |
| `dev` | ✓ | ✓ (read) | ✓ | — | Read-write |
| `automation` | ✓ | ✓ (read) | ✓ | — | Read-write |
| `interactive` | ✓ | ✓ | ✓ | ✓ | Read-write + persist |

Each profile's complete policy is defined in `openshell/harnesses/<harness>/profiles/<profile>/policy.yaml`.

## Key Takeaways

- OpenShell enforces **deny-by-default** network policies
- Connections to unlisted endpoints are **blocked** and logged as `action=deny`
- Endpoints must be **explicitly allowed** in the policy to be accessible
- Policies are **per-binary** with granular endpoint allowlists
- The `openshell logs` command provides real-time visibility into policy enforcement

This deny-by-default approach ensures that sandboxed workloads can only access the network resources you explicitly permit.
