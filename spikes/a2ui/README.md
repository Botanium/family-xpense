# WP-S1 spike: A2UI round trip (throwaway)

Findings are in [docs/spikes/WP-S1.md](../../docs/spikes/WP-S1.md). Nothing here is merged into `app/`, `server/` or `packages/`.

| Path | What |
|---|---|
| `catalog/spike_catalog.json` | 5-component catalog (Column, Text, Button, cut-down EntryList, ChoicePrompt) in the A2UI `catalog.json` shape, loaded by both sides |
| `catalog/xpense_sizing_draft.json` | a 24-component draft of the full Xpense catalog, used only to measure prompt size (Q7); not the WP-31 catalog |
| `server/` | Dart, `genkit 1.0.3`, `genkit_a2ui 0.6.0` (resolves `a2ui_core 0.7.0`, `a2ui_agent 0.3.0`) |
| `client/` | Flutter 3.50.1, `a2ui_flutter 0.4.0`, `a2ui_core 0.8.0` |
| `evidence/` | compiled messages, model requests, traces, screenshots, instruction sizes |

## Run

```bash
cd server && dart pub get
dart run bin/compile_express.dart          # Q1/Q2/Q4: compile Express offline -> evidence/q2_compiled_messages.json
dart run bin/instruction_size.dart         # Q7 (exact counts only with GEMINI_API_KEY)
PORT=8085 genkit start -- dart run bin/server.dart   # agent on :8085/api/spikeAgent
dart run bin/http_client.dart              # Q5 over HTTP
dart run bin/local_surface_probe.dart      # can the agent update a phone-built surface?
# Q6 store layouts, against the emulator only:
firebase emulators:start --only firestore --project xpense-dev   # port 8086 via firebase.json
FIRESTORE_EMULATOR_HOST=127.0.0.1:8086 GOOGLE_CLOUD_PROJECT=xpense-dev dart run bin/store_probe.dart

cd ../client && flutter test               # Q1, Q3, Q4, Q5 (client side), parity
flutter run -d "iPhone 17 Pro"             # live round trip against the server above
```

Without `GEMINI_API_KEY` the server uses `spike/scripted`, a model that streams fixed Express text in 40-character chunks; the text still goes through the real `a2ui()` middleware.
