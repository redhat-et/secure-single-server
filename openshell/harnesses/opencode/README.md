# opencode harness (experimental)

See the [development recipe](../../docs/quickstarts/opencode.md) for the account,
credential, create/connect and teardown contracts. Images are digest-pinned in
`openshell/configs/images.env`; no harness package installation occurs at creation.

Profiles express filesystem permissions and per-binary network endpoints.
`include_workdir` does not mount a checkout or guarantee retention. GitHub API
methods are restricted in dev/automation; Git-over-HTTPS is not read-only.
Landlock is best-effort. See the [threat model](../../docs/threat-model.md).

Creation is detached. `--provider NAME` attaches an explicitly registered
standalone provider; provider keys are never forwarded over SSH. Praxis
integration is experimental for OpenCode and rejected for Codex/OpenClaw.
Real-provider tasks and disconnected harness sessions are not qualified.
