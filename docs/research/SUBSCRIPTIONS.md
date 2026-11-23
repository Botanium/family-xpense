# Family Xpense: Subscription tiers, pricing and getting paid

Status: research and recommendation, 2026-11-22. No app code. Input to WP-P1 (DELEGATION) and to the owner decisions in [DECISIONS.md](../DECISIONS.md) section 4. Launch markets are the **United States and Europe (EU and UK)** (D-43); Iraq is a short note in section 9.

Every external fact has a source and a date in section 10. "Undated" means the page shows only a copyright year. **[3P]** marks a third-party source. All pages were read on 2026-11-22. Where something could not be verified, the text says so.

---

## Summary (one screen)

> **Revised on 2026-11-22: the enrollment recommendation changed.** The first version said the app could be moved to the company with App Transfer before launch. That is not possible: App Transfer needs a version already released on the App Store. Section 7(f) now lists the paths that do work.

> **URGENT: how to enroll in the Apple Developer Program (owner was about to enroll as an individual today).**
> **Recommendation: enroll as an individual today for development and TestFlight, and request a free D-U-N-S number for the US company at the same time. Keep the production bundle id `com.bitrelia.familyxpense` out of the individual account until the seller is decided; test under a separate id such as `com.bitrelia.familyxpense.dev`.** Details in section 7.
> - Enrolling now unblocks Sign in with Apple, App Attest and TestFlight (D-39). Paid-app banking is not needed for that.
> - The company route cannot finish today: D-U-N-S takes up to about 7 business days, and Apple also needs a website and email on the company's domain. Foreign-owned US LLCs using a registered-agent address are being declined, and many report App Store Connect offers them only a W-9, which blocks the Paid Apps Agreement for months.
> - The company does not solve payouts yet. Mercury, Relay, Wise and Novo all refuse an owner who lives in Iraq.
> - If the individual is the seller, the owner's **legal name is shown**, and the EU product page shows an **address (a P.O. box with proof is allowed) and phone number**.
> - **The real blocker is payouts.** Nobody has confirmed that Apple can pay an Iraqi bank. Check this in App Store Connect right after enrolling.
> - **Three ways to end with the company as seller** (section 7(f), which also covers waiting for the company and staying individual):
>   1. Ask Apple to convert the individual membership to an organization before launch. Same account, no App Transfer, but Apple publishes no procedure and conversions have stalled.
>   2. Release from a separate company account. This is cheap only if the individual account never used the production bundle id; the two partners sign in again in the new production project, which D-38 creates empty anyway.
>   3. Release under the individual first, then use App Transfer. This needs a Sign in with Apple migration within 60 days, and Apple does not say subscribers carry over.

### Recommended tiers

All three tiers include both partners and every money feature that makes the ledger correct. Tiers differ by how much cloud AI a household uses, by depth (reports, automation, unlimited budgets and goals), and, for VIP, by household size and service level.

| | **Standard** | **Pro** (recommended, pre-selected) | **VIP** |
|---|---|---|---|
| Members | 2 (you and your partner) | 2 | up to 6 (needs "more than two members", see risk R-4) |
| Capture on the phone (typing, on-device voice, rules, parser, on-device model) | unlimited | unlimited | unlimited |
| Category and account suggestions (Decisions API) per month, then on-phone suggestions | 1,000 | 1,000 | 2,000 |
| **Cloud AI captures** per month (multi-entry messages, cloud voice, receipt photos, commands) | 50 | 150 | 300 |
| of which receipt scans | 15, total only | 75, with line-item split | 150, with line-item split |
| **Questions to the AI** per month | 15 | 40 | 70 |
| Privacy modes (On-device only, Smart, Cloud) | all three | all three | all three |
| Budgets / savings goals | 5 / 2 | unlimited | unlimited |
| Recurring bills | detect and remind | detect, remind or add automatically | same as Pro |
| Nudges | essentials (loan due, budget at 100%, daily rate) | all | all |
| Monthly summary | on-phone summary | + AI-written monthly report | + yearly review, up to 4 custom-range reports a month |
| Export | CSV, any time | + PDF and Excel reports | same as Pro |
| History | kept forever | kept forever | kept forever |
| Support | in-app help, email | email, faster reply | priority email, early access to new features |

Cloud AI, suggestion and question limits never stop a money entry. A typical household (300 entries, about 60 cloud captures, 30 questions and 150 suggestion calls a month) stays well inside Standard's suggestions and Pro's other limits. When a limit is reached, capture falls back to the phone-only path and the manual form (the same experience as being offline), and the household sees one quiet note after saving. See section 4.

### Recommended prices

| | Standard | Pro | VIP |
|---|---|---|---|
| **US** monthly / yearly (before sales tax) | $3.99 / $29.99 | **$7.99 / $59.99** | $14.99 / $119.99 |
| **EU** (euro storefronts, VAT included) | €3.99 / €29.99 | **€7.99 / €59.99** | €14.99 / €119.99 |
| **UK** (VAT included) | £3.49 / £26.99 | **£6.99 / £54.99** | £12.99 / £109.99 |
| Yearly saving vs 12 × monthly | 37% | 37% | 33% |

- **No weekly plan.** Budgeting is a habit measured in months. Weekly plans keep only 3.4% of subscribers after a year, and no budgeting leader sells one (section 6).
- **Free trial: 1 month on yearly plans, 2 weeks on monthly plans,** one trial per household. Longer trials convert and renew better, and a budgeting app shows its value at the end of the first month.
- **No free tier.** After a trial or a lapse the household keeps read-only access and export. Data is never held hostage.
- **Margins:** even if a household uses every allowance in full, every plan keeps at least 50% of proceeds in the US, the UK and every EU country at Apple's 15% rate. The floor is computed at 27% VAT (Hungary, the highest standard rate in the EU); the lowest cases are Pro and VIP yearly at 50.5% and 50.7%. At the 30% rate the lowest is 39.9%. At typical use, every plan keeps 58% to 87% (section 3).
- **Positioning:** below the bank-sync apps (YNAB $109, Monarch $99.99 a year), at the top of the AI-capture trackers ($30 to $70 a year). Family Xpense has no bank sync but includes partners, AI capture, loans and multi-currency.

### Decisions for the owner

These are listed in [DECISIONS.md](../DECISIONS.md) section 4: enrollment route (urgent), the tier set and whether VIP launches on day one, prices, no weekly plan, trial lengths, no free tier, privacy modes in every tier, household entitlement, the billing back end, and two consequences of D-43: EUR/GBP currencies and an EU data region.

---

## 1. What this product's costs are

From [AI_PIPELINE.md](../AI_PIPELINE.md) section 12, updated with the measured values in [spikes/WP-S4.md](../spikes/WP-S4.md) (Decisions call measured at 2,000 tokens; catalog instructions at 4,911 tokens per agent model call).

