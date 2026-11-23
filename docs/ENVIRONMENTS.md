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
| iOS apps | "Family Xpense Dev" `com.bitrelia.familyxpense.dev` (flavor `dev`, used for development and TestFlight); "Family Xpense" `com.bitrelia.familyxpense` (registered, not used by any build, D-44) | `com.bitrelia.familyxpense` (flavor `prod`), reserved until the App Store seller is decided (D-44) |
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

Enabled on 2026-11-23 for the first server deploy: `cloudbuild`. Right after
enabling it, `gcloud builds submit` was refused for a few minutes with a
misleading "serviceusage.services.use" permission error; it worked once the
API had propagated (no grant was needed).

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
| Apple | on, for the iOS bundles `com.bitrelia.familyxpense` and `com.bitrelia.familyxpense.dev` | WP-01; `.dev` added for D-44 |

- Apple was enabled with the Identity Toolkit admin API:
  `POST …/admin/v2/projects/expense-family-cc6ee/defaultSupportedIdpConfigs?idpId=apple.com`
  with `{"enabled":true,"appleSignInConfig":{"bundleIds":["com.bitrelia.familyxpense"]}}`.
  The dev bundle id was added on 2026-11-22 (D-44) with
  `PATCH …/defaultSupportedIdpConfigs/apple.com?updateMask=appleSignInConfig.bundleIds`.
  Native iOS sign-in needs nothing else in Firebase. A Services ID and key
  (code flow) are only needed for web or Android sign-in, which v1 does not
  have.
- Improved email privacy (no account enumeration) is on. Email verification
  is enforced by the app (D-24).
- Authorized domains: `localhost`, `expense-family-cc6ee.firebaseapp.com`,
  `expense-family-cc6ee.web.app`.

### 3.7 iOS apps, flavors and config files

Two Firebase iOS apps, one per bundle id (D-44). Both have the Apple Team ID
`7TMGB6MVP7` and App Attest registered (3.8), and share one API key.

| | Flavor `dev` | Flavor `prod` |
|---|---|---|
| Use | development and TestFlight | the App Store, later; **nobody builds or uploads it yet** (D-44) |
| Bundle id | `com.bitrelia.familyxpense.dev` | `com.bitrelia.familyxpense` |
| Home screen name | Xpense Dev | Family Xpense |
| Firebase app | "Family Xpense Dev", `1:648682359990:ios:79390f4ac98029d8172a17` (created 2026-11-22) | none yet in production. "Family Xpense", `1:648682359990:ios:b2b46595d20bceaf172a17` in this project holds the id today (registered before WP-01; no build uses it) |
| Config file (gitignored) | `app/ios/config/dev/GoogleService-Info.plist` | `app/ios/config/prod/GoogleService-Info.plist`, from the production project (8) |
| Xcode | scheme `dev`; configurations `Debug-dev`, `Release-dev`, `Profile-dev` | scheme `prod`; `Debug-prod`, `Release-prod`, `Profile-prod` |
| Entitlements | none yet; Sign in with Apple and App Attest come after enrollment (D-39, D-44) | none yet |

**Where the flavor settings live.** `app/ios/Flutter/Flavors.xcconfig`
(included by `Debug.xcconfig` and `Release.xcconfig`) picks the bundle id,
name and Google sign-in URL scheme from `XPENSE_FLAVOR`, which
each build configuration sets in `Runner.xcodeproj`. RunnerTests is
`<bundle id>.RunnerTests`. `app/pubspec.yaml` sets `default-flavor: dev`, so
a plain `flutter run` builds `dev`.

**Flavor and backend are separate.** The flavor is the app's identity.
`--dart-define=XPENSE_ENV=dev|prod` picks the backend; without it the app
runs on fakes and needs no config file (CI, a clean checkout). The Xcode
phase "Copy Firebase config" (`app/ios/scripts/copy_firebase_config.sh`)
copies `app/ios/config/<flavor>/GoogleService-Info.plist` into the bundle
when `XPENSE_ENV` is set, and fails the build if the file is missing or if
`XPENSE_ENV` and the flavor differ (each file names its own bundle id).

Commands, from `app/`:

```bash
flutter run                                                   # dev flavor, fakes
flutter run --flavor dev --dart-define=XPENSE_ENV=dev         # dev flavor, project expense-family-cc6ee
flutter run --flavor dev --dart-define=XPENSE_ENV=dev --dart-define=XPENSE_AUTH_EMULATOR=127.0.0.1:9099
flutter build ipa --flavor dev --dart-define=XPENSE_ENV=dev   # TestFlight, after enrollment
flutter build ios --flavor prod --no-codesign                 # compile check only; never upload (D-44)
```

Against the Auth emulator use the IP `127.0.0.1`: the emulator does not
listen on IPv6 `localhost`.

**Config files.** Kept **out of git** (root `.gitignore`); every checkout and
worktree needs its own copy. To fetch the dev file:

