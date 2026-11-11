# Details

This file holds what the [README](README.md) leaves out: the full evaluation, the demo accounts, the start-up steps, the architecture, the MCP server, my notes on AI Hub and the map for idea DPI-I-689. To run any of it yourself, see [REPRODUCE.md](REPRODUCE.md).

## Evaluation

The evaluation runs the whole product over a synthetic dataset of 240 subject cases, 30 in each of 8 categories, seed 2026. It covers the rules, retrieval, the agent with its tools, composition, the release guard and the budget. I ran it for two models and compared the route the product chose with the expected one. The expected decision of every case comes from construction rules written by one author. There was no second annotator. The cases are listed in `data/eval/report.md`. The round before the agent had tools is in `data/eval/report-before-tools.md`. Every evaluation number in this repository comes from the blocks below. They are generated from the report and checked against it by a gate.

**The safety comes from the deterministic layers: without them an agent that does not see the rule's verdict would miss and misjudge results, so the design never lets the agent decide alone. What the agent adds is a justification a person can check.**

### Key figures

| Metric | gpt-5.4-mini | gpt-5.4 |
|---|---|---|
| Rule-critical results silenced | 0 | 0 |
| Criticals released as non-critical, delta floor off, then on (first round, recorded answers replayed) | 19 to 2 | 7 to 2 |
| Criticals released as non-critical in the current round | 0 | 0 |
| Residual contextual criticals: not detected / sent to a person | 2 / 2 | 2 / 2 |
| Contextual criticals the agent put in read-back without the rule's verdict, then sent to a person (of 60) | 37 / 23 | 46 / 14 |
| False criticals the agent created without the rule's verdict | 7 | 0 |
| Contextual criticals ending critical, without tools, then with tools (of 30) | 28 to 28 | 28 to 28 |
| Downgrade attempts held by the floor, without tools, then with tools | 24 to 36 | 18 to 2 |
| Review rate, without tools, then with tools | 17.3% to 27.6% | 15.7% to 28.5% |
| Releases held for a person by the release guard | 22 | 1 |
| Results not clear-cut released as non-critical, guard off, then on (recorded answers replayed) | 10 to 0 | 0 to 0 |
| Review rate without the release guard | 22.6% | 28.3% |
| Tool calls per result | 4.00 | 3.97 |
| Invalid answers | 0.0% | 0.0% |

### Ablation: which layer does what

I replayed the same recorded answers through different arrangements of the layers, over the 240 cases. The replay needs no provider call. The file is `data/eval/ablation.json`, and the arrangement with the full product reproduces the confusion matrices below. "Contextual criticals" are the criticals the range rule does not catch, so something else has to. Without an agent, a result is critical by rule or released, unless the release guard holds it for a person.

In the recorded round the agent saw the change tool's verdict. The rows without the verdict come from a separate paid run per model. In that run the change tool gave the earlier values and the variation, but not the verdict or the limit (`data/eval/ablation-no-verdict.jsonl`). The change rule kept running in that run. The arrangements here leave it out of the floor.

| Arrangement | Model | Contextual criticals: read-back / sent to a person / released | Uncertain results released | Rule-critical silenced | False criticals | Review rate |
|---|---|---|---|---|---|---|
| Range rule only | none | 0 / 0 / 60 | 60 of 60 | 0 | 0 | 0.0% |
| Range rule and release guard, no agent | none | 0 / 31 / 29 | 0 of 60 | 0 | 0 | 37.9% |
| Range rule, change rule and release guard, no agent | none | 58 / 2 / 0 | 0 of 60 | 0 | 0 | 25.8% |
| Range rule, guard and agent without the change rule; the agent saw the rule's verdict | gpt-5.4-mini | 58 / 2 / 0 | 0 of 60 | 0 | 0 | 25.8% |
| Range rule, guard and agent without the change rule; the agent saw the rule's verdict | gpt-5.4 | 57 / 3 / 0 | 0 of 60 | 0 | 0 | 26.2% |
| The same, but the agent saw the earlier values and the variation, not the verdict | gpt-5.4-mini | 37 / 23 / 0 | 0 of 60 | 0 | 7 | 32.5% |
| The same, but the agent saw the earlier values and the variation, not the verdict | gpt-5.4 | 46 / 14 / 0 | 0 of 60 | 0 | 0 | 31.2% |
| The full product | gpt-5.4-mini | 58 / 2 / 0 | 0 of 60 | 0 | 0 | 25.8% |
| The full product | gpt-5.4 | 58 / 2 / 0 | 0 of 60 | 0 | 0 | 25.8% |

