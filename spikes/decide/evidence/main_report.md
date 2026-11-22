# WP-S4 run `main`

Category options: `leaves` (36). Passes: 2. Retries used: 0. Generated 2026-11-22 18:52:50.599783Z UTC.

Re-scored from evidence/raw/main_responses.jsonl with no API calls. The calls themselves used secret version 2 (see docs/spikes/WP-S4.md, "Secret versions used").

## Accuracy per question

| question | pass 1 | pass 2 |
|---|---|---|
| `intent` | 100.0% (53/53) | 100.0% (53/53) |
| `category` | 100.0% (27/27) | 100.0% (27/27) |
| `account` | 95.7% (44/46) | 95.7% (44/46) |
| `who` | 92.3% (12/13) | 92.3% (12/13) |
| `multi_entry` | 100.0% (60/60) | 100.0% (60/60) |
| `repayable` | 100.0% (9/9) | 100.0% (9/9) |
| `needs_followup` | 95.6% (43/45) | 95.6% (43/45) |
| `is_recurring` | 100.0% (27/27) | 100.0% (27/27) |
| `duplicate` | 57.1% (4/7) | 57.1% (4/7) |

Pass 1 details:

- category top-3: 100.0% (27/27)
- account when stated: 93.8% (15/16); not stated (expects `unspecified`): 96.7% (29/30)

### Intent by slice (pass 1)

| slice | intent correct | mean confidence |
|---|---|---|
| single_explicit | 100.0% (11/11) | 0.97 |
| single_terse | 100.0% (7/7) | 0.98 |
| income | 100.0% (6/6) | 0.96 |
| transfer | 100.0% (6/6) | 0.97 |
| loan | 100.0% (8/8) | 0.99 |
| ambiguous | 100.0% (5/5) | 0.64 |
| question | 100.0% (4/4) | 0.99 |
| command | 100.0% (3/3) | 0.99 |
| adversarial | 100.0% (3/3) | 0.94 |

### Follow-up and routing (pass 1, threshold 0.5)

- `needs_followup` recall on the ambiguous slice: 100.0% (6/6)
- `needs_followup` rate on the explicit slice: 0.0% (0/11)
- `multi_entry` recall: 100.0% (6/6); false re-routes of single messages: 0.0% (0/54)

## Calibration (pass 1)

### Choice questions, top-1 confidence vs correct

| bin | n | mean confidence | observed | gap |
|---|---|---|---|---|
| 0.40–0.50 | 8 | 0.467 | 0.750 | 0.283 |
| 0.60–0.70 | 6 | 0.661 | 1.000 | 0.339 |
| 0.70–0.80 | 12 | 0.746 | 1.000 | 0.254 |
| 0.80–0.90 | 24 | 0.858 | 0.958 | 0.100 |
| 0.90–1.00 | 89 | 0.983 | 1.000 | 0.017 |

N = 139, ECE = 0.081, Brier = 0.036

### Yes/no questions, P(yes) vs label

| bin | n | mean P(yes) | observed | gap |
|---|---|---|---|---|
| 0.00–0.10 | 100 | 0.024 | 0.000 | -0.024 |
| 0.10–0.20 | 10 | 0.140 | 0.000 | -0.140 |
| 0.20–0.30 | 5 | 0.237 | 0.200 | -0.037 |
| 0.30–0.40 | 4 | 0.360 | 0.500 | 0.140 |
| 0.50–0.60 | 2 | 0.538 | 0.500 | -0.038 |
| 0.60–0.70 | 2 | 0.650 | 0.500 | -0.150 |
| 0.70–0.80 | 1 | 0.772 | 1.000 | 0.228 |
| 0.80–0.90 | 3 | 0.838 | 1.000 | 0.162 |
| 0.90–1.00 | 21 | 0.971 | 1.000 | 0.029 |

N = 148, ECE = 0.042, Brier = 0.023

### All answers, confidence vs correct

| bin | n | mean confidence | observed | gap |
|---|---|---|---|---|
| 0.40–0.50 | 8 | 0.467 | 0.750 | 0.283 |
| 0.50–0.60 | 2 | 0.538 | 0.500 | -0.038 |
| 0.60–0.70 | 12 | 0.652 | 0.750 | 0.098 |
| 0.70–0.80 | 18 | 0.752 | 0.944 | 0.192 |
| 0.80–0.90 | 37 | 0.857 | 0.973 | 0.116 |
| 0.90–1.00 | 210 | 0.978 | 1.000 | 0.022 |

N = 287, ECE = 0.055, Brier = 0.029

### ECE per question

| question | n | accuracy | mean confidence | ECE | Brier |
|---|---|---|---|---|---|
| `intent` | 53 | 1.000 | 0.941 | 0.059 | 0.017 |
| `category` | 27 | 1.000 | 0.991 | 0.009 | 0.001 |
| `account` | 46 | 0.957 | 0.822 | 0.135 | 0.067 |
| `who` | 13 | 0.923 | 0.792 | 0.131 | 0.076 |
| `multi_entry` | 60 | 1.000 | 0.975 | 0.025 | 0.003 |
| `repayable` | 9 | 1.000 | 0.985 | 0.015 | 0.000 |
| `needs_followup` | 45 | 0.956 | 0.873 | 0.087 | 0.039 |
| `is_recurring` | 27 | 1.000 | 0.971 | 0.029 | 0.002 |
| `duplicate` | 7 | 0.571 | 0.824 | 0.317 | 0.195 |