```bash
cd firebase
firebase apps:sdkconfig IOS 1:648682359990:ios:79390f4ac98029d8172a17 \
  --project expense-family-cc6ee -o ../app/ios/config/dev/GoogleService-Info.plist
```

The main checkout's `config/dev/` held the "Family Xpense" app's file before
D-44; replace it with the command above (delete the old file first;
`apps:sdkconfig` will not overwrite).

**Google sign-in URL scheme.** Firebase Auth's web flow returns through a
URL scheme made of the flavor's Firebase app id with `-` for `:`
(`XPENSE_GOOGLE_AUTH_SCHEME` in `Flavors.xcconfig`, used in `Info.plist`).
Without it the Firebase SDK stops the app on "Continue with Google". `prod`
points at the "Family Xpense" app for now; change it to the production
app's id when that project exists.

**API key.** The Firebase "iOS key (auto created by Firebase)"
(`39858552-…`) is restricted to the bundle ids `com.bitrelia.familyxpense`
and `com.bitrelia.familyxpense.dev` and to the Firebase APIs it was created
with. Both apps use it. `firebase apps:create` made a second, unrestricted
key for the dev app; the dev app was pointed at the restricted key
(`PATCH …/v1beta1/projects/expense-family-cc6ee/iosApps/<app id>?updateMask=apiKeyId,teamId`)
and the extra key deleted (2026-11-22). Check:
`gcloud services api-keys list --project=expense-family-cc6ee --billing-project=expense-family-cc6ee`.

**Team ID.** `7TMGB6MVP7` on both apps, set with the Firebase Management
API (`…?updateMask=teamId`). It was read from the OU field of the owner's
Apple Development signing certificate. The code in parentheses in that
certificate's name is the personal certificate id, not the team. A Team ID
is not a secret. Recheck it after enrollment (D-39).

**Entitlements.** None yet: a free Personal Team cannot sign Sign in with
Apple or App Attest, and Apple sign-in is parked until the developer account
is sorted out. After enrollment (6, step 3) add an entitlements file for the
dev flavor (`com.apple.developer.applesignin` and
`com.apple.developer.devicecheck.appattest-environment = production`) and set
`CODE_SIGN_ENTITLEMENTS` for `dev` in `Flavors.xcconfig`.

### 3.8 App Check

- iOS apps: **App Attest** provider registered on both (token lifetime 1
  hour), with the Team ID set (3.7). "Family Xpense Dev" was registered on
  2026-11-22 with
  `PATCH https://firebaseappcheck.googleapis.com/v1/projects/648682359990/apps/<app id>/appAttestConfig?updateMask=tokenTtl`. Not yet exercised from a device: that needs the App
  Attest capability on the App ID and the entitlement in the app.
- DeviceCheck: not configured. Both household phones (D-37) support App
  Attest; the app's `AppleAppAttestWithDeviceCheckFallbackProvider` falls back
  to DeviceCheck only on iOS versions before 14.
- Debug provider (simulator, CI): allowed **in this project only**. Each
  developer registers their own debug token: run a debug build, copy the
  token the App Check SDK logs, then Firebase console → App Check → Apps →
  Family Xpense Dev → ⋮ → Manage debug tokens → Add. Debug tokens are secrets:
  never commit or paste them into issues, PRs or chat.
- Phone builds (free Personal Team, D-39): App Attest cannot be signed, so
  the dev flavor uses the debug provider with a token given at build time
  (`--dart-define=XPENSE_APP_CHECK_DEBUG_TOKEN`, ignored in `prod`).
  `tools/install_dev_on_iphone.sh` generates it, registers it on "Family
  Xpense Dev" through the App Check API with the owner's gcloud login, and
  keeps it in `~/.config/xpense/appcheck-debug-token-dev` (mode 600). One
  such token was registered on 2026-11-23, display name
  `install_dev_on_iphone <Mac name>`. Owner checklist: `docs/PHONE_TESTING.md`.
- Enforcement: **off** for Firestore, Storage and Auth in development, so the
  simulator and early builds are not blocked while the App Check flow is
  being built. Turn it on in development once a simulator build has shown
  verified App Check requests in the console. The server checks App Check
  tokens on every `/v1` route regardless (ARCHITECTURE 4.4).

### 3.9 Secret Manager

- Secret `GEMINI_API_KEY`: user-managed replication in `me-central1` only;
  labels `app=xpense`, `owner=wp-01`.
- Versions (as of 2026-11-22; values never printed):

  | Version | State | Created (UTC) | Holds |
  |---|---|---|---|
  | 2 | **enabled** | 2026-11-22 18:40 | the new paid-tier key "Family Expense API Key", created in AI Studio at 18:39 and bound to the service account `ais-gemini-key-54028d0765c14ad@648682359990.iam.gserviceaccount.com` |
  | 1 | **disabled** | 2026-11-22 18:26 | the old key from 30 October 2026, since deleted |

  Both versions were added by the owner from their own terminal. Which key
  each holds was checked by comparing fingerprints, without printing either
  value. Version 1 was disabled (not destroyed) by the planning session.
  Cloud Run's `GEMINI_API_KEY:latest` resolves to version 2.