| Unit | Cost (USD) | Source |
|---|---|---|
| `/decide` call (category, account, intent) | 0.0002 | WP-S4 measured |
| average agent capture (1.25 turns, Flash-Lite) | 0.0068 | WP-S4 recomputed |
| cloud audio, extra per 8 s | 0.00008 | AI_PIPELINE 12 |
| cloud receipt (Flash-Lite) | 0.0028 to 0.004 | AI_PIPELINE 12 |
| question (three model calls) | 0.0080 | WP-S4 recomputed |
| monthly report (3.8 Flash, 2027 prices) | 0.016 | AI_PIPELINE 12 |
| Smart household, 300 entries + 30 questions + 1 report | **about 0.75 a month** | WP-S4 |

What this means for tiers:

- **Decisions calls are cheap but not free at the limit.** A typical household makes about 150 a month (USD 0.03). ARCHITECTURE 4.5 allows 600 a day, which over 30 days would cost USD 3.60, more than Standard yearly earns a month. So each tier gets a **monthly cap** (Standard and Pro 1,000, VIP 2,000), counted on the server in a monthly usage document next to the daily one (`households/{hid}/usage/{month}`). Past the cap, `/decide` answers `{unavailable: true}` and the phone uses on-device classification or local pickers, the existing fallback step 3 in AI_PIPELINE 7, so the entry still saves.
- **Audio seconds are almost free too.** The cost of cloud voice is the agent turn it triggers, not the audio. So voice is metered as a cloud AI capture, not in seconds.
- **The real drivers are agent turns, receipts and questions.** These, plus the Decisions cap, are the metered allowances. Reports are capped too (VIP: monthly, yearly and up to 4 custom-range reports a month).
- **The On-device only mode costs nothing to run.** Charging extra for it would make privacy a luxury and contradict principle 4 in the PRD. It is in every tier.
- **History length costs almost nothing.** Firestore storage for a household is tiny. Hiding old data from a lapsed user would be holding it hostage. History is never gated.
- **Infrastructure** (Firestore, Cloud Run, Storage) per household is not measured. The model below assumes **USD 0.10 a month** per household (0.20 for VIP's bigger households). This is an assumption, to be replaced by WP-83 counters.
- The planned trim of the catalog instructions (AI_PIPELINE 12, about 40% less agent input) would cut the agent share by roughly a third. It is not counted below, so the margins are conservative.

## 2. Feature matrix: every PRD story mapped to a tier

S = Standard, P = Pro, V = VIP. "All" means every tier, including during the trial. During the trial the household has Pro.

| Story | What | Tier | Why |
|---|---|---|---|
| ON-1 | value shown before an account | all | before the paywall |
| ON-2 | sign in with Apple, Google, email | all | |
| ON-3 | create household | all | |
| ON-4 | invite partner | all (2 members); V up to 6 | the partner is the product's core promise; one subscription covers the household |
| ON-5 | accounts with opening balances | all, unlimited | the ledger has to be complete |
| ON-6 | first capture before Home | all | the paywall comes right after this |
| ON-7 | CSV import of history | all | lowers the cost of switching; costs nothing |
| CA-1 | typed capture | all | phone path unlimited; agent path counts as a cloud AI capture |
| CA-2 | voice | all | on-device speech unlimited; cloud voice counts as a cloud AI capture |
| CA-3 | several entries in one message | all | counts as a cloud AI capture (agent path) |
| CA-4 | follow-up question | all | part of the same capture, not counted again |
| CA-5 | receipt photo | all (total); P, V (line-item split) | receipts are capped per tier; the split is a clear Pro upgrade |
| CA-6 | manual form | all, unlimited | never gated, it is the fallback for every limit |
| CA-7 | "Guessed" marks | all | |
| CA-8 | learning from corrections | all | moves captures to the free phone path, which lowers cost |
| CA-9 | duplicate warning | all | mostly deterministic; protects data quality |
| CA-10 | offline capture and queue | all | |
| CA-11 | Siri, Shortcut, widget, share sheet | all | daily habit drives retention; the share sheet with a receipt counts against receipts |
| MO-1 | currency per account, base totals | all | essential for this app (D-43 adds EUR and GBP, see R-5) |
| MO-2 | daily rate prompt | all | |
| MO-3 | transfers | all | |
| MO-4 | loans and debts | all, unlimited | a differentiator; gating it would make the ledger wrong |
| MO-5 | savings goals | S 2; P, V unlimited | upgrade lever without breaking the ledger |
| MO-6 | budgets with 80% and 100% warnings | S 5 budgets, warning at 100%; P, V unlimited, both warnings | same |
| MO-7 | recurring detection | S detect and remind; P, V also add automatically | automation is a Pro value |
| MO-8 | partner settle-up (Later) | P, V when built | a couples feature, so not VIP-only |
| RE-1 | Home | all | |
| RE-2 | Activity, search, filters | all | |
| RE-3 | questions to the AI | S 15, P 40, V 70 a month; on-device basics unlimited | metered: USD 0.008 each |
| RE-4 | edit, undo, change history | all | |
| RE-5 | monthly summary and export | S on-phone summary + CSV; P, V AI-written report + PDF and Excel; V yearly review and up to 4 custom-range reports a month | CSV export is a data right, so every tier has it |
| RE-6 | notification centre and nudges | S essentials; P, V all | |
| PR-1 | private personal accounts | all | partner privacy is a principle |
| PR-2 | On-device only, Smart, Cloud | all | costs nothing; privacy is not a luxury |
| PR-3 | Face ID lock | all | |
| PR-4 | Kurdish, Arabic (Later) | all | language is not a paid feature |
| PR-5 | delete account, export data | all, and after a lapse | required for trust and, in the EU, by GDPR |
| PR-6 | categories editor | all | |
| Later | more than two members | V | the honest headline for VIP: parents, adult children, relatives at home |
| Support | | S in-app help and email; P faster email; V priority email and early access (TestFlight) | the owner works alone; promise only what one person can keep |

## 3. Cost per tier and margin after Apple's cut

**Worst case** = every allowance used in full: cloud captures × 0.0068 + questions × 0.008 + the monthly Decisions cap × 0.0002 + reports + infrastructure. Receipts are inside the capture allowance and cost less than an agent capture. **Typical** = the measured Smart household (USD 0.75) for Pro; Standard is near its capture cap; VIP is a 4-person household with 600 entries in Cloud mode (2.15 per 1,000), 60 questions and reports.

| Tier | Captures | Questions | Decisions | Reports | Infra | **Worst case a month** | Typical a month |
|---|---|---|---|---|---|---|---|
| Standard | 50 × 0.0068 = 0.34 | 15 × 0.008 = 0.12 | 1,000 = 0.20 | 0 | 0.10 | **USD 0.76** | about USD 0.70 |
| Pro | 150 = 1.02 | 40 = 0.32 | 1,000 = 0.20 | 0.016 | 0.10 | **USD 1.66** | about USD 0.85 |
| VIP | 300 = 2.04 | 70 = 0.56 | 2,000 = 0.40 | 0.10 | 0.20 | **USD 3.30** | about USD 2.07 |

Without the monthly Decisions cap, the daily limit alone (600 × 30 days) would add up to USD 3.60 to every tier and make Standard yearly lose money at worst case. The monthly cap is part of the recommendation, not an option. A typical household makes about 150 Decisions calls a month, so 1,000 is still far above normal use.

What the developer keeps a month, and the margin at worst case. Small Business Program (15%), and in brackets at the standard 30% for the first year. Apple removes VAT before its commission, so the lowest-net market is the one with the highest VAT. **The EU column uses 27%, Hungary's standard rate, the highest in the EU** (Your Europe VAT table, last checked 2026-07-13); Finland's 25.5% (vero.fi, page updated 2026-01-01) is the highest among euro-zone countries, and Croatia, Denmark and Sweden are at 25%. The 27% column therefore covers every EU storefront, provided storefronts outside the euro are priced at no less than the euro numbers' value (equalized prices from the US base meet this, since Apple adds local tax). EUR is treated as worth 1 USD, which understates EU proceeds by about 9% (ECB rate of 2026-11-20). The UK uses its proposed GBP prices with GBP taken at a conservative 1.20 USD.

| Plan | US net / month | US worst-case margin | EU at 27% VAT net / month | EU at 27% VAT worst-case margin | UK worst-case margin | US typical margin |
|---|---|---|---|---|---|---|
| Standard monthly $3.99 | 3.39 | 78% (73%) | 2.67 | 72% (65%) | 74% (69%) | 79% |
| Standard yearly $29.99 | 2.12 | 64% (57%) | 1.67 | 55% (45%) | 60% (52%) | 67% |
| Pro monthly $7.99 | 6.79 | 76% (70%) | 5.35 | 69% (62%) | 72% (66%) | 87% |
| **Pro yearly $59.99** | 4.25 | **61%** (53%) | 3.35 | **50.5%** (39.9%) | 58% (48%) | **80%** |
| VIP monthly $14.99 | 12.74 | 74% (69%) | 10.03 | 67% (60%) | 70% (64%) | 84% |
| VIP yearly $119.99 | 8.50 | 61% (53%) | 6.69 | **50.7%** (40.1%) | 58% (49%) | 76% |

Reading the table:

- **At Apple's 15% rate, the 50% worst-case floor holds for every plan in every launch market**, including the highest-VAT EU country. A new developer gets 15% through the Small Business Program. The lowest-net cases are Pro yearly (50.5%) and VIP yearly (50.7%) at 27% VAT; in Finland they are 51.1% and 51.3%.
- **At the 30% rate the floor is 39.9%** (Pro yearly at 27% VAT), so the claim at that rate is "about 40%", not 50%. Apple's EU terms since 2026-10-01 put the standard EU rate at 26% (R-12), between the two columns.
- To reach the floor, Pro went from the first draft's 200 captures and 60 questions to 150 and 40 with a 1,000 suggestion cap, and VIP from 500 and 150 to 300 and 70 with a 2,000 cap. Both still exceed a typical household (about 60 captures, 30 questions and 150 suggestion calls; a 4-person VIP household about 120 captures and 60 questions). The prices did not change.
- At typical use, every plan keeps 58% to 87%; the lowest is Standard yearly at 27% VAT.
- If real use shows the limits are too tight, raise them once WP-83 measures actual cost; the planned trim of the catalog instructions (section 1) lowers the capture cost by roughly a third, which would allow about 50% more captures at the same margin.
- Not counted: support time, the Apple Developer fee (USD 99 a year), an EU/UK GDPR representative (about EUR 420 a year and up, section 8), income tax, and possible 30% US withholding for an individual seller (R-2).

## 4. Plans, trials, and the paywall

### Plan lengths

| Plan | Recommendation | Evidence (section 6) |
|---|---|---|
| Weekly | **Do not offer** | 1-year retention 3.4% (RevenueCat 2025); 65% cancel within 30 days (Adapty 2025); no budgeting leader sells one; weekly revenue figures are driven by games and utilities. A household ledger needs months of data to pay off, and a weekly charge in a money app undermines trust. |
| Monthly | Offer | the entry for people who will not commit; 17% 1-year retention |
| Yearly | Offer, **pre-selected** | 44.1% 1-year retention; 67% of top paywalls pre-select annual (Adapty 2026) |
| Monthly with a 12-month commitment | Not at launch | Apple added it on 2026-04-27, outside the US and Singapore only, iOS 26.4+. The UK regime from January 2027 adds a 14-day cooling-off at each renewal of 12-month contracts. Revisit after a year of data. |
| Lifetime | Not at launch | cloud AI is an ongoing cost; a lifetime plan has no ongoing revenue to pay it |

### Trial

- **1 month free on yearly plans, 2 weeks free on monthly plans.** RevenueCat (2026-09-28): annual plans with 17 to 32-day trials convert at 44.6% and renew at 47.5%, against 24% / 18.3% for trials of 4 days or less. Monthly plans with 10 to 16-day trials: 46.6% / 72%. Category leaders: YNAB 34 days, Copilot 1 month.
- Apple allows one introductory offer per subscription group per Apple Account. All tiers sit in one group, so a household gets one trial.
- The trial costs about USD 0.75 in AI for a typical household.
- **Trial reminder:** send a push notification and an email 3 days before the trial converts. No Apple rule requires this, but it is cheap, it lowers refunds, and the UK regime (January 2027) and the proposed EU Digital Fairness Act are both moving towards a required reminder.

### Subscription group

- One group, "Family Xpense", with three levels: VIP level 1, Pro level 2, Standard level 3. Monthly and yearly products at each level (6 products).
- Upgrades take effect at once with a prorated refund. Downgrades wait for the next renewal. Monthly ↔ yearly at the same level waits for renewal (crossgrade of a different duration). The app must explain this on the plan page.
- **Household entitlement, not Family Sharing.** One partner buys; the server records the entitlement on the household (from App Store Server Notifications V2), and the other partner gets it through membership. Family Sharing only works if both partners are in the same Apple family group, and once turned on it cannot be turned off. Apple's Group Purchases (multi-seat) is announced for winter 2026-27 but not live; revisit for VIP's extra members. Apple does not publish a statement on server-side household sharing; YNAB (up to 6 people) and Copilot (household of 3, planned) sell the same idea, so the review risk looks low, but it is an inference.
- **Grace period:** turn on the 16-day billing grace period.

### Lapse and the free state

- No permanent free tier. A hard paywall with a trial converts about 5 times better (10.7% vs 2.1% install to paid by day 35, RevenueCat 2026), and the US leaders (YNAB, Monarch, Copilot) have no free tier.
- After a trial or subscription ends: **read-only access, CSV export and account deletion stay available forever.** Capture and editing stop. Owner decision: whether manual entry also stays free (cost is only Firestore).

### Paywall rules (Apple and regulators)

The paywall must show, for each plan: the name, the length, what's included, and the full price billed. **The billed amount is the most prominent price**; any "per month" figure is smaller and below it (Apple's subscriptions page). Trial plans state the trial length and the price after it. It also needs links to Terms of Use and the Privacy Policy (in the app and in App Store metadata), and Restore Purchases (3.1.1). No "free-trial toggle" paywall: Apple has rejected them under 3.1.2 since mid-January 2026.

