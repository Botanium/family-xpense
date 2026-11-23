#!/bin/sh
# Copies the flavor's Firebase config into the app bundle, where
# `Firebase.initializeApp()` reads it (bootstrap.dart).
#
# Two settings meet here (docs/ENVIRONMENTS.md 3.7, DECISIONS D-44):
# - the flavor (`--flavor dev|prod`, build setting XPENSE_FLAVOR from
#   Flutter/Flavors.xcconfig) is the app's identity: bundle id, name, and
#   which config file belongs to it;
# - the backend (`--dart-define=XPENSE_ENV=dev|prod`) says whether the app
#   uses Firebase at all. Without it the app runs on fakes (the default, and
#   CI) and needs no config file.
#
# The plist stays out of git (root .gitignore): put it at
# app/ios/config/<flavor>/GoogleService-Info.plist.
set -eu

flavor=${XPENSE_FLAVOR:-}
case "$flavor" in
  dev | prod) ;;
  *)
    echo "error: build configuration ${CONFIGURATION} has no XPENSE_FLAVOR. Build with --flavor dev or --flavor prod."
    exit 1
    ;;
esac

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
    # A config file names its bundle id; the dev backend's file does not fit
    # the prod bundle id, and the reverse.
    if [ "$env" != "$flavor" ]; then
      echo "error: XPENSE_ENV=${env} runs only in the ${env} flavor; this build is --flavor ${flavor}. See docs/ENVIRONMENTS.md 3.7."
      exit 1
    fi
    src="${SRCROOT}/config/${flavor}/GoogleService-Info.plist"
    if [ ! -f "$src" ]; then
      echo "error: XPENSE_ENV=${env} needs ${src}, which is not in git. See docs/ENVIRONMENTS.md 3.7."
      exit 1
    fi
    cp "$src" "$dest"
    echo "Firebase config: ${flavor}"
    ;;
  *)
    # A fakes build must not carry a config left by an earlier build.
    rm -f "$dest"
    ;;
esac
