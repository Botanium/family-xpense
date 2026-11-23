# Family Xpense: Data Model

Firestore in Native mode, offline persistence on. Everything a household owns lives under `households/{hid}`. Decisions referenced as `D-nn` are in [DECISIONS.md](DECISIONS.md).

## 1. Money and FX rules

These rules apply to every field that holds money. The pure-Dart implementation lives in `packages/xpense_shared/lib/money/` and is shared by app and server.

| Rule | Detail |
|---|---|
| Type | `int` minor units plus an ISO currency code. Never `double`. |
| Exponent table | Explicit, app-owned: `USD → 2`, `IQD → 0`. Unknown code is a typed failure, never a default. |
| Why IQD is 0 | ISO 4217 lists 3 (fils) but CLDR lists 0, the smallest note is 250, and no fils circulate. Storing whole dinars avoids a 1,000× trap. The table is versioned (`moneySchema: 1`) so a redenomination can be migrated (D-14). |
| One currency per account | A transaction's `currency` always equals its account's currency. |
| Base amount | Every transaction also stores `baseAmountMinor` in the household base currency, computed once at save time and never recomputed. Reports sum this field. |
| Stored rate | `fx.pair` is always `"USD/IQD"` style (market convention), `fx.pairRate` is a decimal **string** (for example `"1520"`), never a float. |
| Rate source | A member enters the day's USD/IQD rate when the app asks (once a day). `official` or `market` is the household's label for that rate; `manual` marks a rate typed for a single transaction. No rate is fetched automatically (D-16). |
| Rounding | Half-even, once, when computing `baseAmountMinor`. Cash IQD is not snapped to 250; what the user says is what is stored. |
| Splits | Every division of money (receipt split, shared items) goes through `allocate()` (largest remainder), so parts sum exactly to the total. |
| Derived totals | Month totals, category totals and goal progress are derived on read. The only stored aggregates are `account.balanceMinor` and `loan.outstandingMinor`, which are maintained by increments and re-verified nightly (section 7). |
| Digits | Western digits only for now. Folding of Arabic-Indic and Persian digits arrives with the deferred languages (D-36). |
| Time | Stored as UTC `Timestamp`. `occurredOn` (local calendar date string, `YYYY-MM-DD`, household time zone) is stored too, so day grouping never shifts. |

## 2. Collections

```
users/{uid}
users/{uid}/devices/{deviceId}
invites/{codeHash}                         server-only
config/runtime                             server-only tunables
agentSessions*, agentSessions-pointers*, agentSessions-shards*   server-only (D-11)
households/{hid}
  members/{uid}
  accounts/{accountId}
  transactions/{txnId}
    revisions/{revId}
  categories/{categoryId}
  people/{personId}
  loans/{loanId}
  goals/{goalId}
  budgets/{budgetId}
  recurring/{recurringId}
  rules/{ruleId}
  fxRates/{yyyy-mm-dd}                     the day's rate, entered by a member
  notifications/{notificationId}
  usage/{yyyy-mm-dd}                       server-only AI counters
```

All documents carry `createdAt`, `updatedAt` (server timestamps), `createdBy`, `updatedBy` (uid or `"system"`) and `schemaVersion`. Document ids for anything created on the phone are client-generated UUID v7, so offline creates are idempotent.

### 2.1 `users/{uid}`
| Field | Type | Notes |
|---|---|---|
| `displayName` | string | |
| `locale` | `en` | UI language; only English for now (D-36) |
| `householdId` | string? | one household per user in v1 |
| `deletionRequestedAt` | timestamp? | account deletion flow |

`devices/{deviceId}`: `fcmToken`, `platform`, `appVersion`, `lastSeenAt`, `onDeviceModel` (`none` \| `apple_fm` \| `gemma` \| `nano`).

### 2.2 `households/{hid}`
| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `baseCurrency` | `USD` \| `IQD` | set at creation; changing it later is a migration, not an edit |
| `timeZone` | IANA string | default `Asia/Baghdad` |
| `memberIds` | string[] (max 2) | used by rules; written by the server only |
| `rateKind` | `official` \| `market` | label for the rate the household enters each day, default `market` |
| `rateAskedOn` | date string? | last day the daily rate prompt was answered or dismissed |
| `cloudInsights` | bool | false when any member is On-device only; gates LLM narration in jobs |
| `weekStart` | `sat` \| `sun` \| `mon` | default `sat` |
| `moneySchema` | int | currently 1 |

### 2.3 `members/{uid}`
`displayName`, `initial`, `role` (`owner` \| `partner`), `privacyMode` (`on_device` \| `smart` \| `cloud`), `notificationPrefs` (map of nudge type → bool), `joinedAt`.