Cancellation: a "Manage subscription" button on the plan page that opens Apple's own screen (`showManageSubscriptions`). Germany's top civil court ruled on 2026-10-21 that the cancel-button duty (§312k BGB) applies to apps; whether it binds a developer whose subscription Apple sells is not verified. A button labelled "Cancel subscription" (German: "Verträge hier kündigen") that opens Apple's screen is a cheap safeguard. California's AB 2863 (since 2025-07-01) requires express consent, an annual reminder and easy online cancellation. The FTC click-to-cancel rule was struck down on 2025-07-08, but ROSCA enforcement continues.

## 5. Upgrade levers: how people move up, honestly

### Why Pro is worth it

1. **More AI, where it saves real time:** 150 cloud captures covers a busy household (the typical one uses about 60), plus receipt line-item splits.
2. **The monthly report written for you**, with PDF and Excel to keep or share.
3. **Automation:** recurring bills added automatically, all nudges (80% budget warnings, goal pace, unusual spending).
4. **No counting:** unlimited budgets and goals, 40 questions a month.

### Why VIP is worth it

1. **The whole family:** up to 6 members (parents, adult children, relatives at home). This is the one thing a two-person household cannot get elsewhere in the plan list.
2. **Room for a big household:** 300 cloud captures, 150 receipts, 70 questions.
3. **The yearly review** and reports for any date range.
4. **Priority support and early access** to new features.

