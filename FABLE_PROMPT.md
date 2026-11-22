# Planning brief for Claude Fable 5.2: Family Xpense (v2, locked 2026-11-22)

> **How to use:** open a new Claude Code session in this folder and run `/model claude-fable-5-2`. Approve the project MCP servers when asked, then say **"Read FABLE_PROMPT.md and carry it out."**
>
> **Design direction (chosen by the owner):** **Signal**. Stone canvas, Geist + Geist Mono figures, ink black, one signal-orange action color, Liquid Glass on the control layer only. Design a matching graphite dark mode.

---

## 1. Your role

You are the lead architect and product planner for **Family Xpense**. Turn the **locked decisions** below into a complete, buildable plan. Then split it into well-scoped work packages that **Claude Opus 5.5** sessions can build independently and in parallel.

- **Do not write application code in this session.** Write planning documents only, under `docs/`.
- Treat section 5 (stack), section 6 (architecture) and section 4 (AI split) as **locked**. Only challenge one with evidence (a broken API, a missing feature), and log it in `docs/DECISIONS.md`.
- Where something is unclear, decide, write down the decision and the reason, and list it for the owner to confirm at the end.

## 2. What to read first

1. This file.
2. The **installed skills** in `.claude/skills/`: `a2ui`, `a2ui-migration`, `developing-genkit-dart`, `developing-genkit-js`. Read the `developing-genkit-dart` references `a2ui.md`, `agents*.md`, `genkit_shelf.md`, `genkit_google_genai.md`, `schemantic.md` and `dotprompt.md`.
3. Primary sources (verify; don't work from memory):
   - A2UI v1.0 spec: https://a2ui.org/specification/v1.0-a2ui/ · repo: https://github.com/a2ui-project/a2ui · Flutter renderer: https://github.com/a2ui-project/a2ui/tree/main/dart/a2ui_flutter · LLM index: https://a2ui.org/llms.txt
   - Genkit: https://genkit.dev/ · https://github.com/genkit-ai/genkit · getting started: https://genkit.dev/docs/js/get-started/ · dev tools: https://genkit.dev/docs/js/devtools/ · samples: https://examples.genkit.dev/
   - Gemini Decisions API: https://blog.google/innovation-and-ai/technology/developers-tools/gemini-decisions-api/
4. The design prototype (clickable): https://claude.ai/artifact/XxHQWTHVpRGpvSfzEQdX9S. Read it with the Artifact tool (`action: "read"`), not a web fetch.
   - Page **v3 · Minimal + Liquid Glass** is **the current visual language**: three directions (Porcelain, Midnight, Signal), each showing Home, Ask (voice / type / photo, with the follow-up question) and the on-device receipt scan with a glass sheet. Take every token (colors, type, radii, glass recipe) from the chosen row.
   - Page **v2 · Premium directions** is superseded. It is for reference only.
   - Page **v1 · First draft** has the full approved flow (restyle it in the chosen direction): onboarding (welcome → account → household + partner invite → accounts → try it), Home, chat expense, two entries in one message, the AI asking when unsure, manual add, Accounts (Mine / Partner / Joint), Savings goals, Loans & debts, Loan detail, and Activity.

## 3. The product

A household money app for **two partners** (the owner and their wife), each with their own sign-in, in one shared household. It tracks **expenses, income, transfers, loans given and taken, debts, savings goals and accounts**. **iOS first**, with Android later from the same Flutter code.

The user can **talk, type, or photograph a receipt** ("I spent 10,000 Iraqi dinars on lunch", "$100 on a gift"). The app then:
- works out the **intent** (expense, income, transfer, loan given or taken, repayment, savings move, or a question) and the **category, account, person and date**;
- handles **several entries in one message**;
- shows the result as **A2UI v1.0 cards** to confirm, edit or save;
- **asks follow-up questions when unsure**;
- is **proactive**: missed recurring bills, budget warnings, loan due dates, monthly summaries.

**Look and feel:** clean, minimalist, premium and "cool" (the first draft was judged "cheap looking"). Keep color coding, cards, charts, suggestion chips, the search bar, the Home / Activity / Ask / Goals / Accounts tabs, and multi-entry capture.

### Design language (locked)
- **Liquid Glass, iOS style, only on the control layer:** the floating tab bar (a pill with 4 tabs: Home, Activity, Goals, Accounts), a **separate round glass Ask button** next to it, the capture dock (voice / type / camera), the top floating buttons and pills, and bottom sheets (e.g. the receipt result). **Content stays on solid surfaces**: balances, cards and lists are never glass, so figures stay crisp. Never put glass on glass.
- **Minimal layout:** content sits on the canvas with hairline separators, not in boxed cards. There is one hero number, one thin chart, and at most one accent color for actions. Color coding uses small dots and figure colors, not filled tiles.
- **Accessibility:** respect *Reduce Transparency* (glass becomes a solid surface), *Increase Contrast*, Dynamic Type and RTL. Text contrast is at least 4.5:1, and figures never sit on glass alone.

| Direction | Canvas | Type | Accent / figures | Notes |
|---|---|---|---|---|
| **Porcelain** | warm white `#F6F5F1` | Inter Tight (figures 200 weight) | emerald `#0E7A57`; terracotta, cobalt, gold category dots | Airy and light, with frosted white glass |
| **Midnight** | near-black `#08090B` | Geist; Instrument Serif hero figures | champagne `#D9C08A`; jade income | Luxurious dark mode, with smoked glass |
| **Signal** | stone `#ECEBE7` | Geist; **Geist Mono** for all figures | one signal orange `#FF5B1A` for the Ask/mic action only; ink black for everything else | Editorial, receipt-like slips, a daily-spend micro chart. Claude's pick |

**Chosen: Signal.** Porcelain and Midnight are for reference only. Produce Signal's light theme (as drawn) and a **graphite dark theme** with the same rules: one orange action color, mono figures, and glass only on the controls.

### Non-negotiable requirements
- **Multi-currency**, IQD and USD first. Each account has its own currency, there is a household base currency, and every transaction stores its exchange rate. **IQD has an official rate and a market rate: the household chooses which one.** Store money as integer minor units and treat IQD as 0 decimals in practice. Support Kurdish and Arabic digits in both input and output.
- **Privacy modes:** *On-device only* · *Smart* (default) · *Cloud*. In on-device mode, no transaction text, audio or image leaves the phone for AI processing.
- **Partner privacy:** personal accounts are private unless shared, joint accounts are visible to both, and Firestore rules enforce this.
- **Kurdish (Sorani), Arabic (right-to-left) and English.** On-device speech-to-text support for Kurdish is weak: plan the fallback.

## 4. Hybrid AI split (locked): each layer handles one part of the request

| Step | Runs on | Responsibility |
|---|---|---|
| 0. Router | **On-device** (Dart) | Chooses the path from privacy mode, connectivity and message complexity (number of amounts, "and"/"و", question words, attachments). |
| 1. Capture | **On-device** | Speech-to-text (`speech_to_text`). OCR (ML Kit). Language detection. In Smart/Cloud modes, Kurdish voice falls back to Gemini audio. |
| 2. Fast parse | **On-device** (deterministic) | Amounts, currency words (dinar, IQD, $, دینار), dates, Kurdish/Arabic numerals; apply the household's learned rules (merchant → category, person → account). |
| 3. Simple extraction | **On-device LLM** (`flutter_edge_ai`: Apple Foundation Models / Gemini Nano / Gemma) | Single-entry messages → structured entry. If the device can't run a model → step 5. |
| 4. Classification | **Gemini Decisions API** (`gemini-decision-1`, called through the backend proxy so the key stays server-side) | Closed-set choices with probabilities: intent, category (from the household list), account, who (you / partner / joint), needs follow-up?, duplicate?, recurring? *On-device-only mode:* the on-device LLM does this instead. |
| 5. Reasoning & dialogue | **Genkit Dart agent on Cloud Run** (Gemini Flash / Flash-Lite through `genkit_google_genai`) | Multi-entry splitting, ambiguous messages, cloud receipt line items, questions and analytics (tools over Firestore), loans, follow-up dialogue, proactive nudges, monthly reports. Streams **A2UI v1.0** surfaces through `genkit_a2ui`. |
| 6. Render | **Flutter** `a2ui_flutter` + `a2ui_core` | One custom **Xpense catalog** renders both agent surfaces and **locally built A2UI messages** from the on-device path, so the UI is identical whichever path ran. |
| 7. Learn | Firestore + on-device cache | User corrections become rules, which are applied at step 2 next time. |

**Confidence policy:** high → prefill; medium → "Guessed" badge; low or a required field missing → follow-up choice card. Propose the thresholds and keep them in Remote Config.

Also design: the intent taxonomy, the default category tree, the Decisions API question set, extraction schemas (schemantic), `.prompt` files, the Xpense A2UI catalog (components, props, actions), an **evaluation set** of at least 150 utterances (EN/CKB/AR) plus receipts, run with `genkit eval`, and the **cost per 1,000 entries** for each privacy mode.

## 5. Tech stack (locked; versions checked 2026-11-22 on pub.dev and npm; re-verify)

| Layer | Choice | Version |
|---|---|---|
| App | **Flutter 3.50.1** (stable) / Dart 3.14.0 | Installed on the owner's Mac. Pin it per project (add FVM or a `.fvmrc`) |
| State / routing | flutter_riverpod / go_router | 3.5.0 / 18.1.4 |
| Generative UI | **a2ui_flutter + a2ui_core (A2UI protocol v1.0)** | 0.4.0 / 0.8.0. **Do not use `genui`, `genui_a2ui` or `flutter_genui`: they're discontinued.** Pre-1.0, so wrap behind an adapter |
| Firebase (Flutter) | firebase_core 5.2.0 · firebase_auth 7.1.0 · cloud_firestore 7.2.0 · firebase_app_check 0.5.2 · firebase_messaging 17.1.0 · firebase_crashlytics 6.1.0 · firebase_analytics 13.1.0 · firebase_remote_config 7.1.0 · firebase_storage 14.1.0 | — |
| On-device AI | flutter_edge_ai | 2.7.1 |
| On-device OCR / speech | google_mlkit_text_recognition / speech_to_text | 1.0.3 / 7.5.0 |
| Liquid Glass | **Evaluate** `liquid_glass_widgets` 1.19.0 (shader-based, iOS 26/27 style, actively maintained) vs `liquid_glass_renderer` 1.0.0-dev.2. Flutter 3.50.1's Cupertino library has no built-in Liquid Glass. Wrap it in a `GlassSurface` widget that falls back to `BackdropFilter` blur, and to a solid surface when Reduce Transparency is on or the device is low-end. Run a performance check on an older iPhone before locking it | — |
| Other app | local_auth 3.0.2 (Face ID) · flutter_secure_storage 11.2.0 · fl_chart 1.3.1 · intl 0.20.3 | — |
| **Backend** | **Genkit Dart 1.0 on Cloud Run**: genkit 1.0.3 · genkit_a2ui 0.6.0 · genkit_google_genai 1.2.0 · genkit_shelf 1.0.3 (`GenkitRouter`) · firebase_admin 0.5.0+2 (Dart, for ID-token and Firestore access) | Agents API is **experimental** (`package:genkit/experimental.dart`); isolate it |
| Why Dart and not TypeScript | Genkit's **JS** A2UI plugin (`@genkit-ai/a2ui` 0.7.0) still emits A2UI **v0.9** under `data.envelopes`, which doesn't work with the v1.0 Flutter renderer. **Genkit Dart emits v1.0 (`data.messages`)**, and Dart models can be shared between app and server. Revisit TypeScript only if JS reaches v1.0 parity | — |
| Data | Firestore (offline persistence on) · agent sessions in `FirestoreSessionStore` · Cloud Storage only for opt-in receipt backup | — |
| Jobs / events | Cloud Scheduler → Cloud Run endpoints (recurring detection, nudges, FX rates, monthly report) · Eventarc Firestore triggers → Cloud Run | — |
| Security | Firebase Auth (Sign in with Apple, Google, email) · App Check (verify on Cloud Run) · Secret Manager (`GEMINI_API_KEY`) · per-household rate limits | — |
| Observability | **Genkit Developer UI** in development (`genkit start`). In production: Genkit telemetry → Cloud Trace/Logging (**verify Dart support for Genkit Monitoring**), plus Crashlytics | genkit-cli 1.45.0 (installed globally) |
| Environments | Two **new** Firebase/GCP projects: `xpense-dev` and `xpense-prod`. Firebase Emulator Suite locally. Do not reuse the gcloud project currently active on this machine | firebase-tools 15.37.0 · gcloud SDK 591.0.0 |

## 6. Architecture (locked shape; detail it)

- **Flutter app:** feature-first modules (`onboarding`, `household`, `accounts`, `capture` (router + on-device AI), `ask` (A2UI surfaces), `activity`, `goals`, `loans`, `budgets`, `insights`, `settings_privacy`). Layers: `core/` (money, FX, theming tokens), `data/` (Firestore repositories), `a2ui/` (Xpense catalog + adapter).
- **Cloud Run service `xpense-agent`** (Dart, `GenkitRouter`): `/agent` (Genkit agent with the `a2ui()` middleware and Firestore tools), `/decide` (Decisions API proxy), `/jobs/*` (scheduled and event-driven work). A context provider verifies the Firebase ID token and the App Check token on every request.
- **Firestore:** `households/{hid}` with sub-collections `members`, `accounts`, `transactions`, `categories`, `loans`, `goals`, `budgets`, `recurring`, `rules`, `fxRates`, `notifications`, and `sessions` (agent).
- Produce a Mermaid system diagram and a sequence diagram for each path in section 4.

## 7. Development workflow (locked)

1. **Plan:** Fable 5.2 (this session) writes `docs/`.
2. **Build:** each work package runs in its **own Opus 5.5 session, git branch and worktree** and ends in a PR. Packages that touch the same files are never run at the same time.
3. **Debug:** `genkit start -- dart run bin/server.dart` (Developer UI at localhost:4000, traces), `genkit start:flutter -- -d <iOS simulator>` for app-side traces, `genkit trace:get <id> --format json`, `genkit flow:run` for headless checks, and the Firebase Emulator Suite. Claude can drive the iOS Simulator directly.
4. **CI (GitHub Actions):** `flutter analyze` + tests, `dart analyze` + tests for the server, Firestore rules tests against the emulator, golden tests for the Xpense catalog, and `genkit eval` on the evaluation set.
5. **Escalate** hard design problems back to Fable.

## 8. Tools available (name the ones each work package uses)

- **Skills (project):** `a2ui`, `a2ui-migration`, `developing-genkit-dart`, `developing-genkit-js`.
- **Plugins (installed):** Dart and Flutter (Dart MCP + skills) · Firebase (MCP) · Flutter Skills (architecture, Riverpod, RTL/i18n, money) · Mobile App Design (iOS) · Design · Mobile Design System.
- **Project MCP servers (`.mcp.json`):** `genkit` (docs, run flows, read traces) · `cloud-run` · `gcloud` (acts with the owner's account) · `context7` (up-to-date library docs).
- **Built in:** iOS Simulator control, the browser pane, and the `gh` CLI.

## 9. Gaps to cover: confirm, then look for more

Budgets with alerts · recurring bills and subscriptions · partner settle-up · narrated monthly report plus PDF/Excel export · FX rate source and history (official vs market IQD) · Face ID lock · offline capture with a queued AI request and conflict handling · edit/undo history and an audit trail · duplicate detection · notifications center · onboarding import (opening balances, CSV) · categories editor · account deletion and data export (App Store requirement) · **Sign in with Apple** (required if Google sign-in is offered on iOS) · accessibility (Dynamic Type, VoiceOver, contrast) · AI cost controls, response caching and a model fallback chain · prompt-injection safety for OCR and receipt text · privacy-respecting analytics · App Store privacy labels · backups · **iOS quick capture**: Siri / App Shortcuts ("log 10,000 dinars lunch"), home and lock screen widgets, share-sheet receipt import · Hijri calendar display (optional) · legal (terms, privacy policy) and store listing.

## 10. Deliverables (write these files)

1. `docs/PRD.md`: personas, user stories, scope for MVP, v1 and later, and success metrics.
2. `docs/ARCHITECTURE.md`: diagrams, module boundaries, endpoints, auth and App Check flow, privacy-mode routing, and the A2UI adapter.
3. `docs/DATA_MODEL.md`: collections, fields, indexes, **security rules**, money/FX rules, and migrations.
4. `docs/AI_PIPELINE.md`: everything in section 4, including schemas, prompts, Decisions API questions, thresholds, the evaluation plan and the cost model.
5. `docs/A2UI_CATALOG.md`: the Xpense catalog (component schemas, actions, data bindings), plus how the on-device path builds the same messages locally.
6. `docs/DESIGN_SYSTEM.md`: tokens from the chosen v3 direction mapped to Flutter `ThemeData` + `ThemeExtension` (colors, type scale, radii, spacing, **glass recipe**: blur, tint, border and highlight for light and dark), RTL, dark/light, motion, haptics, and the component inventory for **all** screens (restyle the whole v1 flow in the chosen direction). Use the *Mobile Design System* and *Mobile App Design (iOS)* plugin skills, and run an *ios-review* pass on the result.
7. `docs/BACKLOG.md`: epics → stories with acceptance criteria, S/M/L estimates, dependencies and milestones (M0 setup/CI/projects · M1 auth, household, accounts · M2 manual entry and Activity · M3 AI text capture (hybrid) · M4 voice and receipts · M5 loans, savings, budgets · M6 proactive agent and reports · M7 on-device privacy mode · M8 polish, localization, App Store launch).
8. `docs/DELEGATION.md`: work packages for **Opus 5.5**. Each one has: goal, owned files, dependencies, skills and MCPs to use, definition of done, test commands, parallel-safe yes/no, and a **ready-to-paste prompt**.
9. `docs/DECISIONS.md`: an ADR log, including every locked decision above.
10. `docs/RISKS.md`: include Liquid Glass performance and package maturity in Flutter, A2UI and Genkit Agents being pre-1.0 or experimental, Kurdish speech-to-text, on-device model availability, IQD rate volatility, Decisions API availability and quotas, and Dart Genkit monitoring gaps.

## 11. How to work

- Verify every version and API against the skills, the MCP servers (`genkit`, `context7`) and the official docs before relying on it. Record what you checked.
- Wrap everything pre-1.0 or experimental behind an interface.
- Keep each document skimmable, with headings, tables and short paragraphs.
- Finish with a short summary for the owner: what you decided, the top 5 open questions, and the first 3 work packages to start.