### Confusion matrices, cost and latency

#### gpt-5.4-mini

Final decision (route) against the expected decision:

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 148 | 0 | 2 | 0 | 0 |
| RECOLLECT | 0 | 0 | 30 | 0 | 0 |
| NEEDS_REVIEW | 0 | 0 | 30 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

Agent decision against the expected decision:

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 112 | 12 | 2 | 24 | 0 |
| RECOLLECT | 0 | 10 | 0 | 20 | 0 |
| NEEDS_REVIEW | 0 | 13 | 0 | 17 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

- Cost per thousand results (USD): 2.8426
- Latency p50 / p95 (ms, recorded): 2975 / 3791
- Silenced criticals: 0
- Missed criticals (expected critical, not critical by rule, not sent to read-back): 2
- Downgrade attempts by the agent on rule-critical results (kept critical): 36

#### gpt-5.4

Final decision (route) against the expected decision:

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 148 | 0 | 2 | 0 | 0 |
| RECOLLECT | 0 | 0 | 30 | 0 | 0 |
| NEEDS_REVIEW | 0 | 0 | 30 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

Agent decision against the expected decision:

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 144 | 1 | 0 | 3 | 2 |
| RECOLLECT | 0 | 30 | 0 | 0 | 0 |
| NEEDS_REVIEW | 0 | 23 | 0 | 7 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

- Cost per thousand results (USD): 9.7268
- Latency p50 / p95 (ms, recorded): 6262 / 7563
- Silenced criticals: 0
- Missed criticals (expected critical, not critical by rule, not sent to read-back): 2
- Downgrade attempts by the agent on rule-critical results (kept critical): 2

### What the numbers say, and what they do not say

- **No result critical by rule was silenced, for either model.** A result the rule table calls critical was never released, never sent to review and never lowered. That holds in every arrangement of the ablation. It includes the cases where the agent answered less than critical and the composition kept the result critical.
- **The safety comes from the deterministic layers.** The range rule, the change rule and the release guard, with no agent, end where the full product does. No critical is released, and the guard holds the two residual cases for a person. Without the change rule, 29 of the 60 contextual criticals would be released automatically.
- **The agent is not a safety net.** When its change tool hands it the rule's verdict, it only reproduces the rule. Without the verdict, gpt-5.4-mini puts 37 of the 60 contextual criticals in read-back, sends 23 to a person and creates 7 false criticals. gpt-5.4 puts 46 in read-back, sends 14 to a person and creates 0 false criticals. This is why the agent never decides alone. Now it is measured, not assumed.
- **What the agent adds is a justification a person can check.** Each decision carries a rationale and the evidence it cites. An answer is accepted only if a tool of the same investigation returned every item of evidence, so each claim traces to a recorded call. With its tools the agent costs about three times as much and takes about three times as long as it did without them. The deterministic layers cost nothing per result.
- **Caveats.** The dataset is synthetic and has a single author, with no second annotator. I set the change limits and the borderline band of the release guard knowing the dataset generator, so their coverage is partly by construction. The results show that deterministic rules can close this kind of hole. They do not show that the limits are clinically calibrated. The ablation replays one recorded run per model, and each run without the verdict is a single paid run.

## Demo

Open http://109.123.244.170/ and press **Run demo sequence**. A critical potassium stops at read-back. A borderline one goes to a person to review. In the third case the agent tries to lower a critical and the floor holds it. To open a read-back task, sign in with one of the demonstration accounts. They share one password.

| Account | Can confirm a read-back |
|---|---|
| `communicator1` | yes |
| `communicator2` | yes |
| `observer` | no, it can only look |

Password: `hVWrjsSnttT8AYIn9acJ`

To open a read-back task, run the demo sequence first. The critical potassium then waits at the read-back station of the flow, in a card marked with the account it is assigned to. Click the card. A side panel opens and asks you to sign in. Use the account the card names. The task goes by rotation to `communicator1` or `communicator2`, and `observer` can look but cannot confirm. Enter whom you told and the value you repeated, then press **Confirm the read-back**. A value that does not match is refused. The task stays open, and the attempt is counted and shown in the panel. Only a matching value closes the task and the alert.

