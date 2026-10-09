# OpenClaw harness

OpenClaw provides the coding-agent experience. This directory packages its
lifecycle scripts, pinned image reference, and OpenShell profiles so the
harness does not need a broad host login to be useful.

Deploy and test OpenClaw from the
[OpenShell single-server guide](../../../docs/quickstarts/openshell-single-server/README.md).
For model access and tools, use the [Praxis walkthrough](../../../docs/quickstarts/openshell-praxis/openclaw.md).
`run.sh` executes a bounded `agent exec` task; `connect.sh` opens a shell.
Browser/gateway authentication, retained sessions, and `--backend` are not qualified.

The preinstalled harness image is digest-pinned in `openshell/configs/images.env`.