VIP is the honest anchor: its features are real and some households need them, so it is not a decoy. Its price (twice Pro) makes Pro look reasonable without a fake middle option. If "more than two members" is not built by the public launch, VIP has no headline feature. Then launch with Standard and Pro, and add VIP later. Adding a higher level to the subscription group later is easy (owner decision).

### Where the upgrade moments are

None of them sits between the user and Save. The capture card never shows a paywall.

| Moment | What the user sees |
|---|---|
| End of onboarding, right after the first capture (ON-6) | The main paywall: three plans, Pro yearly pre-selected, trial timeline ("today: full access · day 27: reminder · day 30: first charge"). Adapty: onboarding paywalls start 53% of revenue, and RevenueCat: 50.6% of conversions happen on day 0. |
| Cloud allowance at 80% | A quiet card on Home: "You've used 40 of 50 AI captures this month. Resets on 1 December." Dismissible. |
| Cloud allowance used up, mid-capture | The capture continues on the phone path; anything the phone cannot settle opens the manual form, as when offline. After saving, one note: "AI captures reset on 1 December. Pro includes 150 a month." Shown once per month. |
| Receipt saved on Standard | In the entry's detail (not the capture card): "Split by category" chip with a small Pro badge. |
| Recurring bill detected on Standard | The offer card shows "Remind me" and "Not now"; "Add automatically" carries a Pro badge. |
| 1st of the month | Standard sees its summary, with "See the written report" as a Pro preview. During the trial everyone gets the full report once. |
| Creating the 6th budget or 3rd goal | A sheet explaining the limit, with Pro. |
| Inviting a third member | A sheet explaining VIP. |
| Settings → Plan | Current plan, usage meters, renewal date, Manage subscription, Restore. |

### What not to do

No countdown timers, no "Most popular" badge until the data supports it ("Recommended" is honest), no pre-ticked extras, no hidden close button, no free-trial toggle, no monthly-equivalent price larger than the billed price, no extra screens before cancelling in the app.

### Apple tools worth using (all free)

- **Win-back offers:** for example 50% off the first month back, two months after a lapse.
- **Retention messages** (2026-11-04): a message on Apple's cancel-confirmation screen, for example "switch to Standard instead". Respect the UK and German rule of no dissuading offers in the cancel flow, so use a plan-switch message, not pressure.
- **Offer codes:** for partners, reviewers and the first users (up to 1 million redemptions a quarter).
- **Billing grace period:** 16 days.

### Billing back end

| Option | Price | Note |
|---|---|---|
| **StoreKit 2 + App Store Server API + Server Notifications V2, own code** (recommended) | free | The server already exists (Genkit Dart on Cloud Run) and needs a household entitlement anyway; Flutter's first-party `in_app_purchase` package is free. |
| RevenueCat | free up to USD 2,500 monthly tracked revenue, then 1% (revenuecat.com/pricing) | Faster paywall experiments and analytics. One RevenueCat page still says USD 1,000; check before relying on it. |
| Adapty | free under USD 5,000 a month, then 1% (Adapty blog, Feb 2026) | Same category. Third-party sites still show older prices. |

None is added by this document.

### Measure after launch

Trial start rate, trial-to-paid, plan mix, refunds, 1st and 2nd renewal, allowance use by tier (to tune the limits), upgrades and downgrades. Analytics carry counts only, never amounts or text (PRD 7).

## 6. Market evidence

### Competitors (USD unless shown)

| App | Monthly | Yearly | Tiers and notes | Source date |
|---|---|---|---|---|
| YNAB | $14.99 (€15.49, £12.99) | $109 (€119, £99) | one plan; 34-day trial; up to 6 people; no AI | ynab.com/pricing, ©2026; App Store |
| Monarch | $14.99 | Core $99.99, Plus $199.99 | 7-day trial; not on the German App Store | monarch.com/pricing, ©2026 |
| Copilot Money | $18 on the App Store | $109 | one plan, AI included; household of 3 "coming" | App Store v8.7.2, 2026-11-04 |
| Rocket Money | Premium pay-what-you-want; Premium+ $15 | – | AI assistant only in the top tier | help.rocketmoney.com, Nov 2026 |
| PocketGuard | $12.99 | $74.99 | 7-day trial | [3P] 2026 reviews |
| Goodbudget | $10 | $80 | free tier 2 devices; Premium 5 devices | help page dated 2020-02-01, prices match 2026 reviews |
| Spendee | Plus $3.99, Premium $7.99 | $27.99, $44.99 | shared wallets from Plus | spendee.com/premium, undated |
| Wallet (BudgetBakers) | $5.99 (€5.99, £5.49) | about $29.99 (€29.99, £24.99) | | App Store 2026-11-13 |
| Toshl | Pro $2.99, Medici $4.99 | $19.99, $39.99 | 30-day trial | toshl.com + [3P] Adapty snapshot, date unknown |
| Cleo | Plus $5.99, Pro $8.99, Builder $14.99 | – | three tiers; advanced AI from Pro up | [3P] 2026-10-26 |
| Emma (UK) | Plus £4.99, Pro £9.99, Ultimate £14.99 | £41.99, £83.99, £124.99 | three-tier ladder of the kind proposed here | help.emma-app.com, 2026-09-15 |
| Snoop (UK) | Plus £5.99 | £47.99 | | App Store, Nov 2026 |
| Outbank (DE) | €3.99 | €39.99 | | [3P] 2026-07 |
| AI-capture trackers (Savi, SpendSmart, AIXpense, Expense Easy) | $3.99–7.99 | $29.99–69.99 | voice and receipts metered or Premium | App Store, Nov 2026 |

