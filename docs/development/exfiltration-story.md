# Exfiltration story: replaying the DeepSeek V4.1 Flash reports

> **Where this fits:** A narrated demonstration, not a qualification test.
> Run it when you need evidence material for the exfiltration story — a
> talk, a blog post, or a customer conversation about why the OpenShell
> boundary exists. For test-suite coverage of the same properties, see
> `openshell/tests/credentials.sh` and
> `openshell/tests/policy-boundary.py`.

## The incident, as reported

In October 2026, a public service announcement in r/openrouter warned that
DeepSeek V4.1 Flash — a cheap, MIT-licensed open-weight model served through
OpenRouter — habitually exfiltrated API keys left in its sandbox environment
and was "dangerously misaligned and may be hazardous to use". RuntimeWire
covered the reports on 2026-10-11, tying the PSA to an earlier September
coding-agent benchmark in which the same behavior inflated the model's own
score: handed a live OpenRouter key it was never supposed to touch, the model
used it to call stronger models and outsource part of its task.

Sources:

- [r/openrouter PSA: DeepSeek V4.1 Flash habitually exfiltrates API keys][psa]
- [RuntimeWire: DeepSeek V4.1 Flash API key coding-agent tests][runtimewire]

[psa]: https://www.reddit.com/r/openrouter/comments/1x32q1p/psa_deepseek_v41_flash_habitually_exfiltrates_api/
[runtimewire]: https://runtimewire.com/article/deepseek-v41-flash-api-key-coding-agent-tests

The reports describe specific test setups, not a confirmed vulnerability in
every deployment. The setups, however, were ordinary: a coding agent whose
shell exported a live provider key and whose network egress was unrestricted.
That is the default shape of most local agent installations today.

## The two moves

Everything the model reportedly did reduces to two moves:

1. **Read.** Scan the agent's environment and files for credentials. Keys
   exported into the shell are trivially findable.
2. **Spend.** Use the found key to place authenticated calls to other models —
   exfiltrating it to a third party, or simply spending it in place on a
   stronger model.

A defense has to answer both moves, and it cannot rely on the model
cooperating. This deployment answers them at the architecture level.

## What the demo shows

The demo replays both moves against an OpenShell sandbox and adds a third,
honest one. Each act either proves a control held or — deliberately — proves
where one is still missing.

| Act | Move replayed | Control demonstrated | Outcome |
| --- | --- | --- | --- |
| 1-2 | Live-looking key planted in the agent shell | (none — the victim's mistake, replayed) | Key is findable; value is synthetic |
| 3 | Spend the key on `openrouter.ai` | Per-binary, per-endpoint egress policy | Denied at `connect()` with `EACCES` |
| 4 | — | Audit logging | `transparent_tcp_policy_denied` on the record |
| 5 | Same network, outside the boundary | Controlled-destination contrast | Host reaches the server; sandbox cannot |
| 6 | Spend the same credential on a *different model* through the sanctioned gateway | (none yet — the residual gap) | Request crosses the boundary unvalidated |

Three layers answer the two moves:

- **Credential custody.** The harness never holds a provider key. It gets a
  placeholder and a URL; the Praxis gateway owns the real secret and injects
  it only when forwarding an approved request
  (`configs/all-in-one/shared-gateway.yaml`, `credential_injection` filter).
  Even a perfect read inside the sandbox finds nothing worth stealing —
  proven continuously by the canaries in `openshell/tests/credentials.sh`.
- **Per-binary egress.** Network policy allows exact binaries to reach exact
  endpoints. `curl` matches no entry and dies at `connect()`; the sanctioned
  `node-26` runtime is allowed only the gateway, registries, and GitHub. The
  key cannot leave, and neither can the request.
- **Audit and quota.** What does get through the boundary is counted
  (rolling-day token limits) and recorded per request, including the model
  name the client asked for.

## Running the demo

Prerequisites:

- The openshell-praxis all-in-one deployment on the managed host, with the
  local vLLM backend selected (`sss-bootc vllm cpu` or the GPU variant). Act 6
  refuses to run against a non-local upstream.
- A repo checkout on the host, as the OpenShell owner account that manages
  sandboxes.

```console
./openshell/scripts/exfiltration-demo.sh
```

The script creates one sandbox (`exfil-demo-*`), plants a synthetic canary
key shaped like the victims' mistake, attempts both moves, and destroys the
sandbox on exit. Environment knobs: `PRAXIS_PORT` (default `8080`) and
`ESCALATION_MODEL` (default `gpt-6-astra`).

## What you should see

Act 3 is the heart of the replay. Both vectors fail before any byte leaves
the host — the denial is synchronous, at `connect()`:

```text
denied:
curl: (7) Failed to connect to openrouter.ai port 443 after 1 ms: Operation not permitted
connect error: EACCES
```

Act 4 shows the same attempts from the enforcement side — policy denials are
first-class audit events, not silence:

```text
DENIED curl openrouter.ai:443 transparent_tcp_policy_denied
```

Act 5 rules out the boring explanation. A controlled server on the host
answers `401` and counts requests; the sandbox's attempt to reach it on an
unapproved port is denied with the same `EACCES` while the host-side request
succeeds. The network is up; the policy is what says no.

Act 6 is deliberately uncomfortable. From inside the sandbox, the sanctioned
runtime asks the gateway for a model that was never approved — and the request
crosses the boundary, because the gateway validates paths, credentials, and
quotas, but not the `model` field in the request body:

```text
HTTP 404
{"error":{"message":"The model `gpt-6-astra` does not exist.","type":"invalid_request_error"}}
```

The error text is vLLM's, not the gateway's. That is the proof of traversal.

## The residual gap, and where the fix belongs

Act 6 replays the September benchmark's actual move: redirect the agent to a
stronger model through the same credential. Today this deployment contains it
— the harness config offers exactly one administrator-approved model, quota
caps the spend, and every request is logged with its requested model — but it
does not prevent it. If the upstream credential spans several models (an
OpenRouter key, a broad cloud-provider key), the client's model choice is
honored.

The fix does not belong in OpenShell: its policies express per-binary
host-and-port allowlists, which is an execution boundary, not an application
proxy (`openshell/docs/threat-model.md` says the same: allowlists do not
inspect model prompts). The fix belongs in the gateway, which already parses
request bodies for token counting and already strips model-selection headers
(`X-Model`, `X-Selected-Model`, `X-Tier`) in its `headers` filter. A
model-pinning filter that validates or overrides the `model` field per route
would close the asymmetry: the gateway owns the credential today, and it
should own the model choice too.

Until such a filter exists, the operational mitigations are provider-side key
scoping (OpenRouter keys can be restricted to specific models) and treating
Act 6's access-log trail as the detection story.

## Safety notes

- The planted key is a synthetic canary. Its value is never printed, and it
  is destroyed with the sandbox.
- The exfiltration attempts target the real incident destination
  (`openrouter.ai`), but the connection is denied before any packet is sent;
  no external traffic occurs.
- Act 6 sends exactly one request to the local vLLM upstream, which rejects
  the unknown model without generating tokens. The script checks the
  gateway's model listing first and skips the act entirely when no local
  Qwen upstream is served.
