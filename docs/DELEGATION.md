# Family Xpense: Work Packages for Opus 5.5

Each package runs in its own Opus 5.5 session, on its own git branch and worktree, and ends in a pull request. Stories and acceptance criteria are in [BACKLOG.md](BACKLOG.md).

## Rules for every package

Every prompt below starts by pointing the session here. These rules apply to all of them.

1. **Read first:** `FABLE_PROMPT.md` sections 3 to 6, then the docs your package names. The docs are the specification. If the docs and reality disagree (an API does not exist, a version does not resolve), stop, write what you found, and escalate to Fable; do not improvise around a locked decision.
2. **Verify, don't recall.** A2UI, Genkit Dart, `flutter_edge_ai`, `liquid_glass_widgets` and the Decisions API are newer than your training data. Read the installed package source (Dart MCP `read_package_uris`, `rip_grep_packages`), the project skills, the `genkit` MCP docs and `context7` before writing code against them.
3. **Stay in your files.** Touch only the paths listed under "Owns". If you need a change elsewhere, note it in the PR description for the owner of that path.
4. **No secrets in the repo.** No API keys, service-account files or debug tokens. Never run a gcloud or firebase command without an explicit `--project xpense-dev`. Never touch `xpense-prod` or any other project.
5. **Money:** integer minor units only, through `xpense_shared`. No `double` for money, no hard-coded `100`.
6. **UI:** no raw colours, radii, durations or font sizes outside `app/lib/core/theme/`. Glass only through `GlassSurface`. Strings only through ARB files, keys prefixed with the feature name.
7. **Pre-1.0 packages stay behind their interface** (ARCHITECTURE 3.2). Only the named adapter file may import them.
8. **Codegen:** run `dart run build_runner build` (no `--delete-conflicting-outputs`; the flag was removed) before analyzing.
9. **Done means:** acceptance criteria met, tests written and passing, analyzers clean, the listed test commands pasted with their output into the PR description, and anything you could not verify stated plainly.
10. **Branch and PR:** branch `wp-NN-short-name` from `main`; one PR; title `WP-NN: …`. Do not merge your own PR.

## Order and parallelism

| Wave | Packages | Notes |
|---|---|---|
| 0 | WP-00 | alone; everything else needs it |
| 1 | WP-01, WP-02, WP-03, WP-05, WP-S1, WP-S2, WP-S3 | all parallel; WP-01 and WP-S3 need the owner present |
| 2 | WP-04, WP-S4, WP-10, WP-30 | parallel |
| 3 | WP-11 → WP-12 → WP-13 | in sequence |
| 4 | WP-20, then WP-21, WP-22, WP-23, WP-24 in parallel | |
| 5 | WP-31 and WP-33 in parallel; WP-32 once WP-31 has merged the catalog JSON; then WP-34; then WP-35 | |
| 6 | WP-40, WP-41, WP-50, WP-51, WP-52, WP-53 | parallel; each owns one feature folder |
| 7 | WP-60 → WP-61, WP-62 | |
| 8 | WP-70 → WP-71 | can overlap wave 6 and 7 |
| 9 | WP-80, WP-81, WP-82, WP-83 in parallel; WP-84 last | |

Two files are shared by many packages. To keep parallel work safe: each feature exports its routes from `features/<name>/routes.dart` (stubs created in WP-10, so the central router is not edited again), and ARB keys are added in a feature-prefixed block (conflicts are mechanical; rebase before opening the PR).

---

## M0

### WP-00 Repository bootstrap
- **Goal:** the empty monorepo with tooling and CI.
- **Owns:** repo root, `.fvmrc`, `.github/workflows/`, `analysis_options.yaml` files, empty `app/`, `server/`, `packages/xpense_shared/`, `firebase/`, `evals/`.
- **Depends on:** nothing. **Parallel-safe:** no (run alone).
- **Skills and tools:** `flutter:project-structure-and-packages`, `flutter:lint-and-style-config`, `flutter:ci-pipeline-and-gates`, `flutter:codegen-and-toolchain`, `flutter:dependency-hygiene`; Dart MCP; `gh`.
- **Done:** S0.1, S0.2. Decision D-22 answered in `docs/DECISIONS.md` (does the app build with `material_ui` and `cupertino_ui` alongside `a2ui_flutter 0.4.0`?).
- **Test:** `flutter analyze` in `app/`; `dart analyze` in `server/` and `packages/xpense_shared/`; CI green on the PR.

```text
You are building work package WP-00 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", then docs/ARCHITECTURE.md sections 2, 3.1 and 8.
Create the monorepo: Flutter app in app/ (package xpense_app, iOS first, bundle id placeholder), Dart server in server/ (xpense_agent), pure Dart package packages/xpense_shared, plus firebase/ and evals/. Pin Flutter 3.50.1 with .fvmrc. app and server depend on xpense_shared by path and keep separate lockfiles; do NOT create a pub workspace (D-05). Add the exact package versions from FABLE_PROMPT.md section 5 to the right pubspecs, with these corrections from docs/DECISIONS.md: firebase_admin_sdk instead of firebase_admin; add genkit_google_cloud, genkit_otel, liquid_glass_widgets; no liquid_glass_renderer; no genui packages. Confirm both projects resolve and analyze clean. Check whether the app can use material_ui and cupertino_ui with a2ui_flutter 0.4.0 and record the answer under D-22. Set up very_good_analysis, the import-rule test skeleton, and path-filtered GitHub Actions jobs (shared, app, server, rules). Initialise git with a main branch. Open a PR titled "WP-00: repository bootstrap".
```

### WP-01 Cloud projects and environments
- **Goal:** `xpense-dev` and `xpense-prod`, emulator suite, secrets.
- **Owns:** `firebase/firebase.json`, `firebase/.firebaserc`, `firebase/emulator/`, `docs/ENVIRONMENTS.md` (new runbook), app Firebase config files.
- **Depends on:** WP-00. **Parallel-safe:** yes. **Needs the owner** for billing, console steps and the region decision.
- **Skills and tools:** Firebase MCP, `gcloud` MCP, `cloud-run` MCP.
- **Done:** S0.3.
- **Test:** `firebase emulators:exec --project xpense-dev "echo ok"`; `gcloud projects describe xpense-dev`.