### 2.4 `accounts/{accountId}`
| Field | Type | Notes |
|---|---|---|
| `name` | string | "Cash wallet", "Joint Visa ••4021" |
| `kind` | `cash` \| `bank` \| `credit` \| `savings` \| `other` | credit balances are negative |
| `currency` | `USD` \| `IQD` | immutable after the first transaction |
| `scope` | `personal` \| `joint` | |
| `ownerUid` | string? | set when `scope == personal` |
| `sharedWithPartner` | bool | personal accounts only; false means private |
| `visibleTo` | string[] | derived: `[ownerUid]`, or both member ids when joint or shared |
| `balanceMinor` | int | maintained aggregate |
| `balanceCheckedAt` | timestamp | last nightly reconcile |
| `archived` | bool | |
| `order` | int | list order |

### 2.5 `transactions/{txnId}`
One document per money event. A transfer is one document with both accounts (D-12).

| Field | Type | Notes |
|---|---|---|
| `type` | `expense` \| `income` \| `transfer` \| `loan_given` \| `loan_taken` \| `repayment_received` \| `repayment_made` \| `adjustment` | ledger type |
| `amountMinor` | int, > 0 | sign comes from `type` |
| `currency` | string | equals the account currency |
| `accountId` | string | the account money leaves (or enters, for `income`, `loan_taken`, `repayment_received`) |
| `toAccountId` | string? | transfers only |
| `toAmountMinor` | int? | transfers between currencies: amount that arrives |
| `baseAmountMinor` | int | in household base currency |
| `fx` | map? | `{pair, pairRate, source, asOf}`; absent when currency equals base |
| `categoryId` | string? | required for `expense` and `income` |
| `who` | `me` resolved to a uid, or `joint` | stored as `whoUid` (string?) plus `whoScope` (`member` \| `joint`) |
| `occurredAt` | timestamp | |
| `occurredOn` | string `YYYY-MM-DD` | household-local date |
| `title` | string | merchant or short label, max 80 chars |
| `note` | string? | max 500 chars |
| `personId` | string? | counterparty for loans and repayments |
| `loanId` | string? | |
| `goalId` | string? | savings moves |
| `recurringId` | string? | posted from a recurring template |
| `groupId` | string? | entries saved together (multi-entry message, receipt split) |
| `source` | `chat` \| `voice` \| `receipt` \| `manual` \| `recurring` \| `import` \| `shortcut` | |
| `ai` | map? | `{path, confidence: {intent, category, account, who}, guessedFields[], rawText?}`; `rawText` is kept only when the member allows history |
| `receipt` | map? | `{merchant, total, lineCount, storagePath?}`; images stay on the phone unless backup is on |
| `visibleTo` | string[] | union of the `visibleTo` of `accountId` and `toAccountId` |
| `deletedAt` | timestamp? | soft delete; hidden from lists, kept for undo and audit |
| `rev` | int | increments on every edit |

`revisions/{revId}`: append-only. `{rev, before (map of changed fields), changedBy, changedAt, reason: edit | undo | delete | restore | system}`.

### 2.6 `categories/{categoryId}`
`slug` (stable, for example `groceries`), `names` (a map by language code; only `en` is filled for now), `kind` (`expense` \| `income`), `parentId?`, `colorKey` (design token name, not a hex), `iconKey`, `order`, `system` (bool), `archived`. The default tree is in [AI_PIPELINE.md](AI_PIPELINE.md) section 4 and is seeded when the household is created.

### 2.7 `people/{personId}`
Counterparties for loans and for "person → account" rules. `name`, `aliases[]`, `memberUid?` (when the person is a household member), `visibleTo`.

### 2.8 `loans/{loanId}`
| Field | Type | Notes |
|---|---|---|
| `direction` | `given` \| `taken` | |
| `kind` | `personal` \| `institution` | |
| `personId` | string | |
| `principalMinor`, `currency` | int, string | |
| `outstandingMinor` | int | maintained aggregate |
| `startedOn`, `dueOn?` | date strings | |
| `installment` | map? | `{amountMinor, dayOfMonth}` for bank loans |
| `accountId` | string? | default account for repayments |
| `scope`, `ownerUid`, `visibleTo` | | same model as accounts |
| `status` | `open` \| `closed` | closes when outstanding reaches 0 |
| `reminder` | map? | `{daysBefore, targetUids[]}` |

### 2.9 `goals/{goalId}`
`name`, `targetMinor`, `currency`, `targetDate?`, `accountId` (a `savings` account; one goal per account in v1), `monthlyPlanMinor?`, `scope`, `visibleTo`, `archived`. Progress is the backing account's balance.

