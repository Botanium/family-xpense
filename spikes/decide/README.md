# WP-S4 spike: Decisions API (throwaway)

Calls `POST https://generativelanguage.googleapis.com/v1beta/decisions` (`gemini-decision-1`) over REST from Dart with the AI_PIPELINE 7 question set, built from the default category tree and a fixture household. The report is [`docs/spikes/WP-S4.md`](../../docs/spikes/WP-S4.md). Nothing here is merged into `app/` or `server/`.

## Layout

| Path | What |
|---|---|
| `data/utterances.json` | 60 English utterances over every AI_PIPELINE 11 slice, with labels written before any call |
| `lib/household.dart` | fixture household: two members, 7 accounts with opaque ids, 5 people, parser context |
| `lib/question_set.dart` | shared input and the 9 questions, as `/decide` would build them |
| `lib/decisions_client.dart` | REST client; classifies answers, both documented safety-block shapes, HTTP and transport errors |
| `lib/scoring.dart` | accuracy, reliability tables, ECE, latency and token statistics |
| `bin/show_inputs.dart` | writes every shared input, no API call |
| `bin/run_eval.dart` | the main run: 60 cases × passes, raw responses and a report |
| `bin/token_breakdown.dart` | input tokens and latency per question |
| `bin/duplicate_variant.dart` | two wordings of the `duplicate` question on 14 cases |
| `bin/probe_errors.dart` | malformed requests, limits, bad key, safety filters, a concurrent burst |
| `bin/catalog_tokens.dart` | countTokens for the injected instructions of the merged Xpense catalog |
| `evidence/` | reports and raw JSONL responses (no key: it is only ever sent as a header) |

## Running

The key is read at runtime from Secret Manager into the process environment. It is never printed, logged or written to a file.

```bash
cd spikes/decide && dart pub get
```

```bash
GEMINI_API_KEY="$(gcloud secrets versions access latest --secret=GEMINI_API_KEY --project=expense-family-cc6ee --billing-project=expense-family-cc6ee)" dart run bin/run_eval.dart --passes 2 --tag main
```

The other scripts take the same environment variable. `run_eval.dart` also takes `--category-options all` (45 options instead of 36) and `--only <keys>`.
