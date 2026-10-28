# Evaluation dataset

Synthetic lab results for the evaluation of the triage agent. Every identifier is synthetic. The file `dataset.jsonl` has one JSON
object per message: `messageId`, `role` (`subject` or `history`), `patientId`, `category`, `expected`, `seed` and `text` (the HL7 message).

Seed 2026, 30 subject cases per category, 240 subject cases in all; the history messages that a case needs come before it.

## How the expected decision is assigned

By the construction rules in this table, which rest on the synthetic policy passages in `data/policy/passages.jsonl`. It is never assigned
by a model. A result critical by the rule table is expected CRITICAL whatever the sample quality or the history says, because the
agent can never lower it (P-1 and P-2).

| Category | How a case is built | Expected | Policy passages |
|---|---|---|---|
| clear-critical | a value beyond a critical limit | CRITICAL | crit-potassium, crit-glucose, crit-hemoglobin, crit-sodium |
| contextual-critical | a value at 93 to 99% of the critical limit after a normal earlier result of the same patient | CRITICAL | ctx-earlier-results (a large change matters more than the absolute value), ctx-acute-drop for hemoglobin |
| explainable-false-critical | potassium at or above 6.5 mmol/L with stable high earlier results (scheduled dialysis) | CRITICAL | ctx-dialysis-stable, review-agent-never-lowers |
| acute-drop-in-range | hemoglobin inside the critical limit, more than 3 g/dL below an earlier result of the last 24 hours | CRITICAL | ctx-acute-drop |
| sample-problem | critical potassium with a hemolysis index above 100 | CRITICAL | recollect-communicate-anyway, recollect-indices |
| recollect | potassium 5.5 to 6.3 mmol/L (not critical) with a hemolysis index above 150 | RECOLLECT | recollect-hemolysis |
| ambiguous | potassium 6.2 to 6.4 mmol/L (below the critical limit), elevated earlier results, hemolysis index 70 to 99 | NEEDS_REVIEW | review-ambiguous |
| normal | a value inside the normal range, no sample flags, no earlier results | NON_CRITICAL | no rule fires |

## Limits of the labels

The labels come from one author reading the policy; there was no second annotator. The contextual-critical rule is the most open to
disagreement: the policy says a large change matters more than the absolute value, and the rule turns that into CRITICAL. The history
messages carry no expected decision and are not part of the matrices; they are processed and counted in cost and latency.
