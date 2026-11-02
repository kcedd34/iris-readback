# iris-readback

An InterSystems AI Hub agent triages laboratory results inside an IRIS Interoperability production: it can raise a result to critical but never lower one the rules call critical, and nobody is notified of a critical result until a person has completed the read-back by repeating the value correctly.

## Fast path

- Video, the main demonstration: [PENDING: publication]
- Live demo (replay mode, reset every hour): http://109.123.244.170/
- Repository: https://github.com/kcedd34/iris-readback
- IPM package: `zpm "install iris-readback"` [PENDING: publication]
- Open Exchange: [PENDING: publication]
- Community Opportunity idea: https://ideas.intersystems.com/ideas/DPI-I-689
- Measured evaluation, full report: `data/eval/report.md`

## Demo

Open http://109.123.244.170/ and press **Run demo sequence**: a critical potassium stops at read-back and a borderline one goes to a person to review. Sign in to open a read-back task with one of the demonstration accounts, all with the same password:

| Account | Can confirm a read-back |
|---|---|
| `communicator1` | yes |
| `communicator2` | yes |
| `observer` | no, it can only look |

Password: `hVWrjsSnttT8AYIn9acJ`

The demo runs in replay mode against a real IRIS instance: the decisions are the recorded answers of a real run of the agent, so no key is needed and no provider is called. The data is synthetic. The demo is plain HTTP, and it is reset every hour, on the hour; it is unavailable for about half a minute while it resets.

The demonstration accounts are deliberately broader than a production deployment would use, because the credential is shared and the demo has to show the escalation working. They hold `%DB_USER` on the USER database, and the two communicator accounts also hold `%EnsRole_AlertAdministrator`, so that they can close alerts they do not own: the read-back task goes by rotation to either communicator, so the person who confirms is not always the owner of the alert. None of them holds `%All`, `%Manager` or `%Admin`. In a production deployment each of these would be a role specific to the Readback, and the alert would be closed in a system context on behalf of the person who confirmed.

The exposure is minimal: only port 80 is open, and the proxy answers 404 for every native IRIS route (`/csp/sys`, `/api/admin`, `/api/mgmnt` and the Atelier API).

## Required by the organizers

### Early Access image and build

The product is built on the InterSystems IRIS for Health Community image with the AI Hub, Early Access **build 154**, tagged `irishealth-community:2026.3.0AI.154.0`. The image comes from the Early Access portal. It is not redistributed here, and nothing in this project pushes it to a registry.

### Load and rename the image

The archive downloaded from the portal is named like `irishealth-community-2026.3.0AI.154.0-docker.tar.gz`.

```
docker load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
docker images | grep irishealth
docker tag <name-printed-by-docker-load>:<tag> irishealth-community:2026.3.0AI.154.0
src/ops/preflight.sh
```

The `docker tag` line is only needed when the loaded image does not already have that name. `src/ops/preflight.sh` checks that the tag exists and, if it does not, prints these steps.

### LLM provider and key variable

The agent calls OpenAI, with the key in the environment variable `OPENAI_API_KEY`. The default model is `gpt-5.4`; `gpt-5.4-mini` is also evaluated below. The key is read from the environment only, and it is never printed, logged or written to a file.

Leave `OPENAI_API_KEY` empty and the product runs in replay mode, with the recorded answers of a real run of 446 messages: everything works with no key and no cost, and the answers are the ones the agent gave. Set it to run live. The estimated cost per thousand results is in the results below.

### Start and verify

```
cp .env.example .env
# edit .env: set READBACK_DEMO_PASSWORD to a password of your choice; leave OPENAI_API_KEY empty to use replay
src/ops/preflight.sh
docker compose up -d --build
src/ops/verify.sh
curl -s http://127.0.0.1:8080/readback/api/status
```

`src/ops/preflight.sh` checks that the image is loaded and that the password reaches the product as you wrote it. Any printable password works: quotes, an apostrophe, `#`, `!`, a backslash, `&`, `;` and spaces inside were all tested end to end. Three things are refused with a message, because they would change the password on the way: a single `$` in `.env` (compose reads it as a variable, so write `$$` for a literal one), a `#` after a space in `.env` (compose reads it as a comment), and a space at either end. `src/ops/verify.sh` waits until the production is running and exits non-zero if it is not; it then waits for the task list layer, which installs after the start, and only warns if that layer is not there. Open http://127.0.0.1:8080 for the panel. The first build downloads the small local embedding model once, so it needs network that one time. The whole battery of checks, from a clean stack, is `tests/e2e/triage_check.sh`.

The product can also be installed as an IPM package into an instance that has the AI Hub: with the repository on disk, `zpm "load /path/to/iris-readback"` installs it, builds the unit conversion component and starts the production. Policy retrieval stays unavailable on such an instance until the embedding model is provided, as the image does; everything else works.

