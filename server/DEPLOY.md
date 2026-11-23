# Deploying the server to `xpense-dev`

Steps for WP-01 to run once the `xpense-dev` project exists. WP-04 did **not**
run any of them: the project did not exist yet, and nothing in WP-04 touched a
real Google Cloud project. Everything here was checked only locally (image
build and container run with Docker, emulator tests).

Rules (DELEGATION rule 4, L-22):

- Every `gcloud` and `firebase` command passes `--project=xpense-dev`
  explicitly. The project that is active in this machine's `gcloud` config
  belongs to something else; never rely on it.
- Never deploy to `xpense-prod` from here. Production deploys run from a
  release tag with manual approval (ARCHITECTURE 8).
- Region is `me-central1` (Doha) for everything (D-18).

## 0. What must exist first (WP-01)

- [ ] Project `xpense-dev` with billing linked.
- [ ] Firestore (Native) in `me-central1`.
- [ ] Firebase Auth with Apple, Google and email providers.
- [ ] App Check with the iOS app registered (App Attest; debug provider allowed
      in `xpense-dev` only).
- [ ] Secret `GEMINI_API_KEY` (paid-tier key, D-34). The server starts without
      it; only model-backed routes need it.
- [ ] Service accounts `xpense-agent`, `xpense-jobs`, `xpense-scheduler`,
      `xpense-eventarc` (names as WP-01 creates them; adjust below if they
      differ).

## 1. Variables

```bash
PROJECT=xpense-dev
REGION=me-central1
REPO=xpense
IMAGE=$REGION-docker.pkg.dev/$PROJECT/$REPO/server:$(git rev-parse --short HEAD)
AGENT_SA=xpense-agent@$PROJECT.iam.gserviceaccount.com
JOBS_SA=xpense-jobs@$PROJECT.iam.gserviceaccount.com
```

## 2. APIs

```bash
gcloud services enable --project=$PROJECT \
  run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com \
  secretmanager.googleapis.com firestore.googleapis.com \
  identitytoolkit.googleapis.com firebaseappcheck.googleapis.com \
  fcm.googleapis.com
```

## 3. Permissions (least privilege)

What the code calls, and the role that allows it:

| Caller | Call | Role |
|---|---|---|
| `xpense-agent` | Firestore reads and writes (member lookup, usage counters, `config/runtime`, sessions) | `roles/datastore.user` |
| `xpense-agent` | `verifyIdToken(checkRevoked: true)` reads the user record | `roles/firebaseauth.viewer` |
| `xpense-agent` | Gemini key | `roles/secretmanager.secretAccessor` on the `GEMINI_API_KEY` secret only |
| `xpense-agent` | App Check token verification | none (public keys) |
| `xpense-jobs` | Firestore | `roles/datastore.user` |
| `xpense-jobs` | push notifications | `roles/firebasecloudmessaging.admin` |
| `xpense-jobs` | Gemini key (monthly report narration) | `roles/secretmanager.secretAccessor` on the secret |
| `xpense-scheduler`, `xpense-eventarc` | call the jobs service | `roles/run.invoker` on `xpense-jobs` only (step 7) |

Later packages add their own needs: account deletion (WP-82) needs
`roles/firebaseauth.admin` on `xpense-agent`; OTLP export (WP-83) needs
`roles/cloudtrace.agent` and `roles/monitoring.metricWriter`.

```bash
for role in roles/datastore.user roles/firebaseauth.viewer; do
  gcloud projects add-iam-policy-binding $PROJECT --project=$PROJECT \
    --member=serviceAccount:$AGENT_SA --role=$role --condition=None
done
for role in roles/datastore.user roles/firebasecloudmessaging.admin; do
  gcloud projects add-iam-policy-binding $PROJECT --project=$PROJECT \
    --member=serviceAccount:$JOBS_SA --role=$role --condition=None
done
for sa in $AGENT_SA $JOBS_SA; do
  gcloud secrets add-iam-policy-binding GEMINI_API_KEY --project=$PROJECT \
    --member=serviceAccount:$sa --role=roles/secretmanager.secretAccessor
done
```

## 4. Image

The Docker build context is the repository root, because `server/` depends on
`../packages/xpense_shared` by path. Build in Cloud Build (it builds for
`linux/amd64`, which Cloud Run needs; a local build on an Apple Silicon Mac
would need `--platform linux/amd64`).

```bash
gcloud artifacts repositories create $REPO --project=$PROJECT \
  --location=$REGION --repository-format=docker \
  --description="Family Xpense server images"

# From the repository root:
gcloud builds submit . --project=$PROJECT --region=$REGION \
  --config=server/cloudbuild.yaml --substitutions=_IMAGE=$IMAGE
```

If regional builds are not offered in `me-central1`, drop `--region` (global
pool); the image still lands in the `me-central1` repository.

## 5. `xpense-agent` (public)

```bash
gcloud run deploy xpense-agent --project=$PROJECT --region=$REGION \
  --image=$IMAGE \
  --service-account=$AGENT_SA \
  --allow-unauthenticated \
  --set-env-vars=XPENSE_ROLE=agent,GOOGLE_CLOUD_PROJECT=$PROJECT \
  --set-secrets=GEMINI_API_KEY=GEMINI_API_KEY:latest \
  --cpu=1 --memory=512Mi --concurrency=40 --timeout=60 \
  --min-instances=0 --max-instances=4
```

