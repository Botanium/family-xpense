# WP-S1 Spike: A2UI round trip

Date: 2026-11-22. Spike code: [`spikes/a2ui/`](../../spikes/a2ui/) (throwaway). Story S0.11.

**Summary.** Every item marked "verify in WP-S1" works as the docs hoped, with no fallback needed. A server on `genkit_a2ui 0.6.0` (which resolves `a2ui_core 0.7.0` and `a2ui_agent 0.3.0`) streams surfaces that render on `a2ui_flutter 0.4.0` / `a2ui_core 0.8.0` with a custom catalog loaded from JSON. Express assigns arrays of objects to `$/drafts`. Custom components write back to the data model and their siblings redraw. Local raw-map surfaces share the processor with agent surfaces. One user message can carry an action and text. Generate middleware reads the request context. `FirestoreSessionStore` works with a per-tenant prefix, and also nested under `households/{hid}` if a small wrapper picks the store per household. The injected catalog instructions cost about 5,500 to 6,300 tokens per model call for a full-size catalog (estimated; see Q7).

The spike found four things the docs do not yet say:
1. The agent **cannot partially update a surface the phone built**, even when the phone attaches it to the turn.
2. **The model never sees local edits.** Later turns replay the surface's original Express.
3. **A property declared as an enum is static in Express.** It cannot be bound, so `EntryList.status` cannot be "dyn enum".
4. The injected contract tells the model that **every parameter named `action` is required**. That conflicts with `ChoicePrompt`'s optional `action`.

## Set-up

| Side | Packages (resolved) | Notes |
|---|---|---|
| Server `spikes/a2ui/server` | `genkit 1.0.3`, `genkit_a2ui 0.6.0`, `a2ui_agent 0.3.0`, **`a2ui_core 0.7.0`**, `genkit_google_cloud 0.3.3`, `google_cloud_firestore 0.5.5` | Agent `spikeAgent` with `use: [householdContext(), a2ui(catalog: 'xpense-spike', validate: 'strict', repair: false)]`, served by `GenkitRouter.addAgent` on `:8085/api/spikeAgent` with a `contextProvider` |
| Client `spikes/a2ui/client` | Flutter 3.50.1, **`a2ui_flutter 0.4.0`, `a2ui_core 0.8.0`**, `genkit 1.0.3` | One `MessageProcessor` (`unifiedOutbound: true`), `remoteAgent`, the copy-in helpers without `_normalizeEnvelopeKeys` |
| Catalog | `spikes/a2ui/catalog/spike_catalog.json` | Column, Text, Button (copied from the v1.0 basic catalog) plus cut-down `EntryList` and `ChoicePrompt`; `catalogId` `https://familyxpense.app/a2ui/catalogs/xpense-spike/v1/catalog.json` |
| Model | `spike/scripted` | **No Gemini API key was available to this session.** A scripted model streams fixed Express text in 40-character chunks through the real `a2ui()` middleware, so the compile, validate, stream and replay paths are real. What a real model writes is not tested. |

Evidence is in `spikes/a2ui/evidence/`:
- `q2_compiled_messages.json`: every Express block below, compiled by the 0.7 server.
- `requests/`: the exact `ModelRequest` each model call received, after all middleware.
- `traces/`: Genkit traces, read with the `genkit` MCP `get_trace`.
- `screenshots/`: iPhone 17 Pro simulator, iOS 26.5.
- `q7_*`: the rendered instructions and the size table.

Commands and output:

