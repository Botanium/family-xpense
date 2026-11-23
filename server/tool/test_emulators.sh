#!/usr/bin/env bash
# Runs the emulator-tagged server tests against the Firebase Auth and
# Firestore emulators. The project is the fake `demo-xpense`, which the
# emulators accept without a login and which never reaches a real project.
#
#   server/tool/test_emulators.sh            # emulator tests only
#   server/tool/test_emulators.sh --all      # the whole suite
# Test files run one at a time: several of them reset the shared emulator.
set -euo pipefail
cd "$(dirname "$0")/.."

# One test file at a time: each emulator test file clears the shared
# emulators in setUp, so files running side by side would wipe each other.
tests="-j 1 -t emulator"
if [[ "${1:-}" == "--all" ]]; then tests="-j 1"; fi

exec firebase emulators:exec \
  --project demo-xpense \
  --config test/emulator/firebase.json \
  --only auth,firestore \
  "dart test --concurrency=1 $tests"