## Confidence policy simulation (pass 1, choice questions)

Defaults (AI_PIPELINE 9): prefill at ≥ 0.85, "Guessed" from 0.55, ask below 0.55. Intent has no "Guessed" state: it is prefilled at ≥ 0.90 (`conf_intent_min`) and always asked below.

| question | n | prefilled | wrong when prefilled | guessed | wrong when guessed | asked |
|---|---|---|---|---|---|---|
| `intent` | 53 | 83.0% (44/53) | 0.0% (0/44) | n/a | n/a | 17.0% (9/53) |
| `category` | 27 | 100.0% (27/27) | 0.0% (0/27) | 0.0% (0/27) | n/a | 0.0% (0/27) |
| `account` | 46 | 54.3% (25/46) | 4.0% (1/25) | 39.1% (18/46) | 0.0% (0/18) | 6.5% (3/46) |
| `who` | 13 | 53.8% (7/13) | 0.0% (0/7) | 23.1% (3/13) | 0.0% (0/3) | 23.1% (3/13) |

Sweep of `conf_high` over all choice answers:

| conf_high | prefilled | wrong prefills (of all answers) |
|---|---|---|
| 0.50 | 94.2% (131/139) | 0.7% (1/139) |
| 0.55 | 94.2% (131/139) | 0.7% (1/139) |
| 0.60 | 94.2% (131/139) | 0.7% (1/139) |
| 0.65 | 92.8% (129/139) | 0.7% (1/139) |
| 0.70 | 89.9% (125/139) | 0.7% (1/139) |
| 0.75 | 84.9% (118/139) | 0.7% (1/139) |
| 0.80 | 81.3% (113/139) | 0.7% (1/139) |
| 0.85 | 75.5% (105/139) | 0.7% (1/139) |
| 0.90 | 64.0% (89/139) | 0.0% (0/139) |
| 0.95 | 56.8% (79/139) | 0.0% (0/139) |

## Latency and tokens (all passes)

| measure | n | mean | p50 | p90 | p95 | min | max |
|---|---|---|---|---|---|---|---|
| latency, ms | 120 | 346 | 324 | 426 | 508 | 274 | 587 |
| input tokens | 120 | 2038 | 2007 | 2124 | 2125 | 1987 | 2230 |
| cost, USD per 100k calls | 120 | 20.38 | 20.07 | 21.24 | 21.25 | 19.87 | 22.30 |

First request of the run (cold connection): 587 ms.

By number of questions asked:

| measure | n | mean | p50 | p90 | p95 | min | max |
|---|---|---|---|---|---|---|---|
| 7 questions: tokens | 84 | 2002 | 2000 | 2017 | 2018 | 1987 | 2023 |
| 7 questions: ms | 84 | 348 | 322 | 442 | 529 | 274 | 587 |
| 8 questions: tokens | 34 | 2114 | 2109 | 2131 | 2133 | 2097 | 2133 |
| 8 questions: ms | 34 | 339 | 328 | 370 | 481 | 277 | 580 |
| 9 questions: tokens | 2 | 2230 | 2230 | 2230 | 2230 | 2230 | 2230 |
| 9 questions: ms | 2 | 396 | 283 | 508 | 508 | 283 | 508 |

Usage fields seen: `total_tokens`, `total_input_tokens`, `input_tokens_by_modality`, `total_output_tokens`.
Sample usage: `{"total_tokens":2000,"total_input_tokens":2000,"input_tokens_by_modality":[{"modality":"text","tokens":2000}],"total_output_tokens":0}`

## Determinism (pass 1 vs pass 2)

439 answers compared; top choice changed in 0; largest change in P(yes) or confidence: 0.0000.

## Errors and blocks during the run

None.

## Misses (pass 1)

| case | question | expected | got | confidence |
|---|---|---|---|---|
| exp-05 "Bought a birthday present for Shilan's sister, 60 dollars on the joint card" | `who` | [joint] | partner | 0.48 |
| exp-06 "Paid the generator guy 50,000 dinars for this month" | `duplicate` | true | P(yes) 0.38 | 0.62 |
| exp-08 "Netflix subscription 15.99 on my checking account" | `duplicate` | true | P(yes) 0.23 | 0.77 |
| exp-11 "Took a taxi to work, 7,500 dinars" | `account` | [unspecified] | cash_iqd | 0.46 |
| inc-01 "My salary came in, 3,200 dollars to checking" | `duplicate` | true | P(yes) 0.39 | 0.61 |
| trf-01 "Moved 500 dollars from checking to the joint card" | `needs_followup` | false | P(yes) 0.52 | 0.52 |
| trf-02 "Withdrew 200 dollars cash from checking" | `needs_followup` | false | P(yes) 0.69 | 0.69 |
| trf-04 "Exchanged 100 dollars to dinars, got 150,000" | `account` | [cash_usd, cash_iqd] | unspecified | 0.88 |