```text
You are building WP-01 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/ARCHITECTURE.md sections 4.1, 4.4 and 8, and docs/DECISIONS.md D-18.
Create two NEW projects, xpense-dev and xpense-prod (ask the owner to confirm the ids are free and to link billing). The gcloud project currently active on this machine belongs to something else: never use it, and pass --project on every command. The owner chose region me-central1 (Doha) for everything; Firestore's location cannot be changed later, so confirm each service below enables cleanly there in xpense-dev before creating xpense-prod, and stop and report if one does not. In each project enable Firestore (Native), Auth (Apple, Google, email), Storage, App Check (App Attest; debug provider in dev only), Cloud Run, Scheduler, Eventarc, Secret Manager. Create the GEMINI_API_KEY secret placeholder and tell the owner how to add a paid-tier key. Create service accounts for the two Cloud Run services, the scheduler and Eventarc with least privilege. Configure the emulator suite (Auth, Firestore, Storage) and register the iOS apps. Write docs/ENVIRONMENTS.md as a runbook of exactly what you did. List every step that needs the owner's hands.
```

### WP-02 Shared core: money, FX, digits, schemas
- **Goal:** the pure Dart foundation used by app and server.
- **Owns:** `packages/xpense_shared/lib/money/`, `lib/schema/`, `lib/taxonomy/`, their tests.
- **Depends on:** WP-00. **Parallel-safe:** yes.
- **Skills and tools:** `flutter:value-objects-money-and-units`, `flutter:dart3-idioms-and-coding-standards`, `flutter:error-handling-typed-results`, `developing-genkit-dart` (schemantic reference).
- **Done:** S0.4, S0.5.
- **Test:** `dart run build_runner build && dart analyze && dart test` in `packages/xpense_shared`.

```text
You are building WP-02 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md section 1 and docs/AI_PIPELINE.md sections 4 and 8 (schemas).
In packages/xpense_shared implement: Currency (explicit exponent table: USD 2, IQD 0; unknown code is a typed failure), Money (int minor units), allocate() with the verified vectors from the value-objects skill, FX conversion using decimal-string pair rates ("USD/IQD" convention, half-even rounding once), digit and separator folding for Arabic-Indic and Persian digits, the intent taxonomy, the default category tree with en/ckb/ar names, and the schemantic types EntryDraft, FxQuote, DraftConfidence, DuplicateHint, RecurringHint, ParseResult, DecideRequest, DecideResponse, ReceiptExtraction. All optional fields nullable. No Flutter, dart:io, Firebase or a2ui_core imports. Table-driven tests for everything, including property tests that allocate() always sums exactly.
```

### WP-03 Design system
- **Goal:** Signal tokens, themes, `GlassSurface`, core UI components, gallery.
- **Owns:** `app/lib/core/theme/`, `app/lib/core/ui/`, `app/assets/fonts/`, `app/ios/Runner/` accessibility channel file, their tests and goldens.
- **Depends on:** WP-00. **Parallel-safe:** yes.
- **Skills and tools:** `flutter:design-system-structure`, `flutter:accessibility-as-code`, `flutter:widget-composition`, `flutter:widget-golden-and-a11y-testing`, `flutter:motion-and-haptics`, `flutter:i18n-rtl-l10n`, `mobile-app-design:ios-screens`; Dart MCP; iOS Simulator.
- **Done:** S0.6, S0.7, S0.8.
- **Test:** `flutter test test/theme test/ui`; run `/gallery` in the simulator in light, dark and RTL and attach screenshots.

```text
You are building WP-03 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and all of docs/DESIGN_SYSTEM.md. Open the design prototype with the Artifact tool (read action) at https://claude.ai/artifact/XxHQWTHVpRGpvSfzEQdX9S, files project/S3Home.dc.html, S3Ask.dc.html, S3Receipt.dc.html, for visual reference.
Implement the two-tier tokens and ThemeExtensions (light and graphite dark), the hand-authored ColorScheme, bundled Geist, Geist Mono and an Arabic-script family (confirm Vazirmatn covers Sorani letters and tabular digits, or propose another OFL family), the contrast unit test, and the raw-value CI gate. Implement GlassSurface over liquid_glass_widgets 1.19.0 with the six variants and four tiers, the Reduce Transparency platform channel, and Increase Contrast handling. Read the package source before using it. Implement every component in DESIGN_SYSTEM section 8 with a debug gallery route and goldens (light/dark, LTR/RTL, text scale 1.0 and 1.5). Do not build product screens.
```

### WP-04 Server skeleton
- **Goal:** a deployable Dart service with auth.
- **Owns:** `server/` except `lib/runtime/`, `lib/tools/`, `lib/decide/`, `lib/jobs/`, `prompts/`.
- **Depends on:** WP-00, WP-01, WP-02. **Parallel-safe:** yes.
- **Skills and tools:** `developing-genkit-dart` (genkit_shelf, agents-deployment, genkit references); `genkit` MCP; `cloud-run` and `gcloud` MCP.
- **Done:** S0.9.
- **Test:** `dart test`; `genkit start -- dart run bin/server.dart` then `curl localhost:8080/healthz`; a request without tokens returns 401; deployed dev URL returns 200 on `/healthz`.

```text
You are building WP-04 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/ARCHITECTURE.md section 4 and the developing-genkit-dart skill references genkit.md, genkit_shelf.md and agents-deployment.md.
Build server/ as in ARCHITECTURE 4.3: bin/server.dart with GenkitRouter, the XPENSE_ROLE switch (agent | jobs), /v1 prefix, /healthz, CORS off. Implement the context provider: verify the Firebase ID token and the App Check token with firebase_admin_sdk (read its source for the exact API), load the member document with a 60 s cache, reject On-device members and over-limit households with typed errors, return {uid, hid, locale, privacyMode, tz}. Add the admin gateway (Firestore via google_cloud_firestore, Messaging), config/runtime loader, usage counters, and genkit_otel wiring with content capture off. One sample flow (ping) behind the provider. Dockerfile per the Genkit Cloud Run guide. Deploy both services to xpense-dev only. Unit-test the provider with fake verifiers.
```