### 2.10 `budgets/{budgetId}`
`categoryId` or `"total"`, `period: monthly`, `limitMinor` (base currency), `alertAt` (`[0.8, 1.0]`), `scope` (`household` \| a uid), `visibleTo`.

### 2.11 `recurring/{recurringId}`
`template` (an entry draft: type, amount, currency, account, category, who, title), `cadence` (`{unit: month | week, interval, dayOfMonth?, weekday?}`), `nextDueOn`, `mode` (`auto` \| `remind` \| `off`), `status` (`suggested` \| `active` \| `paused`), `detectedBy` (`system` \| `user`), `lastTxnId?`, `visibleTo`.

### 2.12 `rules/{ruleId}`
Learned from corrections, applied by the on-device fast parser.

`kind` (`merchant` \| `keyword` \| `person`), `pattern` (normalised, lower-case), `sets` (`{categoryId?, accountId?, whoScope?, whoUid?, type?, currency?}`; `currency` is planned with BACKLOG S3.15), `ownerUid?` (personal rule) or household-wide, `hits`, `lastUsedAt`, `fromTxnId`, `visibleTo`.

### 2.13 `fxRates/{yyyy-mm-dd}` (under the household)

`{usdIqd: "1705", kind: official | market, enteredBy, enteredAt}`. One document per household-local day, written when a member answers the daily rate prompt (ARCHITECTURE 3.5).

- A conversion on a given date uses that day's document, or the most recent earlier one when the day has none.
- The rate is a decimal string in the `USD/IQD` convention.
- Editing a past day's rate does not change transactions already saved; each keeps the rate it was saved with.
- There is no global rate collection and no rate job. An automatic feed is a later option.

### 2.14 `notifications/{notificationId}`
`type` (`budget_warning` \| `bill_missed` \| `loan_due` \| `recurring_suggested` \| `monthly_report` \| `partner_activity` \| `rate_ask` \| `queue_ready`), `titleKey`, `bodyKey`, `params` (map; the phone localises), `action` (`{route, args}`), `targetUids[]`, `readBy[]`, `dedupeKey`, `expiresAt`.

### 2.15 Server-only documents
- `invites/{codeHash}`: `{hid, createdBy, expiresAt, usedBy?}`. Codes are 10 base32 characters, valid 7 days, single use. Only the SHA-256 is stored.
- `usage/{yyyy-mm-dd}` under a household: `{agentTurns, decisions, audioSeconds, images, inputTokens, outputTokens, costMicrosUsd}`.
- `config/runtime`: model ids, per-household daily limits, feature switches for the server.
- `agentSessions*`: Genkit `FirestoreSessionStore` data, prefixed per household and member.

## 3. Balance and aggregate maintenance

A save is one batched write:

1. `set` the transaction.
2. `update` the account with `FieldValue.increment(±amountMinor)`; for transfers, both accounts.
3. For loan events, `increment` `loan.outstandingMinor`.
4. For an edit or delete: write the revision, then apply the difference as increments.

Batched writes with increments work offline and commute, so two partners editing different entries offline never corrupt a balance. Firestore `runTransaction` is not used for saves, because it fails offline.

Effect on balances by type:

| Type | `accountId` | `toAccountId` |
|---|---|---|
| expense, loan_given, repayment_made | − amount | |
| income, loan_taken, repayment_received | + amount | |
| transfer | − amount | + `toAmountMinor` (or amount) |
| adjustment | ± (signed in `adjustmentSign`) | |

`/jobs/reconcile` recomputes every balance and loan total from the ledger nightly, corrects drift, and writes a `system` revision plus a log entry when it finds any.

## 4. Privacy model

- A personal account with `sharedWithPartner == false` is readable only by its owner.
- Rules are not filters, so every list query must be provable. Documents that inherit account privacy (`transactions`, `loans`, `goals`, `rules`, `people`, `recurring`, `budgets`) carry a denormalised `visibleTo` array, and every query includes `where('visibleTo', arrayContains: uid)`.
- When an owner flips `sharedWithPartner`, the phone updates the account; an Eventarc-triggered job (`/events/account-visibility`) rewrites `visibleTo` on that account's transactions in pages of 400. Until it finishes, the partner sees a partial history; the account row shows "Sharing…".
- A transfer from a private account into a joint one is visible to both. The partner sees the amount and "Private account" in place of the source name.
- Household totals on a member's Home include only what that member can see. The label says "Household balance" when everything is visible to them and "Your view" otherwise.

## 5. Security rules