```text
$ dart run bin/compile_express.dart        (server)
q2_drafts_array: OK, 2 messages
q2_choice_prompt: OK, 2 messages
q2_quoted_keys_null_bool: OK, 2 messages
q1_checks_bare: OK, 2 messages
q2_update_element: OK, 1 messages
q4_update_local_surface: FAILED: Bad state: A2UI: failed to compile A2UI Express block: Surface not found for message: local_cap_1
q4_rerender_local_surface: OK, 2 messages
q5_choice_with_action: OK, 2 messages
q2_result_object: OK, 2 messages

$ flutter test                             (client)
00:00 +0: Q1: 0.7-era agent messages render on a2ui_core 0.8 with the custom catalog
00:00 +1: Q1: a legacy bare "checks" key on a v1.0 Button is read (0.8 dual-read)
00:00 +2: Q3: ChoicePrompt writes the bound path and its sibling EntryList re-renders; EntryList writes back through its own binding
00:00 +3: Q3/Q5: a ChoicePrompt with an action emits it with the picked value echoed in its context
00:00 +4: Q4: a local raw-map createSurface (components + dataModel) renders in the same processor beside an agent surface
00:00 +5: parity: the JSON catalog and the Dart implementations agree
00:00 +6: All tests passed!

$ dart analyze (server) / flutter analyze (client)
No issues found!
```

(`q4_update_local_surface` fails on purpose; see Q4.)

## Q1. Does a 0.7-era server's surface render on the 0.8 renderer with a custom catalog?

**Yes.** No key rewriting is needed in this direction.

