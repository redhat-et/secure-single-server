# Secure single-server AI harness

[![Documentation](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://redhat-et.github.io/secure-single-server/)
[![Deploy documentation](https://github.com/redhat-et/secure-single-server/actions/workflows/pages.yml/badge.svg)](https://github.com/redhat-et/secure-single-server/actions/workflows/pages.yml)

Secure single-server AI harness runs [OpenCode](https://github.com/anomalyco/opencode)
and [OpenClaw](https://github.com/openclaw/openclaw) on one dedicated RHEL 9
x86_64 host. [OpenShell](https://github.com/NVIDIA/OpenShell/tree/v0.1.4/docs)
enforces the execution boundary. For the integrated harness paths,
[Praxis](https://github.com/praxis/praxis) routes model traffic, while
[Red Hat bootc](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/index)
packages the reviewed deployment as a repeatable OS image.

> **Published documentation.** The rendered guides live at
> [redhat-et.github.io/secure-single-server](https://redhat-et.github.io/secure-single-server/).

## What you can do

- Run OpenCode or OpenClaw in policy-enforced OpenShell sandboxes on one RHEL host.
- Keep model credentials in Praxis and route approved model traffic centrally.
- Deploy a repeatable RHEL 9 bootc image or evaluate the stack locally with Podman.
- Try scenarios such as Praxis quota tuning, the Streamlit security demo, OpenCode PR queue, or delegated PR review.

## How It Works

The integrated request path is:

```text
OpenCode / OpenClaw → OpenShell sandbox → Praxis → approved model
```

OpenCode and OpenClaw keep their coding workflows while Praxis supplies
approved model access, credential custody, routing, and shared quotas.

- **Agent productivity through Praxis.** OpenCode and OpenClaw turn approved
  model access into coding, review, and bounded task workflows without
  receiving provider credentials. Praxis selects the upstream and enforces
  shared limits, so agents remain useful without becoming a credential-management problem.
- **Dedicated always-on execution.** Long-running agents continue on the
  server while your laptop disconnects. Workspaces, audit records, and cached
  model artifacts remain on the host.
- **Policy-enforced harnesses.** OpenShell confines each harness and its tools
  with declared filesystem, network, process, runtime, and service-account
  policies. The gateway records policy decisions for later review.
- **Centralized model access.** On the integrated paths, Praxis owns provider
  credentials and selects the approved upstream. The harness and sandbox do
  not hold provider keys.
- **Repeatable deployment.** Published bootc images carry the OpenShell CLI,
  service configuration, and pinned workload references. First boot pulls the
  selected control-plane and harness images into rootless Podman storage.

## Quickstart

All quickstarts are published on GitHub Pages:

Manual and bootc deployments can use a spare physical server, virtual machine,
or cloud instance. A GPU is required only when serving models locally; frontier
models routed through Praxis do not require one.

- [Manual single-server deployment](https://redhat-et.github.io/secure-single-server/docs/quickstarts/openshell-single-server/manual/):
  install OpenShell on a dedicated RHEL host and create an OpenCode or OpenClaw sandbox.
- [Podman](https://redhat-et.github.io/secure-single-server/docs/quickstarts/podman/):
  inspect a published image or make a direct model call. This evaluation path does not
  run the complete OpenShell sandbox, protect service-account secrets, or start services at boot.
- [Bootc-enabled operating system](https://redhat-et.github.io/secure-single-server/docs/quickstarts/bootc/):
  switch a bootc-managed RHEL host to a reviewed image. The published image uses OpenCode;
  OpenClaw requires a rebuilt image containing that integration.

Scenarios run after deployment. Praxis token quotas show how to inspect and modify a shared
model allowance; the Streamlit security demo compares an unsafe application with its
OpenShell-confined version; the OpenCode PR queue turns issues or prompts into reviewable
patches; and review as a service delegates pull-request review to a restricted OpenCode
sandbox. OpenCode and OpenClaw are the available coding harnesses. Once you have deployed
manually or by bootc, explore the [scenario catalog](docs/examples/README.md) for
prerequisites and evidence.
