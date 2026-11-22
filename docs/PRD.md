# Family Xpense: Product Requirements

Status: plan v1, 2026-11-22. Owner decisions are locked in `FABLE_PROMPT.md`; anything this document decides beyond the brief is logged in [DECISIONS.md](DECISIONS.md).

## 1. What it is

A household money app for two partners in one shared household. Each partner signs in separately. They capture money events by talking, typing or photographing a receipt, and the app files them. It tracks expenses, income, transfers, loans given and taken, debts, savings goals and accounts, in Iraqi dinar and US dollar first.

iOS first. Android follows from the same Flutter code.

## 2. Personas

| Persona | Who | What they need | What frustrates them today |
|---|---|---|---|
| **The organiser** (owner) | Sets up the household, comfortable with apps, thinks in both USD and IQD | One honest picture of household money; loans and debts that do not get forgotten; fast capture in any language | Spreadsheets nobody updates; apps that assume one currency and one person |
| **The partner** | Joins by invite, captures on the go, often by voice in Kurdish or Arabic | Capture in seconds without forms; her own accounts stay hers | Typing categories; apps in English only; everything visible to everyone |
| **The privacy-minded user** (either partner) | Does not want spending text sent to a cloud model | A mode where the AI runs on the phone and still works | No way to verify what leaves the device |

## 3. Principles

1. **Say it, confirm it.** Nothing is saved without a card the user has seen. One tap to confirm.
2. **Ask instead of guessing wrong.** A wrong intent (loan filed as expense) costs more than one extra tap.
3. **Same card, whichever brain.** On-device and cloud paths produce the same UI.
4. **Private by default.** Personal accounts stay personal. Privacy mode is visible on every capture screen.
5. **Figures are sacred.** Integer money, stored exchange rate, mono figures, never on glass.
6. **Quiet until useful.** Proactive nudges are few, specific and dismissible.

## 4. User stories

Priority: **M** = MVP (TestFlight for the two partners), **1** = v1 (App Store), **L** = later.

### Onboarding and household
| ID | Story | P |
|---|---|---|
| ON-1 | As a new user I see the product's value (a chat example) before creating an account. | M |
| ON-2 | I sign in with Apple, Google or email. | M |
| ON-3 | I create a household with a name, my display name and a base currency. | M |
| ON-4 | I invite my partner with a code or link; they join the same household. | M |
| ON-5 | I add accounts with today's balance, by form or by saying them. | M |
| ON-6 | I try a first capture before reaching Home. | M |
| ON-7 | I import opening history from CSV. | 1 |

### Capture
| ID | Story | P |
|---|---|---|
| CA-1 | I type "10,000 dinars lunch" and get a card with amount, currency, category, account, who and when. | M |
| CA-2 | I speak the same thing in English, Arabic or Kurdish. | M (EN/AR on device, CKB via cloud), 1 (CKB polish) |
| CA-3 | I put several entries in one message ("salary came in and I paid rent") and get one card per entry with "Save all". | M |
| CA-4 | When the app is unsure, it asks one question with tappable answers. | M |
| CA-5 | I photograph a receipt; the total, merchant and date are read; I can split it by category. | M (total), 1 (line-item split) |
| CA-6 | I can always add or edit manually in a form. | M |
| CA-7 | Guessed fields are marked "Guessed"; tapping one lets me change it. | M |
| CA-8 | My corrections are remembered (merchant → category, person → account). | M |
| CA-9 | Possible duplicates are flagged before saving. | 1 |
| CA-10 | I capture while offline; simple entries complete on the phone, complex ones wait in a queue. | M (simple), 1 (queue) |
| CA-11 | I capture through Siri, a Shortcut, a widget or the share sheet. | 1 |

### Money model
| ID | Story | P |
|---|---|---|
| MO-1 | Each account has its own currency; totals show in the household base currency. | M |
| MO-2 | The household chooses the official or the market IQD rate; every transaction stores the rate used. | M |
| MO-3 | I move money between accounts (transfer) without it counting as spending. | M |
| MO-4 | I record a loan I gave or took, repayments, and a due date. | M |
| MO-5 | I keep savings goals with a target and a pace. | 1 |
| MO-6 | I set monthly budgets per category and get warned at 80% and 100%. | 1 |
| MO-7 | Recurring bills and income are detected; I choose "add automatically", "remind me" or "not now". | 1 |
| MO-8 | Partners settle up: who paid what for joint spending, and who owes whom. | L |