Target file: `firebase/firestore.rules`. Tested with `@firebase/rules-unit-testing` against the emulator (`firebase/test/`).

```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {

    function signedIn() { return request.auth != null; }
    function uid() { return request.auth.uid; }
    function household(hid) {
      return get(/databases/$(db)/documents/households/$(hid)).data;
    }
    function isMember(hid) { return signedIn() && uid() in household(hid).memberIds; }
    function canSee() { return uid() in resource.data.visibleTo; }
    function willSee() { return uid() in request.resource.data.visibleTo; }
    function visibleToIsMembers(hid) {
      return request.resource.data.visibleTo.hasOnly(household(hid).memberIds)
          && request.resource.data.visibleTo.size() >= 1;
    }
    function stamps() {
      return request.resource.data.updatedBy == uid()
          && request.resource.data.updatedAt == request.time;
    }

    match /users/{userId} {
      allow read, write: if signedIn() && uid() == userId;
      match /devices/{deviceId} { allow read, write: if signedIn() && uid() == userId; }
    }

    match /invites/{code} { allow read, write: if false; }
    match /config/{doc} { allow read, write: if false; }
    match /{sessionCollection}/{doc=**} {
      allow read, write: if false;   // agentSessions* are server-only
    }

    match /households/{hid} {
      allow get: if isMember(hid);
      allow list: if false;
      allow create: if signedIn()
        && request.resource.data.memberIds == [uid()]
        && request.resource.data.baseCurrency in ['USD', 'IQD'];
      allow update: if isMember(hid)
        && !request.resource.data.diff(resource.data).affectedKeys()
             .hasAny(['memberIds', 'baseCurrency', 'moneySchema', 'cloudInsights']);
      allow delete: if false;

      match /members/{memberId} {
        allow read: if isMember(hid);
        allow create: if false;                       // server (join endpoint)
        allow update: if isMember(hid) && uid() == memberId
          && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['role']);
      }

      match /accounts/{id} {
        allow read: if isMember(hid) && canSee();
        allow create: if isMember(hid) && willSee() && visibleToIsMembers(hid) && stamps()
          && (request.resource.data.scope == 'joint'
              || request.resource.data.ownerUid == uid());
        allow update: if isMember(hid) && canSee() && willSee() && visibleToIsMembers(hid) && stamps()
          && request.resource.data.currency == resource.data.currency
          && request.resource.data.ownerUid == resource.data.ownerUid;
        allow delete: if false;                       // archive instead
      }

      match /transactions/{id} {
        allow read: if isMember(hid) && canSee();
        allow create: if isMember(hid) && willSee() && visibleToIsMembers(hid) && stamps()
          && request.resource.data.amountMinor is int
          && request.resource.data.amountMinor > 0
          && request.resource.data.baseAmountMinor is int
          && request.resource.data.currency in ['USD', 'IQD']
          && request.resource.data.type in ['expense','income','transfer','loan_given',
               'loan_taken','repayment_received','repayment_made','adjustment']
          && exists(/databases/$(db)/documents/households/$(hid)/accounts/$(request.resource.data.accountId))
          && get(/databases/$(db)/documents/households/$(hid)/accounts/$(request.resource.data.accountId))
               .data.visibleTo.hasAny([uid()]);
        allow update: if isMember(hid) && canSee() && willSee() && visibleToIsMembers(hid) && stamps()
          && request.resource.data.rev == resource.data.rev + 1
          && request.resource.data.createdBy == resource.data.createdBy;
        allow delete: if false;                       // soft delete only

        match /revisions/{rev} {
          allow read: if isMember(hid)
            && uid() in get(/databases/$(db)/documents/households/$(hid)/transactions/$(id)).data.visibleTo;
          allow create: if isMember(hid) && request.resource.data.changedBy == uid();
          allow update, delete: if false;
        }
      }

      // Same visibility pattern; no extra field checks beyond stamps.
      match /{coll}/{id} {
        allow read: if coll in ['loans','goals','budgets','recurring','rules','people']
          && isMember(hid) && canSee();
        allow create: if coll in ['loans','goals','budgets','recurring','rules','people']
          && isMember(hid) && willSee() && visibleToIsMembers(hid) && stamps();
        allow update: if coll in ['loans','goals','budgets','recurring','rules','people']
          && isMember(hid) && canSee() && willSee() && visibleToIsMembers(hid) && stamps();
        allow delete: if coll in ['rules','budgets','recurring'] && isMember(hid) && canSee();
      }

      match /categories/{id} {
        allow read: if isMember(hid);
        allow create, update: if isMember(hid) && stamps();
        allow delete: if false;                       // archive instead
      }

      match /fxRates/{day} {
        allow read: if isMember(hid);
        allow write: if isMember(hid) && request.resource.data.enteredBy == uid();
      }

      match /notifications/{id} {
        allow read: if isMember(hid) && uid() in resource.data.targetUids;
        allow update: if isMember(hid) && uid() in resource.data.targetUids
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['readBy']);
        allow create, delete: if false;               // server
      }

      match /usage/{day} { allow read, write: if false; }
    }
  }
}
```

