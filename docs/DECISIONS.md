# Family Xpense: Decision Log

Three parts: decisions locked by the owner (L), decisions made while planning (D), and the record of what was verified. Status values: **Locked**, **Decided** (by the planner, owner may overrule), **Changed** (a locked item corrected with evidence), **Verify** (settled by a named work package).

## 1. Locked by the owner (from `FABLE_PROMPT.md`)

| ID | Decision | Status |
|---|---|---|
| L-01 | Product: household money app for two partners, each with their own sign-in, one shared household; iOS first, Android later from the same code | Locked |
| L-02 | Design direction **Signal**: stone canvas, Geist and Geist Mono, ink, one signal orange, Liquid Glass on the control layer only; matching graphite dark theme | Locked |
| L-03 | Capture by voice, text or receipt photo; A2UI v1.0 cards to confirm; follow-up questions when unsure; several entries per message; proactive nudges | Locked |
| L-04 | Multi-currency with IQD and USD first; currency per account; household base currency; stored rate per transaction; integer minor units | Locked. Rate entry changed by the owner on 2026-11-22: the app asks for the rate every day (D-16) |
| L-05 | Privacy modes: On-device only, Smart (default), Cloud | Locked |
| L-06 | Partner privacy enforced by Firestore rules | Locked |
| L-07 | Languages: Kurdish (Sorani), Arabic, English; RTL; local digits in and out | **Deferred by the owner on 2026-11-22:** English only for now (D-36) |
| L-08 | Hybrid AI split, steps 0 to 7 (router, capture, fast parse, on-device extraction, Decisions API, Genkit agent, A2UI render, learn) | Locked; refined by D-09 |
| L-09 | Confidence policy: high prefill, medium "Guessed", low follow-up; thresholds in Remote Config | Locked; values in D-30 |
| L-10 | App: Flutter 3.50.1 / Dart 3.14.0, Riverpod 3.5.0, go_router 18.1.4 | Locked |
| L-11 | Generative UI: `a2ui_flutter 0.4.0` + `a2ui_core 0.8.0`, A2UI v1.0, behind an adapter; no `genui` packages | Locked |
| L-12 | Firebase client packages at the listed versions | Locked |
| L-13 | On-device AI through `flutter_edge_ai 2.7.1`; OCR through ML Kit; speech through `speech_to_text 7.5.0` | Locked; OCR limits noted in D-08 |
| L-14 | Liquid Glass: evaluate `liquid_glass_widgets` against `liquid_glass_renderer`; wrap in `GlassSurface` with fallbacks; performance check before locking | Locked; outcome in D-07 |
| L-15 | Backend: Genkit Dart 1.0 on Cloud Run (`genkit 1.0.3`, `genkit_a2ui 0.6.0`, `genkit_google_genai 1.2.0`, `genkit_shelf 1.0.3`); Agents API isolated | Locked |
| L-16 | `firebase_admin 0.5.0+2` for ID-token and Firestore access on the server | **Changed** by D-06 |
| L-17 | Dart backend rather than TypeScript, because the JS A2UI plugin still emits v0.9 | Locked (re-confirmed: `@genkit-ai/a2ui` is still 0.7.0) |
| L-18 | Data: Firestore with offline persistence; agent sessions in `FirestoreSessionStore`; Storage only for opt-in receipt backup | Locked; detail in D-11, D-31 |
| L-19 | Jobs: Cloud Scheduler and Eventarc to Cloud Run endpoints | Locked |
| L-20 | Security: Firebase Auth (Apple, Google, email), App Check verified on Cloud Run, Secret Manager, per-household rate limits | Locked |
| L-21 | Observability: Genkit Developer UI in development; production telemetry to Cloud Trace and Logging; Crashlytics | Locked; mechanism in D-29 |
| L-22 | Two new projects, `xpense-dev` and `xpense-prod`; emulator suite locally; never reuse the machine's active gcloud project | Locked |
| L-23 | Architecture shape: feature-first Flutter modules with `core/`, `data/`, `a2ui/`; one Cloud Run service with `/agent`, `/decide`, `/jobs/*`; Firestore under `households/{hid}` | Locked; refined by D-17, D-19, D-20, D-28 |
| L-24 | Workflow: Fable plans, each work package in its own Opus session, branch and worktree; CI with analyzers, tests, rules tests, catalog goldens and `genkit eval` | Locked |