The demo runs in replay mode against a real IRIS instance. The decisions are the recorded answers of a real run of the agent, so no key is needed and no provider is called. The data is synthetic. The demo is plain HTTP and it is reset every hour, on the hour. It is unavailable for about half a minute while it resets.

The demonstration accounts are broader than a production deployment would use. The credential is shared, and the demo has to show the escalation working. They hold `%DB_USER` on the USER database. The two communicator accounts also hold `%EnsRole_AlertAdministrator`, so they can close alerts they do not own. The read-back task goes by rotation to either communicator, so the person who confirms is not always the owner of the alert. None of them holds `%All`, `%Manager` or `%Admin`.

The demo builds its messages with Embedded Python. The `%Service_EmbeddedPython` resource that needs belongs to the web application, through a role matched only while the application serves a request. No account holds it. In production each of these would be a role specific to the Readback. The alert would be closed in a system context on behalf of the person who confirmed.

Only port 80 is open. The proxy answers 404 for every native IRIS route: `/csp/sys`, `/api/admin`, `/api/mgmnt` and the Atelier API.

### Security posture of the demo

- No administrator credential is in the repository, the image, the page or the README, and none is shown in the interface. The published password belongs to the demonstration accounts only.
- The page that anyone can open acts as the `observer` account, which can only look. The proxy adds that identity to the reads it forwards. A person who wants to confirm a read-back signs in with a communicator account.
- The proxy forwards a short list of Readback paths and nothing else. It limits how often a demo case can be submitted. It answers every other path with a plain JSON refusal that carries no platform content or header.
- The demo uses plain HTTP. That is why the credential is a shared demonstration one and the data is synthetic. A deployment would terminate TLS in front of the proxy.
- No tool accepts a patient or case identifier, because the server binds the case before the session starts. The scope policy is a second layer: a call that names another patient is refused and the refusal is recorded.

## Start-up in detail

`src/ops/preflight.sh` checks that the image is loaded and that the password reaches the product as you wrote it. Any printable password works. I tested quotes, an apostrophe, `#`, `!`, a backslash, `&`, `;` and spaces inside, end to end. Three things are refused with a message, because they would change the password on the way. They are a single `$` in `.env` (compose reads it as a variable, so write `$$`), a `#` after a space in `.env` (compose reads it as a comment) and a space at either end.

`src/ops/verify.sh` waits until the production is running and exits non-zero if it is not. It then checks that the task list layer is in the image and exits non-zero if it is not. Open http://127.0.0.1:8080 for the panel. The build downloads the small local embedding model and installs the IPM client and the workflow layer, so it needs network that one time. The running container needs none. The whole battery, from a clean stack, is `tests/e2e/triage_check.sh`.

In the container, only the start script, `src/ops/bootstrap.sh`, starts the production. It does so after the Java gateway of the unit conversion component accepts a connection, because IRIS does not start the gateway by itself. The script runs at every start, so `docker compose restart iris` brings the production back with no other step. If the component cannot be set up, the container stops with a message instead of starting half a production. `src/ops/verify.sh` says "the production is not running" as soon as the container stops or the start reports a failure. The event log of a start holds no error and no warning, and `tests/e2e/start_check.sh` checks it.

The product can also be installed as an IPM package into an instance that has the AI Hub. With the repository on disk, `zpm "load /path/to/iris-readback"` installs it, builds the unit conversion component and starts the production. From the registry, `zpm "install iris-readback"` does the same. Policy retrieval stays unavailable on such an instance until the embedding model is provided, as the image does. Everything else works. The package sets the production to start with the instance, so on an IPM installation too the production is running again after the instance restarts, with no other step. `tests/e2e/ipm_check.sh` restarts the instance three times and checks it.

## What the production contains

These are the Interoperability components the product uses.

