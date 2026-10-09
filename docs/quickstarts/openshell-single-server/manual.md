# Manual single-server container deployment

Install OpenShell and a harness sandbox on a dedicated RHEL 9 x86_64 VM or
bare-metal host. Run from a reviewed repository checkout in a Bash session.
For the OS-image route, use the separate [bootc guide](bootc.md).

OpenShell runs under a locked service account with rootless Podman. Praxis is
an optional, separately installed model gateway. Review the
[qualification and policy limits](reference.md) before extending this deployment.

## 1. Install OpenShell

Use a dedicated RHEL 9 x86_64 host. For first qualification, use a disposable
instance before changing a long-lived server. On the host, install Podman,
Python 3, OpenSSH clients, curl, and the SELinux management tools, then
transfer or check out the reviewed repository revision. Run from the repository
root:

```bash
sudo dnf install -y podman python3 policycoreutils openssh-clients curl
```

```bash
sudo openshell/scripts/install.sh --owner openshell-svc
```

The installer creates the locked `openshell-svc` account, enables lingering so
the gateway remains available after logout, and starts the loopback-only
OpenShell gateway with TLS/mTLS for the service operator.
It pre-pulls every pinned supported harness image; the selected harness is
chosen when its sandbox is created. If it reports that cgroup delegation needs
a host reboot, reboot and rerun the same installer.

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
    "$@"
}
```

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

OpenCode launches its CLI. OpenClaw opens a shell in the sandbox because its
service command and authentication are not yet qualified.

Use `dev` for the initial deployment. Each sandbox defaults to two CPUs, 4 GiB
of memory, and 2048 PIDs. See the [qualification reference](reference.md) for
profile and harness limitations.

## 4. Choose model access

Standalone model credentials are never forwarded through the SSH helper. If a
reviewed deployment needs one, import an administrator-reviewed provider
profile, register the credential from a hidden prompt in the service-owner
environment, and attach it explicitly with `create.sh --provider NAME`:

```bash
os_run bash -c '
openshell profile lint -f /path/to/reviewed-provider-profile.yaml
openshell profile import -f /path/to/reviewed-provider-profile.yaml
read -r -s -p "Synthetic provider key: " PROVIDER_KEY; printf "\n"
export PROVIDER_KEY
openshell provider create --name test-provider --type openai \
  --credential PROVIDER_KEY
unset PROVIDER_KEY
'
```

Use synthetic credentials first. If you select the optional OpenCode Praxis
integration, do not attach a direct provider: integrated mode rejects the
binding and the separate [Praxis workflow](../openshell-praxis/README.md)
documents its own qualification limits.

When creating a standalone sandbox that uses the registered provider, append
`--provider test-provider` to the selected `create.sh` command. Use a new name
if the earlier sandbox already exists:

```bash
os_run "$repo/openshell/harnesses/$harness/create.sh" \
  --profile dev --name "$harness"-provider --provider test-provider
```

## 5. Verify the deployment

Set `sandbox` to the name you created, then verify its runtime ceilings from
the host:

```bash
sandbox="${harness}-dev"  # or "${harness}-provider" for the provider example
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
OpenCode sandbox without a direct `--provider` binding. OpenClaw + Praxis is
unsupported.

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