## 2. Decisions made while planning

### Changes to locked items (with evidence)

**D-06. Server uses `firebase_admin_sdk 0.5.6`, not `firebase_admin 0.5.0+2`.** Status: Changed.
- Evidence: the `firebase_admin` README on pub.dev says it "only supports admin methods for … authentication, realtime database". It has no Firestore, App Check or Messaging. Its publisher is a third party.
- `firebase_admin_sdk` is published by `firebase.google.com`, and its README lists App Check, Authentication, Firestore (through `google_cloud_firestore`), Messaging and Storage as fully supported. Its `google_cloud_firestore` range is compatible with `genkit_google_cloud`'s.
- Consequence: one admin gateway on the server; no hand-written App Check verification.

**D-08. Receipt OCR stays on ML Kit for now, behind an `OcrEngine` interface; Arabic-script receipts use the cloud path.** Status: Decided.
- Evidence: ML Kit Text Recognition v2 supports Chinese, Devanagari, Japanese, Korean and Latin scripts only; the Flutter plugin states that on iOS only Latin is supported. Receipts printed in Arabic script cannot be read by it.
- With Kurdish and Arabic deferred (D-36), ML Kit is enough for Latin receipts. Arabic-script receipts go to the agent as an image in Smart and Cloud, or to manual entry of the total in On-device mode.
- When the languages return, Apple Vision is the candidate on-device engine: its accurate level listed `ar-SA` in a probe on macOS 27; support on iPhone and for Sorani letters is untested.

**D-09. When the phone has no usable on-device model, a single-entry message goes to `/decide`, not to the agent.** Status: Decided (refines L-08, which said "no model → step 5").
- Evidence: Apple's on-device model needs an iPhone 15 Pro or newer with iOS 26, and the `flutter_edge_ai` built-in engine does not yet support structured output. Without this rule, every single-entry message from an older phone would take the agent path at about 40 times the cost of a Decisions call.
- The fast parser already extracts amount, currency and date; the Decisions API classifies from the raw text.
- Reversible: Remote Config flag `router_no_model_uses_decide`.