### Review
| ID | Story | P |
|---|---|---|
| RE-1 | Home shows the household balance, this month's net, daily spending and recent entries. | M |
| RE-2 | Activity lists everything, grouped by day, with search and filters. | M |
| RE-3 | I ask questions ("how much did we spend on food this month?") and get an answer with a chart or list. | M (cloud), 1 (on-device basics) |
| RE-4 | I edit or undo any entry; the history shows who changed what. | M |
| RE-5 | I get a monthly summary, and can export PDF, Excel or CSV. | 1 |
| RE-6 | I see a notification centre with nudges and partner activity. | 1 |

### Privacy, security and settings
| ID | Story | P |
|---|---|---|
| PR-1 | My personal accounts are invisible to my partner unless I share them. | M |
| PR-2 | I choose On-device only, Smart or Cloud. The current mode shows on the Ask screen. | M (Smart, Cloud), 1 (On-device only) |
| PR-3 | The app locks with Face ID. | M |
| PR-4 | I use the app in English, Kurdish (Sorani) or Arabic, right-to-left where needed, with local digits. | M (EN + RTL-ready), 1 (CKB, AR complete) |
| PR-5 | I delete my account and data, and export my data, from inside the app. | 1 |
| PR-6 | I edit categories. | 1 |

## 5. Scope by release

| Release | Contains | Milestones |
|---|---|---|
| **MVP** (internal TestFlight) | Auth, household, accounts, manual entry, Activity, Home, hybrid text capture, voice, receipt total, loans, Smart and Cloud modes, Face ID, English with RTL-ready layouts | M0 to M4, loans from M5 |
| **v1** (App Store) | Goals, budgets, recurring, proactive nudges, monthly report and export, On-device only mode, full Kurdish and Arabic, quick capture (Siri, widgets, share sheet), account deletion and export, notifications centre, categories editor, duplicate detection, CSV import | M5 to M8 |
| **Later** | Android, partner settle-up, more than two members, more currencies with live rates, bank or SMS import, Hijri calendar display, iPad layout, Apple Watch | after v1 |

### Out of scope for v1
Bank connections, investment tracking, bill payment, shared households beyond one, web app, tax reports.

## 6. Requirements that cut across features

| Area | Requirement |
|---|---|
| Money | Integer minor units; IQD stored with 0 decimals; every transaction stores currency, rate, rate source and base amount. See [DATA_MODEL.md](DATA_MODEL.md). |
| Languages | English, Sorani Kurdish, Arabic. Input accepts Western, Arabic-Indic and Persian-style digits. Output digits follow a user setting (default Western). |
| Privacy modes | On-device only: no transaction text, audio or image leaves the phone for AI processing. Smart (default): the phone does what it can; classification and hard cases go to the cloud. Cloud: cloud does the AI work. |
| Offline | Reading, manual entry and simple capture work offline. Writes sync when back online. |
| Accessibility | Dynamic Type to the largest accessibility size, VoiceOver labels, 4.5:1 contrast, 44 pt targets, Reduce Transparency, Reduce Motion, Increase Contrast. |
| Performance | Cold start under 2.5 s on iPhone 12. Card after a typed message: under 600 ms on-device path, under 2.5 s cloud path (first surface). 60 fps scrolling with glass controls on iPhone 12. |
| Cost | Smart mode stays under USD 1.00 per household per month at 300 entries (estimate: about USD 0.52). See the cost model in [AI_PIPELINE.md](AI_PIPELINE.md). |

## 7. Success metrics

| Metric | Target at v1 | How measured |
|---|---|---|
| Capture time, typed (open Ask → saved) | median under 8 s | analytics timing event, no content |
| Entries saved without any field edit | at least 80% | `entry_saved` with `edited_fields=0` |
| Intent accuracy on the evaluation set | at least 97% | `genkit eval`, see AI_PIPELINE |
| Category accuracy on the evaluation set | at least 90% top-1 (each language) | `genkit eval` |
| Follow-up rate | 10% to 25% of captures | `followup_shown / capture_started` |
| Wrong-save rate (saved, then intent edited within 24 h) | under 2% | revision log analytics |
| Both partners active weekly | yes, 4 weeks running | per-member weekly active flag |
| Share of captures that never leave the phone (Smart mode) | at least 40% | router path counter |
| Crash-free sessions | at least 99.5% | Crashlytics |
| AI cost per 1,000 entries, Smart mode | under USD 1.50 | server usage counters |

Analytics never include amounts, merchant names, notes or transcripts. Events carry path, language, counts and durations only.

## 8. Dependencies and assumptions

- The owner has an Apple Developer account and can create two Firebase/GCP projects with billing.
- Both partners use iPhones recent enough for App Attest (iOS 14+). On-device LLM needs newer hardware; the app works without it.
- The Gemini Decisions API stays available at its announced price. If not, Flash-Lite with a constrained schema replaces it (see RISKS).
- A2UI Flutter packages and the Genkit Agents API are pre-1.0 or experimental, so both sit behind adapters.