- The server compiled Express against the JSON catalog and emitted v1.0 messages with `deleteSurface` before `createSurface`, `"sendDataModel": false`, and bare envelope keys. For example, a Button with checks is written `"checks": [{"condition": {"@call": "required", …}}]`, not `@checks`.
- `a2ui_core 0.8.0` read all of it:
  - The `deleteSurface` for an unknown id was a no-op.
  - The custom components resolved under the matching `catalogId`.
  - The bare `checks` was read as a real check, not as an unknown property. The `required` check disabled the Button until `/name` was set (test 2, using the server's own output).
- Live on the simulator, the streamed turn rendered both drafts with the "Guessed" marker (screenshots `01_agent_and_local_surfaces.png` and `02_agent_surface_two_drafts.png`; trace `5853b7ca5b11e2f6ac071fc47c49f466`).

```json
{"version":"1.0","createSurface":{"surfaceId":"legacy_keys","catalogId":"https://familyxpense.app/a2ui/catalogs/xpense-spike/v1/catalog.json","sendDataModel":false,
 "components":[{"id":"root","component":"Button","child":"label","variant":"primary",
   "action":{"event":{"name":"go","context":{"name":{"@path":"/name"}}}},
   "checks":[{"condition":{"@call":"required","args":{"value":{"@path":"/name"}}},"message":"Name is required"}]}, …]}}
```

Side findings:
- **Function calls use `@call`.** A hand-written check using `call` failed validation in `a2ui_core 0.8` (`invalid 'checks': Expected to match exactly one schema`). The local `SurfaceBuilder` must emit `@call` and `@path`, exactly as the server does.
- **The same catalog file works on both sides.** `loadCatalog(ai, file: …)` on the server and `Catalog.fromJson` in `a2ui_core 0.8` both read it. The parity test compares component names and property names (test 6).
- **Drop the `_normalizeEnvelopeKeys` helper.** It handles the opposite case (a newer agent sending `@` keys to an older client). It is not needed while the server is on 0.7 and the phone on 0.8.

## Q2. Can A2UI Express assign an array of objects to `$/drafts` and bind a prop to it?

**Yes.** The assignment is folded into the `createSurface`'s `dataModel`; no separate `updateDataModel` is sent. The binding compiles to `{"@path": "/drafts"}`.

Express (exactly the A2UI_CATALOG section 7 example):

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

Compiled by the 0.7 server:

```json
[{"version":"1.0","deleteSurface":{"surfaceId":"cap_k3m9"}},
 {"version":"1.0","createSurface":{"surfaceId":"cap_k3m9",
   "catalogId":"https://familyxpense.app/a2ui/catalogs/xpense-spike/v1/catalog.json","sendDataModel":false,
   "components":[{"id":"root","component":"EntryList","drafts":{"@path":"/drafts"},"status":"review","title":"I found two things in that:"}],
   "dataModel":{"drafts":[{"id":"d1","intent":"income","amountMinor":320000,"currency":"USD","categoryId":"salary","accountId":"acc_chk","who":"me","occurredOn":"2026-11-22","title":"Salary","confidence":{"intent":0.99,"category":0.97,"account":0.96}},
                          {"id":"d2","intent":"expense","amountMinor":140000,"currency":"USD","categoryId":"rent","accountId":"acc_chk","who":"joint","occurredOn":"2026-11-22","title":"Rent","confidence":{"intent":0.98,"category":0.99,"account":0.97},"guessed":["who"]}]}}}]
```

Also verified (all in `q2_compiled_messages.json`):

| Case | Express | Result |
|---|---|---|
| JSON-style quoted keys, `null`, booleans, nested map | `$/drafts = [{"id": "d1", "accountId": null, "duplicate": false, "fx": {"pairRate": "1705"}}]` | compiles; values kept as written |
| One element of the array, later turn, no `root` | `$/drafts/1/who = "me"` | `{"updateDataModel":{"surfaceId":"cap_k3m9","path":"/drafts/1/who","value":"me"}}`, applied on the phone (test 1) |
| An object | `$/result = {total: 48650, rows: [...]}` | compiles into `dataModel.result` |
| ChoicePrompt writing into an array element | `ChoicePrompt("…", [{label, value, hint}, …], $/drafts/0/intent)` | `"value":{"@path":"/drafts/0/intent"}` |

The A2UI_CATALOG section 7 fallback (the server pushes `/drafts` itself) is **not needed**. Two limits remain:
- `drafts` is typed `DynamicValue`, so `a2ui()` checks it only as "any JSON". The `EntryDraft` shape is **not** validated by the middleware. `outputGuard` or `surfaceValid` must do it.
- Whether a real model writes these arrays reliably was not measured (no key).

## Q3. Can a custom component write back (`ComponentProps.writable`), and does a sibling re-render?

**Yes.**

**ChoicePrompt writing an array element.** Tapping "No, gift or payment" called `props.writable('value')!.set('expense')`. That wrote `/drafts/0/intent`, and the sibling `EntryList` (bound to `/drafts`) redrew from `LOAN_GIVEN` to `EXPENSE`. Its build counter rose and no message went to the agent (test 3; screenshots `04_choice_prompt_before.png` and `05_choice_prompt_pick_and_action.png`).

**EntryList editing its own drafts.** `props.writable('drafts')!.set(newList)` replaces the array. A per-field edit therefore writes the whole array back:

```dart
final draftsBinding = props.writable('drafts');      // null unless bound to a path
onToggleWho: (i) {
  final next = [for (final d in drafts) Map<String, Object?>.from(d)];
  next[i]['who'] = next[i]['who'] == 'joint' ? 'me' : 'joint';
  draftsBinding!.set(next);
}
```

**An agent update after a local edit merges cleanly.** After a local edit (Rent: `joint` → `me`), the agent's `updateDataModel` on `/drafts/1/note` was applied, and the local edit was kept (screenshot `03_writeback_and_saved_plus_text.png`).

**With an `action`, the pick is sent too.** When `ChoicePrompt` has an `action`, the pick fires it, and the event context echoes the freshly written value: `xp.answer {field: "intent", value: "expense"}` (test 4; trace `fb492093c0460fc2a7444dc82a9a52f3`).

Limits:
- `writable()` returns null when the prop holds a literal. `EntryList` must treat unbound drafts as read-only, and the agent rule "bind to `$/drafts`" becomes load-bearing.
- **The model never sees local edits.** On later turns `genkit_a2ui` replays the surface's original Express (`metadata.a2uiExpress`), not the phone's data model. In trace `d6fdfd7d…` the phone had changed Rent to `who: "me"` before sending "Saved + text", but the model's input still shows the original block with `who: "joint"`.
- Express accepts `surface("id", sendDataModel=true)`, but `genkit_a2ui 0.6.0` never reads a client data model back. A grep for `a2uiRendererDataModel` finds no hit. Anything the agent must know about an edit has to travel in an action's context.

## Q4. Do locally built raw-map messages render in the same MessageProcessor beside agent surfaces?

**Yes.** `localCaptureSurface()` returns plain maps with no `a2ui_core` types: one `createSurface` carrying `components` and `dataModel`, as in A2UI_CATALOG section 8. It was processed by the same `MessageProcessor` as the streamed agent surfaces and rendered beside them: the yellow "LOCAL" card next to the blue "AGENT" card in screenshots 01 to 03, and test 5.

**New finding: the agent cannot update a phone-built surface.**
- The server checks every block against a mirror of the surfaces *the agent* created.
- A partial update to `local_cap_1` is rejected with "Surface not found for message: local_cap_1" (strict; in `warn` mode it is silently dropped).
- It is still rejected when the phone sends the local `createSurface` as an A2UI data part in the same user turn (`bin/local_surface_probe.dart`). The middleware turns that part into the line `(UI surface local_cap_1 was rendered here.)` for the model, but does not add it to the mirror (`requests/local_surface_probe_request_2.json`).
- A **full re-render with `root`** under the same id is accepted. It replaces the phone's surface, because a `deleteSurface` comes first.

What this means:
- Local surfaces are owned by the phone.
- To involve the agent in a local draft, send the drafts in an action's context (for example `xp.refine {drafts}`). The agent then renders its own surface.
- Local surface ids need their own prefix (`loc_…`), so an agent surface can never replace one by accident.

## Q5. Can one user message carry an action data part plus text?

**Yes**, over HTTP with `remoteAgent`, from both a Dart script and the phone.

The message is `[DataPart({messages:[{version:"1.0", action:{name:"xp.saved", …}}]}, mimeType application/a2ui+json), TextPart("Also, the rent was split with my sister.")]`. The `a2ui()` middleware turns the data part into one line and passes the text through, so the model receives two text parts in one user message:

```json
{"role":"user","content":[
  {"text":"[UI action \"xp.saved\" from root on surface cap_k3m9 context={\"draftIds\":[\"d1\",\"d2\"],\"txnIds\":[\"t_101\",\"t_102\"]}]"},
  {"text":"Also, the rent was split with my sister."}]}
```

Sources:
- From the phone: trace `d6fdfd7d178bda51f36969acf9ca481a` (model span input) and screenshot 03.
- From `bin/http_client.dart`: trace `488d6e87f2f6ee658fe46ae77668ff16`.
- The session history keeps both parts (`client history roles: [user:1, model:2, user:2, model:2]`).

Client helper:

```dart
Message a2uiActionToMessage(ActionMessage action, {String? text}) => Message(
  role: Role.user,
  content: [
    DataPart(data: RendererToAgentMessagePayload.of(action).toJson(),
             metadata: {'mimeType': a2uiMimeType}),
    if (text != null && text.isNotEmpty) TextPart(text: text),
  ],
);
```

The A2UI_CATALOG section 5.2 fallback (sending the note as a line of text) is not needed. Also available: an action may carry `userMessage`. Express `Event(name, ctx, userMessage=…)` sets it, and the middleware appends ` message="…"` to the action line.

## Q6. Per-household context in middleware; FirestoreSessionStore layouts

### Middleware

**Yes.** A `GenerateMiddleware.model` hook reads `ctx.context`:
- Over HTTP, `ctx.context` is the `contextProvider` result.
- In process, it is `chat.send(context: …)`.

Listed before `a2ui()` in `use`, the household block is appended to the system message *before* the A2UI instructions. This is visible in the model span input of traces `072beb9800e467d18a98317e21a54769` (flow `trySpikeAgent`, run through the `genkit` MCP) and `d6fdfd7d…` (HTTP, header-derived context).

```dart
class HouseholdContextMiddleware extends GenerateMiddleware {
  @override
  Future<ModelResponse> model(ModelRequest request, ActionFnArg<…> ctx, … next) {
    final c = ctx.context ?? const {};
    final block = '<<<household\nhid: ${c['hid']}\nmember: ${c['uid']}\n…household>>>';
    // append a TextPart to the system message, then next(newRequest, ctx)
  }
}
```

- The hook runs on **every model call** in the tool loop, so the planned 60 s cache for the Firestore read matters.
- **Privacy:** the whole context map is recorded on agent and model spans as `genkit:metadata:context`. Whatever `householdContext` puts in the context (names, locale) is exported with traces. Keep the context map to ids.

### FirestoreSessionStore (verified against the Firestore emulator only)

Store `genkit_google_cloud 0.3.3`. The source shows its layout is `<collection>/<prefix>/snapshots/{id}`, `<collection>-pointers/<prefix>/pointers/{sessionId}` and `<collection>-shards/<prefix>/shards/{id}_{n}`. The prefix comes from `snapshotPathPrefix(context)` and must not contain `/`. `collection` accepts a nested path.

| Layout | Code | Paths written (`bin/store_probe.dart`) | Isolation |
|---|---|---|---|
| **Prefix** (D-11 as written) | `FirestoreSessionStore(collection: 'agentSessions', snapshotPathPrefix: (c) => '${c?['hid']}_${c?['uid']}')` | `agentSessions/hh_alpha_u_owner/snapshots/…`, `agentSessions-pointers/hh_alpha_u_owner/pointers/…`, `agentSessions-shards/hh_alpha_u_owner/shards/…` | another household reading the same session id gets `null` |
| **Nested** | `HouseholdSessionStore`: one `FirestoreSessionStore(collection: 'households/$hid/agentSessions', snapshotPathPrefix: (c) => c['uid'])` per household, chosen from `context['hid']` (40 lines, `server/lib/household_store.dart`) | `households/hh_alpha/agentSessions/u_owner/snapshots/…`, `households/hh_alpha/agentSessions-pointers/u_owner/pointers/…`, `households/hh_alpha/agentSessions-shards/u_owner/shards/…` | same |

The nested layout cannot come from the prefix alone, because the prefix is a single document id. It needs the wrapper. The wrapper as written implements only `SessionStore`. It drops the store's optional `SnapshotMetadataReader` and `SnapshotChangeNotifier` interfaces, which detach and background agents use, unless they are forwarded too.

**Recommendation for D-11:** keep the prefix layout (`{hid}_{uid}`) with no custom code. Household deletion then removes `agentSessions*/{hid}_*`. Choose the nested layout only if the owner wants sessions inside the household tree; then forward the optional interfaces.

**Stale read:** in about 2 of 12 runs, `getSnapshot(sessionId: …)` read right after a turn returned the *previous* snapshot (2 messages instead of 4). This happened with both layouts. Reading by `snapshotId` was always right. It was not investigated further. Resume by `snapshotId` where possible, and do not assume read-after-write by session id.

## Q7. How many input tokens do the injected catalog instructions cost?

**Measured in characters, estimated in tokens.** `countTokens` needs a Gemini key, which this session did not have. `bin/instruction_size.dart` calls the API when `GEMINI_API_KEY` is set; WP-32 should run it once.

`renderCatalogInstructions(catalog)` is exactly what `a2ui()` appends. It is visible in every model span.

| Catalog | Components | Characters | Words | ≈ tokens (chars/4 … chars/3.5) |
|---|---|---|---|---|
| one component (fixed contract only) | 1 | 7,030 | 1,044 | 1,760 … 2,010 |
| spike | 5 | 11,153 | 1,696 | 2,790 … 3,190 |
| **Xpense sizing draft** (8 basic + 16 custom, per A2UI_CATALOG section 3) | 24 | **22,003** | 3,354 | **5,500 … 6,290** |
| A2UI basic catalog | 18 | 22,560 | 3,372 | 5,640 … 6,450 |

In the Xpense draft:
- About 7,460 characters are the fixed preamble and Express grammar.
- About 11,060 are component signatures.
- About 3,490 are the 10 functions.

Cost:
- **Per model call:** the instructions are injected on every model call. At `gemini-3.5-flash-lite`'s $0.30 per 1M input tokens, that is about **$0.0017 to $0.0019**.
- **Per agent turn:** a capture turn has at least two calls (the `prepareEntries` tool call, then the render). That is about **$0.0035 to $0.0038 per turn, or $3.5 to $3.8 per 1,000 agent turns**, from the instructions alone.
- Gemini's implicit prefix caching may lower this. It was not verified.

Cheap reductions:
- Drop the `weight` property from the copied basic components (8 × 212 ≈ 1,700 characters).
- Drop functions the agent never uses (`regex`, `length`, `numeric`, `pluralize`, `formatDate`).
- Keep descriptions to one line.
- If more is needed, use `a2ui(instructions: 'none')` with a trimmed `renderCatalogInstructions` output in the `.prompt` file.

## Other findings

1. **Enum properties are static in Express.** The signature renderer marks a plain `enum` property `(static)`, and rule 13 of the contract forbids binding it. `EntryList.status`, listed as "dyn enum", cannot be bound and enum-checked at once.
2. **The contract's rule 14 conflicts with optional actions.** It says: "Parameters named 'action' … are strictly required … provide a dummy click event like Event("click")". `ChoicePrompt.action?`, `Nudge.action?` and `Notice.action?` are optional by design. A model following rule 14 would make every pick an agent turn. Not observed (no real model), but the text is in the prompt (`evidence/q7_instructions_spike.txt`).
3. **`sendDataModel` is always `false`.** `genkit_a2ui` ignores client data models (see Q3).
4. **The genkit MCP only finds runtimes in the main checkout.** It discovers runtimes under `~/Developer/family-xpense/.genkit/runtimes/`, while a runtime started in a worktree registers in its own folder. The spike copied the runtime file across once to use `run_flow`. After a restart the MCP did not pick it up again, but `get_trace` still read every trace. Worth knowing for every worktree session.
5. **The server resolves exactly what the docs say:** `a2ui_core 0.7.0`, `a2ui_agent 0.3.0` (ARCHITECTURE section 7, rule 7).

## Changes the docs need (not edited here)

### A2UI_CATALOG.md

1. **Section 7 intro:** remove "exact Express syntax for arrays of objects is verified in WP-S1; if Express cannot assign them, the server pushes `/drafts`…". Replace it with: "`$/path = [...]` assigns arrays and maps (quoted keys, `null` and booleans allowed); in a block with `root` the assignment travels inside `createSurface.dataModel`, otherwise as `updateDataModel`."
2. **Section 3.2 `EntryList.status?`:** change "dyn enum" to a static enum (`review` \| `saved`), and note that the phone keeps post-save state in its own path (for example `/ui/status`), not in the agent's prop. Add a rule to section 2: "an enum-typed property is static in Express; to bind a property, type it `DynamicString` and lose the enum check."
3. **Section 3.2 `ChoicePrompt.action?`, and `Nudge`/`Notice` `action?`:** add the rule-14 risk. The action router drops events named `click`. Either WP-32's prompt overrides rule 14 for these components, or the property is renamed (a breaking change only before v1 ships). WP-32's evaluation checks that picks without `action` produce no agent turn.
4. **Section 3 header:** "dyn (array of `EntryDraft`)" is `DynamicValue` in the catalog JSON. `a2ui()` validates it as any JSON, so the `EntryDraft` shape is checked by `outputGuard` and `surfaceValid`.
5. **Section 5.2:** remove "**Verify in WP-S1**…". State that `xp.saved` travels as an A2UI data part before the text part in the same user message, and the model reads `[UI action "xp.saved" from … context={…}]` followed by the text.
6. **Sections 5.2 and 6, new paragraph:** "The agent sees a surface only as the Express it wrote. Edits made on the phone are invisible to later turns unless an action's context carries them. `sendDataModel` does not help with `genkit_a2ui 0.6`."
7. **Section 8:** function calls in raw maps use `@call` (bindings `@path`); `call` fails validation in `a2ui_core 0.8`. Local surface ids use the prefix `loc_`. The agent cannot update a local surface (Q4), so to hand a local draft to the agent, send it in an action context (`xp.refine {drafts}`) and let the agent render its own surface.
8. **Section 1, parity test:** add "the same JSON loads with `loadCatalog` (server) and `Catalog.fromJson` (`a2ui_core 0.8`); compare `schema.value['properties']` keys" (spike test 6).
9. **Section 2, rule 5 (Small):** add the measured budget. About 22,000 characters (≈ 5,500 to 6,300 tokens) are injected per model call for the 24-component catalog. Drop `weight` from the copied basic components and unused functions; one-line descriptions.

### ARCHITECTURE.md section 7

1. **Rule 3:** add "Local surfaces are owned by the phone. The server validates agent blocks against the surfaces the agent created, so it rejects partial updates to a local surface (even if the phone attaches the `createSurface` to the turn); a full re-render with a root replaces it."
2. **Rule 7:** replace the "temporary dual-read" caveat with the evidence: bare `checks` from the 0.7 server is read by 0.8 (spike test 2). The copy-in `_normalizeEnvelopeKeys` helper is not needed in this direction; do not copy it into `XpenseSurfaceHost`.
3. **New rule:** actions that must reach the agent with typed text are sent as one user message, data part first and text part second (`a2uiActionToMessage(action, text:)`).

### DECISIONS.md

1. **D-11:** change status from Verify to Decided. The prefix layout `agentSessions/{hid}_{uid}` works unchanged, and the nested layout `households/{hid}/agentSessions` works with a per-household store wrapper (Q6). Recommend prefix. Note the stale read by session id.
2. **Section 3, "What was verified":** add a WP-S1 row; remove "Express syntax for arrays of objects" from the "Not verified" line.

### AI_PIPELINE.md

1. **Section 8, Definition:** `householdContext()` before `a2ui()` puts the household block ahead of the A2UI instructions (verified). The context map is recorded in trace attributes, so keep it to ids.
2. **Section 12, cost:** add about 5,500 to 6,300 input tokens per agent model call for the catalog instructions (estimate; exact count pending a key).

### RISKS.md

1. **R-17:** the Express array syntax is confirmed. Lower the likelihood, and replace the trigger with "model omits or misorders positional args" (real-model rate still unmeasured). Add the rule-14 dummy-action risk.
2. **R-02:** add "verified in WP-S1 with the server's real output, including bare `checks`."

## Not verified

- **Real model behaviour:** no Gemini API key was available, so all agent text came from the scripted model. Untested: whether Gemini writes valid Express arrays, respects static properties and positional order, or adds dummy `Event("click")` actions. Also untested: `repair: true`.
- **Exact token counts:** Q7 gives characters and a range only.
- **Real Firestore:** only the Firestore emulator was used. The stale read by session id was seen on the emulator only.
- **The nested store wrapper:** not tested with detach, background or `getSnapshot` HTTP routes (it does not forward the optional interfaces).
- **A physical iPhone:** simulator only (iPhone 17 Pro, iOS 26.5).
- **D-22 bridge:** the spike client uses the bundled `MaterialApp`, not the `material_ui` set-up from D-22.
- **The genkit MCP `run_flow` after the server restart:** the MCP stopped finding the runtime. Traces from that run were read from the trace store, and the in-process flow trace `072beb98…` predates the final small changes to the scripted model (reply rules and log file names only).
