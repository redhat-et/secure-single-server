# OpenShell + Praxis Integration

This scenario demonstrates a credential-starved, sandboxed harness architecture where:

1. **Harness** (OpenCode/OpenClaw/Codex) runs inside an OpenShell sandbox
2. **OpenShell sandbox** enforces per-binary network policies and filesystem isolation
3. **Praxis loopback gateway** (127.0.0.1:8080) is the sandbox's only model egress
4. **Provider** receives requests proxied through Praxis

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ OpenShell Sandbox (credential-starved, sandboxed)      │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Harness (opencode/openclaw/codex)                │  │
│  │ - No provider credentials in environment         │  │
│  │ - Network policy: ONLY Praxis loopback allowed   │  │
│  └──────────────────┬───────────────────────────────┘  │
│                     │                                   │
│                     │ http://host.openshell.internal:   │
│                     │            8080/v1                │
└─────────────────────┼───────────────────────────────────┘
                      │
                      ▼
           ┌──────────────────────┐
           │ Praxis All-in-One    │
           │ (loopback 8080/8081) │
           │ - Quota enforcement  │
           │ - Request logging    │
           │ - Circuit breaker    │
           └──────────┬───────────┘
                      │
                      │ HTTPS (with credentials)
                      ▼
           ┌──────────────────────┐
           │ Provider             │
           │ (api.anthropic.com,  │
           │  api.openai.com)     │
           └──────────────────────┘
```

## Security Properties

- **Credential-starved**: Harness has no provider API keys
- **Default-deny network**: Only Praxis loopback is permitted (no direct api.anthropic.com / api.openai.com)
- **Sandboxed**: OpenShell enforces per-binary network and filesystem policies
- **Centralized governance**: Administrator controls model access via Praxis configuration
- **Auditable**: All model requests pass through Praxis (logging, quotas, circuit breaker)

## Components

- **OpenShell gateway**: Manages sandboxed containers (binds 127.0.0.1:8090/8091)
- **Praxis all-in-one gateway**: Proxies model requests (binds 127.0.0.1:8080/8081)
- **Integrated profiles**: Four profiles (review/dev/automation/interactive) with graded permissions
- **Harness provider config**: Points to `http://host.openshell.internal:8080/v1` (Praxis loopback)

## When to Use This Scenario

- **POC/development**: Test credential-starved architecture without deploying remote infrastructure
- **Security-first demos**: Show deny-by-default networking and centralized model governance
- **Policy validation**: Verify harness behavior when direct provider access is blocked

## When NOT to Use This Scenario

- **Production deployments**: Use remote-gateway scenario with TLS and JWT verification
- **Multi-user systems**: Praxis all-in-one is single-user; use distributed Praxis for scale
- **Public-facing services**: Loopback-only; not reachable from other hosts

## Limitations

- Praxis all-in-one runs on loopback (127.0.0.1) — not accessible from other hosts
- OpenShell gateway also runs on loopback (127.0.0.1) — local development only
- No TLS between sandbox and Praxis (localhost HTTP only)
- Single-user scenario (no multi-tenant isolation)

## Next Steps

- [Installation Guide](install.md) — Install the openshell-praxis scenario
- [User Guide](users.md) — Create sandboxes with integrated profiles
- [Policy Walkthrough](../../../openshell/docs/policy-walkthrough.md) — Understand deny-by-default enforcement
