# Signal reference artboards (WP-D1)

Pixel references for every screen in [DESIGN_SYSTEM](../DESIGN_SYSTEM.md) section 9, in the light theme and the graphite dark theme, drawn only with the merged tokens in `app/lib/core/theme`. Screen packages build against these; WP-85 overlays simulator captures on the 1x files.

- **Canvas:** page "v4 · Signal, all screens" on the [design canvas](https://claude.ai/artifact/XxHQWTHVpRGpvSfzEQdX9S#page-v4) (private to the owner). Light row above, dark row below, in four groups. The earlier pages (v1 to v3, including S3Home, S3Ask and S3Receipt) are unchanged.
- **Files:** `png/<num>-<screen>-<theme>@1x.png` (390 x 844) and `@3x.png` (1170 x 2532). Contact sheets: [contact-light.png](contact-light.png), [contact-dark.png](contact-dark.png).
- **Source:** [source/](source/). `tokens.py` is a copy of the token values, `components.py` draws the `app/lib/core/ui` widgets, `screens.py` lays out the 23 screens, `build.py` writes the canvas artboards and preview pages, `render.py` makes the PNGs, `contact.py` the contact sheets.

## Frame and placement rules

| Rule | Value | From |
|---|---|---|
| Frame | 390 x 844 pt, safe areas 47 top and 34 bottom (an iPhone 12 to 14 class frame) | DESIGN_SYSTEM 13 |
| Top controls (top bar, Home header) | 44 high, top edge at 55 (safe area + s8) | this package |
| First content line under a top bar | 115 (top bar + s16) | this package |
| Bottom controls (tab bar, Ask button, dock, bottom buttons) | 42 above the bottom edge: `max(34, 8) + 8` | `XpSpace.bottomControlOffset` |
| Margins | content 24, floating controls 16, sheets 8 | `XpSpace` |
| Hairlines | one physical pixel at 3x (0.33 pt); chip, button and badge outlines and dotted leaders two (0.67 pt) | `XpSpace.hairline` |

Lists that run under the tab bar or the dock are drawn scrolling under the glass, as they will in the app.

## How the PNGs were made

They were not exported from the canvas. The same markup that is on the canvas was rendered locally:

```bash
python3 docs/design/source/build.py --out /tmp/wp-d1
python3 docs/design/source/render.py --out /tmp/wp-d1 --dest docs/design/png
```

1. `build.py` writes each artboard twice: as a `.dc.html` for the canvas (fonts from Google Fonts) and as a plain HTML page whose `@font-face` rules point at the app's bundled `app/assets/fonts` (Geist 400/500/600, Geist Mono 300/400/500). The frame markup is identical in both.
2. `render.py` opens each page in headless Google Chrome 157 (`--headless --window-size=390,844 --force-device-scale-factor=3 --hide-scrollbars --allow-file-access-from-files`, a fresh profile per page) and saves the screenshot as the 3x PNG.
3. The 1x PNG is the 3x PNG downsampled with macOS `sips --resampleHeightWidth 844 390`, so it matches a 3x simulator capture scaled to 1x rather than a 1x render (where a hairline would be a whole point).

## Where the drawing differs from the app by construction

- **Glass** is drawn at the blur tier (CSS `backdrop-filter: blur() saturate(1.6)`, tint, 1 pt rim, 1 pt top highlight, recipe shadow). The shader tiers add refraction at the rim that a browser cannot draw.
- **Sheet and dock corners** are superellipses in the app (`RoundedSuperellipseBorder`) and circular arcs here; they differ by under a point near the corners.
- **Shadows** use the token blur radius as the CSS blur. Flutter turns a `blurRadius` r into a Gaussian sigma of 0.577 r + 0.5, CSS into r / 2, so the app's shadows are slightly softer and wider.
- **The camera** is a drawn receipt on the scan backdrop; the receipt's 10 pt type is part of the picture, not UI.
- **System pieces** are not drawn: status bar, home indicator, keyboard.

## Decisions taken where the spec was silent

- **Onboarding headings** use `quote` (Geist 500, 20/27), the largest sans style; there is no display style in `XpType`.
- **Sign-in buttons** are three equal `XpButton.secondary` outlines without brand marks. WP-11 should use the official Sign in with Apple and Google button artwork at the same size and order.
- **Screen 20b "Settings, today's rate"** is an extra artboard: the `RateChangeSheet` number pad that both the Settings rate row and the Home `RatePrompt` "Change" open.
- **Composed rows with no component of their own:** the privacy-mode options in Settings (`XpListRow` layout with a trailing check), notification rows (`Dot.unread`, caption, mono time, text action), Goals suggestions (`XpChip` outlines standing in for `SuggestionChips`), the monthly report breakdown (`LedgerRow` with category dots standing in for `BreakdownList`), budget meters (`Dot`, figures, `ThinBar`).
- **Sample data:** one household ("Our home": you and Sam), base currency USD, market rate 1,705 dinars per dollar (DECISIONS D-16), so IQD 10,000 is USD 5.87. Totals add up across screens (accounts sum to the Home balance, budget and report categories sum to their totals).
- **Privacy mode** is shown as On-device only, to match the Ask and Receipt screens. Smart is the product default.

## Findings for the token owners

1. **The dark modal barrier lightens the screen.** `showGlassSheet` uses `colors.ink` at 24 %, which in graphite dark is `#F2F1ED`, so the screen behind a sheet turns grey instead of dimming (09 and 20b dark show it as the code would draw it). Black at about 40 % would match iOS.
2. **No display type style.** Onboarding headings top out at 20 pt (`quote`). If the owner wants a larger welcome headline, it needs a token.
3. **`SuggestionChips` and `BreakdownList`** are named in DESIGN_SYSTEM 8.2 and 9 but do not exist in `app/lib/core/ui`.
4. **Dark control glass at 64 %** (already escalated in WP-03): inactive tab labels over light content stay under 4.5:1. Not visible on these artboards because the content under the dark tab bar is dark.

## Index

| # | Screen | Theme | 1x | 3x | Canvas artboard | Components |
|---|---|---|---|---|---|---|
| 01 | Welcome | light | [png/01-welcome-light@1x.png](png/01-welcome-light@1x.png) | [png/01-welcome-light@3x.png](png/01-welcome-light@3x.png) | `V4-01-Welcome-Light.dc.html` | TranscriptQuote, EntrySlip, DashedRule, XpButton (primary, text) |
| 01 | Welcome | graphite dark | [png/01-welcome-dark@1x.png](png/01-welcome-dark@1x.png) | [png/01-welcome-dark@3x.png](png/01-welcome-dark@3x.png) | `V4-01-Welcome-Dark.dc.html` | TranscriptQuote, EntrySlip, DashedRule, XpButton (primary, text) |
| 02 | Create account | light | [png/02-create-account-light@1x.png](png/02-create-account-light@1x.png) | [png/02-create-account-light@3x.png](png/02-create-account-light@3x.png) | `V4-02-CreateAccount-Light.dc.html` | XpTopBar, GlassIconButton, StepBar, XpButton (secondary) |
| 02 | Create account | graphite dark | [png/02-create-account-dark@1x.png](png/02-create-account-dark@1x.png) | [png/02-create-account-dark@3x.png](png/02-create-account-dark@3x.png) | `V4-02-CreateAccount-Dark.dc.html` | XpTopBar, GlassIconButton, StepBar, XpButton (secondary) |
| 03 | Household and invite | light | [png/03-household-light@1x.png](png/03-household-light@1x.png) | [png/03-household-light@3x.png](png/03-household-light@3x.png) | `V4-03-Household-Light.dc.html` | XpTopBar, StepBar, XpTextField, SectionLabel, ChoiceChips, XpButton, LedgerRow |
| 03 | Household and invite | graphite dark | [png/03-household-dark@1x.png](png/03-household-dark@1x.png) | [png/03-household-dark@3x.png](png/03-household-dark@3x.png) | `V4-03-Household-Dark.dc.html` | XpTopBar, StepBar, XpTextField, SectionLabel, ChoiceChips, XpButton, LedgerRow |
| 04 | Add accounts | light | [png/04-add-accounts-light@1x.png](png/04-add-accounts-light@1x.png) | [png/04-add-accounts-light@3x.png](png/04-add-accounts-light@3x.png) | `V4-04-AddAccounts-Light.dc.html` | XpTopBar, StepBar, ChoiceChips, SectionLabel, AmountField, XpListRow, XpButton |
| 04 | Add accounts | graphite dark | [png/04-add-accounts-dark@1x.png](png/04-add-accounts-dark@1x.png) | [png/04-add-accounts-dark@3x.png](png/04-add-accounts-dark@3x.png) | `V4-04-AddAccounts-Dark.dc.html` | XpTopBar, StepBar, ChoiceChips, SectionLabel, AmountField, XpListRow, XpButton |
| 05 | Try it | light | [png/05-try-it-light@1x.png](png/05-try-it-light@1x.png) | [png/05-try-it-light@3x.png](png/05-try-it-light@3x.png) | `V4-05-TryIt-Light.dc.html` | XpTopBar, StepBar, SectionLabel, XpListRow, XpButton (text), CaptureDock |
| 05 | Try it | graphite dark | [png/05-try-it-dark@1x.png](png/05-try-it-dark@1x.png) | [png/05-try-it-dark@3x.png](png/05-try-it-dark@3x.png) | `V4-05-TryIt-Dark.dc.html` | XpTopBar, StepBar, SectionLabel, XpListRow, XpButton (text), CaptureDock |
| 06 | Home | light | [png/06-home-light@1x.png](png/06-home-light@1x.png) | [png/06-home-light@3x.png](png/06-home-light@3x.png) | `V4-06-Home-Light.dc.html` | AvatarPair, GlassIconButton (unread), HeroBalance, MiniBars, LedgerRow, RatePrompt (home), SectionLabel, XpListRow, XpTabBarWithAsk |
| 06 | Home | graphite dark | [png/06-home-dark@1x.png](png/06-home-dark@1x.png) | [png/06-home-dark@3x.png](png/06-home-dark@3x.png) | `V4-06-Home-Dark.dc.html` | AvatarPair, GlassIconButton (unread), HeroBalance, MiniBars, LedgerRow, RatePrompt (home), SectionLabel, XpListRow, XpTabBarWithAsk |
| 07 | Ask | light | [png/07-ask-light@1x.png](png/07-ask-light@1x.png) | [png/07-ask-light@3x.png](png/07-ask-light@3x.png) | `V4-07-Ask-Light.dc.html` | XpTopBar, GlassIconButton, ModeChip, TranscriptQuote, EntrySlip, ChoiceChips, XpButton, CaptureDock (recording), Waveform |
| 07 | Ask | graphite dark | [png/07-ask-dark@1x.png](png/07-ask-dark@1x.png) | [png/07-ask-dark@3x.png](png/07-ask-dark@3x.png) | `V4-07-Ask-Dark.dc.html` | XpTopBar, GlassIconButton, ModeChip, TranscriptQuote, EntrySlip, ChoiceChips, XpButton, CaptureDock (recording), Waveform |
| 08 | Receipt scan | light | [png/08-receipt-light@1x.png](png/08-receipt-light@1x.png) | [png/08-receipt-light@3x.png](png/08-receipt-light@3x.png) | `V4-08-Receipt-Light.dc.html` | ScanFrame, CameraScrim, GlassIconButton (overMedia), GlassPill (overMedia), GlassSheet, ReceiptSheet, XpSwitch, XpButton |
| 08 | Receipt scan | graphite dark | [png/08-receipt-dark@1x.png](png/08-receipt-dark@1x.png) | [png/08-receipt-dark@3x.png](png/08-receipt-dark@3x.png) | `V4-08-Receipt-Dark.dc.html` | ScanFrame, CameraScrim, GlassIconButton (overMedia), GlassPill (overMedia), GlassSheet, ReceiptSheet, XpSwitch, XpButton |
| 09 | Add manually | light | [png/09-add-manually-light@1x.png](png/09-add-manually-light@1x.png) | [png/09-add-manually-light@3x.png](png/09-add-manually-light@3x.png) | `V4-09-AddManually-Light.dc.html` | GlassSheet (large, Cancel and Save), XpFilterBar, AmountField, ChoiceChips, XpDisclosure, XpTextField, XpButton |
| 09 | Add manually | graphite dark | [png/09-add-manually-dark@1x.png](png/09-add-manually-dark@1x.png) | [png/09-add-manually-dark@3x.png](png/09-add-manually-dark@3x.png) | `V4-09-AddManually-Dark.dc.html` | GlassSheet (large, Cancel and Save), XpFilterBar, AmountField, ChoiceChips, XpDisclosure, XpTextField, XpButton |
| 16 | Activity | light | [png/16-activity-light@1x.png](png/16-activity-light@1x.png) | [png/16-activity-light@3x.png](png/16-activity-light@3x.png) | `V4-16-Activity-Light.dc.html` | XpTopBar, XpSearchField, XpFilterBar, XpListRow, UndoToast, XpTabBarWithAsk |
| 16 | Activity | graphite dark | [png/16-activity-dark@1x.png](png/16-activity-dark@1x.png) | [png/16-activity-dark@3x.png](png/16-activity-dark@3x.png) | `V4-16-Activity-Dark.dc.html` | XpTopBar, XpSearchField, XpFilterBar, XpListRow, UndoToast, XpTabBarWithAsk |
| 17 | Entry detail and history | light | [png/17-entry-detail-light@1x.png](png/17-entry-detail-light@1x.png) | [png/17-entry-detail-light@3x.png](png/17-entry-detail-light@3x.png) | `V4-17-EntryDetail-Light.dc.html` | XpTopBar, XpDisclosure, LedgerRow, SectionLabel, HistoryRow, XpButton (destructive) |
| 17 | Entry detail and history | graphite dark | [png/17-entry-detail-dark@1x.png](png/17-entry-detail-dark@1x.png) | [png/17-entry-detail-dark@3x.png](png/17-entry-detail-dark@3x.png) | `V4-17-EntryDetail-Dark.dc.html` | XpTopBar, XpDisclosure, LedgerRow, SectionLabel, HistoryRow, XpButton (destructive) |
| 10 | Accounts | light | [png/10-accounts-light@1x.png](png/10-accounts-light@1x.png) | [png/10-accounts-light@3x.png](png/10-accounts-light@3x.png) | `V4-10-Accounts-Light.dc.html` | XpTopBar, GlassIconButton, MoneyText (medium), XpFilterBar, XpListRow, XpTabBarWithAsk |
| 10 | Accounts | graphite dark | [png/10-accounts-dark@1x.png](png/10-accounts-dark@1x.png) | [png/10-accounts-dark@3x.png](png/10-accounts-dark@3x.png) | `V4-10-Accounts-Dark.dc.html` | XpTopBar, GlassIconButton, MoneyText (medium), XpFilterBar, XpListRow, XpTabBarWithAsk |
| 11 | Account detail | light | [png/11-account-detail-light@1x.png](png/11-account-detail-light@1x.png) | [png/11-account-detail-light@3x.png](png/11-account-detail-light@3x.png) | `V4-11-AccountDetail-Light.dc.html` | XpTopBar, MoneyText (medium), XpSwitch, XpSpinner, SectionLabel, XpListRow |
| 11 | Account detail | graphite dark | [png/11-account-detail-dark@1x.png](png/11-account-detail-dark@1x.png) | [png/11-account-detail-dark@3x.png](png/11-account-detail-dark@3x.png) | `V4-11-AccountDetail-Dark.dc.html` | XpTopBar, MoneyText (medium), XpSwitch, XpSpinner, SectionLabel, XpListRow |
| 12 | Goals | light | [png/12-goals-light@1x.png](png/12-goals-light@1x.png) | [png/12-goals-light@3x.png](png/12-goals-light@3x.png) | `V4-12-Goals-Light.dc.html` | XpTopBar, HeroBalance, GoalBar, SectionLabel, XpChip (as suggestions), XpTabBarWithAsk |
| 12 | Goals | graphite dark | [png/12-goals-dark@1x.png](png/12-goals-dark@1x.png) | [png/12-goals-dark@3x.png](png/12-goals-dark@3x.png) | `V4-12-Goals-Dark.dc.html` | XpTopBar, HeroBalance, GoalBar, SectionLabel, XpChip (as suggestions), XpTabBarWithAsk |
| 13 | Goal detail | light | [png/13-goal-detail-light@1x.png](png/13-goal-detail-light@1x.png) | [png/13-goal-detail-light@3x.png](png/13-goal-detail-light@3x.png) | `V4-13-GoalDetail-Light.dc.html` | XpTopBar, MoneyText (medium), ProgressRing, LedgerRow, XpListRow, XpButton |
| 13 | Goal detail | graphite dark | [png/13-goal-detail-dark@1x.png](png/13-goal-detail-dark@1x.png) | [png/13-goal-detail-dark@3x.png](png/13-goal-detail-dark@3x.png) | `V4-13-GoalDetail-Dark.dc.html` | XpTopBar, MoneyText (medium), ProgressRing, LedgerRow, XpListRow, XpButton |
| 14 | Loans and debts | light | [png/14-loans-light@1x.png](png/14-loans-light@1x.png) | [png/14-loans-light@3x.png](png/14-loans-light@3x.png) | `V4-14-Loans-Light.dc.html` | XpTopBar, Dot, MoneyText (medium), SectionLabel, XpListRow |
| 14 | Loans and debts | graphite dark | [png/14-loans-dark@1x.png](png/14-loans-dark@1x.png) | [png/14-loans-dark@3x.png](png/14-loans-dark@3x.png) | `V4-14-Loans-Dark.dc.html` | XpTopBar, Dot, MoneyText (medium), SectionLabel, XpListRow |
| 15 | Loan detail | light | [png/15-loan-detail-light@1x.png](png/15-loan-detail-light@1x.png) | [png/15-loan-detail-light@3x.png](png/15-loan-detail-light@3x.png) | `V4-15-LoanDetail-Light.dc.html` | XpTopBar, MoneyText (medium), ThinBar, LedgerRow, ChoiceChips, HistoryRow |
| 15 | Loan detail | graphite dark | [png/15-loan-detail-dark@1x.png](png/15-loan-detail-dark@1x.png) | [png/15-loan-detail-dark@3x.png](png/15-loan-detail-dark@3x.png) | `V4-15-LoanDetail-Dark.dc.html` | XpTopBar, MoneyText (medium), ThinBar, LedgerRow, ChoiceChips, HistoryRow |
| 18 | Budgets | light | [png/18-budgets-light@1x.png](png/18-budgets-light@1x.png) | [png/18-budgets-light@3x.png](png/18-budgets-light@3x.png) | `V4-18-Budgets-Light.dc.html` | XpTopBar, MoneyText (medium), ThinBar, Dot, SectionLabel |
| 18 | Budgets | graphite dark | [png/18-budgets-dark@1x.png](png/18-budgets-dark@1x.png) | [png/18-budgets-dark@3x.png](png/18-budgets-dark@3x.png) | `V4-18-Budgets-Dark.dc.html` | XpTopBar, MoneyText (medium), ThinBar, Dot, SectionLabel |
| 19 | Notifications | light | [png/19-notifications-light@1x.png](png/19-notifications-light@1x.png) | [png/19-notifications-light@3x.png](png/19-notifications-light@3x.png) | `V4-19-Notifications-Light.dc.html` | XpTopBar, Dot (unread), SectionLabel |
| 19 | Notifications | graphite dark | [png/19-notifications-dark@1x.png](png/19-notifications-dark@1x.png) | [png/19-notifications-dark@3x.png](png/19-notifications-dark@3x.png) | `V4-19-Notifications-Dark.dc.html` | XpTopBar, Dot (unread), SectionLabel |
| 20 | Settings | light | [png/20-settings-light@1x.png](png/20-settings-light@1x.png) | [png/20-settings-light@3x.png](png/20-settings-light@3x.png) | `V4-20-Settings-Light.dc.html` | XpTopBar, SectionLabel, XpDisclosure, XpSwitch |
| 20 | Settings | graphite dark | [png/20-settings-dark@1x.png](png/20-settings-dark@1x.png) | [png/20-settings-dark@3x.png](png/20-settings-dark@3x.png) | `V4-20-Settings-Dark.dc.html` | XpTopBar, SectionLabel, XpDisclosure, XpSwitch |
| 20b | Settings, today's rate | light | [png/20b-settings-rate-light@1x.png](png/20b-settings-rate-light@1x.png) | [png/20b-settings-rate-light@3x.png](png/20b-settings-rate-light@3x.png) | `V4-20b-SettingsRate-Light.dc.html` | GlassSheet, RateChangeSheet, XpNumberPad, XpButton |
| 20b | Settings, today's rate | graphite dark | [png/20b-settings-rate-dark@1x.png](png/20b-settings-rate-dark@1x.png) | [png/20b-settings-rate-dark@3x.png](png/20b-settings-rate-dark@3x.png) | `V4-20b-SettingsRate-Dark.dc.html` | GlassSheet, RateChangeSheet, XpNumberPad, XpButton |
| 21 | Lock | light | [png/21-lock-light@1x.png](png/21-lock-light@1x.png) | [png/21-lock-light@3x.png](png/21-lock-light@3x.png) | `V4-21-Lock-Light.dc.html` | LockOverlay, XpButton (secondary, Face ID glyph) |
| 21 | Lock | graphite dark | [png/21-lock-dark@1x.png](png/21-lock-dark@1x.png) | [png/21-lock-dark@3x.png](png/21-lock-dark@3x.png) | `V4-21-Lock-Dark.dc.html` | LockOverlay, XpButton (secondary, Face ID glyph) |
| 22 | Monthly report | light | [png/22-monthly-report-light@1x.png](png/22-monthly-report-light@1x.png) | [png/22-monthly-report-light@3x.png](png/22-monthly-report-light@3x.png) | `V4-22-MonthlyReport-Light.dc.html` | XpTopBar, MoneyText (medium), LedgerRow (as BreakdownList), SectionLabel, XpButton |
| 22 | Monthly report | graphite dark | [png/22-monthly-report-dark@1x.png](png/22-monthly-report-dark@1x.png) | [png/22-monthly-report-dark@3x.png](png/22-monthly-report-dark@3x.png) | `V4-22-MonthlyReport-Dark.dc.html` | XpTopBar, MoneyText (medium), LedgerRow (as BreakdownList), SectionLabel, XpButton |