## What the production contains

This is the architecture of the product, the Interoperability components it really uses:

- **HL7 intake**: ORU^R01 lab results arrive by file and by TCP on port 5001 and are normalized and stored.
- **The business process**: a deterministic floor first (critical limits by value, and the change against the patient's earlier results), then the agent, then a composition step that takes the higher of the two, so the agent can only raise.
- **The AI Hub agent step**: one call with a strict JSON schema, an invalid answer becoming a human review. In replay mode a replay operation answers from recordings instead.
- **Unit normalization**: a Production Extension in Java with the UCUM library converts units before the rules run.
- **Retrieval**: laboratory policy passages and similar confirmed cases are found with IRIS Vector Search and local embeddings.
- **Workflow Engine tasks**: the read-back and the human review are Workflow tasks, with a person assigned.
- **Alerting with escalation**: a critical result raises a managed alert over the platform's alert engine, with a custom delivery-and-receipt channel; the alert moves to the next person when nobody confirms in time.
- **Tracing**: every decision keeps its inputs, the floor, the agent's answer, the composition, tokens and cost, linked to the Visual Trace session, and is readable through a small REST API.

## Results

The evaluation runs the whole product, rules, retrieval, agent, composition and budget, over a synthetic dataset of 240 subject cases (30 in each of 8 categories, seed 2026) for two models, and compares the route the product chose with the expected one. The expected decision of every case comes from construction rules written by one author; there was no second annotator. Full detail is in `data/eval/report.md`.

#### gpt-5.4-mini

Final decision (route) against the expected decision:

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 148 | 0 | 0 | 2 | 0 |
| RECOLLECT | 0 | 0 | 28 | 2 | 0 |
| NEEDS_REVIEW | 0 | 0 | 22 | 8 | 0 |
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

What the numbers say, and what they do not say:

- **No result critical by rule was silenced, for either model.** A result the rule table calls critical was never released, never sent to review and never lowered: zero silenced criticals for gpt-5.4 and zero for gpt-5.4-mini, including the cases in which the agent answered less than critical, which the composition kept critical.
- **The agent alone is not the defence.** Before the deterministic delta floor, expected-critical results the rules did not know were released as non-critical: 19 for gpt-5.4-mini and 7 for gpt-5.4. With the delta floor, a rule that raises a result by its change against the patient's earlier results, the released criticals fell from 19 to 2 for gpt-5.4-mini and from 7 to 2 for gpt-5.4. That reduction was measured on the first round (prompt triage-v2, no tools) by replaying the recorded answers; in the current round, in which the agent reads the earlier results through tools, the released criticals are 2 for both models, the same two.
- **Two cases remain for both models.** Two contextual criticals, sodium at 150, fall under every limit: neither the value rule, nor the delta rule, nor the agent caught them. They are the honest limit of this design, listed by case in the report.
- **Caveat that goes with the reduction.** The delta limits were chosen by the author knowing the range of the dataset generator, so the coverage is partly by construction. The result shows that the architecture can close this kind of hole with a deterministic rule; it is not a clinical calibration, and the dataset is synthetic and single-author.
- **What is guaranteed and what is not.** The guarantee that holds, measured: the agent cannot lower a result that is critical by rule. The guarantee that does not exist: a contextual critical that no rule models is caught only if the delta floor, the agent or a review catches it.

## Idea DPI-I-689

This entry also answers the Community Opportunity idea [DPI-I-689](https://ideas.intersystems.com/ideas/DPI-I-689), whose status on the ideas portal is Community Opportunity. The idea asks for traceability of an LLM pipeline over Interoperability. The product demonstrates exactly that on a real clinical pipeline: every decision records the rule that fired, the agent's inputs and answer, the model, the prompt version, tokens, estimated cost and latency, and the outcome of the human step, all linked to the production's own session, and the evaluation turns those records into measured cost and latency. It covers the essence of the idea without reimplementing a general LLM observability product such as Langfuse.

## How it works

The video is the main demonstration: it shows a result arriving, the agent deciding, a critical stopping at the read-back, a person repeating the value and the alert escalating when nobody does. In short:

A lab result enters the production. The rules decide first and fix a floor: a value over the critical limit, or a sharp change against the patient's earlier results, is critical whatever the agent says. The agent then reads the result with the earlier results and the laboratory policy and answers in a strict format; it may raise the severity, and a result it cannot decide goes to a person.

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

## Still to publish

- Open Exchange address of the application: [PENDING: publication]
- Link of the published IPM package: [PENDING: publication]
- Link of the video on YouTube: [PENDING: publication]
