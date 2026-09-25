# Secure single-server Praxis

Run an administrator-managed Praxis AI gateway on RHEL 9. Keep provider
credentials out of harness accounts and apply shared token quotas. Choose
where users run their harnesses before installing the gateway.

## What you'll be running

This repository is a deployment and demonstration environment. The software it
installs comes from two upstream projects — read their pages to understand the
system you are operating:

- **Praxis** — an administrator-managed AI gateway that fronts an
  OpenAI-compatible provider, keeps provider credentials out of harness
  accounts, and enforces shared token quotas. This repo deploys the pinned
  `quay.io/opendatahub/praxis-experimental` image. Source:
  [praxis-proxy/experimental](https://github.com/praxis-proxy/experimental) — an
  experimental proving ground, so features may change before promotion.
- **OpenShell** — a policy-enforced runtime that sandboxes AI coding agents.
  Each agent runs in its own container whose filesystem, network, and provider
  credentials are governed by declarative YAML policies, coordinated by a gateway
  control plane over rootless Podman. The OpenShell demos deploy the pinned
  `quay.io/opendatahub/odh-openshell-*` control-plane images. Source:
  [opendatahub-io/openshell](https://github.com/opendatahub-io/openshell)
  (mirrored at [NVIDIA/openshell](https://github.com/NVIDIA/openshell)).

**What you use, and what to expect when following these processes:**

- **Harnesses** — the AI coding CLIs you actually drive. The Praxis scenarios
  target Claude Code, Codex, and OpenCode; the OpenShell demos use OpenCode,
  OpenClaw, and Codex. You bring the harness; the administrator supplies approved
  model IDs and either a RHEL login (all-in-one) or a gateway URL plus a caller
  JWT (remote gateway).
- **Credentials stay out of your hands.** Provider API keys live only with the
  administrator behind Praxis, or are injected into an OpenShell sandbox at
  runtime — never written into the repository, harness accounts, or CI.
- **Platform and status.** Everything targets RHEL 9 with rootless Podman 4.6+,
  and all images are pinned by `@sha256`. Both upstreams are early/experimental
  here: treat these flows as demonstration and pre-production validation, not a
  supported product.

## Administrator deployment

An administrator starts from a reviewed local checkout, transfers only the
deployment bundle to a private staging directory on RHEL, and installs one
persistent profile. Git and the repository are not required on the server,
and ordinary users do not receive the deployment files.

| Scenario | Harness location and access | Start here |
| --- | --- | --- |
| All-in-one | Users SSH into the RHEL box; inference stays on loopback | [Architecture and installation profiles](docs/quickstarts/all-in-one/README.md) |
| Remote gateway | Harnesses run elsewhere; HTTPS and a caller JWT are required | [Architecture and installation](docs/quickstarts/remote-gateway/README.md) |

Use **Valkey** when token quotas must survive restarts. The in-memory profile
is for development only. Quotas cover rolling usage windows, not USD spend;
see [quota configuration and gaps](docs/quickstarts/common/token-quotas.md).
Install one scenario/profile per host; uninstall before switching profiles.

Read the selected scenario's trust model before granting access. The scripts
are the current installation mechanism: the quickstarts explain their actions
and provide complete copy-paste commands. A packaged release artifact should
replace the staging-directory transfer in a later release.

## User workflow

The administrator supplies accepted model IDs and either a RHEL login or a
gateway URL and caller JWT. Users never need the deployment bundle or provider
keys. Follow the appropriate Claude Code, Codex and OpenCode instructions:

- [All-in-one users](docs/quickstarts/all-in-one/users.md).
- [Remote gateway users](docs/quickstarts/remote-gateway/users.md).

## Development and non-production testing

Repository contributors should start with the [development and testing
guide](docs/testing/README.md).

| Goal | Testing instructions |
| --- | --- |
| Start one disposable Praxis container without installing a service | [Disposable Podman](docs/testing/podman.md) |
| Test images and configuration in the macOS Fedora CoreOS Podman machine | [Fedora CoreOS](docs/testing/fedora-coreos.md) |
| Exercise both installers in a full Fedora VM | [Fedora VM development](docs/testing/fedora-vm.md) |
| Exercise the installer, systemd, SELinux, account separation, logout, and reboot | [Local RHEL 9 VM](docs/testing/rhel-vm.md) |
| Plan and launch two separately controlled RHEL test VMs | [AWS two-VM test guide](docs/testing/aws.md) |
| Test Codex, OpenCode, and Claude Code with protected provider keys, in-memory and Valkey profiles | [Harness acceptance](docs/testing/harnesses.md) |
| OpenShell sandboxing (standalone) | [OpenShell demos](openshell/docs/README.md) |

These paths are for development and pre-production validation. They do not
replace final acceptance on the target RHEL server.

## Target hosts and validation status

The persistent deployment targets RHEL 9 on `x86_64` (`linux/amd64`) and
`aarch64` (`linux/arm64`), with SELinux enforcing, cgroups v2, and Podman 4.6
or newer. Both pinned images contain both architectures; the installer rejects
an image that does not match its host.

Native image tests are automated for both architectures. Full RHEL host and
real-provider harness acceptance remain pending on both; image tests alone
do not qualify a production deployment. See the [validation
matrix](docs/testing/README.md#architecture-qualification).
