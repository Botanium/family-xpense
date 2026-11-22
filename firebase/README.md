# firebase/

Firestore and Storage rules, indexes, emulator configuration and the rules
test suite.

- WP-01: `firebase.json`, `.firebaserc`, `emulator/`.
- WP-05: `firestore.rules`, `firestore.indexes.json`, `storage.rules`,
  `test/`, and `package.json` whose `npm test` runs the suite under
  `firebase emulators:exec`. The `rules` CI job runs it once
  `package.json` exists.

Every `firebase` command passes `--project xpense-dev` explicitly
(DELEGATION rule 4).
