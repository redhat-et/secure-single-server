# Introduction

> **Published documentation:** This introduction and the guides it links are published at
> [redhat-et.github.io/secure-single-server](https://redhat-et.github.io/secure-single-server/).
> The repository [home page](../README.md) is the published landing page.

This site follows one path:

1. Understand what the stack protects.
2. Choose a deployment shape.
3. Run a scenario that shows the value.
4. Reproduce the evidence before relying on it.

## What each part gives you

| Component | Value | Start here |
| --- | --- | --- |
| OpenShell | A policy-enforced sandbox for harness tools, files, processes, and network access | [Architecture walkthrough](quickstarts/architecture-walkthrough/README.md) |
| OpenCode / OpenClaw | Coding agents that keep their normal workflow inside a managed boundary | [Single-server deployment](quickstarts/openshell-single-server/README.md) |
| Praxis | Central custody of model credentials, routing, and shared token limits | [OpenShell + Praxis](quickstarts/openshell-praxis/README.md) |
| bootc | A repeatable RHEL 9 OS image carrying the reviewed deployment | [Bootc quickstart](quickstarts/bootc/README.md) |
| vLLM | Optional private local-model inference on a separate CPU or GPU server | [vLLM deployment](quickstarts/vllm/README.md) |
| Operator CLI | Install, secret, quota, harness, and status commands for the managed host | [Bootc operations](quickstarts/openshell-single-server/bootc.md) |

The value is not that the agents become smarter. The value is that their
powers become bounded, auditable, and operable on one server.

## Choose a deployment path

| Goal | Path |
| --- | --- |
| Understand the architecture before changing a host | [Architecture walkthrough](quickstarts/architecture-walkthrough/README.md) |
| Inspect the published image or make a local model call | [Podman quickstart](quickstarts/podman/README.md) |
| Deploy the complete stack on a bootc-managed RHEL host | [Bootc quickstart](quickstarts/bootc/README.md) |
| Install OpenShell and harnesses manually | [Manual single-server guide](quickstarts/openshell-single-server/manual.md) |
| Centralize model access with Praxis | [OpenShell + Praxis guide](quickstarts/openshell-praxis/README.md) |
| Serve multiple accounts from one RHEL host | [All-in-one gateway](quickstarts/all-in-one/README.md) |
| Connect harnesses on remote client machines | [Remote HTTPS/JWT gateway](quickstarts/remote-gateway/README.md) |

If this is your first exposure, start with the architecture walkthrough. If you
already understand the model and only need a disposable evaluation, use the
bootc quickstart.

## Scenarios

Scenarios begin after a reviewed deployment is running. They show what the
boundary changes in practice:

- [Streamlit before and after OpenShell](examples/streamlit-security/README.md)
  demonstrates credential substitution and filesystem confinement.
- [Praxis token quotas](examples/praxis-quotas/README.md) show how to inspect,
  modify, and verify a shared model-token allowance.
- [OpenCode PR-candidate queue](examples/opencode-pr-queue/README.md)
  turns selected issues or prompts into reviewable patch bundles without
  giving the agent GitHub write access.
- [Review as a service](development/review-service.md) delegates pull-request
  review to a restricted sandbox that can read public repositories but cannot
  push or comment.

See the [scenario index](examples/README.md) for prerequisites and the evidence
each scenario does and does not claim.

## Build confidence

- [Architecture walkthrough](quickstarts/architecture-walkthrough/README.md):
  what each layer protects and what it does not.
- [Verification](quickstarts/openshell-single-server/verification.md):
  prove model access, tools, and policy on your own host.
- [Testing and compatibility](testing/README.md): reproduce the recorded checks
  and review the supported combinations.
- [Threat model](../openshell/docs/threat-model.md): understand the execution
  boundary and its assumptions.

A successful demo is a workflow result, not a substitute for qualification.

## Where files and URLs live

Use the following locations when a guide names a file, command, image, or URL.

| Reference | Where it lives |
| --- | --- |
| Repository paths such as `openshell/`, `configs/`, or `scripts/` | In this repository; rendered guides link back to the reviewed source |
| Deployed checkout on a bootc image | `/usr/share/secure-single-server` |
| Deployed checkout from the manual guide | `/opt/secure-single-server` |
| Host configuration and state such as `/etc/secure-single-server`, `/etc/praxis`, or `/var/lib/` | On the RHEL host, not in the repository checkout |
| Sandbox paths such as `/sandbox`, `/home/node/.openclaw/workspace`, or `/app` | Inside the OpenShell sandbox, governed by the selected policy |
| Local service URLs such as `http://127.0.0.1:8080` | On the RHEL host that runs the service; use the remote gateway URL from clients |
| Published images such as `quay.io/redhat-et/secure-single-server-*` | Listed with deployment commands in [RHEL 9 bootc images](../bootc/README.md) |
| Test evidence under `.state/` or `evidence/` | In the workstation checkout that ran the test; both paths are gitignored |

## Next step

Start with the [architecture walkthrough](quickstarts/architecture-walkthrough/README.md).
If you already understand the system and only need a disposable evaluation,
use the [bootc quickstart](quickstarts/bootc/README.md).
