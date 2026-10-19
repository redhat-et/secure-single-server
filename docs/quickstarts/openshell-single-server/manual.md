# Manual single-server container deployment

Install OpenShell and a harness sandbox on a dedicated RHEL 9 x86_64 VM or
bare-metal host. Run from a reviewed repository checkout in a Bash session.
For the OS-image route, use the separate [bootc guide](bootc.md).

Use either this manual installation or the bootc image on a given host—not
both. On a bootc-managed host, let `bootc` and `sss-bootc` own deployment and
lifecycle commands; do not run this installer there.

OpenShell runs under a locked service account with rootless Podman. Praxis is
an optional, separately installed model gateway. Review the
[qualification and policy limits](reference.md) before extending this deployment.

## 1. Install OpenShell

Use a dedicated RHEL 9 x86_64 host. For first qualification, use a disposable
instance before changing a long-lived server. Install Git, Podman, Python 3,
OpenSSH clients, curl, and the SELinux management tools. RHEL 9 does not
package `ripgrep`, so install the pinned static binary used by the image:

```bash
sudo dnf install -y git podman python3 policycoreutils openssh-clients curl
rg_version=14.1.1
rg_sha256=4cf9f2741e6c465ffdb7c26f38056a59e2a2544b51f7cc128ef28337eeae4d8e
curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/ripgrep-${rg_version}-x86_64-unknown-linux-musl.tar.gz" -o /tmp/rg.tar.gz
printf '%s  /tmp/rg.tar.gz\n' "${rg_sha256}" | sha256sum -c - &&
  tar -xzf /tmp/rg.tar.gz -C /tmp &&
  sudo install -m 0755 "/tmp/ripgrep-${rg_version}-x86_64-unknown-linux-musl/rg" /usr/local/bin/rg
```

Clone the reviewed repository to a durable, service-readable location, review
the checked-out revision, and run the installer from that directory:

```bash
sudo install -d -o "$(id -un)" -m 0755 /opt/secure-single-server
git clone https://github.com/redhat-et/secure-single-server /opt/secure-single-server
cd /opt/secure-single-server
repo="$PWD"
```

```bash
sudo ./openshell/scripts/install.sh --owner openshell-svc
```

The installer creates the locked `openshell-svc` account, enables lingering so
the gateway remains available after logout, and starts the loopback-only
OpenShell gateway with TLS/mTLS for the service operator.
It first verifies Landlock ABI 3 or newer, then pre-pulls every pinned supported
harness image; the selected harness is chosen when its sandbox is created. If
Landlock is unavailable or too old, installation stops with that kernel
diagnostic instead of a later `ContainerExited` sandbox failure. If it reports
that cgroup delegation needs a host reboot, reboot and rerun the same installer.

## 2. Set up the service-owner shell helper

Run the remaining commands in the same Bash session. The helper runs commands
as the locked OpenShell service account with its home and user bus configured.
Keep the checkout and its parent directories readable by `openshell-svc`.

```bash
repo="$PWD"
uid="$(id -u openshell-svc)"
os_run() {
  sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin \
    XDG_RUNTIME_DIR=/run/user/"$uid" \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
    OPENSHELL_BIN="${OPENSHELL_BIN:-/usr/local/bin/openshell}" \
    "$@"
}
```

The harness scripts look for the OpenShell CLI at `/usr/local/bin/openshell`
by default. Export `OPENSHELL_BIN` before using `os_run` when the CLI lives
elsewhere — on bootc hosts, for example, it is `/usr/bin/openshell`.

## 3. Create and connect the harness

Create the selected harness with its `dev` policy. The profile is part of the
create operation:

```bash
harness=opencode  # opencode or openclaw
os_run "$repo/openshell/harnesses/$harness/create.sh" \
  --profile dev --name "$harness"-dev
```

Connect from the same owner environment:

```bash
os_run "$repo/openshell/harnesses/$harness/connect.sh" --name "$harness"-dev
```

OpenCode launches its CLI. OpenClaw opens a shell for inspecting the sandbox.
For OpenClaw model tasks, configure Praxis and use the
[bounded model and tool workflow](../openshell-praxis/openclaw.md).

To inspect any harness sandbox with a Bash session, pass `bash` as the remote
command instead of modifying the harness script:

```bash
os_run "$repo/openshell/harnesses/$harness/connect.sh" --name "$harness"-dev bash
```

Use `dev` for the initial deployment. Each sandbox defaults to two CPUs, 4 GiB
of memory, and 2048 PIDs. See the [qualification reference](reference.md) for
profile and harness limitations.

## 4. Choose model access

Use the [model endpoint guide](model-access.md). Choose a self-hosted or
private OpenAI-compatible endpoint, route OpenAI through Praxis, or attach a
frontier provider directly for evaluation. Do not paste a provider key into OpenCode or store it in harness
configuration. Follow the
[model verification steps](verification.md#1-prove-model-interaction) after
selecting a route.

## 5. Verify the deployment

Set `sandbox` to the name you created, then verify its runtime ceilings from
the host:

```bash
sandbox=opencode-dev  # use opencode-local or opencode-praxis for those routes
cd /
container_id="$(
os_run podman ps --filter name=openshell-default--"$sandbox" -q)"
os_run podman inspect "$container_id" \
  --format 'cpus={{.HostConfig.NanoCpus}} memory={{.HostConfig.Memory}} pids={{.HostConfig.PidsLimit}}'
```

The expected default is `cpus=2000000000` (two CPUs), `memory=4294967296`
(4 GiB), and `pids=2048`.

Run the controlled policy qualification as the service owner from the reviewed
repository checkout:

```bash
cd /
os_run bash "$repo/openshell/tests/openshell-policy.sh"
```

The test starts a local HTTP fixture, creates temporary allow and deny
sandboxes, proves the allowed request reaches the fixture, and proves the denied
request returns `EACCES` without reaching the server. A `401` from the fixture
is a successful positive control; an external website error is not.

Follow the [harness checks](verification.md) to test workspace writes and,
when model access is configured, inference and tool execution.

## Optional Praxis routing

Install the [Praxis gateway and OpenShell add-on](../openshell-praxis/install.md),
then follow the [OpenCode integration configuration](../openshell-praxis/users.md).
The gateway installation is a prerequisite for the add-on. Use an integrated
sandbox without a direct `--provider` binding. For OpenClaw, follow the
[bounded model and tool workflow](../openshell-praxis/openclaw.md).

## Sandbox operations

For a one-off network requirement, add `--policy-advisor` when creating the
sandbox. After the harness reports a denial and proposal, review and approve it
as the same service owner:

```bash
os_run "$repo/openshell/scripts/policy-approve.sh" list HARNESS-dev
os_run "$repo/openshell/scripts/policy-approve.sh" approve HARNESS-dev --chunk-id PROPOSAL-ID
```

The grant applies only to that sandbox instance and disappears when the sandbox
is recreated. Successful approvals are recorded in a local JSONL audit file.

Inspect the sandbox and remove it only after exporting needed work:

```bash
os_run openshell sandbox list
os_run openshell sandbox delete HARNESS-dev
```

