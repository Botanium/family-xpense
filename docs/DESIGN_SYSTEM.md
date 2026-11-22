# Family Xpense: Design System (Signal)

Direction chosen by the owner: **Signal**. Stone canvas, Geist with Geist Mono figures, ink black, one signal orange, Liquid Glass on the control layer only. Light theme as drawn on the v3 prototype page; graphite dark theme designed here to the same rules.

Token values in the light theme are taken from the three Signal artboards (Home, Ask, Receipt). Values marked *new* did not exist in the prototype and are proposed here. Dark values are all new.

## 1. Rules of the language

1. **Glass is for controls only:** tab bar, Ask button, capture dock, floating top buttons and pills, bottom sheets, the undo toast. Never glass on glass.
2. **Content is solid.** Balances, slips, lists and charts sit on the canvas or on an opaque slip. Figures never sit on glass.
3. **One hero number per screen, one thin chart, hairlines instead of boxes.**
4. **Orange means "act or live".** It fills the Ask button and the mic, and marks live or now states (recording waveform, scan frame, today's bar, unread dot, nudge dot). It is never text, never a second button colour, never a category colour. The primary button is ink.
5. **Figures are mono.** Every amount, date stamp, percentage and uppercase label uses Geist Mono.
6. **Colour coding is a dot or a figure colour, never a filled tile,** and always comes with a second signal (sign, label or icon).

## 2. Structure in code

Follows the `design-system-structure` skill: primitives → semantic slots on `ThemeExtension`s → components. No raw colour, radius, duration or font size outside `app/lib/core/theme/`; a grep gate in CI enforces it.

```
app/lib/core/theme/
  primitives.dart        Tier 1: raw values, named by measured value (stone92, ink04, orange60 …)
  xp_colors.dart         Tier 2: semantic colour slots (ThemeExtension, asserting of())
  xp_type.dart           text styles
  xp_space.dart          spacing, sizes, radii
  xp_glass.dart          glass recipes per variant
  xp_motion.dart         durations, curves, reduced-motion resolution
  xp_elevation.dart      the two shadows
  app_theme.dart         buildAppTheme(brightness): hand-authored ColorScheme + all extensions
app/lib/core/ui/         components (section 8)
```

`ThemeData` is built once per brightness with a hand-authored `ColorScheme` (never `fromSeed`), every extension attached to both themes, and `themeAnimationStyle: AnimationStyle.noAnimation`. Theme mode is restored before first paint.

Flutter 3.50 deprecates the bundled `material.dart` and `cupertino.dart` in favour of the `material_ui` and `cupertino_ui` packages. `WP-00` adopts the standalone packages if `a2ui_flutter 0.4.0` builds against them, and records the result (DECISIONS D-22).

## 3. Colour

### 3.1 Semantic slots

| Slot | Light | Dark (graphite) | Use |
|---|---|---|---|
| `canvas` | `#ECEBE7` | `#161617` | screen background |
| `surface` | `#FAF9F6` | `#1F1F21` | slips, solid fallback for glass |
| `surfaceSunken` *new* | `#E3E1DC` | `#101011` | input wells, pressed rows |
| `ink` | `#0B0B0C` | `#F2F1ED` | primary text, figures, icons, chart bars |
| `inkSecondary` | `#67665F` | `#A3A199` | labels, meta, mono captions |
| `inkTertiary` | `#7A7871` (prototype `#9C9A93`, see review item 1) | `#77756E` | large-figure decimals only |
| `inkOnAccent` | `#0B0B0C` | `#0B0B0C` | icon on orange |
| `hairline` | `#D8D6D0` | `#2C2C2F` | separators |
| `hairlineSoft` | `#DEDCD6` | `#252527` | list row separators |
| `leader` | `#A9A7A0` | `#4A4A4E` | dotted leaders |
| `perforation` | `#BDBAB2` | `#3A3A3D` | dashed slip rules, switch off-track |
| `accent` | `#FF5B1A` | `#FF5B1A` | Ask, mic, live marks |
| `accentHalo` | `#FF5B1A` at 16% | `#FF5B1A` at 22% | ring around the recording button |
| `income` | `#127047` | `#4CC38A` | positive figures, income dot, "on-device" chip text |
| `saved` | `#2B59FF` | `#7C9BFF` | savings dot |
| `loan` *new* | `#A15C00` | `#E0A04A` | loans and debts dot, due markers |
| `danger` *new* | `#B3261E` | `#FF8A80` | destructive actions, over-budget |
| `primaryFill` | `#0B0B0C` | `#F2F1ED` | primary button |
| `onPrimaryFill` | `#FAF9F6` | `#0B0B0C` | primary button label |
| `selectedFill` | `#0B0B0C` | `#F2F1ED` | selected chip |
| `tabActiveWell` | ink at 7% | white at 10% | active tab pill |
| `tabInactive` | `#3F3E3A` (prototype `#56554F`, see review item 6) | `#B4B2AA` | inactive tab icon and label |
| `scanBackdrop` | `#1C1C1E` | `#000000` | camera screen |
| `receiptPaper` | `#F4F2EC` | `#F4F2EC` | receipt preview |

Category colours are keys, not hexes (`colorKey` on a category). Eight keys, each with a light and a dark value, used only as 7 pt dots and chart segments: `cat1 … cat8`. Candidate values: `#127047`, `#2B59FF`, `#A15C00`, `#8A3FFC`, `#C2255C`, `#0E7490`, `#5F6B00`, `#6B5B4B` (light) and their lightened counterparts (dark). `WP-03` validates each at 3:1 or better against `canvas` and `surface` in both themes.

### 3.2 Contrast (computed from the hex values)

| Pair | Ratio | Needs |
|---|---|---|
| `ink` on `canvas` (light) | 16.6 : 1 | 4.5 |
| `inkSecondary` on `canvas` (light) | 4.8 : 1 | 4.5 |
| `inkTertiary` `#7A7871` on `canvas` (light) | 3.7 : 1 | 3.0, large figures only |
| `income` on `canvas` / on `surface` (light) | 5.1 : 1 / 5.8 : 1 | 4.5 |
| `inkOnAccent` on `accent` | 6.3 : 1 | 4.5 |
| `accent` on `canvas` (light) | 2.6 : 1 | fails as text: orange is never text |
| `saved` dot on `canvas` (light) | 4.4 : 1 | 3.0 (graphic) |
| `loan` dot on `canvas` (light) | 4.3 : 1 | 3.0 (graphic) |
| `ink` on `canvas` (dark) | 16 : 1 | 4.5 |
| `inkSecondary` on `canvas` (dark) | 7.0 : 1 | 4.5 |
| `income` on `canvas` (dark) | 8.2 : 1 | 4.5 |

Every declared foreground and background pair is asserted in a unit test (`test/theme/contrast_test.dart`) with `Color.computeLuminance()`, for both themes. Increase Contrast swaps `inkSecondary` to `#4A4944` (light) and `#C9C7BF` (dark), and doubles hairline strength.

## 4. Typography

Fonts are bundled (no runtime fetch), licences registered with `LicenseRegistry`.

| Family | Weights | Use |
|---|---|---|
| Geist | 400, 500, 600 | all Latin text |
| Geist Mono | 300, 400, 500 | all figures and mono labels |
| Vazirmatn (proposed) | 400, 500, 600 | Arabic-script text for Arabic and Sorani; `WP-03` confirms coverage of ە ێ ۆ ڵ ڕ ڤ and tabular digits |

`fontFamilyFallback`: Geist → Vazirmatn → system. Mono: Geist Mono → Vazirmatn (tabular figures) → system.

| Style | Family, weight | Size / line | Tracking | Use | iOS role |
|---|---|---|---|---|---|
| `figureHero` | Mono 300 | 50 / 56 | −2.5 | household balance | large title |
| `figureLarge` | Mono 300 | 38 / 42 | −1.6 | slip amount | title 1 |
| `figureMedium` | Mono 300 | 28 / 32 | −1.2 | sheet total, detail total | title 2 |
| `figureBody` | Mono 400 | 14 / 20 | 0 | row amounts | body |
| `figureSmall` | Mono 400 | 12 / 16 | 0 | converted amounts, captions | footnote |
| `monoLabel` | Mono 400 | 11 / 14 | +1.2, upper-case | "NOV 2026 · OUR HOME", "EXPENSE · DINING OUT" | caption 2 |
| `screenTitle` | Mono 400 | 12 / 16 | +1.4, upper-case | "ASK" | headline |
| `quote` | Geist 500 | 20 / 27 | −0.3 | what the user said | title 3 |
| `title` | Geist 600 | 16 / 22 | 0 | merchant, section title | headline |
| `body` | Geist 400 | 15 / 22 | 0 | default text | body |
| `bodyStrong` | Geist 500 | 15 / 22 | 0 | row titles | body |
| `subhead` | Geist 500 | 14 / 20 | 0 | questions, ledger labels | subheadline |
| `caption` | Geist 400 | 13 / 18 | 0 | section labels, links | footnote |
| `meta` | Geist 400 | 12 / 16 | 0 | row subtitles | caption 1 |
| `button` | Geist 600 | 15 / 20 | 0 | buttons | body |
| `chip` | Geist 500 | 13 / 18 | 0 | chips | footnote |
| `tabLabel` | Geist 600 active, 500 inactive | 11 / 13 (prototype 10) | 0 | tab bar | caption 2 |

Rules:
- Sizes are logical points and scale with `MediaQuery.textScaler`. No style is clamped, with one exception: `tabLabel` stops at 1.35×, matching iOS tab bars, and the tab items carry full semantics labels.
- `figureHero` steps down to `figureLarge`, then to compact notation ("IQD 16.3M") when the full figure does not fit the width. It never truncates and never uses a shrinking box.
- At accessibility sizes, rows with a trailing figure stack: label above, figure below, both leading-aligned.
- Mono labels are upper-cased in code for Latin only; Arabic-script labels keep their case and drop the tracking.
- Figures are wrapped in a left-to-right isolate so RTL text never reorders "IQD 10,000".
- Digits follow the member's setting (`latn` or `arab`); mono alignment uses tabular figures in both.

## 5. Space, size, shape

| Token | Value |
|---|---|
| Spacing scale | 4, 8, 12, 16, 20, 24, 32, 40 |
| Screen margin, content | 24 |
| Screen margin, floating controls | 16 (sheet 8) |
| Row heights | ledger row 36, receipt group 44, list row 54 |
| Minimum touch target | 44 × 44 |
| Tab bar | height 62, radius 31, 4 equal items, item well 50 high |
| Ask button | 62 × 62, round |
| Capture dock | radius 34, padding 14; side buttons 48, record button 56 |
| Top glass button | 44 × 44, round |
| Glass pill (mode chip) | height 32, radius 16 |
| Primary button | height 52, stadium |
| Chip | height 38 (visual), 44 hit area, stadium |
| Slip | radius 6, padding 18 |
| Sheet | top radius 38, grabber 38 × 5 |
| Chart bar | radius 2, gap 5 |
| Dots | 7 (ledger), 6 (unread), 18 (nudge) |
| Hairline | 1 physical pixel |

Bottom controls sit `max(safeAreaBottom, 8) + 8` above the bottom edge (26 on the prototype's notched frame). Scrollable content adds bottom padding equal to the tab bar height plus its offset, so the last row clears the glass.

## 6. Glass

### 6.1 Recipes

Values for the light theme come from the prototype's CSS (`backdrop-filter`, tint, border, inset highlight, shadow).

| Variant | Used for | Tint | Blur | Saturation | Border | Top highlight | Shadow |
|---|---|---|---|---|---|---|---|
| `control` | tab bar | `#FAF9F6` at 60% (72% proposed, review item 6) | 24 | 1.6 | white 75% | white 95% | 0 12 32, ink 12% |
| `button` | top round buttons, pills | `#FAF9F6` at 60% | 20 | 1.6 | white 75% | white 90% | 0 4 14, ink 6% |
| `dock` | capture dock, undo toast | `#FAF9F6` at 62% | 26 | 1.6 | white 80% | white 95% | 0 16 40, ink 14% |
| `sheet` | bottom sheets | `#ECEBE7` at 82% | 30 | 1.6 | white 60% | white 90% | 0 −10 40, black 35% (over camera), ink 14% elsewhere |
| `accent` | Ask button | `#FF5B1A` at 94% | 24 | 1.6 | white 40% | white 50% | 0 12 28, orange 35% |
| `overMedia` | controls on the camera | `#FAF9F6` at 18% | 20 | 1.6 | white 22% | white 25% | none; content colour `#FAF9F6` |

Dark theme:

| Variant | Tint | Border | Top highlight | Shadow |
|---|---|---|---|---|
| `control`, `button`, `dock` | `#222224` at 64% | white 10% | white 14% | 0 12 32, black 50% |
| `sheet` | `#1C1C1E` at 84% | white 8% | white 12% | 0 −10 40, black 55% |
| `accent` | `#FF5B1A` at 94% | white 30% | white 40% | 0 12 28, orange 30% |
| `overMedia` | same as light | | | |

### 6.2 `GlassSurface`

One widget hides the glass package. Features never import `liquid_glass_widgets`.

```dart
GlassSurface(
  variant: GlassVariant.control,   // control | button | dock | sheet | accent | overMedia
  shape: const StadiumBorder(),
  child: …,
)
```

| Tier | When | Rendering |
|---|---|---|
| 3 `premium` | Impeller, capable device | `liquid_glass_widgets` shader (refraction, specular rim), recipe mapped to `LiquidGlassSettings` (`glassColor`, `blur`, `thickness`, `saturation`, `lightIntensity`, `rimLight`) |
| 2 `standard` | default | the package's standard quality |
| 1 `blur` | older devices, or frame time over budget | `BackdropFilter` blur + tint + border + highlight (the package's minimal quality) |
| 0 `solid` | Reduce Transparency on, or Low Power Mode, or tier probe fails | opaque `surface` fill, `hairline` border, same shape and shadow |

- Package choice: `liquid_glass_widgets 1.19.0`. `liquid_glass_renderer 1.0.0-dev.2` is ruled out: its SDK constraint (`<3.14.0`) does not resolve on Dart 3.14 (DECISIONS D-07).
- All glass on a screen shares one backdrop read (`GlassBackdropGroup`).
- Reduce Transparency is not exposed by Flutter or by the glass package. `AccessibilityFlags` reads `UIAccessibility.isReduceTransparencyEnabled` through a small platform channel and listens for changes.
- Increase Contrast: tint opacity rises to 90%, border becomes `ink` at 40%.
- The tier is chosen at startup from a device table and can step down at runtime; it never steps up within a session. `WP-S2` measures tiers on an older iPhone before the table is locked.
- Glass over the camera preview (a platform view) needs the package's platform-view mode, which drops to the blur tier; the `overMedia` recipe is designed for that tier.
- A legibility scrim (black 0 → 35%, 120 pt) sits under the top controls on the camera screen, so chips stay readable over a white receipt.

## 7. Motion and haptics

| Token | Value | Use |
|---|---|---|
| `fast` | 120 ms, ease-out | chip select, badge appear |
| `base` | 220 ms, ease-out-cubic | card appear, field change |
| `slow` | 360 ms, spring (damping 0.86) | sheet present, dock mode switch |
| `count` | 400 ms | figure roll when a balance changes |

- Reduce Motion resolves every duration to zero; state changes cross-fade or cut. Motion is never the only signal.
- Streaming surfaces: a slip fades in once per surface; later updates change fields in place without re-animating the slip.
- Waveform animates only while recording.

| Event | Haptic |
|---|---|
| mic start, mic stop | light impact |
| chip or option picked | selection |
| saved | success notification |
| duplicate warning, limit reached | warning notification |
| destructive confirm | medium impact |
| scrolling, tab change, typing | none |

## 8. Components

`app/lib/core/ui/`. Each has a gallery entry (debug-only route `/gallery`) and golden tests in light and dark, LTR and RTL, text scale 1.0 and 1.5.

### 8.1 Mapped to the iOS catalogue

| iOS category | Component here | Notes |
|---|---|---|
| Navigation bar | `XpTopBar` | mono upper-case title, glass back button leading, optional glass pill trailing; no large titles |
| Tab bar | `XpTabBar` + `AskButton` | glass pill with Home, Activity, Goals, Accounts; separate round orange Ask button on the trailing side |
| Toolbar | `CaptureDock` | voice, type and camera modes |
| Search bar | `XpSearchField` | sunken well, stadium; in Activity it doubles as "Search or ask" |
| Lists | `XpListRow`, `LedgerRow`, `XpSection` | hairline separators, no grouped boxes |
| Section header | `SectionLabel` | caption style, optional trailing link |
| Cards | `Slip` | the only raised content surface: receipt-like, dashed rules |
| Disclosure | `XpDisclosure` | chevron row for settings |
| Buttons | `XpButton` (`primary` ink, `secondary` outline, `text`, `destructive`) | stadium, 52 high; one primary per screen |
| Menus | `XpMenu` | system pull-down |
| Segmented control | `XpFilterBar` | text tabs with an ink underline, horizontally scrollable |
| Slider, stepper | not used in v1 | |
| Toggle | `XpSwitch` | ink track when on, 44 pt hit area |
| Pickers | system date and time pickers in a sheet | |
| Text field, editor | `XpTextField`, `AmountField` | underline style; `AmountField` is mono, large, with a currency toggle |
| Progress | `ThinBar` (2 pt), `XpSpinner`, `Skeleton` | |
| Page control | `StepBar` | onboarding progress, 4 segments |
| Sheet | `GlassSheet` | detents medium and large, grabber, Cancel leading and action trailing for forms |
| Action sheet, alert | system | destructive option in `danger` |
| Popover, context menu | system context menu on rows (Edit, Duplicate, Delete) | |
| Share sheet | system | exports |
| Badge | `GuessedBadge`, `Dot`, `CountBadge` | |

### 8.2 Product components

| Component | Description |
|---|---|
| `MoneyText` | formats minor units by currency and member digits; styles `hero`, `large`, `medium`, `body`, `small`; optional sign and converted line |
| `HeroBalance` | label, currency mark, hero figure with tertiary decimals, delta line |
| `MiniBars` | 64 pt daily bars, last bar orange, spoken summary required |
| `LedgerRow` | dot, label, dotted leader, mono value |
| `Slip` / `EntrySlip` | mono header (intent · category, confidence), amount, dashed rule, field rows, question, chips, save |
| `ChoiceChips` | outline chips; selected is ink fill; shows `aria`-equivalent selected state |
| `TranscriptQuote` | mini waveform, duration, quoted text, trailing-aligned |
| `Waveform` | live bars in the dock |
| `ModeChip` | glass pill: lock icon + "On-device", "Smart", "Cloud" |
| `NudgeRow` | orange dot, one line, text action |
| `AvatarPair` | overlapping initials; ink and white |
| `ScanFrame` | four orange corner brackets |
| `ReceiptSheet` | merchant, total, split switch, group rows, Retake and Save |
| `UndoToast` | glass, 10 s, single action |
| `EmptyState` | one line, one action, no illustration |
| `OfflineBanner` | hairline strip under the top bar |
| `LockOverlay` | blurred canvas, app mark, Face ID button |
| `ProgressRing` / `GoalBar` | thin goal progress with percentage in mono |
| `HistoryRow` | who changed what, when; Restore action |

## 9. Screen inventory

The whole v1 flow restyled in Signal, plus screens the brief's gap list requires. Every list screen defines loading (skeleton rows), empty, error (inline notice with Retry) and offline (cached data plus banner).

| # | Screen | Structure | Key components | Notes |
|---|---|---|---|---|
| 1 | Welcome | app mark; one sample exchange shown as a quote and a slip; headline "Say it. We'll sort it."; primary "Get started"; text link for invite | `TranscriptQuote`, `EntrySlip`, `XpButton` | value before account |
| 2 | Create account | `StepBar` 1 of 4; Apple, Google, email buttons of equal weight; privacy note; Terms and Privacy links | `XpButton`, `XpTopBar` | Sign in with Apple first |
| 3 | Household and invite | name, display name, base currency chips (USD, IQD), invite code in mono with Share; shared vs private explained in two ledger rows | `XpTextField`, `ChoiceChips`, `LedgerRow` | "Invite later" link |
| 4 | Add accounts | kind chips; account rows with owner tag and mono balance; "Or just say it" example | `XpListRow`, `AmountField` | opening balances become `adjustment` entries |
| 5 | Try it | hold-to-talk orange button; example lines with mono tags | `CaptureDock`, `XpListRow` | microphone pre-prompt sits here; "Type instead" always visible |
| 6 | Home | mono header with month and household, bell (glass) and `AvatarPair`; `HeroBalance`; `MiniBars`; three `LedgerRow`s (Income, Spent, Saved); `NudgeRow`; Recent list | as listed | no cards; pull to refresh |
| 7 | Ask | glass back, "ASK", `ModeChip`; thread of quotes and slips; `CaptureDock` | `XpSurfaceHost` surfaces | full-height route above the tabs; thread scrolls under the dock |
| 8 | Receipt scan | camera with `ScanFrame`; glass close and "READ ON DEVICE" pill; `ReceiptSheet` | `GlassSurface.overMedia`, `GlassSheet` | dark in both themes |
| 9 | Add manually | `GlassSheet` (large): type filter bar, `AmountField`, category chips, account, who, date, note, "Scan a receipt" | `XpFilterBar`, `ChoiceChips` | Cancel leading, Save trailing and as bottom primary |
| 10 | Accounts | total as medium figure; filter bar (All, Mine, Partner, Joint); rows with mono abbreviations and balances; Loans and debts row | `XpListRow`, `XpFilterBar` | add via glass plus button |
| 11 | Account detail *new* | balance, sharing switch for personal accounts, entries for the account | `XpSwitch`, `XpListRow` | "Sharing…" state while history is being shared |
| 12 | Goals | saved-this-month figure; goal rows with `GoalBar`, pace in mono; example prompts | `GoalBar`, `SuggestionChips` | |
| 13 | Goal detail *new* | target, pace, contributions | | v1 |
| 14 | Loans and debts | two figures (Owed to you, You owe); sections with person rows and due dates | `LedgerRow`, `XpListRow` | |
| 15 | Loan detail | outstanding figure, facts as ledger rows, "Record a repayment" with amount chips, history | `ChoiceChips`, `HistoryRow` | |
| 16 | Activity | search field, filter bar, day groups with net in mono, rows | `XpSearchField`, `XpFilterBar`, `XpListRow` | swipe: Edit, Delete with undo |
| 17 | Entry detail and history *new* | amount, fields as rows (tap to edit), rate used, source, revisions | `HistoryRow` | |
| 18 | Budgets *new* | month total meter, category meters | `ThinBar` | v1 |
| 19 | Notifications *new* | list of nudges, unread dot | `NudgeRow` | v1 |
| 20 | Settings *new* | privacy mode (three options with plain descriptions), language, digits, exchange rate source and market rate entry, Face ID, categories, export, account (sign out, delete) | `XpDisclosure`, `XpSwitch` | delete account is at most two taps from Settings |
| 21 | Lock | `LockOverlay` | | |
| 22 | Monthly report *new* | narrative paragraph, breakdown, compare with last month, Export | `BreakdownList` | v1 |

## 10. Right-to-left and languages

- Layout uses directional insets and alignments only. The tab order mirrors, and the Ask button stays on the trailing side, which is the left edge in RTL.
- Back chevrons and disclosure chevrons flip. The waveform, charts' time axis and receipt preview do not.
- Dotted leader rows mirror: label on the right, figure on the left, figure itself left-to-right.
- Strings come from ARB files (`en`, `ckb`, `ar`). No concatenated sentences; amounts are placeholders.
- Golden tests run in `en` and `ar` for every component and for Home, Ask, Activity and Add manually.

## 11. Accessibility checklist

| Item | Rule |
|---|---|
| Text size | every style scales; layouts stack at large sizes; tested at the largest accessibility size on screens 6, 7, 9 and 16 |
| VoiceOver | icon-only buttons have labels; a slip reads as "Expense, dining out, 10,000 Iraqi dinars, today, guessed category"; charts have a spoken summary |
| Colour | no meaning by colour alone: sign plus colour for income, text badge for guessed, label plus dot in ledgers |
| Targets | 44 × 44 minimum, 8 pt between adjacent targets |
| Transparency | glass becomes solid with a hairline |
| Contrast | pairs in section 3.2 tested; Increase Contrast variants defined |
| Motion | zero under Reduce Motion |
| Focus order | top bar, content, dock or tab bar |

## 12. iOS review pass

Method: the `ios-review` checklist applied to this specification and to the source of the three Signal prototype artboards (HTML). **Nothing was rendered in a simulator, because no app exists yet.** These are findings from reading the design, not from seeing it on a device. A rendered review on a small and a large iPhone, in both themes and at the largest text size, is scheduled as `WP-84`.

### Must fix (all folded into the tokens and rules above)

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | Home hero figure decimals | `#9C9A93` on stone is 2.4 : 1, under the 3 : 1 needed even for large text | `inkTertiary` becomes `#7A7871` (3.7 : 1) |
| 2 | Tab labels, mono labels | fixed 10 and 11 px in the prototype, no Dynamic Type | all text uses scalable styles; `tabLabel` is 11 with a documented cap |
| 3 | Home bell (40 × 40), receipt switch (52 × 32), chips (38 high) | under the 44 pt target | 44 pt hit areas; the visual size may stay |
| 4 | Bottom controls | fixed 26 px offset ignores the home indicator on some devices | offset derives from the safe area |
| 5 | Add manually | the v1 sheet had Close only | Cancel leading, Save trailing, per iOS forms |
| 6 | Tab bar over dark content | inactive `#56554F` on 60% glass over an ink element composites to about 2.5 : 1 | inactive becomes `#3F3E3A`, tint rises to 72%; a test checks the worst-case composite |
| 7 | Permissions | "Try it" starts with hold-to-talk | pre-prompt explaining microphone and speech use, with "Type instead"; camera asked on first scan; notifications asked after the first reminder is set, never at launch |
| 8 | App Store | account deletion and data export were not in the prototype | Settings → Account → Delete account; Sign in with Apple offered with equal prominence; Privacy Policy and Terms linked on sign-in |

### Should fix

| # | Where | Problem | Fix |
|---|---|---|---|
| 9 | Use of orange | the prototype uses orange for the unread dot, nudge dot, today's bar and scan frame as well as the Ask action | rule 4 defines orange as "act or live"; the owner confirms (open question) |
| 10 | Camera screen | light chips over a bright receipt can lose contrast | top scrim under controls |
| 11 | Hero figure in IQD | nine-digit figures overflow at 375 pt | stepped size, then compact notation |
| 12 | Ask thread | the last slip can sit under the dock | bottom padding equals dock height plus offset; auto-scroll on new surface |
| 13 | Edge swipe | custom glass back button | keep Cupertino page routes so the back swipe works; test it |
| 14 | Empty and offline states | not drawn | defined per screen (section 9) |

### Nice to have

| # | Idea |
|---|---|
| 15 | Long-press on a tab item shows the large-content viewer at accessibility sizes |
| 16 | Slip save animates a perforation tear under normal motion settings |
| 17 | Home figure rolls when the balance changes |

Not applicable: paywall checks (the app has no purchases in v1).