`--allow-unauthenticated` only means Cloud Run IAM lets requests through;
every route under `/v1` verifies the Firebase ID token and the App Check token
itself (ARCHITECTURE 4.4). Only `/healthz` and `/health` answer without them.

## 6. `xpense-jobs` (private)

```bash
gcloud run deploy xpense-jobs --project=$PROJECT --region=$REGION \
  --image=$IMAGE \
  --service-account=$JOBS_SA \
  --no-allow-unauthenticated \
  --set-env-vars=XPENSE_ROLE=jobs,GOOGLE_CLOUD_PROJECT=$PROJECT \
  --set-secrets=GEMINI_API_KEY=GEMINI_API_KEY:latest \
  --cpu=1 --memory=512Mi --timeout=300 \
  --min-instances=0 --max-instances=2
```

## 7. Who may call the jobs service

```bash
for sa in xpense-scheduler xpense-eventarc; do
  gcloud run services add-iam-policy-binding xpense-jobs \
    --project=$PROJECT --region=$REGION \
    --member=serviceAccount:$sa@$PROJECT.iam.gserviceaccount.com \
    --role=roles/run.invoker
done
```

The scheduler jobs and the other Eventarc triggers come with the jobs
packages (WP-60 and others).

### Eventarc: account visibility (WP-13)

Firestore events reach `xpense-jobs` through Eventarc; the handler reads the
account path from the event's `document` attribute, so either content type
works. Enable `eventarc.googleapis.com` once, then:

```bash
gcloud eventarc triggers create xpense-account-visibility \
  --project=$PROJECT --location=$REGION \
  --destination-run-service=xpense-jobs --destination-run-region=$REGION \
  --destination-run-path=/events/account-visibility \
  --event-filters=type=google.cloud.firestore.document.v1.updated \
  --event-filters=database='(default)' \
  --event-filters-path-pattern=document='households/{hid}/accounts/{accountId}' \
  --event-data-content-type=application/json \
  --service-account=xpense-eventarc@$PROJECT.iam.gserviceaccount.com
```

Until the trigger exists, a shared account stays on "Sharing…" in the app
(its history is not rewritten); joins still widen joint accounts directly.

## 8. Verify

```bash
AGENT_URL=$(gcloud run services describe xpense-agent --project=$PROJECT \
  --region=$REGION --format='value(status.url)')
JOBS_URL=$(gcloud run services describe xpense-jobs --project=$PROJECT \
  --region=$REGION --format='value(status.url)')

curl -i $AGENT_URL/health
# 200 {"status":"ok","role":"agent"}

curl -i -X POST $AGENT_URL/v1/ping -H 'content-type: application/json' \
  -d '{"data":"hi"}'
# 401 {"code":401,"status":"UNAUTHENTICATED","message":"missing_id_token"}

curl -i $JOBS_URL/health
# 403 from Cloud Run IAM (no identity token)

curl -i -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  $JOBS_URL/health
# 200 {"status":"ok","role":"jobs"} if your own account holds run.invoker
```

**`/healthz` from outside.** Cloud Run's Google front end reserves some URL
paths ending in `z` and may answer `GET /healthz` itself with a 404 before the
request reaches the container (Cloud Run "Known issues", reserved URL paths).
The server therefore serves `/health` as well. Container-level probes reach
the container directly, so `/healthz` works there. If WP-01 sees
`/healthz` return 200 through the service URL, both names keep working.

A 200 from `/v1/ping` needs a real signed-in test user with a household and
an App Check token from the app (debug provider in the simulator); that is
exercised when the app talks to `xpense-dev` (WP-11/WP-12).

## 9. Runtime settings in Firestore

The server runs on the defaults in `lib/config/runtime_config.dart` until a
`config/runtime` document exists. Clients cannot read or write `config/*`
(rules). To change a setting, write the document from the console or an admin
script; changes apply within 60 s:

```json
{
  "models": {"agent": "gemini-3.5-flash-lite", "escalation": "gemini-3.8-flash",
             "decide": "gemini-decision-1"},
  "limits": {"agentTurns": 150, "decisions": 600, "audioSeconds": 600, "images": 40},
  "switches": {"agentEnabled": true, "decideEnabled": true, "liteOnly": false}
}
```

## 10. Environment variables the server reads

| Variable | Where | Meaning |
|---|---|---|
| `XPENSE_ROLE` | required on Cloud Run | `agent` or `jobs`; picks the routes |
| `GOOGLE_CLOUD_PROJECT` | required on Cloud Run | the project id; the server refuses to start without it |
| `PORT` | set by Cloud Run | listen port (8080) |
| `GEMINI_API_KEY` | secret | enables the Google AI plugin |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | optional (WP-83) | turns on OTLP export; content capture stays off regardless |
| `XPENSE_APP_CHECK` | local only | `emulator` skips App Check verification; refused on Cloud Run |

Cloud Run sets `K_SERVICE` and `K_REVISION`; the server uses them to know it is
on Cloud Run and to name its telemetry.
