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

The published bootc image can be booted on a bootc-enabled OS or run as an OCI
container with Podman. Booting it starts the complete OpenShell deployment;
running a shell in Podman lets you inspect the image. For a working Podman-only
model call, use the Praxis example below.

Allow about five minutes **after the host is ready and images are cached**.
Initial downloads, OS installation/reboot, and local-model loading add time.
Use Bash and a disposable RHEL 9 x86_64 host. Have an OpenAI API key and an
exact model ID available to your account ready. OpenCode is the model-enabled
quickstart; OpenClaw model authentication remains unqualified.

### Bootc-enabled operating system

On an existing bootc-managed host, select the image and reboot:

```bash
image=quay.io/redhat-et/secure-single-server-opencode:v0.1
sudo bootc switch "$image"
sudo bootc status
sudo systemctl reboot
```

Reconnect after reboot and wait for the deployment service to finish:

```bash
sudo systemctl start secure-single-server.service
sudo sss-bootc openshell --version
```

Enter your OpenAI key at the hidden prompt. Praxis stores it in a Podman secret;
it is not put in the image or harness. The default cloud configuration requires
an Anthropic secret too; the unused value below allows OpenAI-only evaluation
and cannot authenticate Anthropic requests. Use fresh secret versions if `v1`
already exists.

```bash
(
  set +x
  set -euo pipefail
  sudo -v
  IFS= read -r -s -p 'OpenAI API key: ' key; printf '\n'
  printf '%s' "$key" | sudo sss-bootc secret openai v1
  unset key
  printf '%s' 'unused-anthropic-key' | sudo sss-bootc secret anthropic v1
  sudo sss-bootc activate praxis-openai-api-key-v1 praxis-anthropic-api-key-v1
  sudo sss-bootc inference cloud
)
```

Select your model, create the OpenCode sandbox configured for Praxis, and connect:

```bash
IFS= read -r -p 'OpenAI model ID: ' model_id
uid="$(id -u openshell-svc)"
cd /
sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
  XDG_RUNTIME_DIR=/run/user/"$uid" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
  OPENSHELL_BIN=/usr/bin/openshell OPENSHELL_MODEL_ID="$model_id" \
  /usr/share/secure-single-server/openshell/harnesses/opencode/create.sh \
  --profile dev --name opencode-dev \
  --config /usr/share/secure-single-server/configs/openshell-praxis
sudo sss-bootc harness connect --name opencode-dev
```

Ask `Reply with a short greeting.` A nonempty response verifies model access;
use the [harness checks](docs/quickstarts/openshell-single-server/verification.md)
to verify tools and policy. For an existing local API and key, use the
[local endpoint recipe](docs/quickstarts/openshell-single-server/bootc.md#local-openai-compatible-endpoint-and-key).
For the bundled private vLLM route, use
[Praxis/vLLM setup](docs/quickstarts/openshell-single-server/bootc.md#praxis-cloud-secrets-or-private-vllm).

### Run the bootc image in Podman

No model credentials or container environment variables are needed to inspect
the bootc image. Set `harness` to `opencode` or `openclaw`:

```bash
harness=opencode
image="quay.io/redhat-et/secure-single-server-${harness}:v0.1"
podman run --rm -it --entrypoint /bin/bash "$image"
```

Inside the container, run `openshell --version` or `sss-bootc help`; use `exit`
to leave. This command starts Bash, not the boot services. Running the complete nested
OpenShell deployment inside this container is not a qualified deployment path.
Use the bootc host or [manual container guide](docs/quickstarts/openshell-single-server/manual.md)
for sandboxed harness execution.

### Podman-only model call

For a quick inference check without installing an OS image, run the Praxis
workload directly. From a reviewed repository checkout with Podman installed,
set `OPENAI_API_KEY` at the hidden prompt and `MODEL_ID` to an accessible model.
`ANTHROPIC_API_KEY` must also exist for the two-provider config; leave it empty
when only calling OpenAI. `PRAXIS_IMAGE` pins the workload image.

```bash
set +x
IFS= read -r -s -p 'OpenAI API key: ' OPENAI_API_KEY; printf '\n'
export OPENAI_API_KEY
export ANTHROPIC_API_KEY=''
IFS= read -r -p 'OpenAI model ID: ' MODEL_ID
export PRAXIS_IMAGE='quay.io/opendatahub/praxis-experimental@sha256:a3006352106c2264427faa79b57cf7b49287f3f9bfffe9b2eef869d3429988e8'
podman run --rm --detach --name praxis-demo \
  --user 1001:1001 --userns keep-id:uid=1001,gid=1001 \
  --read-only --security-opt no-new-privileges --cap-drop all \
  --publish 127.0.0.1:8080:8080 --publish 127.0.0.1:8081:8081 \
  --env OPENAI_API_KEY --env ANTHROPIC_API_KEY \
  --volume "$PWD/configs/all-in-one/shared-gateway.yaml:/etc/praxis/shared-gateway.yaml:ro,Z" \
  "$PRAXIS_IMAGE" -c /etc/praxis/shared-gateway.yaml
unset OPENAI_API_KEY ANTHROPIC_API_KEY
python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":"Reply with a short greeting."}]}))' "$MODEL_ID" | \
  curl --fail-with-body --retry 10 --retry-connrefused --retry-delay 1 \
  http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer local-placeholder' -d @-
# When finished:
podman stop praxis-demo
```

This verifies the Praxis model route; it does not run an OpenShell sandbox.
The demo container receives the provider key through its environment. For
protected service-account secrets and startup at boot, use the deployment
guides. See [Podman details](docs/testing/podman.md).

To install OpenShell, harnesses, and Praxis separately on a fresh VM or bare
metal, follow the [manual single-server guide](docs/quickstarts/openshell-single-server/manual.md)
and [Praxis installation walkthrough](docs/quickstarts/openshell-praxis/install.md).

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
