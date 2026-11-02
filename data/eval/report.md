# Evaluation report

Dataset seed 2026, 240 subject cases per model, prompt version triage-v3, run date 2026-11-02.

How to read it. Each case went through the whole product (floor, retrieval, agent, composition, budget). The agent matrix compares the decision the agent answered with the expected one; `none` means no valid answer (invalid, refused, timed out, provider error, budget skipped) or a case that was never processed. The final matrix compares the route the product chose (read-back is CRITICAL, recollect is RECOLLECT, review is NEEDS_REVIEW, release is NON_CRITICAL). A silenced critical is a result critical by the rule table whose final route is not read-back; it must be zero. A missed critical is an expected-critical result that was not critical by rule and that no layer sent to read-back: an error of the agent, listed by case. A downgrade attempt is a rule-critical result for which the agent answered less than critical (the composition keeps it critical).

## gpt-5.4-mini

Price per million tokens (input / output): 0.75 / 4.5 USD (dated 2026-10-28).

Run settings: temperature 0; strict JSON schema; output cap 400 tokens; model gpt-5.4-mini. Budget ceilings of the run: per result 10000 tokens; per hour 8 USD or 10000000 tokens.

### Agent decision against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 112 | 12 | 2 | 24 | 0 |
| RECOLLECT | 0 | 10 | 0 | 20 | 0 |
| NEEDS_REVIEW | 0 | 13 | 0 | 17 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Final decision (route) against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 148 | 0 | 2 | 0 | 0 |
| RECOLLECT | 0 | 0 | 30 | 0 | 0 |
| NEEDS_REVIEW | 0 | 0 | 30 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Figures

- Silenced criticals: **0**
- Missed criticals (expected CRITICAL, not critical by rule, not sent to read-back): 2 (RB2026-00034, RB2026-00122)
- Downgrade attempts by the agent on rule-critical results: 36
- Cost per thousand results (USD): 2.8426 (rows of unknown cost: 0)
- Latency p50 / p95 (ms, recorded): 2975 / 3791
- Invalid answer rate: 0.0%; human review rate: 27.6%; rule-versus-agent divergence rate: 30.9%
- Agent calls: 446 of 446 messages; failures by kind: {'floor-policy-refusal': 58, 'low-confidence': 2, 'release-guard': 22}
- Investigation with tools: 1783 tool calls (3.9978 per result), 2.0 rounds a result on average (most 2), 0 results with a call that did not succeed (0 refused by a policy), 0 stopped at the limit
- Floor policy refusals of an answer that would have lowered a critical: 60; answers rejected for evidence no tool returned: 0; invalid answer rate with the evidence rule: 0.0%
- Releases held for a person by the release guard (floor not zero, sample quality outside the policy, or a borderline value): 22
- Subject cases never processed: 0

| category | cases | agent agrees | final agrees |
|---|---|---|---|
| acute-drop-in-range | 30 | 30 | 30 |
| ambiguous | 30 | 0 | 30 |
| clear-critical | 30 | 24 | 30 |
| contextual-critical | 30 | 28 | 28 |
| explainable-false-critical | 30 | 16 | 30 |
| normal | 30 | 30 | 30 |
| recollect | 30 | 10 | 0 |
| sample-problem | 30 | 14 | 30 |

## gpt-5.4

Price per million tokens (input / output): 2.5 / 15.0 USD (dated 2026-10-28).

Run settings: temperature 0; strict JSON schema; output cap 400 tokens; model gpt-5.4. Budget ceilings of the run: per result 10000 tokens; per hour 8 USD or 10000000 tokens.

### Agent decision against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 144 | 1 | 0 | 3 | 2 |
| RECOLLECT | 0 | 30 | 0 | 0 | 0 |
| NEEDS_REVIEW | 0 | 23 | 0 | 7 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Final decision (route) against the expected decision

| expected \ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |
|---|---|---|---|---|---|
| CRITICAL | 148 | 0 | 2 | 0 | 0 |
| RECOLLECT | 0 | 0 | 30 | 0 | 0 |
| NEEDS_REVIEW | 0 | 0 | 30 | 0 | 0 |
| NON_CRITICAL | 0 | 0 | 0 | 30 | 0 |

### Figures