Patterns: partner-capable bank-sync apps charge $80 to $109 a year; AI-capture trackers $20 to $70; Emma shows a three-tier ladder at about £42 / £84 / £125 works in Europe. None of the budgeting leaders sells a weekly plan. Partner sharing is included in the base price at YNAB, Goodbudget and Copilot.

Could not verify: 1Money and Money Lover subscription prices; official PocketGuard and Cleo pages (blocked); Monarch's current partner terms and AI gating; Copilot's $9 vs $18 monthly discrepancy; whether Honeydue still operates; Finanzguru's yearly price.

### Plan length, trials, conversion

| Fact | Value | Source |
|---|---|---|
| 1-year retention by plan | yearly 44.1%, monthly 17.0%, weekly 3.4% | RevenueCat SOSA 2025 |
| Still paying at day 380 | annual 19.9%, monthly 14.2%, weekly 5.5% | Adapty, 2026-03-26 |
| Weekly cancellations | 65% within 30 days | Adapty, 2025-07-16 |
| Revenue share of weekly plans (all categories) | 43.3% (2023) → 55.5% (2025) | Adapty, 2026-03-26 |
| Plans sold | 42% monthly, 34% yearly; Productivity 77% yearly | RevenueCat SOSA 2026 |
| Trial-to-paid by length | ≤4 days 25.5%, 5–9 days 37.4%, 17–32 days 42.5% | RevenueCat SOSA 2026 |
| Trials cancelled on day 0 | 3-day 55.4%, 7-day 39.8%, 14-day 35.7%, 30-day 31.1% | RevenueCat SOSA 2026 |
| Annual plan by trial length (convert / renew) | ≤4 d 24% / 18.3%; 17–32 d 44.6% / 47.5% | RevenueCat, 2026-09-28 |
| Install to paid, day 35 | hard paywall 10.7%, freemium 2.1% | RevenueCat SOSA 2026 |
| Refunds | annual 4.2%, weekly 2.6% (Adapty 2025); hard paywall 5.8% vs freemium 3.4% (RevenueCat 2025) | as named |
| Median prices | weekly $5.99, monthly $10, yearly $34.80 | RevenueCat SOSA 2026 |
| Annual pre-selected | 67% of top paywalls; ARPU +25–40% in winning tests | Adapty, 2026-11-01 |
| Onboarding paywall | about 4× the conversion of later paywalls; 53% of revenue | Adapty, 2026-11-01 |
| Anchor | a higher plan next to annual lifted revenue 10–15% in winning tests | Adapty, 2026-11-01 |

Caveats: RevenueCat and Adapty sell billing tools. RevenueCat files Finance under "Utilities", so there is no clean finance-only benchmark. No independent study compares three-tier and one-tier paywalls.

## 7. Getting paid (URGENT)

### (a) Individual or company enrollment