### WP-05 Firestore rules and indexes
- **Goal:** rules that enforce partner privacy, with tests.
- **Owns:** `firebase/firestore.rules`, `firebase/firestore.indexes.json`, `firebase/storage.rules`, `firebase/test/`.
- **Depends on:** WP-00. **Parallel-safe:** yes.
- **Skills and tools:** Firebase MCP (security rules docs).
- **Done:** S0.10.
- **Test:** `cd firebase && npm test` (runs under `firebase emulators:exec`).

```text
You are building WP-05 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and all of docs/DATA_MODEL.md.
Write firestore.rules, firestore.indexes.json and storage.rules from DATA_MODEL sections 5 and 6. The rules listing in the doc is a design; make it valid and complete (replace the compact agentSessions wildcard with explicit matches). Write a rules test suite with @firebase/rules-unit-testing that covers every bullet under "Rules tests must cover" plus one positive and one negative case per collection. Pay special attention to: list queries must include the visibleTo filter; memberIds is server-only; rev advances by exactly one; soft delete only. Report any rule in the design that cannot be expressed, with a proposed alternative.
```

### WP-S1 Spike: A2UI round trip
- **Goal:** settle every "verify in WP-S1" item before the catalog is built.
- **Owns:** `spikes/a2ui/` (throwaway), `docs/spikes/WP-S1.md`.
- **Depends on:** WP-00. **Parallel-safe:** yes.
- **Skills and tools:** `a2ui`, `developing-genkit-dart` (a2ui.md, agents.md); `genkit` MCP; Dart MCP; iOS Simulator.
- **Done:** S0.11.
- **Test:** `genkit start -- dart run bin/server.dart` in the spike; run the Flutter client in the simulator; screenshots in the report.

```text
You are running spike WP-S1 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/A2UI_CATALOG.md and docs/ARCHITECTURE.md section 7, the a2ui skill and the developing-genkit-dart a2ui.md reference.
In spikes/a2ui build the smallest thing that answers these questions with evidence: (1) a Dart agent with a2ui() and a custom catalog loaded from JSON (two components: a cut-down EntryList and ChoicePrompt) streams to a Flutter client on a2ui_flutter 0.4.0 / a2ui_core 0.8.0 while the server resolves a2ui_core 0.7: does it render? (2) Can A2UI Express assign an array of objects to the data model ($/drafts = [...]) and bind a component prop to it? Show the compiled messages. (3) Can a custom component write back to the data model (ComponentProps.writable) and does a sibling re-render? (4) Do locally built raw-map messages (createSurface with components and dataModel) render in the same MessageProcessor alongside agent surfaces? (5) Can one user message carry an action data part plus text? (6) Can a generate middleware read the request context to inject per-household system text, and can FirestoreSessionStore use a nested collection path or a per-tenant prefix? (7) How many input tokens do the injected catalog instructions cost? Write docs/spikes/WP-S1.md with answers, code excerpts and any change the catalog or architecture docs need. The spike code is not merged into app/ or server/.
```

### WP-S2 Spike: Liquid Glass performance
- **Owns:** `spikes/glass/`, `docs/spikes/WP-S2.md`. **Depends on:** WP-00. **Parallel-safe:** yes.
- **Skills and tools:** `flutter:flutter-performance`; Dart MCP; iOS Simulator; a physical iPhone if the owner can connect one.
- **Done:** S0.12.

```text
You are running spike WP-S2 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/DESIGN_SYSTEM.md section 6.
Build a test screen in spikes/glass: a long scrolling list of mono figures with a glass tab bar, the orange Ask button, a glass dock and a glass sheet over it, using liquid_glass_widgets 1.19.0 (read its source and PLATFORM_SUPPORT doc first). Measure frame build and raster times in profile mode for the package's premium, standard and minimal qualities and for a solid fallback, on the oldest iPhone available and a current one (the simulator is CPU-only, so say clearly which numbers come from real hardware). Test Reduce Transparency, Low Power Mode and glass over a camera preview. Recommend the device-to-tier table and any recipe changes. Write docs/spikes/WP-S2.md.
```

### WP-S3 Spike: on-device AI, speech and OCR
- **Owns:** `spikes/ondevice/`, `docs/spikes/WP-S3.md`. **Depends on:** WP-00. **Parallel-safe:** yes. **Needs the owner's iPhone.**
- **Skills and tools:** `flutter:service-boundary-and-native`; Dart MCP; `context7`.
- **Done:** S0.13.

```text
You are running spike WP-S3 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/AI_PIPELINE.md sections 3 and 6.
On a real iPhone (ask the owner which model and iOS version), measure: (1) flutter_edge_ai_builtin_ai: availability status, languages accepted, JSON extraction quality on 10 English utterances; (2) flutter_edge_ai_litertlm with Gemma 4 E2B: download size, load time, peak memory, constrained JSON output, extraction on 10 English, 10 Arabic and 10 Sorani utterances from docs/AI_PIPELINE.md samples (ask the owner to supply or check the Kurdish ones); (3) speech_to_text with onDevice: true for en-US and ar-SA, and what happens for ckb; (4) Apple Vision OCR through a minimal platform channel on 3 Latin and 3 Arabic-script receipts, including Sorani letters; compare with google_mlkit_text_recognition. Read each package's source before use. Write docs/spikes/WP-S3.md with a capability table and a recommendation for each row of the tables in AI_PIPELINE 3 and 6.
```

### WP-S4 Spike: Decisions API and Kurdish audio
- **Owns:** `spikes/decide/`, `docs/spikes/WP-S4.md`. **Depends on:** WP-01 (API key). **Parallel-safe:** yes.
- **Skills and tools:** `developing-genkit-dart`; `genkit` MCP.
- **Done:** S0.14.

