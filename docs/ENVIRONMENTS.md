# Family Xpense: Environments

Runbook of what WP-01 set up on 2026-11-22, and how to repeat or check it. No
secrets are written here: no API key strings, debug tokens or service-account
keys. The repository is public.

## 1. At a glance

| | Development | Production |
|---|---|---|
| Project name | Expense Family | not created yet (D-38) |
| Project id | `expense-family-cc6ee` | planned `xpense-prod` (suffixed if taken) |
| Project number | 648682359990 | |
| Firebase alias | `dev` in `firebase/.firebaserc` | |
| Billing | Blaze, linked to the owner's billing account | |
| Region | `me-central1` (Doha) for everything regional (D-18) | `me-central1` |
| iOS bundle id | `com.bitrelia.familyxpense` | same |
| App Check | App Attest registered; debug tokens allowed; not enforced yet | App Attest only, enforced on Firestore and Storage |
| Data | test and seed data only | real |

The docs written before D-38 say `xpense-dev`. For any command that reaches a
real project, read that as `expense-family-cc6ee`. Emulators keep their fake
ids (`demo-xpense`, and `xpense-dev` in WP-05's rules tests); those never reach
a real project.

## 2. Rules for every command

- `gcloud`: pass **both** `--project=expense-family-cc6ee` and
  `--billing-project=expense-family-cc6ee`. The second matters: for some
  command groups (`gcloud billing …`, `gcloud services api-keys …`) `--project`
  only names the resource, and the request is billed to the machine's
  *active* gcloud project, which belongs to something else and must never be
  used. WP-01 hit this twice with read-only calls; both were refused because
  that project lacks the APIs, and nothing changed there.
- `firebase`: run from `firebase/` and pass `--project expense-family-cc6ee`
  (or `--project dev`).
- Raw REST calls: send `x-goog-user-project: expense-family-cc6ee`.
- Never run `gcloud config set project`. The active project is not ours.
- In zsh, keep repeated flags in an array (`B=(--project=… --billing-project=…)`,
  then `gcloud … $B`); a plain string variable is passed as one word.

## 3. Development project, step by step

### 3.1 Project choice and clean-up (owner and the planning session)

The owner chose to reuse an existing test project, "Expense Family", and to
"start new and fresh within that project" (D-38). Before WP-01 began, the
planning session deleted the old Cloud Run service `family-xpense-api`, the
Artifact Registry repository `family-xpense-containers`, the old `(default)`
Firestore database (it was in `me-central2`) and the two test Auth users.
During WP-01 the owner's side also removed the old secret
`family-xpense-gemini-api-key`, the service accounts `family-xpense-run` and
`fx-deploy-gate-signer`, and the custom roles `familyXpenseAuthLookup` and
`familyXpenseFirestore`. WP-01 deleted nothing.

Kept from before: the iOS app registration, Google and email/password sign-in,
the default Firebase and Compute service accounts, and two AI Studio key
service accounts `ais-gemini-key-*` with the old API key "Family Expense API
Key" (owner to decide; see section 6).

### 3.2 Region check (D-18)

Done in this project before anything regional was created:

| Service | Check | Result |
|---|---|---|
| Firestore | `gcloud firestore locations list` | `me-central1` (Doha) listed |
| Cloud Run | `gcloud run regions list` | listed |
| Cloud Scheduler | `gcloud scheduler locations list` | listed |
| Eventarc | `gcloud eventarc locations list` | listed |
| Secret Manager | `gcloud secrets locations list` | listed |
| Cloud Storage for Firebase | default bucket created there (3.5) | created in `ME-CENTRAL1` |

Every service enabled and was available in `me-central1`; no fallback region
was needed.

### 3.3 APIs

Enabled by WP-01: `cloudscheduler`, `eventarc`, `firebaseappcheck`,
`firebasestorage`, `apikeys` (all `.googleapis.com`).

Already enabled: `run`, `secretmanager`, `firestore`, `datastore`,
`identitytoolkit`, `securetoken`, `fcm`, `pubsub`, `iam`, `iamcredentials`,
`logging`, `monitoring`, `cloudtrace`, `telemetry`, `artifactregistry`,
`generativelanguage`, `firebase`, `firebaserules`, `firebaseinstallations`,
`firebaseremoteconfig`, `storage`, and others.

Not enabled yet (the server deploy needs it): `cloudbuild` (server/DEPLOY.md step 2).

### 3.4 Firestore

- Database `(default)`, Native mode, `me-central1`, delete protection on.
  Created by the planning session on 2026-11-22 after the old one was
  deleted.
- Rules: `firebase/firestore.rules` (WP-05) released to `cloud.firestore` on
  2026-11-22 with
  `firebase deploy --project expense-family-cc6ee --only firestore:rules`
  from `firebase/`. This replaced a ruleset left over from the old test
  project. The released source was compared with the repository file and
  matches.
- Indexes: the 13 composite indexes in `firebase/firestore.indexes.json`
  were created on 2026-11-22 with `gcloud firestore indexes composite create`
  (one call per index, `--database=(default)`). `firebase deploy --only
  firestore:indexes` could not be used from this Mac: every Firebase CLI
  15.34.2 request to `firestore.googleapis.com` hung ("HTTP/2 headers
  timeout"), while gcloud and the CLI's calls to the Rules API worked. Try the
  CLI again first next time; if it hangs, create each index with gcloud from
  the JSON, as was done here. No field overrides exist yet. All 13 reached
  `READY` on 2026-11-22; none failed.
- `firebase.json` names no `database`. With `"database": "(default)"` the CLI
  tried to create the existing `cloud.firestore` release and failed with
  HTTP 409.

### 3.5 Cloud Storage for Firebase

- Default bucket `expense-family-cc6ee.firebasestorage.app`, location
  `ME-CENTRAL1`, class STANDARD. Created through the REST API, since the
  console offers a region picker but the CLI does not:
  `POST https://firebasestorage.googleapis.com/v1alpha/projects/expense-family-cc6ee/defaultBucket`
  with body `{"location":"me-central1"}`.
- Public access prevention: **enforced** (receipts are private; Firebase
  access goes through rules, not public URLs). Soft delete: 7 days (default).
- Rules: `firebase/storage.rules` (WP-05), released to
  `firebase.storage/expense-family-cc6ee.firebasestorage.app` on 2026-11-22
  (`firebase deploy --project expense-family-cc6ee --only storage`). The
  released source matches the repository file.
- Buckets outside the US have no free tier; usage is billed at standard
  Cloud Storage prices. Expected usage (opt-in receipt backups, ≤ 5 MB each)
  is small.

### 3.6 Authentication

| Provider | State | Set up by |
|---|---|---|
| Email and password | on, password required | before WP-01 |
| Google | on (OAuth client created by the console) | before WP-01 |
| Apple | on, for the iOS bundle `com.bitrelia.familyxpense` only | WP-01 |

- Apple was enabled with the Identity Toolkit admin API:
  `POST …/admin/v2/projects/expense-family-cc6ee/defaultSupportedIdpConfigs?idpId=apple.com`
  with `{"enabled":true,"appleSignInConfig":{"bundleIds":["com.bitrelia.familyxpense"]}}`.
  Native iOS sign-in needs nothing else in Firebase. A Services ID and key
  (code flow) are only needed for web or Android sign-in, which v1 does not
  have.
- Improved email privacy (no account enumeration) is on. Email verification
  is enforced by the app (D-24).
- Authorized domains: `localhost`, `expense-family-cc6ee.firebaseapp.com`,
  `expense-family-cc6ee.web.app`.

### 3.7 iOS app and config file

- Firebase iOS app "Family Xpense", bundle id `com.bitrelia.familyxpense`, app
  id `1:648682359990:ios:b2b46595d20bceaf172a17` (registered before WP-01).
- Apple Team ID on the app: `7TMGB6MVP7`, set on 2026-11-22 with the
  Firebase Management API
  (`PATCH …/v1beta1/projects/expense-family-cc6ee/iosApps/<app id>?updateMask=teamId`).
  It was read from the OU field of the owner's Apple Development signing
  certificate. The code in parentheses in that certificate's name is the
  personal certificate id, not the team. App Attest and Sign in with Apple
  need it. A Team ID is not a secret; it is in every app the team signs.
- The repository's Xcode project still uses the placeholder bundle id
  `app.familyxpense.xpenseApp`; it must become `com.bitrelia.familyxpense`
  before the app can talk to this project (owner of `app/ios/`).
- The Firebase iOS API key ("iOS key (auto created by Firebase)") is
  restricted to the bundle id `com.bitrelia.familyxpense` (WP-01) and to the
  Firebase APIs it was created with.
- Config file `GoogleService-Info.plist`: kept **out of git** (root
  `.gitignore`). A copy is at
  `~/Developer/family-xpense/app/ios/config/dev/GoogleService-Info.plist` in
  the main checkout. To fetch it again (any checkout):

  ```bash
  cd firebase
  firebase apps:sdkconfig IOS 1:648682359990:ios:b2b46595d20bceaf172a17 \
    --project expense-family-cc6ee -o ../app/ios/config/dev/GoogleService-Info.plist
  ```

  How the app loads it for `XPENSE_ENV=dev` (copy step in the Xcode build, or
  `FirebaseOptions` from a `--dart-define-from-file`) is left to the owner of
  `app/ios/` and `bootstrap.dart`. `Firebase.initializeApp()` with no options
  reads the plist from the app bundle, and Google sign-in also needs its
  `REVERSED_CLIENT_ID` as a URL scheme in `Info.plist`.

### 3.8 App Check

- iOS app: **App Attest** provider registered (token lifetime 1 hour), with
  the Team ID set (3.7). Not yet exercised from a device: that needs the App
  Attest capability on the App ID and the entitlement in the app.
- DeviceCheck: not configured. Both household phones (D-37) support App
  Attest; the app's `AppleAppAttestWithDeviceCheckFallbackProvider` falls back
  to DeviceCheck only on iOS versions before 14.
- Debug provider (simulator, CI): allowed **in this project only**. Each
  developer registers their own debug token: run a debug build, copy the
  token the App Check SDK logs, then Firebase console → App Check → Apps →
  Family Xpense → ⋮ → Manage debug tokens → Add. Debug tokens are secrets:
  never commit or paste them into issues, PRs or chat.
- Enforcement: **off** for Firestore, Storage and Auth in development, so the
  simulator and early builds are not blocked while the App Check flow is
  being built. Turn it on in development once a simulator build has shown
  verified App Check requests in the console. The server checks App Check
  tokens on every `/v1` route regardless (ARCHITECTURE 4.4).

### 3.9 Secret Manager

- Secret `GEMINI_API_KEY`: user-managed replication in `me-central1` only;
  labels `app=xpense`, `owner=wp-01`.
- Version 1: added by the owner from their own terminal; **enabled**, created
  2026-11-22 18:26 UTC, stored in `me-central1`. Checked with
  `gcloud secrets versions list` only; the value was never printed or read.
- Open question (section 6, step 5): when version 1 was checked, this
  project's API key list still showed only the old "Family Expense API Key"
  for the Gemini API, plus both old `ais-gemini-key-*` service accounts. No
  new key was visible here. Either the new key was created in another
  project, or the old key was stored.
- Accessors (`roles/secretmanager.secretAccessor` on this secret only):
  `xpense-agent-run` and `xpense-jobs-run`.
- The key must be **paid tier** (D-34): create it in a project with billing
  on, and check that AI Studio shows a paid tier for it, not "Free".

### 3.10 Service accounts and permissions

All in `expense-family-cc6ee`, created by WP-01. None has a key file; Cloud
Run, Scheduler and Eventarc use them as attached identities.

| Service account | Used by | Grants |
|---|---|---|
| `xpense-agent-run@expense-family-cc6ee.iam.gserviceaccount.com` | Cloud Run `xpense-agent` (runtime) | `roles/datastore.user`, conditional on database `(default)` only · custom `xpenseAgentAuthUsers` (`firebaseauth.users.get`, `firebaseauth.users.delete`) · `roles/telemetry.writer` · secret accessor on `GEMINI_API_KEY` · `roles/storage.objectUser` on the default bucket only |
| `xpense-jobs-run@expense-family-cc6ee.iam.gserviceaccount.com` | Cloud Run `xpense-jobs` (runtime) | `roles/datastore.user`, conditional on `(default)` · custom `xpenseJobsMessaging` (`cloudmessaging.messages.create`) · `roles/telemetry.writer` · secret accessor on `GEMINI_API_KEY` |
| `xpense-scheduler@expense-family-cc6ee.iam.gserviceaccount.com` | Cloud Scheduler OIDC identity | none yet; `roles/run.invoker` on the `xpense-jobs` service only, granted when that service is deployed |
| `xpense-eventarc@expense-family-cc6ee.iam.gserviceaccount.com` | Eventarc Firestore triggers | `roles/eventarc.eventReceiver` (project; required to receive events) · `roles/run.invoker` on `xpense-jobs` only, at deploy time |

Why each grant:

- `datastore.user` with the IAM condition
  `resource.name == "projects/expense-family-cc6ee/databases/(default)"`:
  reads and writes through the Admin SDK, limited to the one database.
- `xpenseAgentAuthUsers`: `verifyIdToken(checkRevoked: true)` reads the user
  record; `/account/delete` (WP-82) deletes it. Narrower than
  `roles/firebaseauth.viewer` + `roles/firebaseauth.admin`.
- `xpenseJobsMessaging`: sending push notifications through FCM HTTP v1.
  Narrower than `roles/firebasecloudmessaging.admin`. gcloud warned that the
  permission's API is not enabled although `fcm.googleapis.com` is; confirm
  with the first real send (WP-60).
- `roles/telemetry.writer`: OTLP export to `telemetry.googleapis.com`
  (`telemetry.traces.write`, `monitoring.timeSeries.create`,
  `logging.logEntries.create`), which is what `genkit_otel` uses (D-29).
- `storage.objectUser` on the bucket: `/account/delete` removes a user's
  receipt backups.
- App Check token verification needs no IAM (public keys).

Not changed by WP-01, worth a look: the default Compute service account holds
`roles/editor` on the project. Nothing of ours runs as it; removing that grant
is the owner's call.

### 3.11 Cloud Scheduler and Eventarc

APIs enabled and `me-central1` confirmed. No jobs or triggers exist yet; they
come with the jobs packages (WP-60 and others), after the `xpense-jobs`
service is deployed. Eventarc Firestore triggers must use location
`me-central1` (the database's location).

## 4. Local emulators

Configuration: `firebase/firebase.json` (Auth `9099`, Firestore `8280`,
Storage `9199`, UI `4100`), project id `demo-xpense`. Details and the ports
used by the other emulator configs: `firebase/emulator/README.md`.

```bash
cd firebase
firebase emulators:exec --project demo-xpense --only auth,firestore,storage "echo ok"
```

## 5. Server deployment (follow-up, not WP-01)

WP-04's `server/DEPLOY.md` is written for `xpense-dev`. When it is run, use:

```bash
PROJECT=expense-family-cc6ee
AGENT_SA=xpense-agent-run@$PROJECT.iam.gserviceaccount.com
JOBS_SA=xpense-jobs-run@$PROJECT.iam.gserviceaccount.com
```

- Step 2: only `cloudbuild` is missing; the rest is enabled.
- Step 3 (permissions): **skip**. WP-01 already granted narrower equivalents
  (3.10). Do not add `roles/firebaseauth.viewer`, `roles/firebaseauth.admin`
  or `roles/firebasecloudmessaging.admin`.
- Step 7: bind `roles/run.invoker` on `xpense-jobs` for `xpense-scheduler` and
  `xpense-eventarc`, as written.
- Add `--billing-project=$PROJECT` to every gcloud line (section 2).
- The deployer (the owner, or a CI identity later) needs
  `iam.serviceAccounts.actAs` on the runtime accounts; the owner has it. A CI
  deploy identity for the `deploy-dev` job (ARCHITECTURE 8) is not created
  yet.

## 6. Owner steps

Done by the owner (or by the planning session on the owner's behalf):

- Chose region `me-central1` (D-18) and to reuse "Expense Family" for
  development (D-38).
- Billing: Blaze was already linked.
- iOS app registration, Google and email/password sign-in (before WP-01).
- Clean-up of the old test resources (3.1).

Still needed:

1. ~~Apple Team ID~~: done, `7TMGB6MVP7` (3.7). Sign in with Apple and App
   Attest need a paid Apple Developer Program membership on that team;
   confirm it is not a free "Personal Team".
2. ~~Gemini key~~: version 1 stored on 2026-11-22 (3.9). To rotate later
   (paid tier, D-34): in Google AI Studio → API keys → Create API key →
   project "Expense Family", check the key shows a paid tier, then store it
   from your own terminal (zsh) without it being echoed or written to a file:

   ```bash
   read -rs "KEY?Gemini key: " && printf %s "$KEY" | gcloud secrets versions add GEMINI_API_KEY --project=expense-family-cc6ee --billing-project=expense-family-cc6ee --data-file=- ; unset KEY
   ```

   Check without printing the value:

   ```bash
   gcloud secrets versions list GEMINI_API_KEY --project=expense-family-cc6ee --billing-project=expense-family-cc6ee
   ```

3. **Apple Developer, App ID `com.bitrelia.familyxpense`:** turn on the
   capabilities *Sign in with Apple* and *App Attest*. The matching
   entitlements in `app/ios/Runner` are added by the app packages (WP-11 for
   sign-in; App Attest's `com.apple.developer.devicecheck.appattest-environment`
   with the App Check wiring).
4. **App Check debug token** for each simulator or Mac used for development
   (3.8).
5. **Old Gemini keys (open):** the owner confirmed they were used only by
   the old test app and planned to delete them in Google AI Studio (project
   "Expense Family"). At the last check (2026-11-22, after version 1 was
   stored) the old "Family Expense API Key" and both `ais-gemini-key-*`
   service accounts still existed, and no new key showed in this project.
   - Confirm the stored key is a **new paid-tier key** made in "Expense
     Family". If it was made in another project, that project must have
     billing on.
   - Then delete the old key. If its service account remains, remove that in
     IAM → Service accounts.
   - Keep the Firebase "iOS key" and "Browser key": the app needs the iOS key.
6. **Compute account:** decide whether to remove its `roles/editor` (3.10).
7. **Budget alert (recommended):** Billing → Budgets & alerts, a monthly
   budget on this project with email alerts.

## 7. Verification (2026-11-22)

| Check | Command | Result |
|---|---|---|
| Project | `gcloud projects describe expense-family-cc6ee --project=expense-family-cc6ee` | ACTIVE, number 648682359990 |
| Billing | `gcloud billing projects describe expense-family-cc6ee --billing-project=expense-family-cc6ee` | billingEnabled: true |
| Firestore | `gcloud firestore databases list --project=…` | `(default)` · `me-central1` · delete protection enabled |
| Storage | `gcloud storage buckets describe gs://expense-family-cc6ee.firebasestorage.app --project=…` | `ME-CENTRAL1`, public access prevention enforced |
| Rules | `firebase deploy --project expense-family-cc6ee --only firestore,storage --dry-run` | both rules files compile; indexes read |
| Rules deploy | `firebase deploy --project expense-family-cc6ee --only firestore:rules` and `--only storage` | released; released source equals the repository files |
| Indexes | `gcloud firestore indexes composite list --project=… --billing-project=… --database='(default)'` | 13 indexes, all `READY` (see 3.4) |
| Emulators | `firebase emulators:exec --project demo-xpense --only auth,firestore,storage "echo ok"` | `ok`, exit 0 |

## 8. Production (later, D-38)

Created before the App Store release, as a new project with nothing in it.
Repeat section 3 with these differences:

- New project id (planned `xpense-prod`), same billing account, same region
  check first (Firestore's location is permanent).
- Register the same bundle id `com.bitrelia.familyxpense` with the same Team
  ID; download its `GoogleService-Info.plist` to
  `app/ios/config/prod/` (ignored by git).
- App Check: App Attest only, **no debug tokens**, enforcement **on** for
  Firestore and Storage from day one.
- Auth: Apple, Google, email and password, as in development.
- Same service accounts, custom roles and conditions, with the new project id.
- `GEMINI_API_KEY`: its own paid-tier key, created in the production project.
- Add a `prod` alias to `firebase/.firebaserc` only when the project exists.
  Deploys to production run from a release tag with manual approval
  (ARCHITECTURE 8).
