# firebase/

Firestore and Storage rules, indexes, emulator configuration and the rules
test suite.

- WP-01: `firebase.json` (deploy targets and the local emulator suite),
  `.firebaserc` (alias `dev` → `expense-family-cc6ee`, D-38), `emulator/`.
  Environments runbook: `docs/ENVIRONMENTS.md`.
- WP-05: `firestore.rules`, `firestore.indexes.json`, `storage.rules`,
  `test/`, and `package.json` whose `npm test` runs the suite under
  `firebase emulators:exec`. The `rules` CI job runs it once
  `package.json` exists.

Every `firebase` command passes `--project` explicitly (DELEGATION rule 4):
`demo-xpense` (or `xpense-dev` in the rules tests) for emulators, and
`expense-family-cc6ee` for the real development project (D-38).
