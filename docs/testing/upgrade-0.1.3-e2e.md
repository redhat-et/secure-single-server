# OpenShell 0.1.3 deployment end-to-end qualification

On 2026-10-09, two fresh AWS RHEL x86_64 `m7i.2xlarge` hosts in
`us-east-1` exercised the manual and bootc deployment guides with a real OpenAI
account and `gpt-4.1-mini`. OpenShell was 0.1.3; OpenClaw was 2026.9.9.
The workload and control-plane digest pins are recorded in the
[upgrade qualification](upgrade-0.1.3.md). Provider keys were passed over SSH
stdin to the documented credential/secret helpers, never put in OS images or
command arguments. Saved logs remain outside the committed tree.

## Manual deployment

The reviewed checkout was transferred to service-readable `/var/tmp`, then the
manual package and OpenShell installer commands ran on a fresh RHEL 9.6 host.
The separately installed Praxis memory profile used versioned service-account
Podman secrets; the OpenShell add-on preserved the Praxis managed manifest.

| Check | Result |
| --- | --- |
| Direct OpenAI provider profile import, credential registration and attached OpenCode sandbox | Real model greeting passed |
| OpenCode through Praxis | Real model wrote a script, executed it with Bash, read the command-produced file and returned a final response; independent readback matched `MANUAL_OPENCODE_OK` |
| OpenClaw through Praxis | Real model wrote and read the workspace greeting; `ok: true`, final response and independent `MANUAL_OPENCLAW_OK` readback |
| Controlled network policy | Allowed fixture reached; denied request returned `EACCES` without reaching it |
| Host reboot | Rootless services restarted automatically; Praxis healthy, SELinux enforcing, managed manifest unchanged |
| Sandbox credential isolation | Both integrated harness environments contained neither real provider key |
| Both harnesses after reboot | Real model responses passed; OpenClaw read the preserved workspace file |

## Bootc OS deployment

The OS images were built from reviewed PR revision
`3e65fca03fc705a629fe811105dd39cdc7584330`, using the reviewed RHEL 9 bootc
parent digest. Base and both harness image contracts passed. This tested
**PR-built images**, not the previously published mutable `v0.1` tags.

On the disposable AWS host, `bootc install to-existing-root` installed the
OpenCode image. Its root SSH key was supplied with the installer option.
Test-specific cloud-init/SSH configuration preserved key-only access. Copied
RHEL 9.6 host keys initially had group-readable permissions rejected by the
newer SSH server; disk recovery corrected them to root-owned mode `0600` and
restored labels. This was administrator access setup, not a workload failure.

| Check | Result |
| --- | --- |
| Actual OS boot | RHEL 9.8; `bootcHost`; expected image digest; read-only `/usr`; SELinux enforcing |
| Automatic first-boot reconciliation | OpenShell ready; Praxis correctly waited for secrets |
| Credential provisioning and cloud activation | Both real provider secrets created; Praxis healthy |
| OpenCode through Praxis | Real model write, Bash execution, final response and independent `BOOTC_OPENCODE_OK` readback |
| OpenCode → OpenClaw image switch and reboot | Selected image and digest changed; secrets and activation settings persisted |
| OpenClaw through Praxis | Real model workspace write/read, `ok: true`, final response and independent `BOOTC_OPENCLAW_OK` readback |
| Return to OpenCode and direct provider injection | Rollback boot passed; provider registration persisted; real greeting contained `BOOTC_DIRECT_OPENAI_OK` |
| Booted host controls | Both variants passed healthy rootless services, private locked accounts, loopback-only listeners and management authentication checks |

The OS image references used local `containers-storage` transport, since these
changes are not released. Fresh installation retains the old system's container
store under `/sysroot`; the OpenClaw image was copied into the booted host's store
before `bootc switch`. This qualifies OS installation, boot, service startup and
variant switching; it does not certify distribution of an unreleased registry tag.

OpenShell 0.1.3 accepts certificate-free TLS handshakes for sandbox JWT clients.
Management RPCs still require identity: an isolated client with no operator
certificate or token was rejected with `missing authorization header`.
`bootc/test-host` now checks that rejection, alongside a CA-verified TLS positive
control and an authenticated operator sandbox listing, rather than expecting
all certificate-free TLS handshakes to fail.

## Repeat and remaining scope

Follow the [manual guide](../quickstarts/openshell-single-server/manual.md) and
[bootc guide](../quickstarts/openshell-single-server/bootc.md), selecting a model
available to the test account. Require a final response, tool evidence and
independent file readback; gateway health alone does not prove inference.
Run `bootc/test-host` on the booted host after secrets and service startup.
The [upgrade tests](upgrade-0.1.3.md) cover controlled authentication, both
harnesses and policy negative controls in CI without paid model credentials.

These real-account tests cover OpenAI cloud routing. They do not repeat GPU
vLLM qualification, Anthropic model calls, browser login, retained OpenClaw
sessions, or automatic OpenClaw `exec`. OpenClaw model tools remain read/write;
OpenCode is the qualified route for model-driven command execution.
