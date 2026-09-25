# OpenShell sandbox experiments

This repository consumes pinned OpenShell control-plane and preinstalled harness
images. The current deployment target is a disposable, trusted single-operator
RHEL 9 x86_64 host with rootless Podman. Bootc builds one OS image per harness.

- [Codex recipe](quickstarts/codex.md)
- [OpenCode recipe](quickstarts/opencode.md)
- [OpenClaw recipe](quickstarts/openclaw.md)
- [Praxis integration status](../../docs/quickstarts/openshell-praxis/users.md)
- [Threat model](threat-model.md)
- [Policy test contract](policy-walkthrough.md)
- [AWS validation](../../bootc/VALIDATION.md)

The gateway controls its owner's Podman service and permits unauthenticated local
operators. This is not shared-host multi-tenant authorization. Provider credentials
use explicit bindings or Praxis; SSH helpers do not forward them.

CI always runs static/offline regressions in UBI 9 on x86_64. Structural YAML checks
are distinct from native schema validation with the pinned CLI. Runtime CI requires
manual dispatch, the OPENSHELL_SELF_HOSTED variable, and a disposable runner labeled
self-hosted/Linux/X64/rhel9/openshell-disposable. One installer-owned gateway fixture
spans the native schema and controlled policy checks. A skipped job is no runtime
evidence. Praxis inference requires a separate configured fixture. The existing
Praxis amd64/arm64 tests remain separate and unchanged.