| | Individual (owner, living in Iraq) | Organization (owner's US company) |
|---|---|---|
| Fee | USD 99 a year | USD 99 a year |
| Can it finish today? | Probably. Needs the owner's legal name, address (no P.O. box), phone, own payment card; Apple may ask for ID in the Apple Developer app. | **No.** Needs a D-U-N-S number (free; up to 5 business days at D&B plus up to 2 for Apple), legal-entity status (no DBA), legal binding authority, a working public website **on the company's domain** and an email on that domain; possibly notarized documents. |
| Seller name on the App Store | the owner's personal legal name | the company name |
| Known problems | Apple publishes no list of supported countries, only "Enrollment may not be supported in certain regions, for example due to sanctions or other restrictions." One Iraq-based developer got "Your enrollment could not be completed" in March 2026 (forum, no reply). **Iraq support not verified.** | A foreign-owned Wyoming LLC using a registered agent's shared virtual address and an un-notarized operating agreement was declined as "final" (forum, Aug to Sep 2026). |

### (b) Banking and payouts

- Apple publishes no list of bank countries: "If you can't identify your bank in App Store Connect, it may be that Apple can't send payments to that bank." **Whether any Iraqi bank appears is not verified**; an Iraq-based developer in April 2026 reported no supported banking setup (forum, no reply).
- Iraq is not in Apple's payment-threshold table, so the default USD 40 minimum would apply (US, UK and EU banks: USD 0.02).
- One bank only; the account should belong to the enrolled individual or company (Apple's pages are inconsistent on whether the holder name must match). No intermediary banks.
- Apple pays within 45 days after the end of each fiscal month (Schedule 2 §3.5, updated 2026-10-13).
- Apple says nothing about fintech or virtual accounts, or about whether a US company may use a non-US bank account.

### (c) A US business bank account while living in Iraq

| Provider | Owner living in Iraq? | Source |
|---|---|---|
| Mercury | No, Iraq is a prohibited country (by residence) | support.mercury.com, via search snippets (page blocked the fetch) |
| Relay | No, Iraq is listed and the rule covers any beneficial owner | relayfi.com help, updated 2026-08-11 |
| Wise Business | No, Iraq is a country where you can't register | wise.com/help/articles/2978049, via snippets |
| Novo | No, every owner needs an SSN, US address and US phone | novo.co help |
| Airwallex | Not verified; restricted-country list not readable; Iraq is restricted for incoming SWIFT | help.airwallex.com |
| Brex | Not verified; needs a US entity with an EIN | brex.com legal |
| Payoneer | Not verified for Iraq; Payoneer's own page says App Store Connect can pay into its US receiving account | payoneer.com vendor page, undated |

No first-hand report was found of Apple paying into Mercury or Wise.

### (d) Tax

- **Individual outside the US:** Form W-8BEN in App Store Connect. **The US has no income tax treaty with Iraq** (IRS treaty list, reviewed 2026-01-03), so the default 30% withholding on US-source income could apply. Apple withholds when it "reasonably believes" tax is due (Schedule 2 §3.7). **Whether Apple withholds 30% on an Iraq resident's US sales is not verified.** Ask Apple Finance and a tax adviser.
- **Foreign-owned single-member US LLC:** many 2026 forum threads report App Store Connect offers only a W-9 to such LLCs, with Finance cases unanswered for weeks or months, blocking the Paid Apps Agreement.
- **Form 5472 already applies to the owner's LLC** if it is a foreign-owned single-member LLC: a pro forma Form 1120 with Form 5472 every year, penalty USD 25,000 per failure plus 25,000 if not fixed within 90 days of an IRS notice (IRS instructions, rev. 12/2024). This is true whether or not the LLC ever sells an app. **The owner should confirm with a US tax adviser that these filings are up to date.**
- **Sales tax and VAT:** Apple collects and remits tax in the US, the UK and all 27 EU states (Schedule 2 Exhibit B, updated 2026-11-18). EU and UK prices include VAT; US prices exclude sales tax, which is added at checkout. California taxes App Store software from 2027-01-01 (Apple news 2026-11-17). The developer files no VAT or sales tax returns for App Store sales.

### (e) EU Digital Services Act: trader status

- Since 2025-02-17, apps without a declared trader status are removed from the EU App Store. A subscription seller is a trader.
- Traders must verify an **address, phone number and email, shown publicly on the EU product page**.
  - **Individual:** an address or a P.O. box (with a bill or receipt proving the link). The owner's name is already public as the seller.
  - **Organization:** the address comes from the D-U-N-S record, so a registered-agent address would appear if that is the D-U-N-S address. Apple says nothing about registered agents.

### (f) Ending with the company as seller

Two Apple mechanisms exist, and they are different:

- **Account conversion** changes the membership itself from individual to organization. Apple: "If you'd like to update your membership from an individual to an organization, please submit a request." You must be the founder or cofounder and give the organization's D-U-N-S number; business documents may be requested (Apple, "Updating your account information", undated). Apple does not say whether apps stay on the account or whether the seller name changes. It does say that changing an *organization* name "will update your vendor name across all your apps", and that it resets the identifier-for-vendor (IDFV) for existing users, which "cannot be undone".
- **App Transfer** moves one app between two accounts. **The app must have at least one version already released to the App Store** (App transfer criteria, undated, re-read 2026-11-22; paraphrased, the page was read through a summarising fetch). Ratings and reviews stay with the app and users keep receiving updates; apps with auto-renewable subscriptions must use an app-specific shared secret (Overview of app transfer, undated; paraphrased the same way). Neither page says whether existing subscribers keep renewing or whose name appears as seller afterwards.
- **Sign in with Apple across teams:** each user's identifier is scoped to the developer team, so it changes when the app moves to another team. The sending team generates a *transfer identifier* for each user through Apple's `userMigrationInfo` endpoint, and the receiving team "needs to exchange the transfer identifiers for new team-scoped identifiers within 60 days of accepting the app transfer" (Apple documentation, "Transferring your apps and users to another team", undated). This needs server code on both sides. Private relay email addresses are team-scoped too.

So **App Transfer cannot be used before the first release**. The first version of this document said it could; that was wrong.

Paths that end with the company as seller:

| Path | How | When it works | Sign in with Apple users | Subscribers | Trade-offs |
|---|---|---|---|---|---|
| **1. Convert the account before launch** | Enroll as an individual today; when the company has a D-U-N-S number, a website and email on its domain, and a bank account Apple pays, ask Apple Support to convert the membership | any time, no release needed | unchanged if the team stays the same (inference: conversion updates the existing membership; Apple does not state that the Team ID is kept) | none yet | one account, no migration. But Apple publishes no procedure or timeline; forum reports of conversions cancelled partway (threads 844503, 840067) and of the seller name on already released apps staying personal (thread 813734, January to October 2026). Converting before any release avoids the last problem only if Apple's reported behaviour is limited to released apps, which is not verified. |
| **2. Release from a separate company account** | Individual account for development and TestFlight only, under a separate bundle id (for example `com.bitrelia.familyxpense.dev`). The company enrolls as an organization and creates the production app record with `com.bitrelia.familyxpense` | as soon as the company account is approved, before launch | the two partners sign in again; their accounts start fresh in the production Firebase project, which D-38 creates empty anyway (or they bring data over with CSV export and import) | none yet | no Apple-side migration at all; costs a second USD 99 membership and a small build change (a second bundle id and its Firebase app). Depends on the company passing Apple's organization checks, the same blockers as enrolling the company today. Not verified: whether `com.bitrelia.familyxpense`, already used with the free Personal Team (ENVIRONMENTS 3.7), can be registered by a different team; keep it unused in the paid individual account and check in the developer portal. |
| **3. Release under the individual, transfer later** | Launch with the owner as seller; when the company account exists, use App Transfer | only after a version is released | every user must be migrated with transfer identifiers within 60 days of the transfer; needs code on the server and in the app before the transfer | not stated by Apple; the shared-secret requirement suggests subscriptions continue, but this is not verified | the most expensive path, and it grows with every user. Users see the seller name change. Financial reports split at the transfer date. |
| **4. Wait and enroll only the company** | Skip the individual account | when the company is approved (D-U-N-S up to about 7 business days, plus website, domain email, possible documents) | n/a | n/a | delays D-39 (Sign in with Apple, App Attest, TestFlight) by weeks or more, and the company still has no bank account that accepts an owner living in Iraq. |
| **5. Stay individual** | The owner is the seller for good | now | n/a | n/a | simplest. Personal name, EU address and phone are public; payouts to Iraq unverified; possible 30% US withholding (R-2). |

### Recommendation

1. **Today:** enroll as an individual. This unblocks D-39 (Sign in with Apple, App Attest, TestFlight).
2. **Today:** register a development bundle id (for example `com.bitrelia.familyxpense.dev`) in the individual account and use it for TestFlight. Do not create an App Store Connect record or upload a build with `com.bitrelia.familyxpense` from the individual account until the seller is decided. This keeps paths 1, 2 and 5 open at no cost. The build change (a second bundle id and Firebase iOS app) is a small follow-up task, not part of this document.
3. **Today, in parallel:** request a free D-U-N-S number for the US company through Apple's lookup tool.
4. **Right after enrollment:** open App Store Connect → Agreements, Tax and Banking; start the Paid Apps Agreement and check whether Iraq and the owner's bank can be selected, and what the tax questionnaire offers. Record the result in DECISIONS. This is the single most important unknown.
5. **If no Iraqi bank is accepted:** try a Payoneer USD receiving account (unverified for Iraq), or a bank account in a country where the owner can legally open one.
6. **Before the public launch, choose the seller.** If it should be the company and the company has a bank account Apple pays: try path 1 (conversion) first, because it keeps one account; if Apple refuses or it stalls, use path 2. Use path 3 only if the app is already released. If the owner is content to be the seller, path 5.
7. **This week:** ask a US tax adviser about Form 5472 for the existing LLC and about withholding as an individual.

## 8. Risks and open questions

| ID | Risk or question | Effect | What to do |
|---|---|---|---|
| R-1 | **No way to receive Apple's payouts** from Iraq (bank not selectable, fintechs refuse Iraq residents) | no revenue at all | step 4 of the section 7 recommendation right after enrolling; Payoneer; a company bank account |
| R-2 | **30% US withholding** on an individual with no treaty | US net drops by 30% of proceeds; Pro and VIP yearly worst-case margins in the US fall from 61% to 44% and 45% | confirm with Apple Finance and a tax adviser; if it applies, sell through an entity that can claim a lower rate, or price up |
| R-3 | **Publishing a personal address and phone** on the EU App Store | privacy, harassment | P.O. box with proof; or use the company with its own address |
| R-4 | **VIP's headline feature is not built** (more than two members is "Later") | VIP looks like a decoy | pull member expansion into the public release, or launch with two tiers |
| R-5 | **US/EU users need USD, EUR and GBP** (today IQD and USD); "more currencies" is Later | EU users cannot use their own currency | add EUR and GBP before the public launch |
| R-6 | **EU user data stored in Doha** (`me-central1`, D-18). Qatar has no EU adequacy decision, so this is a third-country transfer needing SCCs and a transfer assessment | GDPR exposure | host EU and UK households in `europe-west1` or `europe-west3`; needs an architecture decision |
| R-7 | **GDPR Article 27 representative** needed for EU (and UK) users when the seller has no EU establishment | legal duty | Prighter from EUR 420 a year (pricing page 2026-08-24); VeraSafe USD 2,700 a year; option only, not added |
| R-8 | **US users expect bank sync** (YNAB, Monarch, Copilot all have it); Family Xpense does not | lower conversion in the US | position as "no bank login needed, private, built for two"; price below bank-sync apps |
| R-9 | **UK subscription regime from January 2027**: reminders by email or another durable medium, 14-day cooling-off after a trial converts and after each renewal, easy online exit | refunds, extra emails | send trial and renewal reminders by email; the details are not yet published |
| R-10 | **Germany's cancel button** and the **EU withdrawal button** (since 2026-06-19) may bind the developer even when Apple sells the subscription | fines, warning letters | "Cancel subscription" button opening Apple's screen; legal check |
| R-11 | **Server-side household sharing** of one Apple subscription is an inference, not an Apple statement | review rejection (low) | say "covers your household" on the paywall; keep Family Sharing as the fallback |
| R-12 | **EU commission terms changed on 2026-10-01** (Apple newsroom, August 2026: 26% standard, 15% Small Business Program and after a subscriber's first year); the two research notes describe the alternative-terms split differently | EU margin | confirm in App Store Connect when signing the EU terms; the margin table already covers 15% and 30% |
| R-13 | **Prices are a first guess**; prices can be lowered at once, but raising them needs consent in some EU states (Austria, Germany, Poland since 2025-08-04) | lost revenue if too low | start where recommended; test before raising |
| R-14 | **Abuse**: one household with many Apple accounts to restart trials | small AI cost | trial is once per Apple Account per group; the server can also refuse a second trial per household (StoreKit intro-eligibility JWS, 2025) |

Open questions for the owner are in [DECISIONS.md](../DECISIONS.md) section 4.

## 9. Iraq (short note; not a launch market under D-43)

- The App Store works in Iraq and is priced in USD, like the US. Apple lists only "most credit and debit cards" as payment in Iraq: no carrier billing, no Apple Pay. Iraqi bank cards have failed on Apple accounts before (Rest of World, 2023). Google Play does take Zain, Asiacell and Korek phone billing.
- The dinar's official rate moved from 1,320 to 1,520 per USD on 2026-10-07 (Shafaq News). World Bank GNI per person: USD 5,690 (2025). Spotify Individual in Iraq costs 4,900 IQD a month.
- If Iraq is added later, set Iraq prices by hand (for example Standard $1.99, Pro $3.99), since a hand-set storefront price is allowed and an equalized one would equal the US price.

## 10. Sources

All read on 2026-11-22. Full research notes, with more detail, are in the shared notes folder of this planning group (`subs-research-*.md`).

**Apple**
- App Review Guidelines (3.1.1, 3.1.2(a)–(c), 5.6, 2.5.19), last updated 2026-10-16: https://developer.apple.com/app-store/review/guidelines/
- Auto-renewable subscriptions (levels, paywall checklist, billed amount most prominent), undated: https://developer.apple.com/app-store/subscriptions/
- Apple Developer Program License Agreement, Schedule 2 §3.4, §3.5, §3.7, §3.8; Schedule 2 updated 2026-10-13, exhibits 2026-11-18: https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- Introductory offers, undated: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions
- Intro-offer eligibility JWS, undated: https://developer.apple.com/documentation/storekit/product/purchaseoption/introductoryoffereligibility(compactjws:)
- Promotional offers, undated: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions
- Offer codes, undated: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes ; offer codes for all IAP types, news 2025-10-29
- Win-back offers, undated: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers/
- Monthly billing with 12-month commitment, news 2026-04-27: https://developer.apple.com/news/?id=agq42lxe
- Family Sharing, undated: https://developer.apple.com/documentation/storekit/supporting-family-sharing-in-your-app
- Group Purchases, news 2026-09-16: https://developer.apple.com/news/?id=likeohx4
- Retention messages, news 2026-11-04: https://developer.apple.com/news/?id=fk9ps3gv
- Small Business Program, undated: https://developer.apple.com/app-store/small-business-program/
- EU changes, Apple Newsroom, August 2026: https://www.apple.com/newsroom/2026/08/apple-announces-changes-for-apps-in-the-european-union/
- Subscription prices and tax updates, news 2025-08-21: https://developer.apple.com/news/?id=yo2104n5 ; tax and price changes, news 2026-11-17: https://developer.apple.com/news/?id=4o5ie73a
- Set a price, undated: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- Price-increase thresholds (Iraq in USD), undated: https://developer.apple.com/help/app-store-connect/reference/auto-renewable-subscription-price-increase-thresholds
- Refunds, 2026-09-17: https://support.apple.com/en-us/118223
- Enrollment, undated: https://developer.apple.com/programs/enroll/ ; https://developer.apple.com/help/account/membership/program-enrollment/ ; https://developer.apple.com/support/enrollment/ ; identity verification: https://developer.apple.com/help/account/membership/identity-verification/
- D-U-N-S, undated: https://developer.apple.com/support/D-U-N-S/
- Banking information, undated: https://developer.apple.com/help/app-store-connect/reference/banking-information ; minimum payment threshold: https://developer.apple.com/help/app-store-connect/reference/minimum-payment-threshold ; enter banking information: https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information
- US tax information, undated: https://developer.apple.com/help/app-store-connect/provide-tax-information/provide-us-tax-information
- DSA trader requirements, undated: https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements ; removal date, news 2025-02-17: https://developer.apple.com/news/upcoming-requirements/?id=02172025a
- App Transfer, undated, re-read 2026-11-22 for the released-version rule: https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer ; criteria: https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria
- Sign in with Apple, transferring apps and users to another team (transfer identifiers, 60-day window), undated: https://developer.apple.com/documentation/signinwithapple/transferring-your-apps-and-users-to-another-team
- Updating your account information (individual to organization), undated: https://developer.apple.com/support/account/
- Developer forum threads (anecdotes, [3P] in effect): 817574 (Iraq enrollment, 2026-03), 822904 (Iraq banking, 2026-04), 844256 (foreign-owned LLC declined, 2026-08/09), 840067, 813734 (seller name after conversion, 2026-01 to 10), 844503, 826739, 852138, 845983, 847336 (W-9 only for foreign-owned LLCs, 2026)
- Apple payment methods by country (Iraq: cards only), 2026-11-20: https://support.apple.com/en-us/111741 ; App Store availability, 2026-10-30: https://support.apple.com/en-us/118205

**Tax and law**
- IRS Form 5472 instructions, rev. 12/2024: https://www.irs.gov/instructions/i5472
- IRS tax treaties A to Z (no Iraq), reviewed 2026-01-03: https://www.irs.gov/businesses/international-businesses/united-states-income-tax-treaties-a-to-z
- IRS NRA withholding (30%), reviewed 2026-03-14: https://www.irs.gov/individuals/international-taxpayers/nra-withholding
- IRS W-9 instructions, rev. 03/2024: https://www.irs.gov/instructions/iw9
- Your Europe, VAT rules and rates (standard rates; Hungary 27%, Finland 25.5%), last checked 2026-07-13: https://europa.eu/youreurope/business/taxation/vat/vat-rules-rates/index_en.htm
- Finnish Tax Administration, rates of VAT (25.5%), page updated 2026-01-01: https://www.vero.fi/en/businesses-and-corporations/taxes-and-charges/vat/rates-of-vat/
- EU adequacy decisions (no Qatar), newest item 2026-11-16: https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection/adequacy-decisions_en
- EDPB Guidelines 05/2021 on Article 3 and transfers: https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-052021-interplay-between-application-article-3_en
- [3P] UK subscription regime brought forward to January 2027: Stephenson Harwood, 2026-08-24; DWF, 2026-10-22; Reed Smith, 2026-04-09
- [3P] EU Digital Fairness Act proposal, Euronews, 2026-11-11: https://www.euronews.com/2026/11/11/eu-targets-subscription-traps-addictive-design-and-hidden-fees-with-new-digital-rules
- [3P] BGH cancel button applies to apps (I ZR 243/25, 2026-10-21): ra-plutte.de, updated 2026-11-17; it-recht-kanzlei.de, 2026-11-18
- [3P] FTC click-to-cancel vacated 2025-07-08: https://www.gtlaw.com/en/insights/2025/7/eighth-circuit-vacates-ftcs-click-to-cancel-rule ; ROSCA enforcement: Holland & Knight, 2025-09
- [3P] California AB 2863, in force 2025-07-01 (law-firm summaries)
- Prighter pricing, 2026-08-24: prighter.com/pricing ; VeraSafe EU representative, ©2026: info.verasafe.com/eu-data-protection-representative-program

**Banking providers**
- Relay restricted countries, updated 2026-08-11 (relayfi.com help); Mercury prohibited countries (support.mercury.com, snippets); Wise unsupported countries (wise.com/help/articles/2978049, snippets); Novo non-US owners (novo.co/help); Airwallex eligibility (help.airwallex.com); Payoneer for app developers (payoneer.com, vendor page, undated)

**Market data**
- RevenueCat State of Subscription Apps 2026: https://www.revenuecat.com/state-of-subscription-apps ; 2025: https://www.revenuecat.com/state-of-subscription-apps-2025
- RevenueCat, free-trial length, 2026-09-28: https://www.revenuecat.com/blog/growth/free-trial-length
- RevenueCat, toggle paywall rejections, 2026-02-09 (updated 2026-04-23): https://www.revenuecat.com/blog/growth/r-i-p-toggle-paywall-we-hardly-knew-ye/
- RevenueCat benchmarks 2026, 2026-03-19: https://revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026
- Adapty, weekly vs monthly vs annual, 2026-03-26: https://adapty.io/blog/weekly-monthly-annual-subscription-plan/
- Adapty, State of In-App Subscriptions 2025, 2025-07-16: https://adapty.io/blog/state-of-in-app-subscriptions-2025-in-10-minutes/
- Adapty, paywall optimization tests, 2026-11-01: https://adapty.io/blog/paywall-optimization-tests/
- RevenueCat pricing: https://www.revenuecat.com/pricing (read 2026-11-22) ; Adapty pricing 2026, Feb 2026: https://adapty.io/blog/adapty-new-pricing-2026/
- Competitor pages as named in section 6 (ynab.com/pricing; monarch.com/pricing; copilot.money/pricing and App Store id1447330651; help.rocketmoney.com; spendee.com/premium; goodbudget.com help; help.emma-app.com; App Store listings for Wallet, Snoop, Toshl, Money Lover, AI trackers)

**Iraq**
- Apple payment methods (2026-11-20) and App Store availability (2026-10-30), above; Apple Pay countries, 2026-10-27: https://support.apple.com/en-us/102775
- Google Play carrier billing in Iraq, undated: https://support.google.com/googleplay/answer/2651410?co=GENIE.CountryCode%3DIQ
- Rest of World, 2023-02-08: https://restofworld.org/2023/iraq-digital-payments/
- Shafaq News, dinar rate, 2026-10-07: https://shafaq.com/en/Economy/Iraq-raises-official-dollar-rate-to-1-520-IQD
- World Bank GNI per capita, Iraq, updated 2026-11-11: https://api.worldbank.org/v2/country/IRQ/indicator/NY.GNP.PCAP.CD
- Spotify Iraq, undated: https://www.spotify.com/iq-en/premium/

### What could not be verified

- Whether Iraq is supported for Apple Developer enrollment, and whether any Iraqi bank can receive Apple payouts.
- Whether Apple withholds 30% on US sales for an Iraq-resident individual.
- Whether Payoneer, Airwallex or Brex accept an owner living in Iraq; whether Apple pays reliably into any fintech account.
- Whether existing subscribers keep renewing through an App Transfer, and whose name is the seller afterwards.
- Whether an individual-to-organization conversion keeps the Team ID, the apps and the seller name, and how long it takes.
- Whether the bundle id `com.bitrelia.familyxpense`, used with the free Personal Team, can be registered by another team.
- Apple's current default EUR, GBP and CHF prices for a US base price (the table is only in App Store Connect); the EU and UK prices above are set by hand, which Apple allows.
- Whether the UK regime, the EU withdrawal button and Germany's §312k bind the developer when Apple sells the subscription.
- Infrastructure cost per household (assumed USD 0.10 a month).
- Whether server-side household sharing of one Apple subscription is explicitly allowed (inferred).