```text
You are running spike WP-S4 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/AI_PIPELINE.md sections 7, 11 and 12.
Using the paid-tier key from Secret Manager in xpense-dev (never print it), call POST https://generativelanguage.googleapis.com/v1beta/decisions with model gemini-decision-1 over REST from Dart. Fetch the current API docs first; do not rely on the summary in our docs. Run the question set from AI_PIPELINE 7 against the default category tree on 60 utterances (20 English, 20 Arabic, 20 Sorani; the owner reviews the non-English ones). Report accuracy per question and language, a reliability table for calibration, measured input tokens and latency, and behaviour on errors and safety blocks. Separately, send 10 Sorani and 5 Arabic audio clips (recorded by the owner) to gemini-3.5-flash-lite and gemini-3.8-flash and score the transcripts. Recommend go or no-go for Decisions on each language and for Kurdish voice, and update the cost table inputs. Write docs/spikes/WP-S4.md.
```

## M1

### WP-10 App shell
- **Owns:** `app/lib/main.dart`, `bootstrap.dart`, `app.dart`, `core/routing/`, `core/l10n/`, `app/lib/l10n/`, `features/*/routes.dart` stubs, `services/` interfaces, `features/settings_privacy/` skeleton, lock overlay.
- **Depends on:** WP-03. **Parallel-safe:** yes.
- **Skills and tools:** `flutter:app-startup-and-bootstrap`, `flutter:navigation-and-routing`, `flutter:state-management-riverpod`, `flutter:flutter-architecture`, `flutter:i18n-rtl-l10n`, `flutter:async-safety`; Dart MCP; iOS Simulator.
- **Done:** S1.1, S1.2.
- **Test:** `flutter test`; launch in the simulator, switch language to Arabic, attach screenshots of the four tabs in LTR and RTL.

```text
You are building WP-10 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/ARCHITECTURE.md section 3 and docs/DESIGN_SYSTEM.md sections 8 to 10.
Build the app shell: startup order from ARCHITECTURE 3.3, Riverpod composition root with overridable providers, go_router with a StatefulShellRoute for Home, Activity, Goals, Accounts (placeholder screens), the Ask route above the shell opened by the round glass button, deep-link parsing, gen-l10n with en, ckb and ar and a language switch, the settings store, the Face ID lock overlay, and the service interfaces listed in ARCHITECTURE 3.2 (interfaces and fakes only). Create a routes.dart stub in every feature folder so later packages never edit the central router. Add the import-rule test for the layer table in ARCHITECTURE 3.1.
```

### WP-11 Auth and onboarding screens
- **Owns:** `features/onboarding/`, `data/auth_repository.dart`.
- **Depends on:** WP-10, WP-01. **Parallel-safe:** yes.
- **Skills and tools:** `mobile-app-design:ios-flows`, `mobile-app-design:onboarding`, `flutter:forms-and-input`, `flutter:ui-states-and-feedback`; Firebase MCP; iOS Simulator.
- **Done:** S1.3.
- **Test:** `flutter test`; sign in with email against the Auth emulator in the simulator.

```text
You are building WP-11 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/PRD.md stories ON-1 to ON-6 and docs/DESIGN_SYSTEM.md screens 1, 2 and 5 and review items 7 and 8.
Build Welcome, Create account and Try it in the Signal style using only components from core/ui. Sign in with Apple, Google and email through firebase_auth behind an AuthRepository; Apple and Google buttons carry equal weight; Terms and Privacy links present. Try it shows the microphone pre-prompt and always offers "Type instead" (voice itself arrives in WP-40; wire the typed path to a stub). Handle errors inline, with loading and offline states. Widget tests for each state.
```

### WP-12 Household, invite, join
- **Owns:** `features/household/`, `data/household_repository.dart`, `server/lib/household/`.
- **Depends on:** WP-11, WP-04, WP-05. **Parallel-safe:** no (first writer of household data; run before WP-13).
- **Skills and tools:** `developing-genkit-dart`, `flutter:state-management-riverpod`; Firebase MCP.
- **Done:** S1.4, S1.5.
- **Test:** `flutter test`; `dart test` in `server/`; two simulators: create a household on one, join by code on the other.

```text
You are building WP-12 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md sections 2.2, 2.3, 2.15 and 5, and docs/ARCHITECTURE.md 4.2.
Build screen 3 (household name, display name, base currency, invite). Creating a household writes the household, the member document and the default categories in one batch from the phone. Invites and joins go through the server flows /household/invite and /household/join (admin SDK): 10-character base32 codes, SHA-256 stored, 7-day expiry, single use, at most two members, rate limited per uid. Support the xpense://join?code= deep link and manual code entry ("I have an invite"). Tests: server flow unit tests with the Firestore emulator; widget tests; a rules test proving the phone cannot change memberIds.
```

### WP-13 Accounts
- **Owns:** `features/accounts/`, `data/accounts_repository.dart`, `server/lib/jobs/account_visibility.dart`.
- **Depends on:** WP-12. **Parallel-safe:** yes after WP-12.
- **Done:** S1.6, S1.7, S1.8.
- **Test:** `flutter test`; emulator scenario: partner cannot see a private account or its total.

```text
You are building WP-13 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md sections 2.4, 3 and 4, and docs/DESIGN_SYSTEM.md screens 4, 10 and 11.
Build the accounts repository and screens: add, edit, archive; kinds and currencies; personal or joint; the sharing switch that maintains visibleTo; the filter bar (All, Mine, Partner, Joint); totals in base currency for what the viewer can see, labelled "Household balance" or "Your view". Opening balances are adjustment transactions (use a minimal write helper; WP-20 replaces it). Implement the /events/account-visibility handler that rewrites visibleTo on an account's transactions in pages, and the "Sharing…" state. Every list query includes the visibleTo filter.
```

## M2

### WP-20 Transaction write path
- **Owns:** `data/transactions_repository.dart`, `data/write/`, `data/mappers/`, `packages/xpense_shared/lib/ledger/`.
- **Depends on:** WP-13, WP-02. **Parallel-safe:** no (the single write path; run alone).
- **Skills and tools:** `flutter:error-handling-typed-results`, `flutter:testing-strategy`.
- **Done:** S2.1.
- **Test:** `flutter test test/data`; emulator integration test that saves, edits and deletes offline and reconciles on reconnect.

