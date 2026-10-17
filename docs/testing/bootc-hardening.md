# Bootc service hardening

> **Where this fits:** Why the bootc reconciler units carry the sandbox flags
> they do, and what still has to be confirmed on a booted host.

The bootc image runs three oneshot reconciler services. Each one prepares a
workload and then exits:

| Unit | Script | Workload |
| --- | --- | --- |
| `secure-single-server.service` | `bootc/scripts/reconcile` | Praxis and OpenShell |
| `secure-single-server-praxis.service` | `bootc/scripts/praxis` | Standalone Praxis |
| `secure-single-server-vllm.service` | `bootc/scripts/vllm` | Optional vLLM |

All three set `UMask=0077`, `NoNewPrivileges=true` and `PrivateTmp=true`. The
container units that these reconcilers write into
`/etc/containers/systemd/users/<uid>/` set `NoNewPrivileges=true` as well, and
`tests/shared-gateway-static.sh` fails the build when a rendered container
manifest drops it.

## Why `NoNewPrivileges=true` does not break rootless Podman

A review of `secure-single-server-praxis.service` raised the concern that
`NoNewPrivileges` prevents the setuid/capability `newuidmap` and `newgidmap`
helpers from applying the subordinate UID/GID ranges that the installer
provisions for `praxis-svc`. If that were true, the reconciler would fail at its
first rootless Podman call, so the concern is worth answering precisely.

`NoNewPrivileges` is retained because it cannot reach the code that creates the
container's user namespace:

1. **The user namespace is created by the `praxis-svc` user manager, not by the
   service.** The reconciler only asks for the work over D-Bus with
   `as_service systemctl --user restart praxis.service`. The user manager starts
   the quadlet container as one of *its* units; it is not a descendant of the
   oneshot system service, so the system service's `NoNewPrivileges` is not
   inherited along that path. `NoNewPrivileges` is a per-process attribute and
   is not carried across a D-Bus request.
2. **The reconciler's own Podman calls never create a user namespace.** Through
   `as_service` it runs `podman image exists`, `podman pull` and
   `podman image inspect`; those are image operations that need no UID mapping.
   The mapping is only requested when the quadrant container starts, which is
   case 1.

`NoNewPrivileges` does survive `setpriv --no-new-privs` and `runuser`, so the
concern is still testable directly, and it does not hold on a current Podman.
Measured on Fedora 42 with rootless Podman 5.7.1 and SELinux Enforcing, where
`/usr/bin/newuidmap` and `/usr/bin/newgidmap` carry
`cap_setuid=ep`/`cap_setgid=ep` rather than the setuid bit:

```console
sudo setpriv --no-new-privs runuser -u "$USER" -- grep NoNewPrivs /proc/self/status
```

```text
NoNewPrivs: 1
```

```console
sudo setpriv --no-new-privs runuser -u "$USER" -- \
  env XDG_RUNTIME_DIR="/run/user/$(id -u "$USER")" \
  podman run --rm --userns keep-id:uid=1001,gid=1001 \
  docker.io/library/alpine:latest id
```

```text
uid=1001(test) gid=1001(1001) groups=1001(1001)
```

Inside that container `NoNewPrivs` reads `1` and `/proc/self/uid_map` is
byte-identical to the same run without `setpriv`, so the keeper mapping was
applied normally. The container's own `NoNewPrivileges=true` is what actually
constrains the workload, and it is set by the quadlet, inside the namespace.

## What still needs confirmation

The measurement above is Fedora 42 Podman 5.7.1. The bootc images are built
`FROM ${RHEL_BOOTC_IMAGE}` and ship RHEL 9's Podman, so confirm the same path on
a freshly booted image before treating it as qualified:

```console
sudo systemctl show secure-single-server-praxis.service \
  -p NoNewPrivileges -p PrivateTmp -p UMask
sudo systemctl status secure-single-server-praxis.service --no-pager
sudo sss-praxis status
```

`bootc/test-host` performs these checks, including the `praxis-shared-gateway`
health status through `as_service`, and is the supported way to run them on a
booted host. A pass there is the evidence that the reconciler reached its
rootless Podman workload under enforcement.

Outstanding work that this document does not yet contain evidence for:

- A booted RHEL 9 image on the pinned `RHEL_BOOTC_IMAGE` digest, rather than a
  Fedora development host.
- A `grep`-based assertion in CI that the three systemd units keep
  `NoNewPrivileges=true`, `PrivateTmp=true` and `UMask=0077`, and that the
  quadlet templates keep `NoNewPrivileges=true`. Only the rendered container
  manifests are asserted today.
- The SELinux-enforcing lane described in
  [Testing](README.md#local-development-checks); no CI job runs these container
  suites with Podman on an enforcing host, so `:z`/`:Z` mount options are
  currently only exercised as syntax by the Docker-based jobs.
