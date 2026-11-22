# firebase/emulator/

Local Firebase Emulator Suite for day-to-day development (Auth, Firestore,
Storage). The configuration is `../firebase.json`; this folder holds exported
emulator data, which stays out of git (`data/` is ignored).

```bash
cd firebase
# Start with an empty state:
firebase emulators:start --project demo-xpense --only auth,firestore,storage
# Or keep state between runs:
firebase emulators:start --project demo-xpense --only auth,firestore,storage \
  --import emulator/data --export-on-exit emulator/data
```

The project id is `demo-xpense`. A `demo-` id never reaches a real project,
needs no login, and is the only id the server accepts off Cloud Run (WP-04).
Anything that talks to these emulators (server, app, scripts) must use the
same id, or it sees an empty, separate database.

| Emulator | Address |
|---|---|
| Auth | `127.0.0.1:9099` |
| Firestore | `127.0.0.1:8280` |
| Storage | `127.0.0.1:9199` |
| Emulator UI | `http://127.0.0.1:4100` |

The ports avoid the ones already taken during development: the server on
`8080` and the Genkit Developer UI on `4000` (ARCHITECTURE 4.6), the rules
tests on `8180`/`9299` (`../firebase.rules-test.json`, WP-05), and the server's
emulator tests on `8380`/`9399` (`server/test/emulator/firebase.json`, WP-04).
All four sets can run at the same time.

Point the server at them:

```bash
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 FIRESTORE_EMULATOR_HOST=127.0.0.1:8280 \
  XPENSE_APP_CHECK=emulator genkit start -- dart run bin/server.dart
```

Smoke test (DELEGATION WP-01):

```bash
firebase emulators:exec --project demo-xpense --only auth,firestore,storage "echo ok"
```
