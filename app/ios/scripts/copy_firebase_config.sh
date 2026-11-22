#!/bin/sh
# Copies the Firebase config of the environment picked with
# `--dart-define=XPENSE_ENV=dev|prod` into the app bundle, where
# `Firebase.initializeApp()` reads it (bootstrap.dart).
#
# The plist stays out of git (root .gitignore; docs/ENVIRONMENTS.md 3.7):
# put it at app/ios/config/<env>/GoogleService-Info.plist. A build without
# XPENSE_ENV (the `fakes` environment, CI) needs none and gets none.
set -eu

env=""
# Flutter passes every --dart-define base64-encoded, comma-separated.
old_ifs=$IFS
IFS=','
for entry in ${DART_DEFINES:-}; do
  decoded=$(printf '%s' "$entry" | base64 --decode 2>/dev/null || true)
  case "$decoded" in
    XPENSE_ENV=*) env=${decoded#XPENSE_ENV=} ;;
  esac
done
IFS=$old_ifs

dest="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/GoogleService-Info.plist"
case "$env" in
  dev | prod)
    src="${SRCROOT}/config/${env}/GoogleService-Info.plist"
    if [ ! -f "$src" ]; then
      echo "error: XPENSE_ENV=${env} needs ${src}, which is not in git. See docs/ENVIRONMENTS.md 3.7."
      exit 1
    fi
    cp "$src" "$dest"
    echo "Firebase config: ${env}"
    ;;
  *)
    # A fakes build must not carry a config left by an earlier dev build.
    rm -f "$dest"
    ;;
esac
