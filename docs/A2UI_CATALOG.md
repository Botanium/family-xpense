# Family Xpense: A2UI Catalog

The Xpense catalog is the set of components the agent may render and the phone knows how to paint. One catalog serves both sources of UI: surfaces streamed by the cloud agent and surfaces built on the phone by the on-device path. Protocol: A2UI v1.0.

Facts about the protocol and packages were read from the A2UI spec, the package READMEs and changelogs on 2026-11-22 (DECISIONS section 3). Items that documentation could not settle were checked by the WP-S1 spike ([docs/spikes/WP-S1.md](spikes/WP-S1.md)); this document reflects its findings.

## 1. Identity and files

| Item | Value |
|---|---|
| `catalogId` | `https://bitrelia.com/xpense/a2ui/catalogs/xpense/v1/catalog.json` (a stable unique URI on the owner's domain; it does not need to resolve; D-40) |
| `protocolVersion` | `"1.0"` |
| Server lookup id | `xpense` (used in `a2ui(catalog: 'xpense')`) |
| Source of truth | `packages/xpense_shared/lib/catalog/xpense_catalog.json`, in the A2UI `catalog.json` shape |
| Server registration | `await loadCatalog(ai, id: 'xpense', file: …)` at startup, before any turn |
| Phone registration | `CatalogImplementation(id: catalogId, protocolVersion: A2uiProtocolVersion.v1_0, components: xpenseComponents, functions: xpenseFunctions)` inside `XpenseSurfaceHost` |
| Parity test | the same JSON loads with `loadCatalog` (server) and `Catalog.fromJson` (`a2ui_core 0.8`); a test compares each component's `schema.value['properties']` keys with the Dart implementations |

The catalog is loaded from JSON rather than built with `basicCatalog.extend`, because `extend` keeps all 18 basic components and this catalog deliberately leaves some out.

## 2. Design rules for this catalog

1. **Semantic, not presentational.** Components describe money concepts (an entry, a budget). They carry no colours, sizes or fonts. The Signal theme decides the look.
2. **Smart where money is written.** `EntryList` and `ReceiptSummary` own editing and saving on the phone. The agent proposes data; it never performs the save.
3. **Data in the data model, bound by path.** Drafts live at `/drafts`. Components bind to paths, so a follow-up answer updates a field in place and the card redraws without a model call.
4. **No remote content.** No image, video, audio, modal or link components, and no `openUrl` function.
5. **Small.** 8 basic components and 16 Xpense components. Fewer components mean a shorter prompt and more consistent output. Measured in WP-S1: the injected catalog instructions are about 22,000 characters (estimated 5,500 to 6,300 tokens) per model call. Keep descriptions to one line, drop `weight` from the copied basic components, and leave out unused functions.
6. **Property order is part of the contract.** A2UI Express is positional: the order of properties in the JSON schema is the argument order. Appending an optional property is compatible; reordering is breaking.
7. **Reserved names.** No property is named `checks`, `metadata`, `accessibility` or `catalogId` (the renderer treats these as envelope keys). Component ids are identifiers with underscores, never hyphens. Surface ids follow the same rule.
8. **Enum properties are static.** In Express an enum-typed property cannot be bound to the data model. To make a property bindable, type it as a dynamic string and lose the enum check.
9. **The agent sees only what it wrote.** On later turns a surface is replayed as its original Express. Edits made on the phone are invisible to the agent unless an action's context carries them; `sendDataModel` does not help with `genkit_a2ui 0.6`.

## 3. Components

`dyn` means a literal or a data binding (`{"@path": "/…"}` on the wire, `$/…` in Express). `path` means a plain data-model path string. `?` marks optional. Properties are listed in positional order.

### 3.1 Basic subset (same names and schemas as the A2UI v1.0 basic catalog, re-implemented in the Signal style)

| Component | Properties | Notes |
|---|---|---|
| `Column` | `children`, `justify?`, `align?` | |
| `Row` | `children`, `justify?`, `align?` | |
| `List` | `children`, `direction?`, `align?` | supports the template form `{"path": "/items", "componentId": "tpl"}` |
| `Text` | `text` (dyn), `variant?` (`caption` \| `body`) | inline Markdown limited to bold, italic and lists; a `## ` line renders as a section label |
| `Divider` | `axis?` | hairline |
| `Button` | `child`, `variant?` (`primary` \| `default` \| `borderless`), `action` | primary is the ink pill, never orange |
| `TextField` | `label`, `value` (writable), `placeholder?`, `variant?` (`shortText` \| `longText` \| `number`) | checks supported |
| `DateTimeInput` | `value` (writable), `enableDate?`, `enableTime?`, `min?`, `max?`, `label?` | |

Left out on purpose: `Image`, `Icon`, `Video`, `AudioPlayer`, `Card`, `Tabs`, `Modal`, `CheckBox`, `ChoicePicker`, `Slider`.

### 3.2 Capture

**`EntryList`**: one slip per draft, with confirm and save.

| Property | Type | Description |
|---|---|---|
| `drafts` | dyn (array of `EntryDraft`) | normally `$/drafts` |
| `status?` | static enum `review` \| `saved` | default `review`. The agent sets it once; after a save the phone keeps its own state at `/ui/status` |
| `title?` | dyn string | for example "I found two things in that" |

Behaviour on the phone:
- Renders each draft as a slip: a mono label line (intent and category, confidence), the amount with its converted value, then Who, When and From rows.
- Fields listed in the draft's `guessed` show a "Guessed" badge; tapping any field opens a local picker and writes back into the data model.
- For the first field in `missing`, shows an inline question with options built from household data (accounts, categories, members), ranked by the draft's probabilities.
- A duplicate hint shows "Looks like one you already saved" with View and Save anyway.
- When a draft needs a conversion and nobody has entered today's rate, the slip asks for it inline (prefilled with the latest rate; "Use 1,705" or "Change"). The answer is saved as the day's rate for the household.
- One primary button: "Save", "Save both", or "Save 3 entries". Disabled while any draft has `missing` fields.
- After saving: the slip shows the saved line (for example "SAVED · DINING 85,000 / 120,000" when a budget exists), an Undo link for 10 seconds, and the recurring offer when the hint passes the threshold.

**`ChoicePrompt`**: one question with tappable answers.

| Property | Type | Description |
|---|---|---|
| `question` | dyn string | |
| `options` | list of `{label, value, hint?}` | 2 to 5 |
| `value` | writable binding | where the picked value is stored, for example `$/drafts/0/intent` |
| `allowOther?` | boolean | adds "Other…", which opens a text field |
| `action?` | action | fired after a pick, only when the agent must react. See the note on optional actions below |

A pick writes `value` locally. Without `action`, no message is sent to the agent.

**Optional actions (`ChoicePrompt`, `Nudge`, `Notice`).** The contract text that `a2ui()` injects tells the model that every parameter named `action` is required and to supply a dummy `Event("click")`. WP-32's prompt overrides that for these three components, the action router drops events named `click`, and the evaluation checks that a pick without `action` starts no agent turn.

**`Transcript`**: what was heard.

| Property | Type | Description |
|---|---|---|
| `text` | dyn string | |
| `seconds?` | dyn number | recording length |

**`ReceiptSummary`**: the result of a scan, shown in the glass sheet.

| Property | Type | Description |
|---|---|---|
| `receipt` | dyn object `{merchant, occurredOn, occurredTime?, currency, totalMinor, lines[] {text, amountMinor, categoryId?}}` | normally `$/receipt` |
| `drafts` | dyn (array of `EntryDraft`) | one per category group when split, one in total otherwise |
| `split` | writable boolean | the "Split by category" switch |
| `source?` | enum `device` \| `cloud` | drives the "Read on device" chip |

Behaviour: totals per group, the switch regroups locally with `allocate()` so groups always sum to the receipt total, and the buttons are Retake and "Save n entries".

**`SavedNote`**: a confirmation line.

| Property | Type | Description |
|---|---|---|
| `text` | dyn string | |
| `tone?` | enum `ok` \| `info` \| `warn` | |

### 3.3 Figures and review

**`MoneyText`**

| Property | Type | Description |
|---|---|---|
| `amountMinor` | dyn number | integer minor units |
| `currency` | dyn string | `USD` \| `IQD` |
| `size?` | enum `hero` \| `large` \| `body` \| `small` | default `body` |
| `sign?` | enum `none` \| `plus` \| `minus` | |
| `tone?` | enum `ink` \| `income` \| `muted` \| `loan` \| `saving` | |
| `approx?` | dyn object `{amountMinor, currency}` | renders "≈ USD 6.58" beneath |

Formatting (grouping, decimals, currency position) is done by the phone from the member's settings. The agent never formats money as text.

**`LedgerRow`**: dot, label, dotted leader, mono value.

| Property | Type |
|---|---|
| `label` | dyn string |
| `amountMinor` | dyn number |
| `currency` | dyn string |
| `dot?` | enum `income` \| `spent` \| `saved` \| `loan` \| `neutral` |

**`MiniBars`**: the thin daily chart.

| Property | Type | Description |
|---|---|---|
| `values` | dyn number list | |
| `caption?` | dyn string | "avg 210/day" |
| `highlight?` | enum `last` \| `max` \| `none` | the highlighted bar uses the accent |
| `description` | dyn string | required spoken summary for VoiceOver |

**`BreakdownList`**: totals by category, account or person.

| Property | Type |
|---|---|
| `items` | dyn array of `{label, amountMinor, share, colorKey?}` |
| `currency` | dyn string |
| `totalLabel?` | dyn string |

**`TransactionList`**

| Property | Type | Description |
|---|---|---|
| `items` | dyn array of `{txnId, title, subtitle, amountMinor, currency, type, occurredOn}` | at most 20 |
| `emptyText?` | dyn string | |

Tapping a row opens the transaction on the phone (local action).

**`BudgetMeter`**

| Property | Type |
|---|---|
| `label` | dyn string |
| `spentMinor` | dyn number |
| `limitMinor` | dyn number |
| `currency` | dyn string |

**`LoanCard`**

| Property | Type | Description |
|---|---|---|
| `personName` | dyn string | |
| `direction` | enum `given` \| `taken` | |
| `outstandingMinor` | dyn number | |
| `principalMinor` | dyn number | |
| `currency` | dyn string | |
| `dueOn?` | dyn string | |
| `loanId?` | dyn string | enables "Record a repayment" and opening the loan |

**`GoalCard`**

| Property | Type |
|---|---|
| `name` | dyn string |
| `savedMinor` | dyn number |
| `targetMinor` | dyn number |
| `currency` | dyn string |
| `pace?` | dyn string |
| `goalId?` | dyn string |

### 3.4 Conversation

**`Nudge`**: a proactive line with one action.

| Property | Type | Description |
|---|---|---|
| `text` | dyn string | |
| `kind` | enum `bill` \| `budget` \| `loan` \| `rate` \| `report` \| `info` | |
| `actionLabel?` | dyn string | |
| `action?` | action | |

**`SuggestionChips`**

| Property | Type | Description |
|---|---|---|
| `options` | list of `{label, message}` | at most 4; tapping sends `message` as the user's next text |

**`Notice`**: errors and limits in plain words.

| Property | Type |
|---|---|
| `text` | dyn string |
| `kind` | enum `offline` \| `limit` \| `privacy` \| `error` |
| `actionLabel?` | dyn string |
| `action?` | action |

## 4. Functions

Kept from the basic catalog: `formatNumber`, `formatDate`, `pluralize`, and the validators `required`, `regex`, `length`, `numeric` with `and`, `or`, `not`. Removed: `openUrl`, `formatCurrency` (money is formatted by `MoneyText`). No custom functions in v1.

## 5. Actions

### 5.1 Handled on the phone

Smart components call the app through an `XpenseActions` interface that the host provides. These never become agent turns.

| Call | Triggered by | Effect |
|---|---|---|
| `saveDrafts(surfaceId, drafts)` | `EntryList`, `ReceiptSummary` | validate, write through the repository, mark `status = saved` in the data model |
| `undoSave(groupId)` | `EntryList` | soft-delete the group |
| `learn(correction)` | `EntryList` on save, when a guessed field was changed | upsert a rule |
| `openTransaction(txnId)`, `openLoan(loanId)`, `openGoal(goalId)` | lists and cards | navigate |
| `sendText(message)` | `SuggestionChips` | start a new capture with that text (goes through the router) |
| `setRecurring(draftId, mode)` | recurring offer in `EntryList` | create or update a recurring template |
| `retakeReceipt()` | `ReceiptSummary` | reopen the camera |
| `openManualForm(draft)` | `EntryList` "Change", `Notice` | open the form prefilled |

Action names that travel as A2UI events but must stay local are prefixed `xp.local.` (used by `Button`, `Nudge` and `Notice` when the on-device builder creates them). The action router consumes them.

### 5.2 Forwarded to the agent

| Event name | Context | Sent when |
|---|---|---|
| `xp.answer` | `{field, value, text?}` | a `ChoicePrompt` with an `action` is answered, or "Other…" text is submitted |
| `xp.refine` | `{note}` | the user asks the agent to redo a proposal |
| `xp.more` | `{topic, range?}` | a follow-on analytics request from a button |

After a local save, the host records `{draftIds, txnIds}` and attaches a compact `xp.saved` action to the user's next turn, so the agent knows what was confirmed without an extra model call. It travels as an A2UI data part before the text part in the same user message (verified in WP-S1); the model reads `[UI action "xp.saved" from … context={…}]` followed by the text.

Input values reach the agent only when the bound paths are echoed in the event context, for example `Event("xp.answer", {field: "note", text: $/answer/text})`.

While a turn is streaming, forwarded actions are ignored and controls show a busy state, so turns never interleave.

## 6. Data model conventions

| Path | Content | Written by |
|---|---|---|
| `/drafts` | array of `EntryDraft` | agent or local builder; edited by `EntryList` |
| `/receipt` | receipt object | builder or agent |
| `/ui/*` | view state such as `/ui/split` | components |
| `/answer/*` | free-text answers | `TextField` |
| `/result/*` | rows and totals for analytics answers | agent |

Nothing secret goes into a data model. Anything bound there can come back through an action.

The agent cannot see changes the phone makes to a data model. When the agent needs the current drafts (for example to redo a proposal), the phone sends them in the action context (`xp.refine {drafts}`).

## 7. What the agent writes

The model writes A2UI Express inside `<a2ui>` blocks; `genkit_a2ui` compiles it to v1.0 messages. `$/path = [...]` assigns arrays and maps (quoted keys, `null` and booleans allowed). In a block with `root` the assignment travels inside `createSurface.dataModel`; otherwise as `updateDataModel` (verified in WP-S1). Illustrative blocks:

Two entries in one message:

```text
surface("cap_k3m9")
$/drafts = [
  {id: "d1", intent: "income", amountMinor: 320000, currency: "USD", categoryId: "salary",
   accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Salary",
   confidence: {intent: 0.99, category: 0.97, account: 0.96}},
  {id: "d2", intent: "expense", amountMinor: 140000, currency: "USD", categoryId: "rent",
   accountId: "acc_chk", who: "joint", occurredOn: "2026-11-22", title: "Rent",
   confidence: {intent: 0.98, category: 0.99, account: 0.97}, guessed: ["who"]}
]
root = EntryList($/drafts, "review", "I found two things in that:")
```

An intent question:

```text
surface("cap_p7x2")
$/drafts = [{id: "d1", intent: "loan_given", amountMinor: 30000, currency: "USD",
  personName: "Alex", accountId: "acc_chk", occurredOn: "2026-11-22", missing: ["intent"]}]
root = Column([ask, list])
ask = ChoicePrompt("Quick check, so I file it right: will Alex pay this back?",
  [{label: "Yes, it's a loan", value: "loan_given", hint: "Alex owes us"},
   {label: "No, gift or payment", value: "expense", hint: "Expense"},
   {label: "I was paying Alex back", value: "repayment_made", hint: "Debt"}],
  $/drafts/0/intent)
list = EntryList($/drafts)
```

An analytics answer:

```text
surface("ans_food_nov")
$/result = {total: 48650, rows: [{label: "Groceries", amountMinor: 38600, share: 0.79},
  {label: "Dining", amountMinor: 10050, share: 0.21}]}
root = Column([head, total, rows, chips])
head = Text("Food in November")
total = MoneyText($/result/total, "USD", "large")
rows = BreakdownList($/result/rows, "USD")
chips = SuggestionChips([{label: "By week", message: "Show food spending by week this month"},
  {label: "Compare to October", message: "Compare food spending with October"}])
```

Agent rules that concern the catalog are in AI_PIPELINE section 8. The server runs `a2ui(validate: 'strict', repair: false)` in development and CI, and `validate: 'warn', repair: true` in production.

## 8. How the on-device path builds the same messages

`packages/xpense_shared/lib/surface/surface_builder.dart` is pure Dart and returns spec-shaped maps. It has no dependency on `a2ui_core`, so the server can run it too (tests, evals, and deterministic surfaces in jobs).

```dart
/// Returns A2UI v1.0 messages, ready for MessageProcessor.processMessages.
List<Map<String, Object?>> captureSurface({
  required String surfaceId,
  required List<EntryDraft> drafts,
  String? title,
  TranscriptData? transcript,
  ChoicePromptData? ask,
});
```

Output for one draft with a missing account (one `createSurface` carrying components and data together, which v1.0 allows):

```json
[{
  "version": "1.0",
  "createSurface": {
    "surfaceId": "cap_k3m9",
    "catalogId": "https://bitrelia.com/xpense/a2ui/catalogs/xpense/v1/catalog.json",
    "components": [
      {"id": "root", "component": "Column", "children": ["heard", "list"]},
      {"id": "heard", "component": "Transcript",
       "text": "Spent ten thousand dinars on lunch with the kids", "seconds": 6},
      {"id": "list", "component": "EntryList", "drafts": {"@path": "/drafts"}, "status": "review"}
    ],
    "dataModel": {
      "drafts": [{
        "id": "d1", "intent": "expense", "amountMinor": 10000, "currency": "IQD",
        "categoryId": "dining", "who": "me", "occurredOn": "2026-11-22", "occurredTime": "13:20",
        "title": "Lunch with the kids",
        "fx": {"pair": "USD/IQD", "pairRate": "1705", "source": "market", "asOf": "2026-11-22", "baseAmountMinor": 587},
        "confidence": {"intent": 0.97, "category": 0.94, "account": 0.31},
        "missing": ["accountId"], "origin": "decisions"
      }]
    }
  }
}]
```

Other builders: `receiptSurface`, `nudgeSurface`, `queuedSurface` (offline queue placeholder), `noticeSurface`, `savedSurface`.

Rules for local messages (from WP-S1):
- Bindings are written `{"@path": …}` and function calls `{"@call": …}`; the bare `call` key fails validation in `a2ui_core 0.8`.
- Local surface ids start with `loc_`.
- The agent cannot update a local surface: the server validates agent blocks against the surfaces the agent itself created. To hand a local draft to the agent, send it in an action context (`xp.refine {drafts}`) and let the agent render its own surface.

Because the account question is derived by `EntryList` from `missing`, the local builder does not need to emit a `ChoicePrompt` for ordinary missing fields. It emits one only for intent questions, where the options change the draft's meaning.

The fixture set `packages/xpense_shared/test/fixtures/surfaces/*.json` holds expected messages for representative inputs. It is used three ways: unit tests of the builder, golden tests of the widgets, and the `surfaceValid` evaluator on agent output.

## 9. Phone implementation notes

| Topic | Rule |
|---|---|
| Component code | one file per component in `app/lib/a2ui/components/`, each a `ComponentImplementation(name, schema, builder)`; the builder maps `ComponentProps` to a plain widget from `app/lib/a2ui/widgets/` that takes typed values, so widgets are testable without A2UI |
| Theming | A2UI v1.0 has no theme message; components read Signal tokens from `ThemeExtension`s. The basic subset is our own implementation, not `BasicComponents`, which are stock Material widgets. |
| Sizing | surfaces get unbounded constraints from the renderer; the host wraps each surface in a width-constrained box, and text fields in a `LimitedBox` |
| Markdown | `A2uiMarkdown` with `flutter_markdown_plus`, links and images disabled |
| Typed drafts | `EntryList` parses each draft with `EntryDraft.$schema`; a draft that fails validation renders as "Needs review" with an Edit button and cannot be saved directly |
| Validation before save | account, category, person, loan and goal ids must exist in the household cache; amount in `1 … 10^12`; currency matches the account; at most 20 drafts |
| Direction | components use directional padding and alignment only, so right-to-left can be added later without rework |
| Accessibility | every component declares a semantics label; `MiniBars` requires `description`; "Guessed" is conveyed by a text badge, not colour alone; live updates (saved state) announce politely |
| Unknown content | an unknown component or a failed message is skipped and counted; the rest of the surface renders |
| Deleted surfaces | a `deleteSurface` for an unknown id is ignored; `genkit_a2ui` sends one before every `createSurface` |
| Testing | golden tests: each component × light and dark × text scale 1.0 and 1.5, from the shared fixtures; widget tests for save, undo, pick and validation flows |

## 10. Versioning

- Adding a component or appending an optional property keeps `v1`. The app ignores components it does not know, and the server only uses new ones for apps that report a high enough build in the `X-Xpense-App` header.
- Renaming, removing or reordering is breaking: publish `…/xpense/v2/catalog.json`, mount `/v2/agent`, and keep `/v1` until old builds are gone.
- Upgrading `a2ui_core`, `a2ui_flutter` or `genkit_a2ui` is a dedicated work package using the `a2ui-migration` skill. The parity test, goldens and `surfaceValid` gate it.
