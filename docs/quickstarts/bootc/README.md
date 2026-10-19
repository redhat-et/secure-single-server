# Bootc quickstart

Run this walkthrough in Bash on a disposable, already bootc-managed RHEL 9
x86_64 host. Have an OpenAI API key and an exact model ID available to your
account ready. This published-image example uses OpenCode with Praxis.
For OpenClaw, use the [bounded model/tool guide](../openshell-praxis/openclaw.md)
with a rebuilt image containing the integration.

Target a first model response in under five minutes after the host is prepared
and images are cached. Initial downloads and the OS reboot add time.
For other deployment and credential options, see the
[full bootc guide](../openshell-single-server/bootc.md).

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

Follow the [frontier provider steps](../openshell-single-server/model-access.md#frontier-provider-models-through-praxis)
to store the OpenAI key in Praxis, create the OpenCode sandbox, and connect to
it. Praxis keeps the key out of the image and harness.

Ask `Reply with a short greeting.` A nonempty response verifies model access;
use the [harness checks](../openshell-single-server/verification.md)
to verify tools and policy. For other routes, see the
[model endpoint guide](../openshell-single-server/model-access.md).

## Next step

- Run the [harness checks](../openshell-single-server/verification.md).
- Try a [scenario](../../examples/README.md) that shows the boundary in practice.

