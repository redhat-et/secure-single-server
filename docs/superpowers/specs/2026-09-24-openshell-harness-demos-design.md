# OpenShell three-harness demonstrations — design

**Date:** 2026-09-24
**Repository:** `redhat-et/secure-single-server`
**Base branch:** `feat/gateway-scenarios` (PR #2 — scenario restructuring)
**Status:** Draft for review

## Summary

Add OpenShell sandboxing demonstrations to `secure-single-server` so the
repository tells complementary single-server security stories on one
private RHEL 9 host:

1. **Praxis gateway** (existing, PR #2 scenarios) — an
   administrator-managed inference gateway that withholds upstream
   provider credentials from coding harnesses.
2. **OpenShell sandboxing (standalone)** (new) — deny-by-default
   network, Landlock filesystem, and non-root process isolation around
   three coding harnesses: **Claude Code**, **OpenCode**, and
   **OpenClaw** (`github.com/anthropics/openclaw`; **not** NemoClaw).
3. **Integrated scenario** (new) — the harness runs inside an OpenShell
   sandbox whose model egress is locked to the **Praxis all-in-one
   gateway on loopback**, combining both models: Praxis withholds
   provider credentials *and* OpenShell filters network / filesystem /
   process.

The work builds on PR #2's scenario framework (`scripts/common`,
`configs/common`, per-scenario directories) and does not change Praxis
demo behavior or its `validate.yml`.

## Goals

- Run each of the three harnesses inside an OpenShell sandbox on RHEL 9,
  under four capability-graded policy profiles
  (`review`/`dev`/`automation`/`interactive`).
- Deploy OpenShell from **pinned odh quay images** (supervisor,
  gateway, cli, sandbox) via rootless Podman **quadlet**, pinned by
  `@sha256:` digest, reusing `scripts/common/lib.sh` helpers.
- Provide an **integrated scenario** that routes OpenShell sandbox model
  traffic through the Praxis all-in-one gateway (loopback `:8080`).
- Provide example policies plus a short teaching pointer showing a live
  deny-by-default -> github-allow transition.
- Add a second GitHub Actions workflow that continually verifies the
  demos with static checks, pinned-image boots, and behavioral policy
  proofs — **without provider credentials**.

## Non-goals

- No changes to Praxis demo behavior or its `validate.yml`.
- No building or publishing of custom harness images (harnesses are
  installed into the odh sandbox base at create-time).
- No end-to-end runs against real providers in CI (no secrets).
- NemoClaw is explicitly **not** used.

## Background: components we build on

### OpenShell runtime

- **gateway** — control plane. Spawns sibling sandbox containers via the
  rootless Podman driver; needs the Podman socket and a
  `/var/lib/openshell` bind-mount whose source path equals its target
  path. Publishes gRPC/control `:8080`, health `:8081`.
- **supervisor image** — the `openshell-sandbox` binary is extracted
  from it on first start and cached under `XDG_DATA_HOME`.
- **sandbox image** — the default base a sandbox (and its harness) runs
  in.
- **cli** — `openshell` (`sandbox create`, `provider create`,
  `policy apply`, `logs`, ...).

odh images:
`quay.io/opendatahub/odh-openshell-{supervisor,gateway,cli,sandbox}`.

### PR #2 framework (base branch `feat/gateway-scenarios`)

- Scenario-first repo: `all-in-one` and `remote-gateway` scenarios over
  a shared `common/`.
- Generic installer: `scripts/common/install --scenario <name>` with
  thin `scripts/<scenario>/install` wrappers, plus
  `scripts/common/{uninstall,upgrade,verify,status,secret-set}` and
  `scripts/common/lib.sh` (`oci_architecture`, digest-pinned
  `DEFAULT_*_IMAGE`, `SCENARIO_FILE`/`PROFILE_FILE`/`MANIFEST_FILE`,
  `die`/`note`/`require_*`).
- Quadlet templates under `configs/common/quadlet/*.container.in`,
  rendered with pinned image references, `Pull=never`, loopback
  `PublishPort`.
- Docs under `docs/quickstarts/<scenario>/` and `docs/testing/`; tests
  under `tests/<area>/`; `validate.yml` matrix (amd64 + arm64) runs
  static checks and boots pinned images without keys.

**Naming caution:** `configs/remote-gateway/policy.yaml` is a **Praxis
JWT-identity plugin** policy — a different schema from an OpenShell
sandbox `policy.yaml`. OpenShell policies are namespaced under
`profiles/<p>/policy.yaml` inside the OpenShell directories to avoid
confusion.

Reused patterns from siblings: `harness-shell-lab` (per-harness
`<harness>-sandbox` CLI shape, four profile policies, OpenClaw as an npm
gateway with a Control UI on `18789`); `cooktheryan/openshell-lab` (the
deny -> allow teaching progression).

## Directory layout

Standalone OpenShell tree (self-contained; borrows `scripts/common/lib.sh`
helpers, not the scenario installer):

```
openshell/
  configs/
    images.env.in                     # single source of truth: odh image digests
    quadlet/openshell-gateway.container.in
    quadlet/openshell.network
    gateway/gateway.toml              # podman driver, deny-by-default
  harnesses/
    claude/   { create.sh, connect.sh, README.md,
                profiles/{review,dev,automation,interactive}/policy.yaml }
    opencode/ { ...same shape... }
    openclaw/ { ...same shape... }    # connect.sh port-forwards 18789
  scripts/{ install.sh, uninstall.sh, lib.sh }   # sources scripts/common/lib.sh
  docs/{ README.md, quickstarts/{claude,opencode,openclaw}.md,
         policy-walkthrough.md, threat-model.md }
  tests/{ openshell-static.sh, openshell-image.sh, openshell-policy.sh }
```

Integrated scenario (plugs into the PR #2 framework):

```
scripts/openshell-praxis/install        # -> scripts/common/install --scenario openshell-praxis
configs/openshell-praxis/
  gateway.toml                          # OpenShell podman driver
  harness-provider.json.in              # harness -> Praxis loopback baseURL
  profiles/{review,dev,automation,interactive}/policy.yaml  # model egress = loopback Praxis only
docs/quickstarts/openshell-praxis/{README.md, install.md, users.md}
tests/openshell-praxis/{image.py|.sh, security.*}
```

Top-level `README.md` gains an "OpenShell sandboxing" scenario row and a
combined "Praxis + OpenShell (integrated)" row alongside the existing
Praxis scenario rows.

## Component design

### OpenShell runtime (pinned odh images via quadlet)

- `configs/images.env.in` holds the four `@sha256:` digests; the only
  place they appear. `openshell/scripts/install.sh` renders `.in`
  templates from it, reusing `scripts/common/lib.sh` (`oci_architecture`,
  render helpers, `die`/`require_*`).
- `openshell-gateway.container.in` (rootless quadlet, modeled on
  `configs/common/quadlet/praxis.container.in`): pinned gateway digest,
  `Pull=never`, `PublishPort=127.0.0.1:8080:8080` and `:8081:8081`,
  `gateway.toml` mounted read-only, `/var/lib/openshell` bind-mount with
  source == target, `XDG_DATA_HOME`/`HOME` set to it, rootless Podman
  socket access, and `OPENSHELL_DB_URL=sqlite:/var/lib/openshell/gateway.db?mode=rwc`.
- `gateway/gateway.toml`: loopback binds, `compute_drivers=["podman"]`,
  `disable_tls=true`, `[openshell.drivers.podman]` with pinned
  `default_image` (sandbox) and `supervisor_image`,
  `image_pull_policy="IfNotPresent"`, `sandbox_namespace="openshell"`,
  and `grpc_endpoint=http://host.openshell.internal:8080` (host alias on
  Linux).
- **CLI**: a thin `openshell` wrapper in `openshell/scripts/lib.sh` runs
  the pinned `odh-openshell-cli` via `podman run` — no host RPM.

### The three harness demos (standalone)

Identical ergonomics per harness (`create.sh`, `connect.sh`, `README.md`,
four profile `policy.yaml`). Provider key from environment/OS keyring,
never committed. Harnesses are installed into the odh sandbox base at
**create-time** via a two-phase launch:

1. **Bootstrap phase** — sandbox starts under a minimal bootstrap policy
   permitting *only* the harness install source, installs the pinned
   harness, then that egress is dropped:
   - Claude Code: `npm i -g @anthropic-ai/claude-code@<pinned>`
     (`registry.npmjs.org`).
   - OpenCode: pinned OpenCode install from its documented channel
     (source/version confirmed at implementation time).
   - OpenClaw: `npm i -g openclaw@<pinned>` (`anthropics/openclaw`).
2. **Demo phase** — the selected profile's `policy.yaml` is applied; the
   harness runs under it.

OpenClaw is a gateway service: `connect.sh` port-forwards the Control UI
on `18789` rather than attaching a TTY; its backend (OpenAI or Anthropic)
is chosen at create-time.

**Accepted trade-off:** create-time install costs a per-sandbox download
and bootstrap egress step. Fallback (if heavy) is building three images
FROM the odh sandbox base; the layout need not change to migrate.

### Integrated scenario (Praxis + OpenShell)

Prerequisite: the Praxis **all-in-one** scenario is installed (loopback
gateway on `:8080`). The integrated scenario adds an OpenShell layer:

- The harness's provider config (`harness-provider.json.in`, modeled on
  `configs/all-in-one/clients/opencode-shared-gateway.json`) points the
  model `baseURL` at the Praxis loopback (`http://127.0.0.1:8080/v1` or
  the sandbox-visible host alias).
- OpenShell policy `network_policies` permit model egress **only** to
  that loopback Praxis endpoint (no direct `api.anthropic.com` /
  `api.openai.com`), scoped to the harness binaries. GitHub/npm/PyPI
  follow the same per-profile grading as standalone.
- Result: the harness holds no provider credential (Praxis) and cannot
  exfiltrate or reach arbitrary hosts (OpenShell). This is the headline
  combined demonstration.

Installed via `scripts/openshell-praxis/install` ->
`scripts/common/install --scenario openshell-praxis`, reusing the PR #2
installer, manifest, uninstall, and verify machinery.

### Policy profiles (per harness / scenario)

Four OpenShell `policy.yaml` files using the standard `filesystem_policy`
+ `landlock` + `process` + L7 `network_policies` shape:

| Profile | Workspace | Network shape (standalone) | Network shape (integrated) |
| --- | --- | --- | --- |
| `review` | read-only | model API only; headless | Praxis loopback only; headless |
| `dev` | read-write | model API + GitHub + npm/PyPI | Praxis loopback + GitHub + npm/PyPI |
| `automation` | read-write | bounded allowlist; headless | Praxis loopback + bounded allowlist |
| `interactive` | read-write + persistent volume | dev + approved docs sites | integrated dev + approved docs sites |

### Teaching pointer

`openshell/docs/policy-walkthrough.md` shows deny-by-default ->
github-allow using the **existing** profiles (no extra policy files):
create a sandbox, show `curl https://api.github.com` blocked, apply the
`dev` GitHub rule, show reads succeed and writes stay blocked.

## CI — `.github/workflows/openshell-validate.yml`

Modeled on the PR #2 `validate.yml`; amd64 + arm64 matrix; paths-filtered
to `openshell/**`, `configs/openshell-praxis/**`,
`scripts/openshell-praxis/**`, and the workflow file. No secrets.

1. **Static** — shellcheck; policy-YAML schema validation; template
   render from `images.env.in`; `@sha256:` digest-format check; native
   runner architecture check via `oci_architecture`.
2. **Boot** — start the pinned gateway (pulling pinned supervisor +
   sandbox) **without provider keys**; verify `/healthz` / `/readyz`.
3. **Policy proof** — create a sandbox; assert
   `curl https://api.github.com` is **blocked** under deny-by-default;
   apply the github-allow rule; assert read succeeds and write is
   blocked.
4. **Integrated smoke** — with a stub loopback endpoint standing in for
   Praxis (no real provider), assert the integrated policy permits the
   loopback and denies direct `api.anthropic.com` / `api.openai.com`.

## Testing & docs

- `openshell/tests/openshell-*.sh` mirror `tests/shared-gateway-*.sh`;
  `tests/openshell-praxis/*` mirror `tests/remote-gateway/*`.
- Docs follow `docs/quickstarts/<scenario>/` and `docs/testing/`
  conventions: one quickstart per harness, an integrated-scenario
  quickstart, a combined threat-model note, and the `README.md`
  additions.

## Risks & open questions

- **odh image digests** must be looked up and pinned during
  implementation; a documented refresh step keeps them current.
- **OpenCode install source/version** to pin — confirm against its
  current distribution channel.
- **Rootless Podman gateway spawning siblings** needs the rootless
  Podman socket and `host.openshell.internal` alias on Linux; validated
  by the CI boot step.
- **Integrated loopback reachability from the sandbox** — the sandbox
  reaches the host Praxis port via `host.openshell.internal`; the policy
  and provider config must agree on that address. Validated by the
  integrated smoke test.
- **PR #2 churn** — building on `feat/gateway-scenarios` means rebasing
  if that branch changes before it merges.

## Acceptance criteria

1. `openshell/scripts/install.sh` renders and starts the pinned gateway
   quadlet on RHEL 9 rootless Podman; the `openshell` CLI wrapper reaches
   the gateway.
2. For each harness, `create.sh --profile <p>` produces a working
   sandbox under each of the four profiles; OpenClaw's `connect.sh`
   serves the Control UI on `18789`.
3. The integrated scenario installs via
   `scripts/common/install --scenario openshell-praxis`, routes model
   traffic through the Praxis loopback, and blocks direct provider hosts.
4. Deny-by-default is observable and the teaching walkthrough reproduces
   the github-allow transition.
5. `openshell-validate.yml` passes on amd64 and arm64 with no secrets,
   including the behavioral policy proof and integrated smoke test.
6. The Praxis scenarios and their `validate.yml` are unchanged.
