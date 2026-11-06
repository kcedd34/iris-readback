# iris-readback

The rules guarantee the safety and the agent explains. An InterSystems AI Hub agent triages laboratory results inside an IRIS Interoperability production: it can raise a result to critical but never lower one the rules call critical, and nobody is notified of a critical result until a person has completed the read-back by repeating the value correctly. The evaluation shows what would happen if the agent decided alone.

![The agent decides on a critical potassium, which stops at read-back, and on a borderline one, which goes to a person to review; replay mode, synthetic data](docs-assets/signature.gif)

## For judges: two minutes

1. Open the [live demo](http://109.123.244.170/) and press **Run demo sequence**: a critical stops at read-back, a borderline one goes to a person, and the agent tries to lower a critical and the floor holds it.
2. Open the **Decisions** tab: floor, agent and final side by side; open the row with the "held" seal to see the rule, the four tool calls and the evidence check.
3. Sign in as `communicator1` (password in the [Demo](#demo) section), open the read-back task, type a wrong value (refused), then the right one (closes the task and the alert).
4. The measured evaluation and the ablation are in [For judges](#for-judges) below.
5. To run it yourself: the five commands of [Run it](#run-it), about two minutes from clone to panel.

## Fast path

- Video, the main demonstration: https://youtu.be/ML2pBgBkqUo
- Live demo (replay mode, reset every hour): http://109.123.244.170/
- Repository: https://github.com/kcedd34/iris-readback
- IPM package: `zpm "install iris-readback"`
- Open Exchange: https://openexchange.intersystems.com/package/Readback
- First article on Developer Community: https://community.intersystems.com/post/ai-agent-can-raise-critical-lab-result-never-lower-it
- Community Opportunity idea: https://ideas.intersystems.com/ideas/DPI-I-689
- Measured evaluation, full report: `data/eval/report.md`

## Run it

```
docker load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz   # then docker tag, if the name differs (build 109: see below)
cp .env.example .env   # set READBACK_DEMO_PASSWORD; leave OPENAI_API_KEY empty for replay
src/ops/preflight.sh
docker compose up -d --build
src/ops/verify.sh
```

Measured: from clone to a working panel in 2 minutes on a clean machine, with the image already loaded (77 s in the last run: image build 56 s with no build cache, start 15 s, verification 1 s; the IPM client and the workflow layer are installed while the image is built, so the start needs no network).

Full steps, with the image rename and the provider key: [Required by the organizers](#required-by-the-organizers). How to run the test battery, run a second stack, reproduce the evaluation and the ablation, free in replay or paid live, and connect an MCP client from your machine: [REPRODUCE.md](REPRODUCE.md).

## For judges

The evaluation is the strongest evidence of this entry, so it comes first. It runs the whole product, rules, retrieval, the agent with its tools, composition, release guard and budget, over a synthetic dataset of 240 subject cases (30 in each of 8 categories, seed 2026) for two models, and compares the route the product chose with the expected one. The expected decision of every case comes from construction rules written by one author; there was no second annotator. Full detail, with the cases listed, is in `data/eval/report.md`; the round before the agent had tools is kept in `data/eval/report-before-tools.md` for comparison. Every evaluation number in this README comes from the blocks below, which are generated from the report and checked against it by the gate.

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

The same recorded answers, replayed through different arrangements of the layers, over the 240 cases (the replay needs no provider call; the arrangement with the full product reproduces the confusion matrices below, and the file is `data/eval/ablation.json`). "Contextual criticals" are the criticals the range rule does not catch, so something else has to. In the two arrangements that have no agent, a result is either critical by rule or released, unless the release guard holds it for a person. The agent saw the change tool's verdict in the recorded round; the rows without the verdict come from a separate paid run per model in which that tool gave the earlier values and the variation but not the verdict or the limit (`data/eval/ablation-no-verdict.jsonl`). The change rule itself kept running in that run, and the arrangements here simply leave it out of the floor.

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

- **No result critical by rule was silenced, for either model.** A result the rule table calls critical was never released, never sent to review and never lowered: zero silenced criticals in every arrangement of the ablation, including the cases in which the agent answered less than critical, which the composition kept critical.
- **The safety comes from the deterministic layers.** The arrangement with only the range rule, the change rule and the release guard, and no agent, ends where the full product does: no critical released, and the two residual cases held for a person by the guard. Leave out the change rule as well and 29 of the 60 contextual criticals would be released automatically.
- **The agent is not a safety net.** When its change tool hands it the rule's verdict, it only reproduces the rule. Without the verdict, gpt-5.4-mini puts 37 of the 60 contextual criticals in read-back, sends 23 to a person and creates 7 false criticals; gpt-5.4 puts 46 in read-back, sends 14 to a person and creates 0 false criticals. That is why the design never lets the agent decide alone, and now it is measured and not assumed.
- **What the agent adds is a justification a person can check.** Each decision carries a rationale and the evidence it cites, and an answer is accepted only if every item of evidence was returned by a tool of the same investigation, so each claim traces to a recorded call. With its tools the agent costs about three times as much and takes about three times as long as it did without them (the blocks of each model), and the deterministic layers cost nothing per result.
- **Caveats.** The dataset is synthetic and has a single author, with no second annotator. The change limits and the borderline band of the release guard were set knowing the dataset generator, so their coverage is partly by construction: the results show that deterministic rules can close this kind of hole, not that the limits are clinically calibrated. The ablation replays one recorded run per model, and each run without the verdict is a single paid run.

## Demo

Open http://109.123.244.170/ and press **Run demo sequence**: a critical potassium stops at read-back, a borderline one goes to a person to review, and in the third the agent tries to lower a critical and the floor holds it. Sign in to open a read-back task with one of the demonstration accounts, all with the same password:

| Account | Can confirm a read-back |
|---|---|
| `communicator1` | yes |
| `communicator2` | yes |
| `observer` | no, it can only look |

Password: `hVWrjsSnttT8AYIn9acJ`

To open a read-back task: after the demo sequence, the critical potassium waits at the read-back station of the flow, in a card marked with the account it is assigned to. Click the card; a side panel opens and asks you to sign in. Use the account the card names (the task goes by rotation to `communicator1` or `communicator2`; `observer` can look but cannot confirm). Enter whom you told and the value you repeated, and press **Confirm the read-back**. A value that does not match is refused: the task stays open and the attempt is counted and shown in the panel; only a matching value closes the task and the alert.

The demo runs in replay mode against a real IRIS instance: the decisions are the recorded answers of a real run of the agent, so no key is needed and no provider is called. The data is synthetic. The demo is plain HTTP, and it is reset every hour, on the hour; it is unavailable for about half a minute while it resets.

The demonstration accounts are deliberately broader than a production deployment would use, because the credential is shared and the demo has to show the escalation working. They hold `%DB_USER` on the USER database, and the two communicator accounts also hold `%EnsRole_AlertAdministrator`, so that they can close alerts they do not own: the read-back task goes by rotation to either communicator, so the person who confirms is not always the owner of the alert. None of them holds `%All`, `%Manager` or `%Admin`. The demo builds its messages with Embedded Python, and the `%Service_EmbeddedPython` resource that needs belongs to the web application, through a role that is matched only while the application serves a request, not to any account. In a production deployment each of these would be a role specific to the Readback, and the alert would be closed in a system context on behalf of the person who confirmed.

The exposure is minimal: only port 80 is open, and the proxy answers 404 for every native IRIS route (`/csp/sys`, `/api/admin`, `/api/mgmnt` and the Atelier API).

### Security posture of the demo

- No administrator credential is in the repository, the image, the page or this README, and none is shown in the interface. The password published above belongs to the demonstration accounts only, and none of them holds `%All`, `%Manager` or `%Admin`.
- The page that anyone can open acts as the `observer` account, which can only look: the proxy adds that identity to the reads it forwards, and a person who wants to confirm a read-back signs in with a communicator account.
- The proxy forwards a short list of Readback paths and nothing else, limits how often a demo case can be submitted, and answers every other path with a plain JSON refusal that carries no platform content or header.
- The demo uses plain HTTP, which is why the credential is a shared demonstration one and the data is synthetic. A deployment would terminate TLS in front of the proxy.
- No tool accepts a patient or case identifier: the server binds the case before the session starts. The scope policy is a second layer: a call that names another patient is refused and the refusal is recorded.

## Required by the organizers

### Early Access image and build

The product is built on the InterSystems IRIS for Health Community image with the AI Hub, Early Access. It runs on two builds of that image: **build 154**, tagged `irishealth-community:2026.3.0AI.154.0` (the default), and **build 109**, tagged `irishealth-community:2027.1.0AI.109.0`. The image comes from the Early Access portal. It is not redistributed here, and nothing in this project pushes it to a registry.

Tested on both: the full battery of 32 steps (`tests/e2e/triage_check.sh`) passes on build 154 and on build 109, each in a stack of its own, and the evaluation in replay gives the shipped report on both. One difference between the builds matters: build 109 renamed the `RESOURCE` parameter of `%AI.MCP.Service` to `SECURITYRESOURCE` and no longer reads the old one, so a service written for 154 stops checking its resource; the product sets both and every tool checks the resource itself.

### Load and rename the image

The archive downloaded from the portal is named like `irishealth-community-2026.3.0AI.154.0-docker.tar.gz` (or `...109.0...` for build 109). Load the one the portal offers you:

```
docker load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
docker images | grep irishealth
docker tag <name-printed-by-docker-load>:<tag> irishealth-community:2026.3.0AI.154.0
src/ops/preflight.sh
```

For build 109, load the 109 archive, tag it `irishealth-community:2027.1.0AI.109.0`, and choose it in `.env` (the default is build 154):

```
docker tag <name-printed-by-docker-load>:<tag> irishealth-community:2027.1.0AI.109.0
echo 'READBACK_BASE_IMAGE=irishealth-community:2027.1.0AI.109.0' >> .env
src/ops/preflight.sh
```

The `docker tag` line is only needed when the loaded image does not already have that name. `src/ops/preflight.sh` checks that the chosen tag exists, says which build it found, and, if it does not exist, prints the load and tag steps for both builds (and tells you when the other build is the one that is loaded).

### LLM provider and key variable

The agent calls OpenAI, with the key in the environment variable `OPENAI_API_KEY`. The default model is `gpt-5.4`. `gpt-5.4-mini` is the cheaper option: it costs a fraction of the default per result and answers faster, but its agent tries to lower criticals more often (the floor holds every attempt) and the release guard holds more of its releases. Its cost, latency and errors are measured next to the default's in [For judges](#for-judges). The key is read from the environment only, and it is never printed, logged or written to a file.

Leave `OPENAI_API_KEY` empty and the product runs in replay mode, with the recorded answers of a real run of the whole evaluation set, tool calls included: everything works with no key and no cost, and the answers are the ones the agent gave. Set it to run live. The cost per thousand results is in [For judges](#for-judges).

### Start and verify

```
cp .env.example .env
# edit .env: set READBACK_DEMO_PASSWORD to a password of your choice; leave OPENAI_API_KEY empty to use replay
src/ops/preflight.sh
docker compose up -d --build
src/ops/verify.sh
curl -s http://127.0.0.1:8080/readback/api/status
```

`src/ops/preflight.sh` checks that the image is loaded and that the password reaches the product as you wrote it. Any printable password works: quotes, an apostrophe, `#`, `!`, a backslash, `&`, `;` and spaces inside were all tested end to end. Three things are refused with a message, because they would change the password on the way: a single `$` in `.env` (compose reads it as a variable, so write `$$` for a literal one), a `#` after a space in `.env` (compose reads it as a comment), and a space at either end. `src/ops/verify.sh` waits until the production is running and exits non-zero if it is not; it then checks that the task list layer is in the image and exits non-zero if it is not. Open http://127.0.0.1:8080 for the panel. The build downloads the small local embedding model and installs the IPM client and the workflow layer, so it needs network that one time; the running container needs none. The whole battery of checks, from a clean stack, is `tests/e2e/triage_check.sh`.

In the container only the start script (`src/ops/bootstrap.sh`) starts the production, and it does so after the Java gateway of the unit conversion component accepts a connection; IRIS does not start it by itself. The script runs at every start of the container, so `docker compose restart iris` brings the production back with no other step, and if the component cannot be set up the container stops with a message instead of starting half a production. `src/ops/verify.sh` says "the production is not running" as soon as the container stops or the start reports a failure, and the event log of a start holds no error and no warning (`tests/e2e/start_check.sh` checks it).

The product can also be installed as an IPM package into an instance that has the AI Hub: with the repository on disk, `zpm "load /path/to/iris-readback"` installs it, builds the unit conversion component and starts the production. Policy retrieval stays unavailable on such an instance until the embedding model is provided, as the image does; everything else works. The package sets the production to start with the instance, so on an IPM installation too the production is running again after the instance restarts, with no other step (`tests/e2e/ipm_check.sh` restarts the instance three times and checks it).

## What the production contains

This is the architecture of the product, the Interoperability components it really uses:

- **HL7 intake**: ORU^R01 lab results arrive by file and by TCP on port 5001 and are normalized and stored.
- **The business process**: a deterministic floor first (critical limits by value, and the change against the patient's earlier results), then the agent, then a composition step that takes the higher of the two, so the agent can only raise. A release guard sits after the answer: a result is released automatically only when the floor is zero, the sample quality is within the policy and the value is not near a critical limit; anything else goes to a person with the reason in the trace, and the agent cannot lift the guard.
- **The AI Hub agent step**: the platform's own agent operation, with a tool set. The agent investigates instead of receiving a prepared context: it asks for the patient's earlier results, the delta assessment of the floor, the passages of the laboratory policy and the sample quality, through four read-only tools, and answers in a strict JSON schema. No tool takes a patient or case identifier as an argument: the server binds the case before the session, so the model cannot even ask for another patient's data. Every identifier the agent cites as evidence must have been returned by a tool in that session, or the answer is invalid. An invalid answer, a failed tool call or a loop that does not end becomes a human review; every session has an explicit limit of iterations. In replay mode a replay operation answers from recordings, tool calls included.
- **Governance attached to the agent**: three policies on the tool set. The *audit* policy records every call, refusals included, in the product's own trace. The *scope* policy refuses a call that names another patient. The *floor* policy refuses, formally, an answer that would lower a result critical by rule or by change, and the refusal is recorded; the composition step still enforces the floor whatever the policy does, so removing the policy removes a record, not the guarantee.
- **Synthetic results**: the demo's messages are generated inside IRIS by Embedded Python, with the same generator that builds the evaluation dataset, and sent into the intake under a case id of their own.
- **Unit normalization**: a Production Extension in Java with the UCUM library converts units before the rules run.
- **Retrieval**: laboratory policy passages and similar confirmed cases are found with IRIS Vector Search and local embeddings (the agent reads them through its policy-search tool). A person's confirmation, a matching read-back or a completed review, is what lets a case into the pool of similar cases: the case, described without any identifier and stored with the product's final decision and route, is retrieved by the agent for the following results. Nothing that no person confirmed enters the pool, and what is stored is the decision the product made, not a judgement written by the person.
- **Workflow Engine tasks**: the read-back and the human review are Workflow tasks, with a person assigned.
- **Alerting with escalation**: a critical result raises a managed alert over the platform's alert engine, with a custom delivery-and-receipt channel; the alert moves to the next person when nobody confirms in time.
- **Tracing**: every decision keeps its inputs, the floor, the agent's answer, the composition, the tool calls in order, tokens and cost, linked to the Visual Trace session, and is readable through a small REST API. The platform's Visual Trace session shows the result, the agent's step, the task and the alerts. The tool calls, in order and with their time, are in the product's own trace and on the Decisions screen, which points to the session; the policy search, which calls another operation, also appears in the Visual Trace. In the flow of the panel the agent's node lights up its calls as sub-steps.

### Read-only MCP server

The product exposes a read-only MCP server: the platform's own `%AI.MCP.Service` (`src/Readback/MCP/Service.cls`) over four tools (`src/Readback/MCP/Tools.cls`): `list_pending_criticals`, `explain_decision`, `read_evaluation` and `read_ablation`. They follow the rules of the public feed: read only, no patient identifier in any answer, and the explanation of a decision is built from its trace record, with no model asked.

**The read-back is deliberately not exposed.** No tool confirms a read-back, closes an alert or completes a task. An AI assistant never closes a critical result: the read-back is the one act a person must do, by repeating the value, and a tool that could do it would take that act away from the person. This is a security decision, not a gap.

The access is closed. The service is the web application `/readback/mcp` on the management port, which the public proxy does not route. A caller needs the resource `Readback_MCP`, held by the role `ReadbackMcp`, and only the read-only demonstration account `observer` has that role.

To connect a client, run the platform's gateway, `iris-mcp-server`, which the image ships, inside the container with this configuration in `/tmp/mcp.toml` (the password is the demonstration password of the `observer` account):

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

Any MCP client that speaks the streamable HTTP transport connects to `http://127.0.0.1:8000/mcp` with the header `Authorization: Basic <observer:password in base64>`; the tools are listed as `readback_mcp_list_pending_criticals`, `readback_mcp_explain_decision`, `readback_mcp_read_evaluation` and `readback_mcp_read_ablation`, and the gateway lists none to a caller without credentials. The client verified here is the MCP Inspector 2.13.0 in command-line mode:

```
npx @modelcontextprotocol/inspector@2.13.0 --cli http://127.0.0.1:8000/mcp --transport http --header "Authorization: Basic <base64>" --method tools/list
```

The web application of the service is created with the type 18, the REST type plus the "MCP Server" bit (16). An application of type 2 only works over plain HTTP but the gateway answers it with a 404 and reports that it "did not identify itself" (`docs/probes.md`, Probe 17).

What was tested: a complete session with the MCP Inspector through the gateway (`tests/e2e/mcp_client_check.sh`): the four tools are listed and no other, the pending criticals and the evaluation are read, a call to a tool that would confirm the read-back is answered `tool_not_found`, and a caller without credentials and an account without the resource are listed no tool; the tools in the platform's own tool manager (`tests/e2e/mcp_check.py`, `tests/objectscript/Readback/Test/McpToolsTest.cls`, `tests/python/test_mcp_source.py`): exactly the four read tools, none of them confirms anything, no table of the product changes when they are called and no answer carries a patient identifier; and over plain HTTP, the service serves nobody directly (401 without credentials, 404 with them: an application of the MCP Server type is reached through the gateway), an account without the `Readback_MCP` resource is listed no tool through the gateway, and the public proxy does not route the service.

## Technology bonuses

| Bonus | Where it is used | File |
|---|---|---|
| PEX (Production Extension) | Unit conversion with the UCUM library, in Java, before the rules run | `java/src/com/readback/units/UnitsOperation.java` |
| Workflow Engine | The read-back and the human review are Workflow tasks, assigned by rotation to a role | `src/Readback/Workflow/ReadbackTask.cls` |
| Custom outbound adapter | The delivery-and-receipt channel of the critical-result alert: an outbound adapter with its own operation, which keeps the receipt apart from the confirmation | `src/Readback/Notify/Pager.cls` |
| Embedded Python | The demo's synthetic HL7 messages are generated inside IRIS by methods with `[ Language = python ]`, running the same Python generator that builds the evaluation dataset outside IRIS. "Send result" and "Run demo sequence" call it for every submission, with a case id of its own. Embedded Python is not used by the rules or the agent | `src/Readback/Demo/Generator.cls`, called from `src/Readback/API/Flow.cls` |
| Vector Search | Policy passages and similar confirmed cases, found by meaning with the IRIS vector store and local embeddings | `src/Readback/Retrieval/Engine.cls` |
| Docker | The image build and the compose stack, including the reverse proxy of the demo | `Dockerfile` |
| IPM | The package descriptor; `zpm "load"` installs it from the repository, and the package is in the community registry as `iris-readback` | `module.xml` |
| MCP server | A read-only `%AI.MCP.Service` with four tools; it refuses to confirm a read-back, on purpose | `src/Readback/MCP/Service.cls` |
| Find a bug in AI Hub | Two bugs found, reported in the AI Hub bug tracker with reproductions that do not use this product: [issue 18](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/18) (the agent loop has no default bound; first reported as [ai-hub-eap 41](https://github.com/intersystems-community/ai-hub-eap/issues/41)) and [issue 19](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/19) (the embedding model is described as bundled and is downloaded; first reported as [ai-hub-eap 44](https://github.com/intersystems-community/ai-hub-eap/issues/44)). The other reports, an enhancement or a documentation gap each, are [42](https://github.com/intersystems-community/ai-hub-eap/issues/42), [43](https://github.com/intersystems-community/ai-hub-eap/issues/43), [46](https://github.com/intersystems-community/ai-hub-eap/issues/46) and [47](https://github.com/intersystems-community/ai-hub-eap/issues/47), listed in [Feedback on AI Hub EAP](#feedback-on-ai-hub-eap) | `README.md` |
| First article on Developer Community | The product, the decision flow, the AI Hub experience and the safety model: https://community.intersystems.com/post/ai-agent-can-raise-critical-lab-result-never-lower-it | `README.md` |
| Video on YouTube | The main demonstration of the product: https://youtu.be/ML2pBgBkqUo | `README.md` |
| Online demo | http://109.123.244.170/ in replay mode, behind a proxy that forwards only the Readback paths | `src/ops/proxy/nginx.conf.template` |
| Implement Community Idea (DPI-I-689) | Traceability of an LLM pipeline over Interoperability: every decision, tool call and human step is recorded | `src/Readback/Trace/Decision.cls` |

## Feedback on AI Hub EAP

Observed on the Early Access build 154 while building this product, and checked again on build 109. Each item says whether it worked, needed a workaround here, or is a candidate for a report. The five candidates below were checked against the issues of `intersystems-community/ai-hub-eap` for duplicates and reported from this project; the argument types in policies were already reported by someone else. The two that are bugs, the loop and the embedding class, were also filed in `intersystems-community/ai-hub-eap-bugreports`, the tracker for bugs found in AI Hub, with their reproductions, after a search for duplicates there.

### What worked

- The platform's agent operation hosts a tool set and several rounds, parallel tool calls included, and a subclass can own the session: it sets the iteration limit and reads the statistics and the exported history in the same job.
- The strict `response_format` travels with the tools in every round, on the wire and on the real provider, so structured output and tools work together.
- Authorization and audit policies attach to the tool set. A `ReadOnly` requirement on a tool reaches the authorization policy as metadata, and a tool without it never ran.
- The exported session holds the messages, the tool calls and their results, so the path of an investigation can be rebuilt from it, and a tool that calls another Interoperability operation shows up in the Visual Trace as steps of the same session.
- The native retrieval classes (knowledge base over the IRIS vector store) serve the policy search tool as they are.

### What needed a workaround

- **Token usage covers the last round only.** With a tool round, the response reports less than the session statistics. Cost here is the difference of the session statistics before and after the case.
- **Calling the statistics from inside an audit callback never returns.** Reading them after the call works.
- **A tool failure, a denial or an unknown tool does not reach the caller**: the model gets an error message and the loop goes on, and an unknown tool is not even audited. The product reads the session history to detect them and sends the case to a person.
- **`max_tokens` is rejected by the provider for the model used**, which wants `max_completion_tokens`; the session configuration does not take it directly and it goes through `extra_params`.
- **The usage carries token counts only**, so the product keeps a dated price table and shows `unknown`, never zero, for a model without a price.
- **The provider does not read the key from the environment on its own**; the key is passed with an environment reference, and an unset variable gives an opaque error.
- **The local embedding model is described as bundled, and the first use downloads it** (about 87 MB); the product fetches it at image build time so that a running container needs no network.
- **The argument types differ between the policies**: an object in the authorization policy, a JSON string in the audit callbacks. This is already reported in the tracker as [issue 40](https://github.com/intersystems-community/ai-hub-eap/issues/40).

### Found when moving to build 109

- **`RESOURCE` became `SECURITYRESOURCE` in `%AI.MCP.Service`, and the old parameter is ignored without a warning.** On build 109 the class does no authorization of its own unless `SECURITYRESOURCE` is set or `OnAuthenticate()` is overridden (its description says so). The read-only MCP server of this product set `RESOURCE`, so on 109 an authenticated account without the resource listed and called the tools; the step of the battery that checks this account caught it. The product now sets both parameters and each tool checks the resource itself, and a test calls the tools directly as an account without it. A request without credentials is answered 401 on 154 and 404 on 109; both refuse. Reported as [issue 47](https://github.com/intersystems-community/ai-hub-eap/issues/47), with a reproduction that uses none of this product's code.

### Reported from this project

Each report has a reproduction that does not use this product: the stock build 154 image and a small mock provider, with no key.

- **[Issue 41](https://github.com/intersystems-community/ai-hub-eap/issues/41), bug: the agent loop has no default bound and outlives the caller's timeout.** With a distinct argument on every call and no iteration limit, the loop made thousands of provider requests and went on after the caller had given up; with a real provider that is open-ended spend. Setting an iteration limit makes the call stop with a clear error, but the Interoperability adapter has no setting for it. Also filed in the contest's bug tracker as [issue 18](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/18), with the reproduction in the report; the discussion is in issue 41.
- **[Issue 42](https://github.com/intersystems-community/ai-hub-eap/issues/42), enhancement: provider error text reaches the event log and the message header unredacted**, and a provider that echoes the credential puts it there. Reproduced with the platform's own operation and a mock that echoes the header; the real service masks the key.
- **[Issue 43](https://github.com/intersystems-community/ai-hub-eap/issues/43), enhancement: an exception inside an audit policy is swallowed silently**, with no error and no log line, while the same failure in an authorization policy is reported. The product's policies catch their own errors and a test proves their entries exist.
- **[Issue 44](https://github.com/intersystems-community/ai-hub-eap/issues/44), bug: the embedding class description says the model is bundled and needs no network**, while the first `Create()` downloads it and fails offline. Also filed in the contest's bug tracker as [issue 19](https://github.com/intersystems-community/ai-hub-eap-bugreports/issues/19); the discussion is in issue 44.
- **[Issue 46](https://github.com/intersystems-community/ai-hub-eap/issues/46), docs: a `%AI.MCP.Service` web application without the "MCP Server" type bit is answered 404 by `iris-mcp-server`**, which reports that the endpoint "did not identify itself"; with type 18 it works. Found while building the read-only MCP server of this product. Related to issue 21.

## Idea DPI-I-689

This entry also answers the Community Opportunity idea [DPI-I-689](https://ideas.intersystems.com/ideas/DPI-I-689), whose status on the ideas portal is Community Opportunity. The idea asks for traceability of an LLM pipeline over Interoperability. The product demonstrates exactly that on a real clinical pipeline: every decision records the rule that fired, the agent's inputs and answer, each tool call it made and what the call returned, the model, the prompt version, tokens, estimated cost and latency, and the outcome of the human step, all linked to the production's own session, and the evaluation turns those records into measured cost and latency. The Visual Trace session of a decision shows the result, the agent's step, the task and the alerts; the tool calls, in order and with their time, are in the product's own trace and on the Decisions screen, which points to that session, and the policy search, which calls another operation, also shows in the Visual Trace. It covers the essence of the idea without reimplementing a general LLM observability product such as Langfuse.

What an LLM tracing tool records, and where each item is in Readback (the decision is read through `GET /readback/api/decisions/{controlId}`, the one record behind every row):

| What an LLM tracing tool records | Where it is in Readback |
|---|---|
| A session per request | `sessionId`, the session of the production's own message trace, shown by the Decisions screen with its link to the Visual Trace; table `Readback.Trace.Decision` |
| Model and prompt version | `model`, `provider`, `promptVersion` and `mode` of the decision; `Readback.Trace.Decision` |
| Tokens, cost and latency | `inputTokens`, `outputTokens`, `costUsd` and `latencyMs` of the decision; cost per thousand results and percentiles in `GET /readback/api/indicators`; `Readback.Trace.Indicators` |
| Tool calls | `toolCalls` of the decision, in order, with arguments, result, status and time; table `Readback.Trace.ToolCall`; the policy search also appears in the Visual Trace |
| Retrieval | `passageIds`, `caseLabels`, `indexVersion` and `retrievalNote` of the decision; `Readback.Retrieval.Engine` |
| Errors and policy refusals | `failureKind`, `failureReason`, `policyRefusal` and `evidenceCheck` of the decision; a refused or failed call has its `status` in `toolCalls` |
| Human outcome | `confirmedBy`, `readbackMatch`, `reviewedBy` and `taskId` of the decision; each attempt in `Readback.Trace.ReadbackAttempt`; the history of each alert in `GET /readback/api/alerts`; `GET /readback/api/taskview/{decisionId}` |

## How it works

The [video](https://youtu.be/ML2pBgBkqUo) is the main demonstration: it shows a result arriving, the agent deciding, a critical stopping at the read-back, a person repeating the value and the alert escalating when nobody does. In short:

A lab result enters the production. The rules decide first and fix a floor: a value over the critical limit, or a sharp change against the patient's earlier results, is critical whatever the agent says. The agent then investigates the result through four read-only tools, the earlier results, the delta assessment, the laboratory policy and the sample quality, and answers in a strict format; it may raise the severity, and a result it cannot decide goes to a person. A release guard after the answer lets a result go automatically only when the floor is zero, the sample is good and the value is not near a limit.

A critical result becomes a read-back task for a person. The task shows the value, the rule that fired and the agent's rationale and evidence, labelled as the agent's. The person must call the clinician and repeat the value; only a value that matches closes the task and the alert. If nobody confirms in time, the alert escalates to the next person.

The panel shows the flow live and the queue of critical alerts with the history of each alert. The same flow runs from recordings with no key, which is how the demo runs.

## Built with

| Library | Version | Licence |
|---|---|---|
| React, React DOM | 19.3.1 | MIT |
| @xyflow/react (React Flow) | 12.12.0 | MIT |
| Vite | 7.3.7 | MIT |
| TypeScript | 7.0.2 | Apache-2.0 |
| Vitest, Testing Library, jsdom | 5.0.5, 16.3.3, 30.1.3 | MIT |
| Playwright | 1.64.1 | Apache-2.0 |
| nginx (the reverse proxy of the demo) | 1.30.6 | BSD-2-Clause |
| UCUM for Java (`org.fhir:ucum`) | 1.0.9 | BSD-3-Clause |

The product runs on InterSystems IRIS for Health Community with the AI Hub (Early Access build 154); the REST layer of the Workflow Engine comes from the community package `workflow-rest`. The frontend loads nothing from a network at run time, and its initial JavaScript and CSS are under 150 KB compressed.

## Author

Carlos Eduardo Dias Duarte. Released under the MIT licence, see `LICENSE`.