```text
You are building WP-20 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/DATA_MODEL.md sections 1 to 3 and 7.
Implement the single write path: saveEntries(List<EntryDraft>) validates drafts against the household cache, converts to transactions with stored FX (pair, pairRate, source, asOf, baseAmountMinor), and commits one batched write with FieldValue.increment on account balances and loan totals; editEntry writes a revision and applies the difference; deleteEntry soft-deletes with reversing increments; undo restores. Client-generated UUID v7 ids. No runTransaction (it fails offline). Put the pure balance-effect table in xpense_shared so the server reconcile job can reuse it. Return typed Results, never throw into the UI. Test every transaction type, cross-currency transfers, edit and delete deltas, and offline behaviour against the emulator.
```

### WP-21 Add manually, entry detail and history
- **Owns:** `features/capture/manual/`, `features/activity/detail/`.
- **Depends on:** WP-20. **Parallel-safe:** yes.
- **Skills:** `flutter:forms-and-input`, `mobile-app-design:ios-screens`.
- **Done:** S2.2, S2.3.
- **Test:** `flutter test`; simulator walk-through of each entry type.

```text
You are building WP-21 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DESIGN_SYSTEM.md screens 9 and 17 and review item 5, and docs/DATA_MODEL.md 2.5.
Build the Add manually sheet (expense, income, transfer, loan) with AmountField (no decimal key for IQD), category chips, account, who, date, note, Cancel leading and Save trailing, validation next to fields, and the Entry detail screen with tap-to-edit rows, the rate used, source, and the revision history with Restore. All writes go through the WP-20 repository. The form accepts a prefilled EntryDraft (used later by "Change" on a slip).
```

### WP-22 Activity
- **Owns:** `features/activity/` except `detail/`. **Depends on:** WP-20. **Parallel-safe:** yes.
- **Skills:** `flutter:flutter-performance`, `flutter:ui-states-and-feedback`.
- **Done:** S2.4.

```text
You are building WP-22 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DESIGN_SYSTEM.md screen 16 and docs/DATA_MODEL.md section 6.
Build Activity: paged day groups with the day's net in mono, the filter bar (All, Out, In, Loans, You, Partner), the "Search or ask" field (client-side search over the cached window; a question-like query opens Ask with the text), swipe actions (Edit, Delete with the undo toast), context menu, and loading, empty, error and offline states. Queries must use the indexes in DATA_MODEL 6 and always filter by visibleTo. Keep scrolling at 60 fps with 1,000 rows.
```

### WP-23 Home
- **Owns:** `features/home/`. **Depends on:** WP-20. **Parallel-safe:** yes.
- **Done:** S2.5.

```text
You are building WP-23 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/DESIGN_SYSTEM.md sections 1, 4 (hero figure rules) and screen 6.
Build Home exactly in the Signal layout: mono header, bell and avatar pair, HeroBalance in the base currency with the other-currency line, month delta, MiniBars for daily spending with a spoken summary, the three ledger rows (Income, Spent, Saved), a NudgeRow slot (static provider for now), and Recent with "See all". Totals are derived from the viewer's visible transactions for the month, in base currency, using stored baseAmountMinor. Stepped hero sizing and stacking at large text sizes. Goldens in light, dark, RTL and text scale 1.5.
```

### WP-24 FX rates and categories editor
- **Owns:** `server/lib/jobs/fx_rates.dart`, `data/fx_repository.dart`, `features/settings_privacy/fx/`, `features/settings_privacy/categories/`.
- **Depends on:** WP-20, WP-04. **Parallel-safe:** yes.
- **Done:** S2.6, S2.7.

```text
You are building WP-24 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md sections 1, 2.6 and 2.13, and docs/DECISIONS.md D-15 and D-16.
Server: /jobs/fx-rates fetches the official USD/IQD figures (Frankfurter v2 CBI provider, with open.er-api as a cross-check; fetch their current docs and terms first), writes fxRates/{day} with sources, and never overwrites a day with missing data. Phone: FxRepository resolves the rate for a date and source (official cash 1520-style, CBI, or the household's market rate); settings screens to choose the source and enter the market rate with a stale warning after 7 days; the rate used is shown on every converted amount. Also build the categories editor (rename in three languages, add, reorder, archive).
```

## M3

### WP-30 Fast parser
- **Owns:** `packages/xpense_shared/lib/parse/`. **Depends on:** WP-02. **Parallel-safe:** yes.
- **Skills:** `flutter:dart3-idioms-and-coding-standards`, `flutter:i18n-rtl-l10n`, `flutter:testing-strategy`.
- **Done:** S3.1.
- **Test:** `dart test test/parse` in `packages/xpense_shared`.

```text
You are building WP-30 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/AI_PIPELINE.md sections 2 (signals), 3 (language detection) and 5.
Implement the deterministic fast parser as pure, total functions: normalisation, amounts (digits, separators, k/m, number words and multipliers in English, Arabic and Sorani), local slang (daftar, waraqa, dropped thousands), currency lexicon with the magnitude check, dates, account and person hints, rule application, complexity signals, language detection, and the receipt-text parser (merchant, date, total, lines). Table-driven tests with at least 150 cases across the three languages; mark every Kurdish and Arabic expectation that needs owner review. No model, no I/O.
```

### WP-31 Xpense catalog, host and local builder
- **Owns:** `packages/xpense_shared/lib/catalog/`, `lib/surface/`, `test/fixtures/surfaces/`, `app/lib/a2ui/`.
- **Depends on:** WP-S1, WP-03, WP-20. **Parallel-safe:** yes. Merge the catalog JSON as an early first PR so WP-32 can start.
- **Skills and tools:** `a2ui`, `developing-genkit-dart` (a2ui.md), `flutter:widget-golden-and-a11y-testing`, `flutter:accessibility-as-code`; Dart MCP.
- **Done:** S3.2, S3.3, S3.4, S3.5.
- **Test:** `dart test` in `packages/xpense_shared`; `flutter test test/a2ui`.

```text
You are building WP-31 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", all of docs/A2UI_CATALOG.md, docs/ARCHITECTURE.md section 7 and docs/spikes/WP-S1.md (its findings override the catalog doc where they differ; update the doc).
First PR: xpense_catalog.json in the A2UI catalog.json shape for all 24 components, property order as documented. Then: SurfaceBuilder in xpense_shared (raw spec-shaped maps, no a2ui_core) with fixtures; the phone catalog (one ComponentImplementation per component mapping props to typed widgets built from core/ui); EntryList and ReceiptSummary as smart components with local editing, validation and save through an XpenseActions interface; XpenseSurfaceHost (one MessageProcessor per conversation, ordered queue, action routing by the xp.local. prefix, per-message error isolation, restricted Markdown); the catalog parity test; goldens from the fixtures (light/dark, LTR/RTL, scale 1.0 and 1.5); widget tests for save, undo, pick and validation. Only app/lib/a2ui may import a2ui_core and a2ui_flutter.
```

