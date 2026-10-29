# Evaluation report

Dataset seed 2026, 240 subject cases per model, prompt version triage-v2, run date 2026-10-28.

How to read it. Each case went through the whole product (floor, retrieval, agent, composition, budget). The agent matrix compares the decision the agent answered with the expected one; `none` means no valid answer (invalid, refused, timed out, provider error, budget skipped) or a case that was never processed. The final matrix compares the route the product chose (read-back is CRITICAL, recollect is RECOLLECT, review is NEEDS_REVIEW, release is NON_CRITICAL). A silenced critical is a result critical by the rule table whose final route is not read-back; it must be zero. A missed critical is an expected-critical result that was not critical by rule and that no layer sent to read-back: an error of the agent, listed by case. A downgrade attempt is a rule-critical result for which the agent answered less than critical (the composition keeps it critical).

## gpt-5.4-mini

Price per million tokens (input / output): 0.75 / 4.5 USD (dated 2026-10-28).

Run settings: temperature 0; strict JSON schema; output cap 400 tokens; model gpt-5.4-mini. Budget ceilings of the run: per result 10000 tokens; per hour 20 USD or 10000000 tokens.

### Agent decision against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 124 | 0 | 0 | 26 | 0 |
| RECOLLECT | 0 | 29 | 0 | 1 | 0 |
| NEEDS_REVIEW | 0 | 30 | 0 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Final decision (route) against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 126 | 0 | 5 | 19 | 0 |
| RECOLLECT | 0 | 0 | 30 | 0 | 0 |
| NEEDS_REVIEW | 0 | 0 | 30 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Figures

- Silenced criticals: **0**
- Missed criticals (expected CRITICAL, not critical by rule, not sent to read-back): 24 (RB2026-00002, RB2026-00018, RB2026-00026, RB2026-00034, RB2026-00042, RB2026-00050, RB2026-00058, RB2026-00066, RB2026-00082, RB2026-00090, RB2026-00098, RB2026-00106, RB2026-00122, RB2026-00130, RB2026-00138, RB2026-00154, RB2026-00170, RB2026-00186, RB2026-00194, RB2026-00202, RB2026-00210, RB2026-00218, RB2026-00226, RB2026-00234)
- Downgrade attempts by the agent on rule-critical results: 2
- Cost per thousand results (USD): 0.9555 (rows of unknown cost: 0)
- Latency p50 / p95 (ms, recorded): 1127 / 1553
- Invalid answer rate: 0.0%; human review rate: 18.4%; rule-versus-agent divergence rate: 5.6%
- Agent calls: 446 of 446 messages; failures by kind: none
- Subject cases never processed: 0

| category | cases | agent agrees | final agrees |
|---|---|---|---|
| acute-drop-in-range | 30 | 30 | 30 |
| ambiguous | 30 | 0 | 30 |
| clear-critical | 30 | 28 | 30 |
| contextual-critical | 30 | 6 | 6 |
| explainable-false-critical | 30 | 30 | 30 |
| normal | 30 | 30 | 30 |
| recollect | 30 | 29 | 0 |
| sample-problem | 30 | 30 | 30 |

## gpt-5.4

Price per million tokens (input / output): 2.5 / 15.0 USD (dated 2026-10-28).

Run settings: temperature 0; strict JSON schema; output cap 400 tokens; model gpt-5.4. Budget ceilings of the run: per result 10000 tokens; per hour 20 USD or 10000000 tokens.

### Agent decision against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 130 | 0 | 6 | 14 | 0 |
| RECOLLECT | 0 | 30 | 0 | 0 | 0 |
| NEEDS_REVIEW | 0 | 30 | 0 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Final decision (route) against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 132 | 0 | 11 | 7 | 0 |
| RECOLLECT | 0 | 0 | 30 | 0 | 0 |
| NEEDS_REVIEW | 0 | 0 | 30 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Figures

- Silenced criticals: **0**
- Missed criticals (expected CRITICAL, not critical by rule, not sent to read-back): 18 (RB2026-00002, RB2026-00018, RB2026-00026, RB2026-00034, RB2026-00042, RB2026-00050, RB2026-00058, RB2026-00082, RB2026-00098, RB2026-00106, RB2026-00122, RB2026-00130, RB2026-00138, RB2026-00186, RB2026-00194, RB2026-00202, RB2026-00218, RB2026-00226)
- Downgrade attempts by the agent on rule-critical results: 2
- Cost per thousand results (USD): 3.3272 (rows of unknown cost: 0)
- Latency p50 / p95 (ms, recorded): 2042 / 2506
- Invalid answer rate: 0.0%; human review rate: 18.4%; rule-versus-agent divergence rate: 4.0%
- Agent calls: 446 of 446 messages; failures by kind: none
- Subject cases never processed: 0

| category | cases | agent agrees | final agrees |
|---|---|---|---|
| acute-drop-in-range | 30 | 30 | 30 |
| ambiguous | 30 | 0 | 30 |
| clear-critical | 30 | 28 | 30 |
| contextual-critical | 30 | 12 | 12 |
| explainable-false-critical | 30 | 30 | 30 |
| normal | 30 | 30 | 30 |
| recollect | 30 | 30 | 0 |
| sample-problem | 30 | 30 | 30 |

## Comparison

| | gpt-5.4-mini | gpt-5.4 | first live run of gpt-5.4 (26 sample messages) |
|---|---|---|---|
| Cost per thousand (USD) | 0.9555 | 3.3272 | 3.3306 |
| Latency p50 (ms) | 1127 | 2042 | 2231 |
| Latency p95 (ms) | 1553 | 2506 | 3268 |
| Invalid answer rate | 0.0% | 0.0% | n/a |
| Human review rate | 18.4% | 18.4% | n/a |
| Silenced criticals | 0 | 0 | n/a |

## Limits

- The expected decision of every case comes from construction rules written in `DATASET.md`, by one author; there was no second annotator.
- The provider is not guaranteed to be deterministic at the settings used. The recorded run is the published one, and replay reproduces it.
- Cost is computed from the recorded token counts and the dated price above; a model with no price shows `unknown`, never zero.
