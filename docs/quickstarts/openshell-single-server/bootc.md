# Single-server bootc deployment

Use this route for the published OS image. For individual container installation,
use the [manual guide](manual.md). Review the [qualification and policy limits](reference.md).


The quick path uses the project's published RHEL bootc image. Select exactly one
harness variant:

```text
quay.io/redhat-et/secure-single-server-opencode:v0.1
quay.io/redhat-et/secure-single-server-openclaw:v0.1
```

This demonstration intentionally uses the mutable `v0.1` tags directly. The
image contains the optional Praxis service, but it does not become a model
route until its separate secrets and activation workflow are configured; the
OpenShell sandbox checks do not depend on that service.

### Apply the image to an existing bootc host

On a booted RHEL image-mode host, deploy the selected image and reboot:

```console
sudo bootc switch quay.io/redhat-et/secure-single-server-opencode:v0.1
sudo bootc status
sudo systemctl reboot
```

Use the OpenClaw image reference instead when that is the selected harness.
Switching variants replaces the selected harness configuration; it does not
migrate existing sandboxes. Export and recreate them as needed.

### Apply the image to a fresh single server or bare-metal host

For a fresh VM or bare-metal host, use a standard bootc deployment workflow
and supply the selected published image as the source. Do not create or
substitute a locally built image. First boot pulls the pinned control-plane
and selected harness images.

### Experiment with the container image in Podman

A bootc image is also a standard OCI container image. For lightweight
userspace experimentation, pull the published tag and start an interactive
shell with Podman. Replace the OpenCode reference with the OpenClaw variant
when needed:

```bash
podman pull quay.io/redhat-et/secure-single-server-opencode:v0.1
podman run --rm -it quay.io/redhat-et/secure-single-server-opencode:v0.1 bash
```

This does not boot the OS or run the boot reconciliation service, so it cannot
validate the always-on OpenShell gateway, lingering service account, host
SELinux state, or sandbox lifecycle. Use the VM or bare-metal deployment for
those qualification checks.

### Verify and create the sandbox

After boot, SSH to the administrator account and verify the deployment:

```console
sudo journalctl -u secure-single-server.service -b
sudo systemctl status secure-single-server.service --no-pager
sudo sss-bootc openshell --version
sudo sss-bootc openshell sandbox list
```

The default bootc service can leave its optional model-routing service waiting
for separately provisioned secrets while OpenShell is already ready. Complete
standalone model access with the provider guidance in
[manual provider setup](manual.md#4-choose-model-access), or select the optional
[model-routing guide](../openshell-praxis/README.md), before running the model
prompt below. The OpenShell policy and sandbox commands do not require that
optional service to be active.

Create and connect the sandbox with the selected policy:

```console
sudo sss-bootc harness create --profile dev --name opencode-dev
sudo sss-bootc harness connect --name opencode-dev
```

For the OpenClaw image, use `openclaw-dev` as the name. OpenCode launches its
CLI; OpenClaw opens a shell because its browser service command is not yet
qualified.

The bootc service uses locked, separate rootless accounts and enables lingering.
OpenShell listens only on loopback ports 8090/8091. Keep SELinux Enforcing and
do not expose the management port beyond the host.
Reach the host remotely through your normal administrator SSH path, for example
`ssh -t ADMIN_USER@RHEL_HOST`, and then run `sudo sss-bootc harness connect`.
Do not publish OpenShell's management port to make remote access work.

Confirm the runtime ceilings from the administrator account:

```bash
cd /
uid="$(id -u openshell-svc)"
sandbox=opencode-dev
container_id="$(
sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
  PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
  XDG_RUNTIME_DIR=/run/user/"$uid" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
  podman ps --filter name=openshell-default--"$sandbox" -q)"
sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
  PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
  XDG_RUNTIME_DIR=/run/user/"$uid" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
  podman inspect "$container_id" \
  --format 'cpus={{.HostConfig.NanoCpus}} memory={{.HostConfig.Memory}} pids={{.HostConfig.PidsLimit}}'
```

Use the selected sandbox name and expect the same two-CPU, 4 GiB, 2048-PID
limits used by the manual deployment.

To run the controlled policy qualification on a quickstart host, copy the
reviewed repository to a temporary service-readable location:

```bash
uid="$(id -u openshell-svc)"
reviewed_checkout="$HOME/secure-single-server"
sudo rm -rf /var/tmp/secure-single-server-policy
sudo install -d -m 0755 /var/tmp/secure-single-server-policy
for directory in openshell scripts configs; do
  sudo cp -a "$reviewed_checkout/$directory" /var/tmp/secure-single-server-policy/
done
sudo chown -R root:"$(id -gn openshell-svc)" /var/tmp/secure-single-server-policy
sudo chmod -R u=rwX,g=rX,o= /var/tmp/secure-single-server-policy
cd /
repo=/var/tmp/secure-single-server-policy
sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
  PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
  XDG_RUNTIME_DIR=/run/user/"$uid" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
  OPENSHELL_BIN=/usr/bin/openshell \
  bash "$repo/openshell/tests/openshell-policy.sh"
sudo rm -rf /var/tmp/secure-single-server-policy
```

Follow the [harness checks](verification.md) after deployment. For optional model
routing, see the [OpenShell + Praxis guide](../openshell-praxis/README.md).