### WP-32 Agent, tools and prompts
- **Owns:** `server/lib/runtime/`, `lib/tools/`, `lib/catalog/`, `lib/safety/`, `server/prompts/`.
- **Depends on:** WP-04, WP-S1, WP-S4, catalog JSON from WP-31. **Parallel-safe:** yes.
- **Skills and tools:** `developing-genkit-dart` (agents*, a2ui, dotprompt, schemantic, middleware), `a2ui`; `genkit` MCP (run flows, read traces).
- **Done:** S3.6, S3.12.
- **Test:** `dart test`; `genkit flow:run tryCapture '"Salary came in 3200 and I paid rent 1400"' -- dart run bin/server.dart` then `genkit trace:get <id> --format json`.

```text
You are building WP-32 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md sections 8 to 10, docs/A2UI_CATALOG.md section 7 and docs/spikes/WP-S1.md and WP-S4.md.
Build xpenseAgent with definePromptAgent, FirestoreSessionStore (genkit_google_cloud), and the middleware order householdContext → outputGuard → a2ui(catalog: 'xpense') → retry. Only server/lib/runtime may import package:genkit/experimental*.dart. Implement the tools in AI_PIPELINE 8 with schemantic schemas; every tool takes the household from ctx.context and filters by visibleTo; prepareEntries replaces the whole draft set. Write the .prompt files. Register model ids from config/runtime with the escalation rule. Add throwaway flows (tryCapture, tryQuestion) so the agent can be exercised with flow:run. Use validate: 'strict', repair: false in development. Verify with traces, not blind runs, and paste trace excerpts showing the tool call and the emitted surface.
```

### WP-33 Decisions proxy
- **Owns:** `server/lib/decide/`, `app/lib/services/decisions_client.dart`.
- **Depends on:** WP-04, WP-S4. **Parallel-safe:** yes.
- **Done:** S3.7, S3.14.
- **Test:** `dart test test/decide`; `genkit flow:run decide '{…}' -- dart run bin/server.dart`.

```text
You are building WP-33 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md section 7 and docs/spikes/WP-S4.md.
Implement the decide flow behind the auth context provider: build the question set server-side from the household's categories, accounts and members (keys only in options, names in descriptions, catch-all options), call the Decisions API over REST with one request per message, map answers to DecideResponse, apply the fallback chain (retry, Flash-Lite with a constrained schema marked calibrated: false, unavailable), the 10-minute LRU cache, usage counters, and deterministic duplicate candidates with the duplicate question. Client: DecisionsClient behind its interface with typed failures. Unit-test with a fake HTTP client, including error and safety-block paths.
```

### WP-34 Capture router and Ask screen (text)
- **Owns:** `features/capture/router/`, `features/ask/`, `data/rules_repository.dart`, `services/agent_client.dart`.
- **Depends on:** WP-30, WP-31, WP-32, WP-33. **Parallel-safe:** no (integration package).
- **Skills and tools:** `developing-genkit-dart` (agents.md "Using from Flutter"), `flutter:async-safety`, `flutter:ui-states-and-feedback`; `genkit` MCP; iOS Simulator.
- **Done:** S3.8 to S3.11.
- **Test:** `flutter test`; `genkit start:flutter -- -d <simulator>` and capture three messages, one per path, with screenshots and trace ids.

```text
You are building WP-34 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md sections 2 and 9, docs/ARCHITECTURE.md sections 5 and 6, and docs/DESIGN_SYSTEM.md screen 7.
Implement the router as a pure function with one test per row of the decision table. Implement AgentClient over remoteAgent (ID token and App Check headers, one chat per conversation, streaming, cancel, typed errors). Build the Ask screen: thread of quotes and surfaces through XpenseSurfaceHost, the capture dock in type mode, the mode chip, busy, error, limit and offline states. Wire the three paths end to end for typed text. Apply the confidence policy from Remote Config, the follow-up order, and learning (corrections upsert rules; the rule cache feeds the parser). The same input must produce golden-identical cards from the local builder and from the agent fixture.
```

### WP-35 Evaluation harness
- **Owns:** `evals/`, `server/bin/evals.dart`, `server/lib/evals/`, the `evals` CI job.
- **Depends on:** WP-30, WP-32, WP-33. **Parallel-safe:** yes.
- **Skills and tools:** `developing-genkit-dart`; `genkit` MCP (evaluation docs).
- **Done:** S3.13.
- **Test:** the two `genkit eval:flow` commands in AI_PIPELINE 11.

```text
You are building WP-35 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/AI_PIPELINE.md sections 9, 11 and 12.
Create the datasets (at least 182 utterances per the slice table, plus receipt fixtures; draft Kurdish and Arabic cases and flag them for owner review), the wrapper flows, and the custom evaluators with ai.defineEvaluator. Add the CI job that runs on main and nightly and fails below the gates. Run the suite, tune the thresholds in section 9 against the results, replace the estimated token counts and costs in section 12 with measured ones, and report per-language results honestly, including any gate that cannot be met yet.
```

## M4

### WP-40 Voice capture
- **Owns:** `services/speech_capture*.dart`, `features/capture/voice/`. **Depends on:** WP-34, WP-S3. **Parallel-safe:** yes.
- **Skills:** `flutter:service-boundary-and-native`, `mobile-app-design:ios-screens`.
- **Done:** S4.1, S4.2.

```text
You are building WP-40 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md section 3, docs/ARCHITECTURE.md 5.4 and docs/spikes/WP-S3.md and WP-S4.md.
Implement SpeechCapture: on-device recognition with speech_to_text (onDevice: true) for the languages the spike confirmed, raw recording with record (AAC mono 16 kHz, 60 s cap) for the cloud fallback, live waveform levels, and the permission pre-prompts. Dock voice mode: tap to start, stop button, switch to type or camera. Cloud fallback sends the audio part to the agent, shows the returned Transcript, and lets the user correct it by typing. In On-device mode, unsupported languages show the Notice with "Type instead". Audio is never stored.
```

