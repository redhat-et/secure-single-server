# Model endpoint configuration

Choose one model route after OpenShell is ready. The deployment guides link
here instead of repeating provider setup.

| Route | Use it when… |
| --- | --- |
| [Self-hosted or private OpenAI-compatible service](#self-hosted-or-private-openai-compatible-service) | You operate an inference endpoint on the OpenShell host, another VM, or another private server. |
| [Frontier provider models through Praxis](#frontier-provider-models-through-praxis) | You want OpenAI models without a local GPU and want Praxis to own the provider credential. |
| [Direct frontier provider attachment](#direct-frontier-provider-attachment) | You need an OpenShell-only evaluation path for OpenAI or Anthropic before deploying Praxis. |
| [Private vLLM inference](../vllm/README.md) | You want the repository's pinned private Qwen serving path, optionally on a separate GPU or CPU server. |

## Self-hosted or private OpenAI-compatible service

This route is for an endpoint you administer, such as vLLM or another private
OpenAI-compatible inference service. It can run on the OpenShell host, a local
VM, or a server from any cloud provider. It is not the route for
`api.openai.com` or `api.anthropic.com`; use
[one of the frontier provider routes](#frontier-provider-models-through-praxis)
for those services.

On the server, create this non-secret profile. Replace the host and port with
the endpoint you administer. This example assumes HTTPS on port 443:

```bash
cat > /var/tmp/local-model.yaml <<'YAML'
id: local-model
display_name: Private OpenAI-compatible inference
category: inference
credentials:
  - name: api_key
    env_vars: [OPENAI_API_KEY]
    required: true
    auth_style: bearer
    header_name: authorization
endpoints:
  - {host: inference.internal, port: 443, protocol: rest, access: read-write, enforcement: enforce}
binaries: [/usr/local/bin/opencode, /usr/bin/node-26]
YAML
```

Import the profile and register the endpoint's real key at the hidden prompt.
On a [manual deployment](manual.md), run:

```bash
os_run openshell profile lint -f /var/tmp/local-model.yaml
os_run openshell profile import -f /var/tmp/local-model.yaml
os_run bash -c '
cd /
set -eu
set +x
IFS= read -r -s -p "Model API key: " OPENAI_API_KEY; printf "\n"
export OPENAI_API_KEY
openshell provider create --name local-key --type local-model \
  --credential OPENAI_API_KEY
unset OPENAI_API_KEY
'
```

On a [bootc deployment](bootc.md), run:

```bash
sudo sss-bootc openshell profile lint -f /var/tmp/local-model.yaml
sudo sss-bootc openshell profile import -f /var/tmp/local-model.yaml
uid="$(id -u openshell-svc)"
sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
  XDG_RUNTIME_DIR=/run/user/"$uid" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus bash -c '
cd /
set -eu
set +x
IFS= read -r -s -p "Model API key: " OPENAI_API_KEY; printf "\n"
export OPENAI_API_KEY
/usr/bin/openshell provider create --name local-key --type local-model \
  --credential OPENAI_API_KEY
unset OPENAI_API_KEY
'
```

Create and connect a sandbox with the attached provider. For manual deployment:

```bash
os_run "$repo/openshell/harnesses/opencode/create.sh" \
  --profile dev --name opencode-local --provider local-key
os_run "$repo/openshell/harnesses/opencode/connect.sh" --name opencode-local
```

For bootc deployment:

```bash
sudo sss-bootc harness create --profile dev --name opencode-local \
  --provider local-key
sudo sss-bootc harness connect --name opencode-local
```

For a service on the OpenShell host, substitute `host.openshell.internal` and
its listening port in the profile and client URL. For another machine, use a
reachable private hostname or IP. Sandbox `127.0.0.1` refers to the sandbox.
If the server uses private HTTP, use its `http://` URL and actual port; HTTP
provides no transport encryption for the bearer key.

### Configure OpenCode

Inside the new sandbox, save this as `~/.config/opencode/opencode.json` before
restarting OpenCode. Replace `SERVED_MODEL_ID` in both places and the base URL.
The config refers to the attached credential placeholder, not the real key:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Private inference",
      "options": {
        "baseURL": "https://inference.internal/v1",
        "apiKey": "{env:OPENAI_API_KEY}"
      },
      "models": {
        "SERVED_MODEL_ID": {"name": "Private model"}
      }
    }
  },
  "model": "local/SERVED_MODEL_ID"
}
```

The client SDK must be present in the pinned image, and the endpoint must
support the API and tool calls required by the harness. A model listing alone
does not prove that support. Run the [harness checks](verification.md).

### Service without API-key authentication

Replace the profile's entire `credentials` block with `credentials: []` before
importing. Create `local-key` with `--type local-model` and omit `--credential`;
there is no hidden key prompt. Keep the endpoint and binary restrictions.
In OpenCode's config, set `"apiKey": "unused"` instead of the environment lookup.
That value only satisfies the client SDK; it is not a secret or an authentication
mechanism.

## Frontier provider models through Praxis

Use Praxis for OpenAI models. Praxis keeps the provider credential on the
server, injects it only when it calls the approved upstream, and exposes a
placeholder key to the harness. A GPU is not required for this route.

Praxis also supports Anthropic's native Messages API, but the current integrated
OpenCode template uses the OpenAI-compatible listener and does not translate
between API dialects. Do not use that template for Anthropic. Use
[direct frontier provider attachment](#direct-frontier-provider-attachment) for
an OpenShell-only Anthropic evaluation, or the
[native harness configuration](../openshell-praxis/harness-configuration.md)
for a deployment that intentionally uses Anthropic-native clients.

### Manual deployment

Install the [Praxis gateway and OpenShell add-on](../openshell-praxis/install.md).
From the reviewed checkout, enable the provider you approved and set its shared
quota. Enter the real provider key at the hidden prompt:

```bash
sudo scripts/common/providers enable openai
sudo scripts/common/quota-set --provider openai --capacity 2000000 --apply
```

Then create an OpenCode sandbox that uses the Praxis configuration:

```bash
IFS= read -r -p 'Approved model ID: ' model_id
os_run env OPENSHELL_MODEL_ID="$model_id" \
  "$repo/openshell/harnesses/opencode/create.sh" \
  --profile dev --name opencode-praxis \
  --config "$repo/configs/openshell-praxis"
os_run "$repo/openshell/harnesses/opencode/connect.sh" --name opencode-praxis
```

Do not attach `--provider` in this mode. Praxis owns the upstream credential;
the sandbox receives only its placeholder. Use
[quota management](../../examples/praxis-quotas/README.md) to inspect and adjust
shared allowances.

### Bootc deployment

The bundled cloud profile expects both secret slots. Enter the real OpenAI key
and a non-empty placeholder for the unused Anthropic slot; the current OpenCode
template does not use Anthropic's native Messages API. Use fresh secret versions
if `v1` already exists:

```bash
(
  set +x
  set -euo pipefail
  sudo -v
  IFS= read -r -s -p 'OpenAI API key: ' key; printf '\n'
  printf '%s' "$key" | sudo sss-bootc secret openai v1
  unset key
  IFS= read -r -s -p 'Anthropic API key: ' key; printf '\n'
  printf '%s' "$key" | sudo sss-bootc secret anthropic v1
  unset key
  sudo sss-bootc activate praxis-openai-api-key-v1 praxis-anthropic-api-key-v1
  sudo sss-bootc inference cloud
)
```

Choose an exact model ID available to the OpenAI account, then create and
connect the OpenCode sandbox:

```bash
IFS= read -r -p 'Approved model ID: ' model_id
uid="$(id -u openshell-svc)"
cd /
sudo runuser -u openshell-svc -- env HOME=/var/lib/openshell-svc \
  XDG_RUNTIME_DIR=/run/user/"$uid" \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
  OPENSHELL_BIN=/usr/bin/openshell OPENSHELL_MODEL_ID="$model_id" \
  /usr/share/secure-single-server/openshell/harnesses/opencode/create.sh \
  --profile dev --name opencode-praxis \
  --config /usr/share/secure-single-server/configs/openshell-praxis
sudo sss-bootc harness connect --name opencode-praxis
```

For OpenClaw, use the [bounded Praxis workflow](../openshell-praxis/openclaw.md)
instead of automatic provider attachment.

## Direct frontier provider attachment

Use this evaluation path only when Praxis is not deployed. OpenShell holds the
provider credential and substitutes it only at the endpoint named in the
profile, but this route does not provide Praxis quotas, routing, or centralized
provider management.

Create a non-secret profile for the provider you need:

```bash
cat > /var/tmp/openai-model.yaml <<'YAML'
id: openai-model
display_name: OpenAI model access
category: inference
credentials:
  - name: api_key
    env_vars: [OPENAI_API_KEY]
    required: true
    auth_style: bearer
    header_name: authorization
endpoints:
  - {host: api.openai.com, port: 443, protocol: rest, access: read-write, enforcement: enforce}
binaries: [/usr/local/bin/opencode, /usr/bin/node-26]
YAML

cat > /var/tmp/anthropic-model.yaml <<'YAML'
id: anthropic-model
display_name: Anthropic model access
category: inference
credentials:
  - name: api_key
    env_vars: [ANTHROPIC_API_KEY]
    required: true
    auth_style: header
    header_name: x-api-key
endpoints:
  - {host: api.anthropic.com, port: 443, protocol: rest, access: read-write, enforcement: enforce}
binaries: [/usr/local/bin/opencode, /usr/bin/node-26]
YAML
```

Import the selected profile with the manual or bootc command from
[self-hosted or private OpenAI-compatible service](#self-hosted-or-private-openai-compatible-service).
Replace the profile path, provider name, profile type, and credential variable
with the values for your selected provider. At the hidden prompt, register the
matching provider:

- OpenAI: `--name openai-key --type openai-model --credential OPENAI_API_KEY`
- Anthropic: `--name anthropic-key --type anthropic-model --credential ANTHROPIC_API_KEY`

Create the sandbox with the selected provider, then use OpenCode's model picker
to choose an exact model available to that account. Do not paste the real key
into OpenCode's `/connect` prompt or harness configuration.

## Sources and qualification

The pinned [OpenShell provider contract](https://github.com/NVIDIA/OpenShell/blob/v0.1.4/docs/how-it-works/inference.mdx)
defines profile-bound credential substitution and custom endpoints. OpenCode's
[provider configuration](https://opencode.ai/docs/providers/#custom-provider) and
[environment substitution](https://opencode.ai/docs/config/#env-vars) define
client configuration. These examples describe setup; real inference and tool
execution must be qualified on the deployed host. For OpenClaw, use the [bounded Praxis workflow](../openshell-praxis/openclaw.md)
and review its recorded test evidence.