- **HL7 intake.** ORU^R01 lab results arrive by file and by TCP on port 5001. They are normalized and stored.
- **The business process.** A deterministic floor comes first: critical limits by value, and the change against the patient's earlier results. Then the agent answers. A composition step takes the higher of the two, so the agent can only raise. A release guard sits after the answer. A result is released automatically only when the floor is zero, the sample quality is within the policy and the value is not near a critical limit. Anything else goes to a person with the reason in the trace. The agent cannot lift the guard.
- **The AI Hub agent step.** It is the platform's own agent operation, with a tool set. The agent investigates instead of receiving a prepared context. Through four read-only tools it asks for the patient's earlier results, the delta assessment of the floor, the passages of the laboratory policy and the sample quality. It answers in a strict JSON schema. No tool takes a patient or case identifier as an argument, because the server binds the case before the session. The model cannot even ask for another patient's data. Every identifier the agent cites as evidence must have been returned by a tool in that session, or the answer is invalid. An invalid answer, a failed tool call or a loop that does not end becomes a human review. Every session has an explicit limit of iterations. In replay mode a replay operation answers from recordings, tool calls included.
- **Governance attached to the agent.** Three policies sit on the tool set. The *audit* policy records every call, refusals included, in the product's own trace. The *scope* policy refuses a call that names another patient. The *floor* policy refuses, formally, an answer that would lower a result critical by rule or by change, and the refusal is recorded. The composition step enforces the floor whatever the policy does. Removing the policy removes a record, not the guarantee.
- **Synthetic results.** Embedded Python generates the demo's messages inside IRIS, with the same generator that builds the evaluation dataset. They enter the intake under a case id of their own. "Send result" and "Run demo sequence" call the generator for every submission. Embedded Python is not used by the rules or the agent.
- **Unit normalization.** A Production Extension in Java with the UCUM library converts units before the rules run.
- **Retrieval.** IRIS Vector Search and local embeddings find laboratory policy passages and similar confirmed cases. The agent reads them through its policy-search tool. A person's confirmation, a matching read-back or a completed review, is what lets a case into the pool of similar cases. The case enters described without any identifier, and stored with the product's final decision and route. Nothing that no person confirmed enters the pool. What is stored is the decision the product made, not a judgement written by the person.
- **Workflow Engine tasks.** The read-back and the human review are Workflow tasks, with a person assigned.
- **Alerting with escalation.** A critical result raises a managed alert over the platform's alert engine, with a custom delivery-and-receipt channel. The alert moves to the next person when nobody confirms in time.
- **Tracing.** Every decision keeps its inputs, the floor, the agent's answer, the composition, the tool calls in order, tokens and cost. It is linked to the Visual Trace session and readable through a small REST API ([the map](#idea-dpi-i-689)). Every tool call is also a step of that session. The audit policy sends one message per call to the `Readback.Agent.ToolTrace` operation, which only records. The message carries the tool, a summary of its arguments, the status and the time. In replay mode the recorded calls are sent as the same messages, labelled `replay`. The full arguments and results stay in the product's own trace and on the Decisions screen. The message is a side channel. If it cannot be sent, or the operation is switched off, the decision is the same. In the flow of the panel, the agent's node lights up its calls as sub-steps.

### Read-only MCP server

The product exposes a read-only MCP server. It is the platform's own `%AI.MCP.Service` (`src/Readback/MCP/Service.cls`) over four tools (`src/Readback/MCP/Tools.cls`): `list_pending_criticals`, `explain_decision`, `read_evaluation` and `read_ablation`. They follow the rules of the public feed. They only read, no answer carries a patient identifier, and the explanation of a decision is built from its trace record, with no model asked.

**The read-back is not exposed.** No tool confirms a read-back, closes an alert or completes a task. An AI assistant never closes a critical result. The read-back is the one act a person must do, by repeating the value, and a tool that could do it would take that act away from the person. This is a security decision, not a gap.

The access is closed. The service is the web application `/readback/mcp` on the management port, which the public proxy does not route. A caller needs the resource `Readback_MCP`, held by the role `ReadbackMcp`. Only the read-only demonstration account `observer` has that role.

To connect a client, run the platform's gateway, `iris-mcp-server`, which the image ships. Run it inside the container with this configuration in `/tmp/mcp.toml`. The password is the demonstration password of the `observer` account.

```
[[iris]]
name = "readback"
[iris.server]
host = "127.0.0.1"
port = 1972
username = "observer"
password = "<the demonstration password>"
[[iris.endpoints]]
path = "/readback/mcp"
```

```
docker compose exec iris /usr/irissys/bin/iris-mcp-server -c /tmp/mcp.toml -t http://127.0.0.1:8000 run
```

Any MCP client that speaks the streamable HTTP transport connects to `http://127.0.0.1:8000/mcp`. It sends the header `Authorization: Basic <observer:password in base64>`. The tools are listed as `readback_mcp_list_pending_criticals`, `readback_mcp_explain_decision`, `readback_mcp_read_evaluation` and `readback_mcp_read_ablation`. The gateway lists none to a caller without credentials. The client I verified is the MCP Inspector 2.13.0 in command-line mode:

