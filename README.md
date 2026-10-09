# Secure single-server AI harness

Secure single-server AI harness runs [OpenCode](https://github.com/anomalyco/opencode)
and [OpenClaw](https://github.com/openclaw/openclaw) on one dedicated RHEL 9
x86_64 host. [OpenShell](https://github.com/NVIDIA/OpenShell/tree/v0.1.2/docs)
enforces the execution boundary. For the OpenCode path,
[Praxis](https://github.com/praxis/praxis) routes model traffic, while
[Red Hat bootc](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/index)
packages the reviewed deployment as a repeatable OS image.

> [!IMPORTANT]
> This is an experimental demonstration, not a production-ready platform. Use
> a disposable host for first evaluation and review the linked qualification
> evidence before extending a deployment.

## How It Works

The validated OpenCode request path is:

```text
OpenCode → OpenShell sandbox → Praxis → approved model
```

OpenClaw is available as an OpenShell sandbox variant; its Praxis adapter is
not yet qualified.

- **Dedicated always-on execution.** Long-running agents continue on the
  server while your laptop disconnects. Workspaces, audit records, and cached
  model artifacts remain on the host.
- **Policy-enforced harnesses.** OpenShell confines each harness and its tools
  with declared filesystem, network, process, runtime, and service-account
  policies. The gateway records policy decisions for later review.
- **Centralized model access.** On the OpenCode path, Praxis owns provider
  credentials and selects the approved upstream. The harness and sandbox do
  not hold provider keys.
- **Repeatable deployment.** Published bootc images carry the OpenShell CLI,
  service configuration, and pinned workload references. First boot pulls the
  selected control-plane and harness images into rootless Podman storage.

## Quickstart

Use a disposable RHEL 9 x86_64 host that is already bootc-managed. Select the
published image for one harness, then reboot. Set `harness` to `opencode` or
`openclaw`:

```shell
harness=opencode  # or openclaw
image="quay.io/redhat-et/secure-single-server-${harness}:v0.1"
sudo bootc switch "$image"
sudo bootc status
sudo systemctl reboot
```

After reboot, reconnect and set `harness` to the same value. Then verify the
deployment and create a sandbox:

```shell
harness=opencode  # or openclaw
sandbox="${harness}-dev"
sudo sss-bootc openshell --version
sudo sss-bootc harness create --profile dev --name "$sandbox"
sudo sss-bootc harness connect --name "$sandbox"
```

To deploy the individual containers on a fresh VM or bare-metal host, follow the
[manual single-server guide](docs/quickstarts/openshell-single-server/manual.md)
to install OpenShell and create an OpenCode or OpenClaw harness sandbox. To add
Praxis for model routing and provider secrets, follow the
[Praxis installation walkthrough](docs/quickstarts/openshell-praxis/install.md),
including its prerequisite gateway setup and optional local inference.

## Explore Further

- [Architecture walkthrough](docs/quickstarts/architecture-walkthrough/README.md):
  why each layer exists and what its evidence does not prove.
- [Manual single-server guide](docs/quickstarts/openshell-single-server/manual.md):
  OpenShell installation, harness setup, verification, and policy tests.
- [OpenShell trust model](openshell/docs/threat-model.md): the execution
  boundary and assumptions behind the current single-operator deployment.
- [Praxis integration](docs/quickstarts/openshell-praxis/README.md): model
  routing, quota semantics, and the experimental OpenCode path.
- [Private vLLM inference](bootc/VLLM.md): the separate CPU or GPU server used
  by the strongest validated local-model path.
- [Published bootc images](bootc/README.md): available OpenCode and OpenClaw
  variants and their deployment commands.
- [Testing and compatibility](docs/testing/README.md): how to reproduce the
  recorded checks and review the compatibility matrix.
- [Documentation map](docs/README.md): alternate deployment shapes and
  configuration guides.

## Notice and Disclaimer

This demonstration retrieves pinned external container images and, when local
inference is enabled, model artifacts. Those materials are governed by their
own terms, licenses, and security posture. You are responsible for reviewing
and complying with those terms and for verifying that the artifacts are
suitable for your environment. This repository is provided for demonstration
and evaluation purposes, without warranty of any kind.
