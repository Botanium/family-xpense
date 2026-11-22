# xpense_agent: the Family Xpense server

Genkit Dart 1.0 service. One container image, two Cloud Run services selected
by `XPENSE_ROLE` (D-17): `xpense-agent` (public, token-verified routes under
`/v1`) and `xpense-jobs` (IAM-private `/jobs/*` and `/events/*`). See
ARCHITECTURE section 4; deployment is in [DEPLOY.md](DEPLOY.md).

## Run locally

```bash
cd server
genkit start -- dart run bin/server.dart     # Developer UI on :4000, server on :8080
curl -i localhost:8080/healthz               # 200 {"status":"ok","role":"agent"}
curl -i -X POST localhost:8080/v1/ping -H 'content-type: application/json' -d '{"data":"hi"}'
# 401 {"code":401,"status":"UNAUTHENTICATED","message":"missing_id_token"}
```

Off Cloud Run the server only accepts a `demo-` project (default
`demo-xpense`), so a local run can never reach a real project. To serve real
requests locally, start the Auth and Firestore emulators and point the server
at them; App Check cannot be emulated, so it is switched to accept any token:

```bash
firebase emulators:start --project demo-xpense \
  --config test/emulator/firebase.json --only auth,firestore
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9399 FIRESTORE_EMULATOR_HOST=127.0.0.1:8380 \
  XPENSE_APP_CHECK=emulator genkit start -- dart run bin/server.dart
```

## Test

```bash
dart analyze --fatal-infos
dart test                        # unit tests; emulator tests skip
tool/test_emulators.sh           # emulator tests against Auth + Firestore (demo-xpense)
tool/test_emulators.sh --all     # everything, under the emulators
```

## Layout

| Path | What |
|---|---|
| `bin/server.dart` | entry point: environment, telemetry, Genkit, gateway, Shelf server, shutdown |
| `lib/xpense_server.dart` | composition root: provider, flows, routers, handler |
| `lib/http/` | Shelf pipeline (`/healthz`, `/health`, `/v1` mount, access log) and the route lists per role |
| `lib/auth/` | context provider, member directory (60 s cache), typed failures, `XpenseContext` |
| `lib/admin/` | admin gateway interface and its `firebase_admin_sdk` implementation (the only place that imports it) |
| `lib/config/` | process environment (`ServerEnv`) and `config/runtime` loader |
| `lib/telemetry/` | `genkit_otel` wiring (content capture off), usage counters, structured logs |
| `lib/flows/ping.dart` | sample flow behind the provider |
| `lib/genkit.dart` | the Genkit instance and plugins |
| `lib/runtime/` | the agent (WP-32): `definePromptAgent`, session store, `householdContext` middleware, Firestore household reader, demo household, `tryCapture`/`tryQuestion` flows; the only module that imports `package:genkit/experimental*.dart` |
| `lib/tools/` | the agent tools and their schemantic schemas; household data through `HouseholdReader` |
| `lib/catalog/` | registers the agent's trimmed view of the shared Xpense catalog |
| `lib/safety/` | `outputGuard` and the untrusted-content wrapper |
| `prompts/` | `.prompt` files: `xpense_agent` (production), `xpense_agent.strict` (development and CI), partials |

`lib/jobs/` belongs to a later package.

## Run the agent locally

AI_PIPELINE section 8 has the details. The key is read from Secret Manager
into the process environment only; it is never printed or written.

```bash
# The demo household from memory, no emulator:
XPENSE_AGENT_DATA=demo tool/with_gemini_key.sh \
  genkit flow:run tryCapture '"Salary came in 3200 and I paid rent 1400"' -- dart run bin/server.dart
genkit trace:get <traceId> --format json

# The production path (Firestore reader and sessions, the /decide classifier):
tool/with_gemini_key.sh firebase emulators:exec --project demo-xpense \
  --config test/emulator/firebase.json --only firestore \
  'dart run tool/seed_demo_household.dart && genkit flow:run tryQuestion "\"How much did we spend on food this month?\"" -- dart run bin/server.dart'

# The A2UI instructions the agent pays for on every model call:
tool/with_gemini_key.sh dart run tool/instruction_tokens.dart
```

Off Cloud Run the agent runs the strict prompt (`a2ui` validate strict, no
repair); `XPENSE_A2UI=warn` switches to the production one.

## Request contract for `/v1/*`

Headers: `Authorization: Bearer <Firebase ID token>` and
`X-Firebase-AppCheck: <App Check token>`. Body: `{"data": <input>}`; add
`?stream=true` to stream. Refusals use Genkit's error body
`{"code", "status", "message"}`, where `message` is one of these codes:

| HTTP | `message` | Meaning |
|---|---|---|
| 401 | `missing_id_token` | no `Authorization: Bearer` header |
| 401 | `invalid_id_token` | expired, revoked, wrong project, or disabled user: refresh and retry once |
| 401 | `missing_app_check` | no `X-Firebase-AppCheck` header |
| 401 | `invalid_app_check` | App Check token did not verify |
| 403 | `no_household` | signed in, but `users/{uid}.householdId` is unset |
| 403 | `not_member` | the household does not list the user |
| 403 | `on_device_mode` | the member is in On-device mode; AI routes are refused |
| 429 | `over_limit` | the household reached a daily limit (`config/runtime`) |
| 503 | `auth_unavailable` | Auth, App Check keys or Firestore unreachable; retry later |

On success the action context is `{uid, hid, locale, privacyMode, tz}`
(`XpenseContext.of(ctx.context)`). Tools and flows read ids only from it,
never from input or model output.

## Adding a route

Add the action in `lib/http/routes.dart` with
`contextProvider: auth.forRoute(meters: {...})`, naming the usage counters the
route consumes (for example `{UsageCounter.agentTurns}` for `/agent`), and add
to the counters with `UsageCounters.add` after the work is done.