- The old Gemini keys and all of their `ais-gemini-key-*` service accounts
  are deleted. The only one left is the new key's account, named above.
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

## 5. Server deployment

**Deployed on 2026-11-23** (public service only):

| | |
|---|---|
| Artifact Registry | `me-central1-docker.pkg.dev/expense-family-cc6ee/xpense` (Docker), created then |
| Image | `…/xpense/server:455834d` (main at PR #35), built with Cloud Build in `me-central1` |
| Service | `xpense-agent`, `https://xpense-agent-648682359990.me-central1.run.app` |
| Runtime account | `xpense-agent-run` |
| Settings | `XPENSE_ROLE=agent`, `GOOGLE_CLOUD_PROJECT=expense-family-cc6ee`, secret `GEMINI_API_KEY:latest` (version 2), 1 CPU, 512 Mi, concurrency 40, timeout 60 s, 0 to 4 instances, `--allow-unauthenticated` |
| Checked | `/health` 200; `/v1/ping` 401 without tokens; with a throwaway email user's ID token and an App Check token from the registered debug token, `/v1/ping` 200 and `/v1/agent` answered with an A2UI card; a bad App Check token gives 401 `invalid_app_check`. The test user, its household and its agent sessions were deleted afterwards. |

`xpense-jobs` is **not** deployed yet (step 6), so the account-visibility
trigger (WP-13) does not exist either. Steps 6 and 7 need the IAM bindings
there, which the owner runs.

To redeploy after a server change, from the repository root (zsh):

```bash
B=(--project=expense-family-cc6ee --billing-project=expense-family-cc6ee)
IMAGE=me-central1-docker.pkg.dev/expense-family-cc6ee/xpense/server:$(git rev-parse --short HEAD)
gcloud builds submit . $B --region=me-central1 --config=server/cloudbuild.yaml --substitutions=_IMAGE=$IMAGE
gcloud run deploy xpense-agent $B --region=me-central1 --image=$IMAGE
```

`gcloud run deploy` with only `--image` keeps the account, settings and
secret of the running service.

WP-04's `server/DEPLOY.md` is written for `xpense-dev`. When it is run, use:

```bash
PROJECT=expense-family-cc6ee
AGENT_SA=xpense-agent-run@$PROJECT.iam.gserviceaccount.com
JOBS_SA=xpense-jobs-run@$PROJECT.iam.gserviceaccount.com
```

- Step 2: done (`cloudbuild` enabled 2026-11-23).
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
2. ~~Gemini key~~: done; version 2 holds the new paid-tier key (3.9). To
   rotate later (paid tier, D-34):
   1. In Google AI Studio → API keys → Create API key → project "Expense
      Family", and check the key shows a paid tier.
   2. Store it from your own terminal (zsh); it is never echoed or written to
      a file.
   3. Disable the previous version
      (`gcloud secrets versions disable <n> --secret=GEMINI_API_KEY …`).
   4. Only then delete the old key in AI Studio.

   Store command (step 2):

   ```bash
   read -rs "KEY?Gemini key: " && printf %s "$KEY" | gcloud secrets versions add GEMINI_API_KEY --project=expense-family-cc6ee --billing-project=expense-family-cc6ee --data-file=- ; unset KEY
   ```

   Check without printing the value:

   ```bash
   gcloud secrets versions list GEMINI_API_KEY --project=expense-family-cc6ee --billing-project=expense-family-cc6ee
   ```

3. **Apple Developer, after enrollment is approved:** register the App ID
   `com.bitrelia.familyxpense.dev` with the capabilities *Sign in with
   Apple* and *App Attest*, then add the dev flavor's entitlements (3.7). Do **not** register
   `com.bitrelia.familyxpense` in the individual account: it waits for the
   App Store seller decision (D-44).
4. **App Check debug token** for each simulator or Mac used for development
   (3.8).
5. ~~Old Gemini keys~~: done. The owner deleted them in AI Studio, and
   their service accounts are gone (3.9). Keep the Firebase "iOS key" and
   "Browser key": the app needs the iOS key.
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
- Register the bundle id `com.bitrelia.familyxpense` (flavor `prod`) with
  the Team ID of the account that will sell the app (D-44); download its
  `GoogleService-Info.plist` to `app/ios/config/prod/` (ignored by git); set
  `XPENSE_GOOGLE_AUTH_SCHEME_prod` in `app/ios/Flutter/Flavors.xcconfig` to
  its app id; add a prod entitlements file.
- App Check: App Attest only, **no debug tokens**, enforcement **on** for
  Firestore and Storage from day one.
- Auth: Apple, Google, email and password, as in development.
- Same service accounts, custom roles and conditions, with the new project id.
- `GEMINI_API_KEY`: its own paid-tier key, created in the production project.
- Add a `prod` alias to `firebase/.firebaserc` only when the project exists.
  Deploys to production run from a release tag with manual approval
  (ARCHITECTURE 8).
