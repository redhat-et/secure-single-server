# OpenShell + Praxis (experimental)

The intended model path is a sandboxed harness → Praxis → upstream provider.
Praxis owns provider credentials; harnesses should only use its local inference
endpoint. The bootc base runs both services, but service health alone does not
qualify that complete path.

See the [supported matrix and qualification limits](users.md), [add-on installer](install.md),
[bootc deployment](../../../bootc/README.md), and [threat model](../../../openshell/docs/threat-model.md).
Codex/OpenClaw Praxis configuration is currently unsupported. OpenCode configuration
is experimental until host-alias routing, actual inference and tool tasks pass.

Development profiles also permit selected GitHub/package/documentation traffic;
they are not restricted to Praxis for all egress. Loopback management trusts local
host users, and is not a multi-tenant authorization boundary.
