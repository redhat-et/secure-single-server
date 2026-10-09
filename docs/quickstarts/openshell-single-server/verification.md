# Verify the single-server harness

[Manual deployment](manual.md) · [Bootc deployment](bootc.md)


Run these checks after the sandbox is Ready and before giving it valuable work.
They are intentionally small enough to repeat after every image or policy
change. The model prompt assumes that the selected harness already has working
model access; the filesystem and network controls do not.

### 1. Prove model interaction

For either harness, once its model access is configured, use this prompt:

```text
In one sentence, explain why a network allowlist improves AI-agent security.
```

A useful response confirms the model path, not the policy. OpenCode can run
model-directed file and command tools. For OpenClaw, use the
[bounded Praxis runner](../openshell-praxis/openclaw.md), which permits only
`read` and `write`; browser/gateway authentication is outside this tested path.

### 2. Prove tool execution and writable workspace

For OpenCode with model access configured, use this prompt:

```text
Create /sandbox/openshell-check.txt containing the text "policy applied". Read
the file back and show its exact contents.
```

For OpenClaw, use the same prompt with
`/home/node/.openclaw/workspace/openshell-check.txt` as the path and run it through
[the bounded runner](../openshell-praxis/openclaw.md).

After the model task, connect to OpenCode and independently read the file:

```sh
cat /sandbox/openshell-check.txt
```

For OpenClaw, substitute `/home/node/.openclaw/workspace/openshell-check.txt`
in the shell command. If model access is not configured, a manual file write
and read checks filesystem permissions only; it does not prove model tool use.

The file must exist outside the model response. An agent can describe an action
without executing it.

### 3. Prove policy-controlled network behavior

Use the controlled policy test rather than an arbitrary public endpoint. On a
manual deployment, run the service-owner command shown in
[manual verification](manual.md#5-verify-the-deployment). For bootc, use the [policy qualification commands](bootc.md#verify-runtime-limits-and-policy)
to stage the checkout and run the same test as the service owner.

The suite proves both directions with a local fixture: the allowed request must
reach the server and return its known `401`, while the denied request must
return `EACCES` without producing a server-side request. Do not use a failed
GitHub, OpenAI, or example.com request as positive evidence; DNS failures,
timeouts, and unrelated network errors can look identical to a policy denial.

### 4. Exercise a small coding task

For OpenCode, use this prompt:

```text
Create /sandbox/add.mjs that exports add(a, b), create test_add.mjs with
node:test cases for (2, 3), (-2, -3), and (0, 0), then run
node --test --test-reporter=tap test_add.mjs.
```

Require nonzero passing tests and independently rerun the command after the
harness exits. This checks tool execution, file creation, and command completion
inside the sandbox.