### WP-41 Receipts
- **Owns:** `services/ocr_engine*.dart`, `app/ios/Runner/` Vision channel, `features/capture/receipt/`, `data/receipt_store.dart`. **Depends on:** WP-34, WP-S3. **Parallel-safe:** yes.
- **Done:** S4.3, S4.4, S4.5.

```text
You are building WP-41 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md sections 3 and 10, docs/ARCHITECTURE.md 5.5, docs/DESIGN_SYSTEM.md screen 8 and docs/spikes/WP-S3.md.
Implement OcrEngine with Apple Vision through a platform channel (accurate level, languages from the spike) and ML Kit for Latin as fallback; the scan screen with the camera preview, scan frame, glass controls over media with the scrim, and the ReceiptSummary sheet. Use the shared receipt parser for merchant, date and total; classify through /decide; for line-item split in Smart and Cloud send the image to the agent (receipt_lines prompt) and regroup locally with allocate() so groups sum exactly. OCR text is untrusted: pass it only inside the data delimiters. Images stay in the app's documents directory unless backup is on.
```

## M5

### WP-50 Loans and debts
- **Owns:** `features/loans/`, `data/loans_repository.dart`, `data/people_repository.dart`. **Depends on:** WP-34. **Parallel-safe:** yes.
- **Done:** S5.1, S5.2.

```text
You are building WP-50 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md 2.7 and 2.8, docs/DESIGN_SYSTEM.md screens 14 and 15, and docs/A2UI_CATALOG.md (LoanCard, ChoicePrompt).
Build people and loans repositories, the Loans and debts list, Loan detail with "Record a repayment" and history, and chat support: "Gave Alex 300" produces the intent question (loan, gift, repayment) and files accordingly; "Alex paid back 100" matches the open loan. Outstanding is maintained by increments in the same batch as the transaction and the loan closes at zero.
```

### WP-51 Goals
- **Owns:** `features/goals/`, `data/goals_repository.dart`. **Depends on:** WP-34. **Parallel-safe:** yes. **Done:** S5.3.

```text
You are building WP-51 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md 2.9 and docs/DESIGN_SYSTEM.md screens 12 and 13.
Build goals backed by a savings account (create the account when the goal is created), the Goals tab with GoalBar and pace, Goal detail with contributions, and chat support for "move 200 to the trip fund" and "start a goal for a new car, 6,000 by next summer" (savings_move intent and a goal-creation command that opens a prefilled form).
```

### WP-52 Budgets
- **Owns:** `features/budgets/`, `data/budgets_repository.dart`, `server/lib/jobs/budget_event.dart`. **Depends on:** WP-34. **Parallel-safe:** yes. **Done:** S5.4.

```text
You are building WP-52 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md 2.10 and docs/DESIGN_SYSTEM.md screen 18.
Build monthly budgets per category and for the total, the Budgets screen with thin meters, the budget line in the slip's saved state ("SAVED · DINING 85,000 / 120,000"), and the /events/transaction-written handler that writes a budget_warning notification at 80% and 100% (once per threshold per month, by dedupeKey).
```

### WP-53 Recurring
- **Owns:** `features/insights/recurring/`, `data/recurring_repository.dart`. **Depends on:** WP-34. **Parallel-safe:** yes. **Done:** S5.5.

```text
You are building WP-53 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md 2.11 and docs/AI_PIPELINE.md section 9 (recurring_offer).
After saving an entry whose recurring hint passes the threshold, show the offer (Add automatically, Remind me, Not now) and create the template. Build the list and edit screens under Settings. Server-side detection and posting come in WP-60; expose the template format they need.
```

## M6

### WP-60 Jobs: nudges, recurring, reconcile, retention
- **Owns:** `server/lib/jobs/` (except files owned by WP-13, WP-24, WP-52), scheduler config in `firebase/` or `infra/`. **Depends on:** WP-52, WP-53. **Parallel-safe:** yes.
- **Skills and tools:** `developing-genkit-dart`; `gcloud` and `cloud-run` MCP.
- **Done:** S6.1 to S6.4.

```text
You are building WP-60 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/ARCHITECTURE.md 4.1, 4.2 and 5.6, and docs/DATA_MODEL.md sections 2.14, 3 and 9.
Implement the jobs as idempotent flows on the private xpense-jobs service: nudges (missed bill, budget warning, loan due, stale rate; at most two per member per day; dedupe keys), recurring detection over three months of history and posting of auto templates with source: recurring, nightly reconcile using the shared balance-effect table, and retention. Detection is rule-based; no model call. Create Cloud Scheduler jobs in xpense-dev with OIDC to the private service. Test each job against the emulator with seeded data, including a drift-correction case.
```

### WP-61 Push and notification centre
- **Owns:** `features/notifications/`, `services/push*.dart`, `server/lib/admin/messaging.dart`. **Depends on:** WP-60. **Parallel-safe:** yes. **Done:** S6.5.

```text
You are building WP-61 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/DATA_MODEL.md 2.14 and docs/DESIGN_SYSTEM.md screen 19 and review item 7.
Register FCM tokens per device, ask for notification permission in context (after the first reminder is set), send pushes from the server for new notifications in the member's language, build the notification centre with read state, and open a tapped notification as a locally built Nudge surface in Ask or the right screen. Feed the Home NudgeRow from the latest unread nudge.
```

### WP-62 Monthly report, export and import
- **Owns:** `features/insights/report/`, `features/settings_privacy/export/`, `server/lib/jobs/monthly_report.dart`, `server/prompts/monthly_report.prompt`. **Depends on:** WP-60. **Parallel-safe:** yes. **Done:** S6.6, S6.7.

```text
You are building WP-62 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md section 8 (monthly_report prompt rule: no arithmetic by the model) and docs/DESIGN_SYSTEM.md screen 22.
Compute the report numbers in code (shared ReportNumbers), narrate with the escalation model only when cloudInsights is true, otherwise fill a localised template. Build the report screen, PDF and Excel export on the phone (check pdf and excel package compatibility with the pinned SDK first), CSV export of entries, and CSV import with a column-mapping step and a dry-run preview.
```