Notes for the implementer:

- The wildcard `/{sessionCollection}/{doc=**}` block must be written as explicit matches for `agentSessions`, `agentSessions-pointers` and `agentSessions-shards`; a top-level catch-all would shadow the other matches. It is shown compactly here.
- Balance increments are not verified field-by-field in rules. Two trusted members plus the nightly reconcile are the control (D-13).
- Rules tests must cover at least: a non-member reads nothing; a partner cannot read a private account or its transactions; a partner cannot list transactions without the `visibleTo` filter; `memberIds` cannot be changed from the phone; `visibleTo` cannot name a non-member; `rev` must advance by exactly 1; hard deletes are refused; server-only collections refuse every phone read and write.

`firebase/storage.rules`: `households/{hid}/receipts/{txnId}/{file}` readable and writable by a member who can see the transaction (checked with `firestore.get`), images only, 5 MB maximum.

## 6. Indexes

`firebase/firestore.indexes.json`. All are collection-scope on the sub-collection.

| Collection | Fields | Used by |
|---|---|---|
| transactions | `visibleTo` (array), `deletedAt`, `occurredAt` desc | Activity, Home recent |
| transactions | `visibleTo` (array), `occurredOn` asc | month totals, daily chart |
| transactions | `visibleTo` (array), `accountId`, `occurredAt` desc | account detail |
| transactions | `visibleTo` (array), `categoryId`, `occurredOn` desc | category drill-down, budgets |
| transactions | `visibleTo` (array), `type`, `occurredAt` desc | Activity filters |
| transactions | `visibleTo` (array), `loanId`, `occurredAt` desc | loan history |
| transactions | `visibleTo` (array), `whoUid`, `occurredAt` desc | "You / Partner" filter |
| transactions | `visibleTo` (array), `amountMinor`, `occurredOn` | duplicate check |
| accounts | `visibleTo` (array), `archived`, `order` | Accounts tab |
| loans | `visibleTo` (array), `status`, `dueOn` | Loans, due reminders |
| recurring | `status`, `nextDueOn` | `/jobs/recurring` (server) |
| notifications | `targetUids` (array), `createdAt` desc | notifications centre |
| rules | `visibleTo` (array), `kind`, `lastUsedAt` desc | rule cache sync |

Search in Activity is client-side over the cached month window (title, note, category name, amount). A household creates a few hundred entries a month, so no search service is needed.

## 7. Offline, conflicts and audit

| Case | Behaviour |
|---|---|
| Create offline | Client id, batched write, appears at once with a "syncing" dot until acknowledged. |
| Same entry edited by both partners | Last write wins per document; both edits are in `revisions`, so either can be restored. `rev` must advance by 1, so the losing write is rejected and the app re-applies it on top of the new state. |
| Undo after save | Soft delete (`deletedAt`) with reversing increments; 10-second undo toast, and "Restore" in history afterwards. |
| Balance drift | Nightly reconcile from the ledger. |
| Clock skew | `occurredAt` comes from the phone; `createdAt` and `updatedAt` are server timestamps. |

## 8. Migrations

- Every document has `schemaVersion`. Readers accept the current and the previous version.
- Additive changes need no migration. Breaking changes ship as a server job `/jobs/migrate/{name}` that pages through households, is idempotent, and records progress in `config/migrations/{name}`.
- `moneySchema` on the household guards the currency exponent table. A dinar redenomination would be `moneySchema: 2` with a one-off rewrite of IQD amounts.
- Changing `baseCurrency` is a migration that recomputes `baseAmountMinor` from stored rates; it is not offered in v1.

## 9. Retention

| Data | Kept |
|---|---|
| Transactions, revisions | until the household is deleted |
| Agent sessions | 30 days, then deleted by `/jobs/retention` |
| `ai.rawText` on transactions | only if the member's "Keep what I said" setting is on (default on in Smart and Cloud, off in On-device) |
| Receipt images | on the phone only, unless receipt backup is on |
| Usage counters | 13 months |
| Used or expired invites | 30 days |

Account deletion (`POST /account/delete`) removes the Auth user, `users/{uid}`, the member document and all personal-scope data. Joint data stays with the remaining partner; if no member remains, the household is deleted.
