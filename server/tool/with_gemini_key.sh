#!/usr/bin/env bash
# Runs a command with GEMINI_API_KEY set to the latest enabled version of the
# dev project's secret, read at run time. The key exists only in this
# process's environment: it is never printed, logged or written to disk.
#
#   tool/with_gemini_key.sh genkit flow:run tryCapture '"..."' -- dart run bin/server.dart
set -euo pipefail
project=expense-family-cc6ee
flags=(--project="$project" --billing-project="$project")
version=$(gcloud secrets versions describe latest --secret=GEMINI_API_KEY "${flags[@]}" --format='value(name)')
version=${version##*/}
echo "with_gemini_key: using GEMINI_API_KEY version $version" >&2
GEMINI_API_KEY=$(gcloud secrets versions access "$version" --secret=GEMINI_API_KEY "${flags[@]}")
export GEMINI_API_KEY
exec "$@"