```
npx @modelcontextprotocol/inspector@2.13.0 --cli http://127.0.0.1:8000/mcp --transport http --header "Authorization: Basic <base64>" --method tools/list
```

The web application of the service has the type 18, which is the REST type plus the "MCP Server" bit (16). An application of type 2 works over plain HTTP, but the gateway answers it with a 404 and reports that it "did not identify itself" (`docs/probes.md`, Probe 17).

What was tested:

- A complete session with the MCP Inspector through the gateway (`tests/e2e/mcp_client_check.sh`). The four tools are listed and no other. The pending criticals and the evaluation are read. A call to a tool that would confirm the read-back is answered `tool_not_found`. A caller without credentials, and an account without the resource, are listed no tool.
- The tools in the platform's own tool manager (`tests/e2e/mcp_check.py`, `tests/objectscript/Readback/Test/McpToolsTest.cls`, `tests/python/test_mcp_source.py`). There are exactly the four read tools. None of them confirms anything. No table of the product changes when they are called, and no answer carries a patient identifier.
- Over plain HTTP, the service serves nobody directly: 401 without credentials, and 404 with them, because an application of the MCP Server type is reached through the gateway. An account without the `Readback_MCP` resource is listed no tool through the gateway. The public proxy does not route the service.

## Feedback on AI Hub EAP

I observed this on the Early Access build 154 while building the product, and checked it again on build 109. Each item says whether it worked, needed a workaround here, or became a report. I checked the candidates against the issues of `intersystems-community/ai-hub-eap` for duplicates before I reported them. Someone else had already reported the argument types in policies. I also filed the two bugs, the loop and the embedding class, in `intersystems-community/ai-hub-eap-bugreports`, the tracker for bugs found in AI Hub. There I searched for duplicates first and attached the reproductions.

### What worked

- The platform's agent operation hosts a tool set and several rounds, parallel tool calls included. A subclass can own the session: it sets the iteration limit and reads the statistics and the exported history in the same job.
- The strict `response_format` travels with the tools in every round, on the wire and on the real provider. Structured output and tools work together.
- Authorization and audit policies attach to the tool set. A `ReadOnly` requirement on a tool reaches the authorization policy as metadata, and a tool without it never ran.
- The exported session holds the messages, the tool calls and their results, so I can rebuild the path of an investigation from it. A tool that calls another Interoperability operation shows up in the Visual Trace as steps of the same session.
- The native retrieval classes, a knowledge base over the IRIS vector store, serve the policy search tool as they are.

### What needed a workaround