## M7

### WP-70 On-device LLM and privacy modes
- **Owns:** `services/on_device_llm/`, `features/settings_privacy/privacy/`. **Depends on:** WP-S3, WP-34. **Parallel-safe:** yes.
- **Done:** S7.1, S7.2, S7.3.

```text
You are building WP-70 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/AI_PIPELINE.md sections 2 and 6, docs/ARCHITECTURE.md section 6 and docs/spikes/WP-S3.md.
Implement OnDeviceLlm over flutter_edge_ai (read the package source; the 3.0 API renames are coming): engine selection, capability per language, extraction against the EntryDraft schema with validation and one retry, the 0.80 confidence cap, a 4 s timeout, and classification for On-device mode. Build the privacy settings with plain descriptions of the three modes, the optional Gemma download (size shown, Wi-Fi only, resumable, deletable), and the pickers-only path when no model is present. The server already refuses AI routes for On-device members; make the phone never call them in that mode.
```

### WP-71 Privacy egress test, offline queue, on-device evaluation
- **Owns:** `app/integration_test/`, `data/capture_queue.dart`. **Depends on:** WP-70. **Parallel-safe:** yes. **Done:** S7.4 to S7.6.

```text
You are building WP-71 for Family Xpense. Read docs/DELEGATION.md "Rules for every package", docs/ARCHITECTURE.md section 6 and docs/AI_PIPELINE.md section 11.
Write the egress test: run a set of captures (text, voice transcript, receipt) in On-device mode behind a recording HTTP client and fail on any request to a host other than the Firebase data hosts. Implement the local capture queue for complex captures made offline (stored on the phone only; resolved when online; a queue_ready notice). Add the on-device evaluation integration test that runs the single-entry dataset slices through OnDeviceLlm on a real iPhone and scores them with the shared scorer.
```

## M8

### WP-80 iOS quick capture
- **Owns:** `app/ios/` extensions and intents, `features/capture/quick/`. **Depends on:** WP-34, WP-41. **Parallel-safe:** yes. **Done:** S8.1.

```text
You are building WP-80 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/ARCHITECTURE.md 3.3 (deep links).
Add an App Shortcut "Log an expense" with a text parameter that opens Ask with the text (evaluate app_intents 0.21.1 against a small native App Intents target; read the source first), home and lock screen widgets (balance for the viewer's visible data, and a quick-add button) with home_widget or native WidgetKit, and a share extension that sends a receipt image into the scan flow. Widgets must respect the Face ID lock setting: hide figures when the lock is on.
```

### WP-81 Localisation and RTL completion
- **Owns:** `app/lib/l10n/*.arb`, RTL goldens. **Depends on:** all screens. **Parallel-safe:** yes (ARB only). **Done:** S8.2.

```text
You are building WP-81 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/DESIGN_SYSTEM.md sections 4 and 10.
Complete the ckb and ar ARB files (draft translations, flagged for native review by the owner; never ship unreviewed financial terms), the digits setting (latn or arab) through the money and date formatters, plural rules, and RTL goldens for every screen. Fix every layout that uses non-directional insets. List strings that are hard to translate with context notes.
```

### WP-82 Account deletion, data export, legal and store
- **Owns:** `server/lib/account/`, `features/settings_privacy/account/`, `docs/store/`. **Depends on:** WP-04. **Parallel-safe:** yes. **Done:** S8.3, S8.4.

```text
You are building WP-82 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/DATA_MODEL.md section 9.
Implement /account/delete (re-authentication on the phone, then server-side deletion of the Auth user, the user and member documents and personal-scope data; joint data stays with the remaining partner; the household is deleted when no member remains) and a full data export as a zip of CSV and JSON. Draft, for the owner's review: Terms, Privacy Policy (covering the three privacy modes and Google's paid-tier data terms), App Store privacy labels, review notes with a demo account, and store listing text in three languages.
```

### WP-83 Observability, cost controls, App Check enforcement
- **Owns:** `server/lib/telemetry/`, alerting config, `docs/RUNBOOK.md`. **Depends on:** WP-04. **Parallel-safe:** yes. **Done:** S8.5, S8.6.

```text
You are building WP-83 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/ARCHITECTURE.md 4.5 and 4.6.
Export OTLP traces and metrics from genkit_otel to Cloud Trace and Monitoring with content capture off; verify no message text appears in any span or log. Finish usage counters, per-household limits and the global spend switch. Add a GCP budget alert, Firestore point-in-time recovery and a weekly export. Add privacy-respecting Analytics events (no amounts, names or text). Turn on App Check enforcement for Firestore, Storage and the server in xpense-prod only with the owner's go-ahead, and write docs/RUNBOOK.md.
```

### WP-84 Rendered design review and performance
- **Owns:** fixes across `features/` (coordinate: run last, alone). **Depends on:** everything. **Parallel-safe:** no.
- **Skills and tools:** `flutter:design-review-workflow`, `mobile-app-design:ios-review`, `design:accessibility-review`, `flutter:flutter-performance`; iOS Simulator.
- **Done:** S8.7, S8.8.

```text
You are running WP-84 for Family Xpense. Read docs/DELEGATION.md "Rules for every package" and docs/DESIGN_SYSTEM.md, especially section 12.
Run one structured review on a release build: every screen on a small and a large iPhone, light and dark, English and Arabic, largest accessibility text size, Reduce Motion, Reduce Transparency and Increase Contrast, plus a pass on a physical older iPhone. Grade findings (blocker, fix, note); every accessibility-floor violation is a blocker. Do one fix round, re-check, and write a dated sign-off with screenshots. Measure cold start and scrolling with glass on iPhone 12-class hardware and finalise the glass tier table. Say plainly what you could not check.
```

---

## Escalate to Fable when

- a locked decision turns out to be wrong or unbuildable;
- a spike result changes the architecture (for example Express cannot carry drafts, or Kurdish accuracy is below the gate);
- two packages need the same file in conflicting ways;
- an evaluation gate cannot be met after tuning.