**D-07. Liquid Glass package: `liquid_glass_widgets 1.19.0`.** Status: Decided; tiers Verify (WP-S2).
- `liquid_glass_renderer 1.0.0-dev.2` declares `sdk: ">=3.13.0 <3.14.0"`. Flutter 3.50.1 ships Dart 3.14.0, so it does not resolve. It also has no stable release.
- `liquid_glass_widgets` has no third-party dependencies, quality tiers down to a plain `BackdropFilter`, and Impeller is optional.
- Flutter 3.50 ships no Liquid Glass widgets (release notes; tracking issue flutter/flutter#170310 is open with no milestone).
- Neither Flutter nor the package exposes Reduce Transparency, so the app reads it through its own platform channel.

### Structure

**D-01. Monorepo: `app/`, `server/`, `packages/xpense_shared/`, `firebase/`, `evals/`, `docs/`.** Shared pure-Dart code (money, parser, schemas, catalog JSON, surface builder) is used by both sides.

**D-05. No pub workspace; `app` and `server` keep separate lockfiles.** `a2ui_flutter 0.4.0` requires `a2ui_core ^0.8.0`; `genkit_a2ui 0.6.0` requires `a2ui_core ^0.7.0`. A workspace forces one resolution and would fail. `xpense_shared` therefore must not depend on `a2ui_core`.

**D-17. One container image, two Cloud Run services:** `xpense-agent` (public, token-verified in the app) and `xpense-jobs` (IAM-private). Keeps job endpoints off the public internet without a second codebase.

**D-19. Extra server endpoints:** `/household/invite`, `/household/join`, `/account/delete`. They need admin rights (membership, Auth user deletion) that rules cannot grant safely.

**D-20. Extra app modules:** `home` and `notifications`.

**D-28. Extra collections:** `people` (counterparties), `transactions/{id}/revisions` (audit trail), `usage` (AI counters), `invites` and `config` (server-only), household-level `fxRates` for manual market rates alongside global official rates.

**D-32. Public routes are versioned (`/v1/…`)** and tied to the catalog version, because installed apps lag the server.

### Data

**D-10. The phone is the single write path for user-confirmed entries.** The agent proposes drafts; saving happens on the phone through repositories. Reasons: works offline, one path for local and cloud AI, rules remain the enforcement point, and injected text cannot make the server write money data.

**D-11. Agent sessions live in top-level `agentSessions*` collections with a per-household, per-member prefix.** `FirestoreSessionStore` derives three companion collections from one collection name. Whether a nested path under `households/{hid}` works is checked in WP-S1; if it does, move them there (the brief listed `sessions` as a sub-collection). Status: Verify.

**D-12. A transfer is one document with `accountId` and `toAccountId`.** Its `visibleTo` is the union of both accounts' viewers. A partner sees the amount arriving in a joint account and "Private account" as the source. Simpler lists and edits than two linked legs.

**D-13. Balances are maintained with `FieldValue.increment` in the same batched write, and verified nightly.** Batches with increments work offline and commute; `runTransaction` does not work offline. Rules do not verify the arithmetic; the reconcile job does.

**D-14. IQD is stored with 0 decimals (whole dinars); USD with 2.** ISO 4217 says 3 for IQD, CLDR says 0, the smallest note is 250 and no fils circulate. A versioned `moneySchema` allows a migration if Iraq redenominates.

**D-15. Superseded by D-16** (the app no longer picks an official figure; the user enters the rate).

**D-16. The app asks for the USD/IQD rate every day; no rate is fetched.** Status: Locked by the owner on 2026-11-22.
- On the first open of each day, when the household has accounts in both currencies, Home asks "Today's dollar rate?" with yesterday's figure. One tap keeps it; Change opens a number pad. One answer covers both partners (ARCHITECTURE 3.5).
- A cross-currency entry saved before anyone answered asks inline. If skipped, it uses the latest rate and records that rate's date.
- The household labels its rate `official` or `market` (default `market`), so the brief's "household chooses which one" is kept as a label on what they type.
- There is no rate job and no global rate collection. For reference, the rates on 2026-11-22 were 1,520 (official cash, since the 7 October devaluation) and about 1,705 (market). An automatic feed or a prefilled suggestion is a later option.

**D-25. One goal per savings account in v1.** Goal progress is the account balance; savings moves are plain transfers.

**D-27. Invites are 10-character codes, hashed at rest, 7 days, single use, handled by the server.** The prototype's 4-digit code is too short to resist guessing.

### AI

**D-02. Three capture paths:** L (local), D (Decisions) and A (agent). Named so logs, tests and evaluation slices can refer to them.

**D-03. Drafts live in the surface data model and smart components edit them.** `EntryList` binds to `/drafts`; closed-set follow-up answers write locally without a model call. The same structure is produced by the local builder and by the agent.

**D-04. Default agent model `gemini-3.5-flash-lite`; escalation and monthly report on `gemini-3.8-flash`; ids pinned in `config/runtime`.** `-latest` aliases are hot-swapped by Google and are not used. `gemini-4-hydrogen` is noted as the likely successor for the escalation role.

**D-21. Cloud voice goes to the agent as an audio part; there is no separate transcription endpoint.** One call transcribes and files; the transcript is shown to the user.

**D-23. The catalog is loaded from JSON with a reduced basic subset.** No image, video, audio, modal or link components; no `openUrl`.

**D-30. Initial thresholds:** `conf_high 0.85`, `conf_low 0.55`, `conf_intent_min 0.90`, `conf_on_device_cap 0.80`, `dup_warn 0.80`, `recurring_offer 0.75`. Tuned in WP-35.

**D-33. Household flag `cloudInsights`** gates model narration in server jobs; it is false when any member is On-device only.

**D-34. Only a paid-tier Gemini API key is used with real data.** Google's terms allow free-tier content to be used for product improvement and read by reviewers; paid-tier content is not used for that and is logged only briefly for abuse detection.

### Platform and design

**D-18. Region `me-central1` (Doha) for Firestore, Cloud Run, Scheduler, Eventarc, Secret Manager and Storage.** Status: Locked by the owner on 2026-11-22.
- Chosen for proximity to Iraq. Firestore's location cannot be changed after creation.
- Checked on 2026-11-22: Google's location pages for Firestore, Cloud Run, Cloud Scheduler, Eventarc, Cloud Storage, Secret Manager and Cloud Functions each list `me-central1`. Feature parity and pricing tier in that region were not checked; WP-01 confirms each service enables cleanly in `xpense-dev` before `xpense-prod` is created.
- The Gemini Developer API is not regional, so model calls leave the region either way.
- Fallback if a needed service is missing in Doha: keep Firestore and Storage in `me-central1` and run only that service in `europe-west3`.

**D-22. Material and Cupertino imports.** Flutter 3.50 deprecates the bundled libraries in favour of `material_ui 1.11.1` and `cupertino_ui 1.1.7`. Adopt the standalone packages if `a2ui_flutter 0.4.0` builds with them; otherwise stay on the bundled libraries and accept the deprecation notices until the renderer moves. Status: **Decided (verified in WP-00, 2026-11-22): adopt `material_ui` and `cupertino_ui`; bridge the `a2ui_flutter` basic widgets.**
- **It builds.** `material_ui 1.11.1`, `cupertino_ui 1.1.7` and `a2ui_flutter 0.4.0` resolve together; `flutter analyze` is clean; `flutter build ios --simulator --debug` succeeded with a probe entry point that uses all three, plus every plugin in the app's pubspec, at iOS deployment target 15.0. The Flutter 3.50.1 app template itself imports `package:material_ui`.
- **But they are separate libraries, not aliases.** Flutter's bundled `package:flutter/material.dart` and `cupertino.dart` are marked `@Deprecated` (since 3.47) and still hold their own classes. `material_ui` declares its own `ThemeData`, `Theme`, `Material` and `MaterialLocalizations`; `cupertino_ui` its own `CupertinoLocalizations`. `a2ui_flutter 0.4.0` imports the bundled library in 18 files (`// ignore: deprecated_member_use`, citing a2ui issue #3235).
- **Probe** (widget tests; copy in the shared notes folder as `wp-00-d22_probe_test.dart`), rendering a basic-catalog surface with Text, TextField, CheckBox and Button:

  | Set-up | Result |
  |---|---|
  | bundled `MaterialApp` (status quo) | works |
  | `material_ui` `MaterialApp` only | TextField and CheckBox throw "No Material widget found"; layout collapses; a2ui reads the bundled fallback theme (purple), not the app's colours |
  | `material_ui` app + `MaterialUiCompatibilityBridge` + bundled `Material` around the surface | no errors; typing and tapping work; same primary colour on both sides; `en` and `ar` (RTL) |
  | same, without the bundled `Material` | fails as in row 2 |

- **Consequences:**
  1. App code imports `package:material_ui/material_ui.dart` and `package:cupertino_ui/cupertino_ui.dart`, never the bundled libraries.
  2. `XpenseSurfaceHost` (WP-31) wraps each surface in `MaterialUiCompatibilityBridge` (shipped by `material_ui`) and a bundled `Material`. Scope it to surfaces, not the app-wide `MaterialApp.builder`, so nothing else depends on bundled types. Only `lib/a2ui/` may import `package:flutter/material.dart`; the import-rule test enforces it.
  3. The bridge maps only `colorScheme`, `textTheme`, `visualDensity` and `platform`. Theme extensions (Signal tokens) and component themes are not mapped, so the reduced basic subset (D-23) gets the mapped colours and type only; the custom Xpense components read tokens from the `material_ui` theme directly. WP-31 checks the basic-subset goldens.
  4. Localizations (WP-10; matters once the deferred languages return, D-36): `material_ui`'s `MaterialApp` registers `cupertino_ui`'s English-only Cupertino delegate, so `ar` warns unless the app also registers `cupertino_ui`'s `GlobalCupertinoLocalizations.delegate` and `material_ui`'s `GlobalMaterialLocalizations.delegate`. The bridge supplies the bundled `flutter_localizations` delegates for the surfaces (`flutter_localizations` is now in the app pubspec). None of the three libraries has `ckb` (Sorani); WP-10 needs a fallback, not checked here.
  5. `MaterialUiCompatibilityBridge` is itself `@Deprecated` as a temporary migration utility. Remove it when `a2ui_flutter` moves to `material_ui` (watch a2ui issue #3235). If it is removed first, copy its mapping into `lib/a2ui/` (about 150 lines).

**D-24. Email sign-in is email and password with verification in the MVP.** Passwordless links need extra hosting setup; revisit for v1.

**D-26. Orange means "act or live":** the Ask button and mic, plus live and now markers (waveform, scan frame, today's bar, unread and nudge dots). Never text, never another button. The brief said "for the Ask/mic action only"; the chosen prototype already uses it for those markers. Owner to confirm.

**D-29. Production telemetry through `genkit_otel 0.2.3` and OTLP.** The Genkit Dart docs state there is no Genkit Monitoring plugin for Dart. Content capture stays off.

**D-31. `FirestoreSessionStore` comes from `genkit_google_cloud 0.3.3`,** a package the brief did not list. It is pre-1.0 and wrapped in `runtime/session_store.dart`.

**D-37. Test devices and the household's own setup.** Status: stated by the owner on 2026-11-22.
- Phones: iPhone 17 Pro and iPhone 15 Pro Max. Both qualify for Apple's on-device model (with iOS 26 or later and Apple Intelligence on), so English on-device extraction needs no model download in this household.
- These two phones are the only real test hardware. The iPhone 15 Pro Max is the performance reference; the earlier "iPhone 12" targets are replaced. Smaller and older iPhones are covered by simulators for layout only, and their glass tier defaults to plain blur until measured.
- Household base currency: USD. Onboarding preselects USD; it stays fixed after creation.

**D-35. Arabic-script typeface: deferred with the languages.** Geist has no Arabic script; Vazirmatn is the candidate when Kurdish and Arabic are added.

**D-36. English only for now.** Status: Locked by the owner on 2026-11-22.
- Deferred: Kurdish (Sorani) and Arabic interface text, voice, on-device Arabic-script OCR, right-to-left layout and goldens, local digits, digit folding, slang parsing (daftar, waraqa), the multilingual evaluation slices, and native-speaker review.
- Kept, because it is free now and avoids rework later: all strings in an ARB file, directional insets and alignments, parser lexicons and category names keyed by language code.
- Consequence for capture: speech is `en-US` only; receipts in Arabic script are read by the cloud model or entered by hand.
- The research findings that matter when the languages return are in section 3 (no Sorani speech recogniser anywhere, no Arabic in Apple's on-device model or in ML Kit).

## 3. What was verified (2026-11-22)

| Subject | How | Result |
|---|---|---|
| All package versions in the brief | pub.dev API, npm registry | every listed version is the current latest; `genui`, `genui_a2ui`, `flutter_genui` are marked discontinued; `@genkit-ai/a2ui` is 0.7.0 |
| Local toolchain | `flutter --version`, `genkit --version`, `firebase --version`, `gcloud --version` | Flutter 3.50.1, Dart 3.14.0, genkit-cli 1.45.0, gcloud 591.0.0. **firebase-tools is 15.34.2 locally, not 15.37.0** as the brief states. FVM is not installed. |
| Genkit Dart APIs | project skill `developing-genkit-dart` (SKILL and references `a2ui`, `agents`, `agents-sessions`, `agents-deployment`, `agents-state`, `agents-custom`, `agents-human-in-the-loop`, `genkit`, `genkit_shelf`, `genkit_google_genai`, `schemantic`, `dotprompt`); `genkit` MCP docs for evaluation, Cloud Run, authorization, observability | APIs used in ARCHITECTURE and AI_PIPELINE are taken from these sources |
| Genkit Dart monitoring | Genkit docs `dart/local-observability.md` | "There is no Genkit Monitoring plugin for Dart"; use `genkit_otel` |
| Genkit evaluation in Dart | Genkit docs `dart/evaluation.md`, `js/evaluation.md` | full framework; metrics are custom evaluators; CLI `eval:flow`, `eval:run` |
| A2UI v1.0 | a2ui.org spec, basic catalog JSON, package READMEs and changelogs (research agent) | message set, binding and template notation, catalog rules, no theme in v1.0, `createSurface` may carry components and data model |
| `a2ui_core` 0.7 ↔ 0.8 | changelogs and pubspecs | 0.8 renderer reads 0.7-era bare envelope keys through a temporary dual-read; the reverse is not compatible; versions cannot share one resolution |
| `a2ui_flutter 0.4.0` | README, source on `main` | basic components are plain Material widgets; no golden guidance; Markdown not built in; surfaces are unbounded. Signatures were read from `main`, which is slightly ahead of 0.4.0. |
| Decisions API | Google AI docs, API reference, pricing, rate limits, terms, launch blog (research agent) | endpoint, request and response shapes, USD 0.10 per 1M input tokens, beta, API key only, no Dart SDK, no language statement |
| Gemini models and prices | Google AI models and pricing pages | `gemini-3.5-flash-lite`, `gemini-3.8-flash` (price doubles on 2027-01-01), `gemini-4-hydrogen`; audio 25 to 32 tokens per second (docs disagree); image 258 to 1,120 tokens (docs disagree) |
| Speech | Apple feature availability, local macOS probe, `speech_to_text` README, Whisper language table, Gemini transcription language list | Arabic on-device dictation listed; no Kurdish anywhere; `onDevice: true` exists in 7.5.0 |
| Apple Foundation Models | Apple docs and support article, local macOS probe | iOS 26+, iPhone 15 Pro and newer; Arabic and Kurdish unsupported |
| `flutter_edge_ai` | pub.dev, README, docs site | engines are separate packages; built-in engine refuses structured output today; Gemma 4 E2B is 2.6 GB; speech is a separate package |
| OCR | ML Kit language page, plugin README, local Vision probe | ML Kit has no Arabic script; Vision lists `ar-SA` at accurate level on macOS |
| Liquid Glass packages | pub.dev, READMEs, pubspecs, Flutter 3.50 release notes | see D-07 |
| Server Firebase packages | pub.dev READMEs and publishers | see D-06 |
| IQD rates | Shafaq News, CBI site, Frankfurter, open.er-api (research agent) | official rate devalued on 2026-10-07 to 1,500 / 1,510 / 1,520; market about 1,705 to 1,710 on 2026-11-21 |
| Design tokens | Artifact read of the three Signal artboards and the fifteen v1 artboards | tokens in DESIGN_SYSTEM are copied from the artboard source; contrast ratios computed by hand from the hex values |
| Package resolution (WP-00) | pub.dev API; `pub get` in `app/`, `server/`, `packages/xpense_shared/` | every version in the brief and the D-06/D-07/D-31 corrections still exists and is the latest; all resolve on Dart 3.14.0. The app locks `a2ui_core 0.8.0`, the server `0.7.0` (confirms D-05). **`genkit_otel 0.2.3` requires `dartastic_opentelemetry ^0.11.0`**, so the `0.12.0` named in ARCHITECTURE 4.3 cannot resolve; the server gets 0.11.0 transitively and WP-04 should add it as `^0.11.0` if it imports it directly |
| Material/Cupertino with A2UI (WP-00) | package source, widget-test probe, iOS simulator build | see D-22 |
| iOS build location (WP-00) | `flutter build ios --simulator` | fails in the project folder (iCloud-synced `~/Documents`): codesign rejects `Flutter.framework` with "resource fork, Finder information, or similar detritus not allowed". The same build from a copy outside `~/Documents` succeeds. Build in a worktree outside `~/Documents`, or exclude the folder from iCloud |

Not verified, and settled by spikes: items marked Verify above; Express syntax for arrays of objects; behaviour on a physical iPhone (all local probes ran on macOS or not at all).

## 4. Open questions for the owner

Answered on 2026-11-22: region is Doha (D-18); English only for now (D-36); the app asks for the exchange rate every day (D-16); phones are iPhone 17 Pro and iPhone 15 Pro Max, and the base currency is USD (D-37).

Still open:

1. **Orange.** Is "act or live" (Ask, mic, plus live markers) acceptable, or should every marker other than Ask and mic become ink? (D-26)
2. **Rate label.** Is the rate you will type each day the market rate (my default) or the official one? It only changes the label shown in reports.
3. **Categories.** Review the default tree, especially `electricity_generator`, `family_support`, `charity` and `occasions`.
4. **Domain and bundle id.** The catalog id uses `familyxpense.app` as a placeholder.
5. **Email sign-in.** Email and password for the MVP, or is Apple plus Google enough?
6. **Apple Intelligence.** Is it switched on, with iOS 26 or later, on both phones? On-device extraction depends on it.