- **Token usage covers the last round only.** With a tool round, the response reports less than the session statistics. Cost here is the difference of the session statistics before and after the case.
- **Calling the statistics from inside an audit callback never returns.** Reading them after the call works.
- **A tool failure, a denial or an unknown tool does not reach the caller.** The model gets an error message and the loop goes on. An unknown tool is not even audited. The product reads the session history to detect these cases and sends them to a person.
- **`max_tokens` is rejected by the provider for the model used.** The provider wants `max_completion_tokens`. The session configuration does not take it directly, so it goes through `extra_params`.
- **The usage carries token counts only.** The product keeps a dated price table and shows `unknown`, never zero, for a model without a price.
- **The provider does not read the key from the environment on its own.** The key is passed with an environment reference, and an unset variable gives an opaque error.
- **The local embedding model is described as bundled, and the first use downloads it.** The download is about 87 MB. The product fetches it at image build time, so a running container needs no network.
- **The argument types differ between the policies.** The authorization policy gets an object, and the audit callbacks get a JSON string. Someone had already reported this as [issue 40](https://github.com/intersystems-community/ai-hub-eap/issues/40).

### Found when moving to build 109

**`RESOURCE` became `SECURITYRESOURCE` in `%AI.MCP.Service`, and the old parameter is ignored without a warning.** On build 109 the class does no authorization of its own unless `SECURITYRESOURCE` is set or `OnAuthenticate()` is overridden. Its description says so. The read-only MCP server of this product set `RESOURCE`. On 109 an authenticated account without the resource could therefore list and call the tools. The step of the battery that checks this account caught it. The product now sets both parameters, each tool checks the resource itself, and a test calls the tools directly as an account without it. A request without credentials is answered 401 on 154 and 404 on 109. Both refuse. I reported it as [issue 47](https://github.com/intersystems-community/ai-hub-eap/issues/47), with a reproduction that uses none of this product's code.

### Reported from this project

Each report has a reproduction that does not use this product. It uses the stock build 154 image and a small mock provider, with no key.

- **[Issue 41](https://github.com/intersystems-community/ai-hub-eap/issues/41), bug: the agent loop has no default bound and outlives the caller's timeout.** With a distinct argument on every call and no iteration limit, the loop made thousands of provider requests. It went on after the caller had given up. With a real provider that is open-ended spend. An iteration limit makes the call stop with a clear error, but the Interoperability adapter has no setting for it. I also filed it in the contest's bug tracker as [issue 18](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/18), with the reproduction in the report. The discussion is in issue 41.
- **[Issue 42](https://github.com/intersystems-community/ai-hub-eap/issues/42), enhancement: provider error text reaches the event log and the message header unredacted.** A provider that echoes the credential puts it there. I reproduced it with the platform's own operation and a mock that echoes the header. The real service masks the key.
- **[Issue 43](https://github.com/intersystems-community/ai-hub-eap/issues/43), enhancement: an exception inside an audit policy is swallowed silently.** There is no error and no log line, while the same failure in an authorization policy is reported. The product's policies catch their own errors, and a test proves their entries exist.
- **[Issue 44](https://github.com/intersystems-community/ai-hub-eap/issues/44), bug: the embedding class description says the model is bundled and needs no network.** The first `Create()` downloads it and fails offline. I also filed it in the contest's bug tracker as [issue 19](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/19). The discussion is in issue 44.
- **[Issue 46](https://github.com/intersystems-community/ai-hub-eap/issues/46), docs: a `%AI.MCP.Service` web application without the "MCP Server" type bit is answered 404 by `iris-mcp-server`.** The gateway reports that the endpoint "did not identify itself". With type 18 it works. I found it while building the read-only MCP server of this product. It relates to issue 21.

## Idea DPI-I-689

This entry also answers the Community Opportunity idea [DPI-I-689](https://ideas.intersystems.com/ideas/DPI-I-689). Its status on the ideas portal is Community Opportunity. The idea asks for traceability of an LLM pipeline over Interoperability. The product shows exactly that on a real clinical pipeline. Every decision records the rule that fired, the agent's inputs and answer, each tool call it made and what the call returned. It also records the model, the prompt version, tokens, estimated cost and latency, and the outcome of the human step. All of it is linked to the production's own session. The evaluation turns those records into measured cost and latency.

The Visual Trace session of a decision shows the result, the agent's step, the task and the alerts. Every tool call of the investigation is a step of its own in that session, in order and with its time. The public demo shows the same steps, labelled replay, from the recorded investigations. The full arguments and results are in the product's own trace and on the Decisions screen. This covers the essence of the idea without reimplementing a general LLM observability product such as Langfuse.

The table shows what an LLM tracing tool records and where each item is in Readback. The decision is read through `GET /readback/api/decisions/{controlId}`, the one record behind every row.

| What an LLM tracing tool records | Where it is in Readback |
|---|---|
| A session per request | `sessionId`, the session of the production's own message trace, shown by the Decisions screen with its link to the Visual Trace; table `Readback.Trace.Decision` |
| Model and prompt version | `model`, `provider`, `promptVersion` and `mode` of the decision; `Readback.Trace.Decision` |
| Tokens, cost and latency | `inputTokens`, `outputTokens`, `costUsd` and `latencyMs` of the decision; cost per thousand results and percentiles in `GET /readback/api/indicators`; `Readback.Trace.Indicators` |
| Tool calls | `toolCalls` of the decision, in order, with arguments, result, status and time; table `Readback.Trace.ToolCall`; every call is also a step of the session in the Visual Trace (`Readback.Agent.ToolTrace`), labelled replay in the replay mode |
| Retrieval | `passageIds`, `caseLabels`, `indexVersion` and `retrievalNote` of the decision; `Readback.Retrieval.Engine` |
| Errors and policy refusals | `failureKind`, `failureReason`, `policyRefusal` and `evidenceCheck` of the decision; a refused or failed call has its `status` in `toolCalls` |
| Human outcome | `confirmedBy`, `readbackMatch`, `reviewedBy` and `taskId` of the decision; each attempt in `Readback.Trace.ReadbackAttempt`; the history of each alert in `GET /readback/api/alerts`; `GET /readback/api/taskview/{decisionId}` |