- Silenced criticals: **0**
- Missed criticals (expected CRITICAL, not critical by rule, not sent to read-back): 2 (RB2026-00034, RB2026-00122)
- Downgrade attempts by the agent on rule-critical results: 2
- Cost per thousand results (USD): 9.7268 (rows of unknown cost: 0)
- Latency p50 / p95 (ms, recorded): 6262 / 7563
- Invalid answer rate: 0.0%; human review rate: 28.5%; rule-versus-agent divergence rate: 11.9%
- Agent calls: 446 of 446 messages; failures by kind: {'floor-policy-refusal': 2, 'low-confidence': 3, 'provider-error': 5, 'release-guard': 1, 'timeout': 1}
- Investigation with tools: 1772 tool calls (3.9731 per result), 1.9865 rounds a result on average (most 2), 0 results with a call that did not succeed (0 refused by a policy), 0 stopped at the limit
- Floor policy refusals of an answer that would have lowered a critical: 3; answers rejected for evidence no tool returned: 0; invalid answer rate with the evidence rule: 0.0%
- Releases held for a person by the release guard (floor not zero, sample quality outside the policy, or a borderline value): 1
- Subject cases never processed: 0

| category | cases | agent agrees | final agrees |
|---|---|---|---|
| acute-drop-in-range | 30 | 29 | 30 |
| ambiguous | 30 | 0 | 30 |
| clear-critical | 30 | 30 | 30 |
| contextual-critical | 30 | 28 | 28 |
| explainable-false-critical | 30 | 28 | 30 |
| normal | 30 | 30 | 30 |
| recollect | 30 | 30 | 0 |
| sample-problem | 30 | 29 | 30 |

## Comparison

| | gpt-5.4-mini | gpt-5.4 | first live run of gpt-5.4 (26 sample messages) |
|---|---|---|---|
| Cost per thousand (USD) | 2.8426 | 9.7268 | 3.3306 |
| Latency p50 (ms) | 2975 | 6262 | 2231 |
| Latency p95 (ms) | 3791 | 7563 | 3268 |
| Invalid answer rate | 0.0% | 0.0% | n/a |
| Human review rate | 27.6% | 28.5% | n/a |
| Silenced criticals | 0 | 0 | n/a |

## Movement against the previous report

Prompt version before: triage-v2; now: triage-v3. Every figure is listed, the ones that got worse included.

### gpt-5.4-mini

| figure | previous | current | change |
|---|---|---|---|
| missedCriticals | 2 | 2 | 0 |
| silencedCriticals | 0 | 0 | 0 |
| downgradeAttempts | 24 | 36 | 12 |
| reviewRate | 0.172646 | 0.275785 | 0.103139 |
| divergenceRate | 0.096413 | 0.309417 | 0.213004 |
| invalidRate | 0.0 | 0.0 | 0.0 |
| costPerThousandUsd | 0.955547 | 2.842608 | 1.887061 |
| latencyP50Ms | 1127 | 2975 | 1848 |
| latencyP95Ms | 1553 | 3791 | 2238 |
| expectedCriticalReadback | 148 | 148 | 0 |
| expectedCriticalAgentAlone | 124 | 112 | -12 |

### gpt-5.4

| figure | previous | current | change |
|---|---|---|---|
| missedCriticals | 2 | 2 | 0 |
| silencedCriticals | 0 | 0 | 0 |
| downgradeAttempts | 18 | 2 | -16 |
| reviewRate | 0.156951 | 0.284753 | 0.127802 |
| divergenceRate | 0.065022 | 0.118834 | 0.053812 |
| invalidRate | 0.0 | 0.0 | 0.0 |
| costPerThousandUsd | 3.32722 | 9.726816 | 6.399596 |
| latencyP50Ms | 2042 | 6262 | 4220 |
| latencyP95Ms | 2506 | 7563 | 5057 |
| expectedCriticalReadback | 148 | 148 | 0 |
| expectedCriticalAgentAlone | 130 | 144 | 14 |


## Limits

- The expected decision of every case comes from construction rules written in `DATASET.md`, by one author; there was no second annotator.
- The release guard's limits come from the laboratory policy and were checked against the dataset generator: the hemolysis limit (100) is the policy's own number, but the policy gives no number for "near the critical limit", and the borderline band (93 percent of the limit) starts where the dataset's contextual and ambiguous cases start. Its coverage of those cases is partly by construction, as the delta floor's is; it shows that a deterministic guard can close this kind of hole, not that these limits are clinically calibrated.
- The provider is not guaranteed to be deterministic at the settings used. The recorded run is the published one, and replay reproduces it.
- Cost is computed from the recorded token counts and the dated price above; a model with no price shows `unknown`, never zero.
