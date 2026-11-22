# WP-S4 run `cat_all`

Category options: `all` (45). Passes: 1. Retries used: 0. Generated 2026-11-22 18:43:06.137354Z UTC.

## Accuracy per question

| question | pass 1 |
|---|---|
| `intent` | n/a |
| `category` | 100.0% (27/27) |
| `account` | n/a |
| `who` | n/a |
| `multi_entry` | n/a |
| `repayable` | n/a |
| `needs_followup` | n/a |
| `is_recurring` | n/a |
| `duplicate` | n/a |

Pass 1 details:

- category top-3: 100.0% (27/27)
- account when stated: n/a; not stated (expects `unspecified`): n/a

### Intent by slice (pass 1)

| slice | intent correct | mean confidence |
|---|---|---|

### Follow-up and routing (pass 1, threshold 0.5)

- `needs_followup` recall on the ambiguous slice: n/a
- `needs_followup` rate on the explicit slice: n/a
- `multi_entry` recall: n/a; false re-routes of single messages: n/a

## Calibration (pass 1)

### Choice questions, top-1 confidence vs correct

| bin | n | mean confidence | observed | gap |
|---|---|---|---|---|
| 0.60–0.70 | 1 | 0.635 | 1.000 | 0.365 |
| 0.80–0.90 | 2 | 0.885 | 1.000 | 0.115 |
| 0.90–1.00 | 24 | 0.991 | 1.000 | 0.009 |

N = 27, ECE = 0.030, Brier = 0.006

### Yes/no questions, P(yes) vs label

| bin | n | mean P(yes) | observed | gap |
|---|---|---|---|---|

N = 0, ECE = 0.000, Brier = 0.000

### All answers, confidence vs correct

| bin | n | mean confidence | observed | gap |
|---|---|---|---|---|
| 0.60–0.70 | 1 | 0.635 | 1.000 | 0.365 |
| 0.80–0.90 | 2 | 0.885 | 1.000 | 0.115 |
| 0.90–1.00 | 24 | 0.991 | 1.000 | 0.009 |

N = 27, ECE = 0.030, Brier = 0.006

### ECE per question

| question | n | accuracy | mean confidence | ECE | Brier |
|---|---|---|---|---|---|
| `category` | 27 | 1.000 | 0.970 | 0.030 | 0.006 |

## Confidence policy simulation (pass 1, choice questions)

Defaults: prefill at ≥ 0.85 (intent: asks below 0.90), "Guessed" from 0.55, ask below 0.55.

| question | n | prefilled | wrong when prefilled | guessed | wrong when guessed | asked |
|---|---|---|---|---|---|---|
| `intent` | 0 | n/a | n/a | n/a | n/a | n/a |
| `category` | 27 | 96.3% (26/27) | 0.0% (0/26) | 3.7% (1/27) | 0.0% (0/1) | 0.0% (0/27) |
| `account` | 0 | n/a | n/a | n/a | n/a | n/a |
| `who` | 0 | n/a | n/a | n/a | n/a | n/a |

Sweep of `conf_high` over all choice answers:

| conf_high | prefilled | wrong prefills (of all answers) |
|---|---|---|
| 0.50 | 100.0% (27/27) | 0.0% (0/27) |
| 0.55 | 100.0% (27/27) | 0.0% (0/27) |
| 0.60 | 100.0% (27/27) | 0.0% (0/27) |
| 0.65 | 96.3% (26/27) | 0.0% (0/27) |
| 0.70 | 96.3% (26/27) | 0.0% (0/27) |
| 0.75 | 96.3% (26/27) | 0.0% (0/27) |
| 0.80 | 96.3% (26/27) | 0.0% (0/27) |
| 0.85 | 96.3% (26/27) | 0.0% (0/27) |
| 0.90 | 88.9% (24/27) | 0.0% (0/27) |
| 0.95 | 85.2% (23/27) | 0.0% (0/27) |

## Latency and tokens (all passes)

| measure | n | mean | p50 | p90 | p95 | min | max |
|---|---|---|---|---|---|---|---|
| latency, ms | 27 | 310 | 282 | 379 | 522 | 243 | 543 |
| input tokens | 27 | 1157 | 1153 | 1180 | 1186 | 1136 | 1188 |
| cost, USD per 100k calls | 27 | 11.57 | 11.53 | 11.80 | 11.86 | 11.36 | 11.88 |

First request of the run (cold connection): 543 ms.

By number of questions asked:

| measure | n | mean | p50 | p90 | p95 | min | max |
|---|---|---|---|---|---|---|---|
| 1 questions: tokens | 27 | 1157 | 1153 | 1180 | 1186 | 1136 | 1188 |
| 1 questions: ms | 27 | 310 | 282 | 379 | 522 | 243 | 543 |

Usage fields seen: `total_tokens`, `total_input_tokens`, `input_tokens_by_modality`, `total_output_tokens`.
Sample usage: `{"total_tokens":1148,"total_input_tokens":1148,"input_tokens_by_modality":[{"modality":"text","tokens":1148}],"total_output_tokens":0}`

## Errors and blocks during the run

None.

## Misses (pass 1)

| case | question | expected | got | confidence |
|---|---|---|---|---|
