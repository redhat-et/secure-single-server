# OpenShell + Praxis Installation

## Prerequisites

- RHEL 9 with rootless Podman 4.6 or newer
- Praxis all-in-one gateway installed and healthy (see `docs/install.md`)
- Root access for OpenShell gateway installation

## Step 1: Verify Praxis All-in-One

Before installing the openshell-praxis scenario, ensure the Praxis all-in-one gateway is running:

```bash
curl -fsS http://127.0.0.1:8081/healthz
```

Expected response: `{"status":"ok"}` or similar healthy status.

Verify the scenario file:

```bash
sudo cat /etc/praxis-shared-gateway/gateway.scenario
```

Expected output: `all-in-one`

## Step 2: Install OpenShell + Praxis Integration

Run the openshell-praxis scenario installer:

```bash
sudo scripts/openshell-praxis/install
```

This installer will:

1. **Validate Praxis** — Confirm all-in-one gateway is installed and healthy
2. **Enable rootless Podman socket** — For the OpenShell gateway
3. **Configure cgroup delegation** — For nested containers
4. **Generate JWT signing keys** — For sandbox authentication
5. **Pull pinned images** — OpenShell gateway, supervisor, and harness images
6. **Install OpenShell CLI binary** — At `/usr/local/bin/openshell`
7. **Start OpenShell gateway** — Binds to `127.0.0.1:8090` (gRPC) and `:8091` (health)
8. **Record scenario** — Updates `/etc/praxis-shared-gateway/gateway.scenario` to `openshell-praxis`

## Step 3: Verify Installation

Check the OpenShell gateway health:

```bash
curl -fsS http://127.0.0.1:8091/healthz
```

Check the Praxis gateway health (should still be running):

```bash
curl -fsS http://127.0.0.1:8081/healthz
```

Verify the scenario was recorded:

```bash
sudo cat /etc/praxis-shared-gateway/gateway.scenario
```

Expected output: `openshell-praxis`

## Port Summary

After installation, the following ports are in use on loopback:

| Service               | Port | Protocol | Purpose                          |
|-----------------------|------|----------|----------------------------------|
| Praxis gateway        | 8080 | HTTP     | Model proxy (OpenAI-compatible)  |
| Praxis health         | 8081 | HTTP     | Health/metrics endpoint          |
| OpenShell gateway     | 8090 | gRPC     | Sandbox management               |
| OpenShell health      | 8091 | HTTP     | Health/status endpoint           |

## Host Alias Reachability

The integrated scenario depends on `host.openshell.internal` resolving inside bridge-networked sandbox containers to reach the Praxis loopback gateway on the host. This reachability is validated by the host smoke test (Task 11); the installer does not verify it.

## Troubleshooting

### Praxis not healthy

If Praxis is not healthy, check the service status:

```bash
sudo systemctl --user -M praxis-shared-gateway@ status praxis.service
```

Reinstall or repair the all-in-one gateway before proceeding with openshell-praxis.

### OpenShell install fails

Check that the user running the install has rootless Podman enabled:

```bash
systemctl --user status podman.socket
```

If cgroup delegation fails, you may need to log out and back in after the installer applies the systemd configuration.

### Port conflicts

If ports 8090 or 8091 are already in use, you will see an error during install. Identify the conflicting process:

```bash
ss -ltn | grep ':809[01]'
```

Stop the conflicting service before retrying.

## Next Steps

- [User Guide](users.md) — Create harness sandboxes with integrated profiles
- [README](README.md) — Understand the architecture and security properties
