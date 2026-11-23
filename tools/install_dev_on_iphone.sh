#!/usr/bin/env bash
# Builds the dev flavor ("Xpense Dev", com.bitrelia.familyxpense.dev) against
# the dev Firebase project and the dev server, and installs it on every iPhone
# connected to this Mac. Owner checklist: docs/PHONE_TESTING.md.
#
#   tools/install_dev_on_iphone.sh                # every connected iPhone
#   tools/install_dev_on_iphone.sh -d <device>    # one phone (id or name prefix)
#   tools/install_dev_on_iphone.sh --prepare      # only the checks and set-up
#
# Signing stays automatic, with the free Personal Team 7TMGB6MVP7 set in the
# Xcode project. Your Apple ID must be signed in to Xcode (Settings → Accounts).
#
# What it sets up on the first run (nothing is printed or committed):
# - app/ios/config/dev/GoogleService-Info.plist, fetched with the Firebase
#   CLI when it is missing or belongs to another app.
# - An App Check debug token for "Family Xpense Dev", generated, registered
#   with your gcloud login, and kept in ~/.config/xpense/ (mode 600). A
#   free-team build cannot use App Attest (D-39), so the dev build uses the
#   debug provider with this token; prod never does.
set -euo pipefail

PROJECT=expense-family-cc6ee
DEV_APP_ID=1:648682359990:ios:79390f4ac98029d8172a17
BUNDLE_ID=com.bitrelia.familyxpense.dev
SERVER_URL="${XPENSE_SERVER_URL:-https://xpense-agent-648682359990.me-central1.run.app/}"
TOKEN_FILE="${XPENSE_APP_CHECK_TOKEN_FILE:-$HOME/.config/xpense/appcheck-debug-token-dev}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/app/ios/config/dev/GoogleService-Info.plist"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33m!   %s\033[0m\n' "$*" >&2; }
die() { printf '\033[31mx   %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"; }

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

DEVICES=()
PREPARE_ONLY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d | --device) [[ $# -ge 2 ]] || die "$1 needs a device id or name"; DEVICES+=("$2"); shift 2 ;;
    --prepare) PREPARE_ONLY=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage; die "Unknown option: $1" ;;
  esac
done

need flutter "Install Flutter 3.50.1 (see /.fvmrc)."
need xcrun "Install Xcode and open it once."
need python3 "Install the Xcode command line tools: xcode-select --install"

# 1. Firebase config for the dev app ---------------------------------------
plist_bundle() { /usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$1" 2>/dev/null || true; }
if [[ "$(plist_bundle "$PLIST")" != "$BUNDLE_ID" ]]; then
  say "Fetching the Firebase config for Family Xpense Dev"
  need firebase "Install the Firebase CLI and run: firebase login"
  tmp="$(mktemp -d)"
  (cd "$ROOT/firebase" && firebase apps:sdkconfig IOS "$DEV_APP_ID" \
    --project "$PROJECT" -o "$tmp/GoogleService-Info.plist" >/dev/null) ||
    die "Could not fetch the config. Run 'firebase login' and try again."
  [[ "$(plist_bundle "$tmp/GoogleService-Info.plist")" == "$BUNDLE_ID" ]] ||
    die "The fetched config is not for $BUNDLE_ID."
  mkdir -p "$(dirname "$PLIST")"
  mv -f "$tmp/GoogleService-Info.plist" "$PLIST"
  rmdir "$tmp"
fi
echo "Firebase config: ok ($BUNDLE_ID)"

# 2. App Check debug token ---------------------------------------------------
if [[ ! -s "$TOKEN_FILE" ]]; then
  say "Registering an App Check debug token for Family Xpense Dev"
  need gcloud "Install the Google Cloud CLI and run: gcloud auth login"
  need uuidgen ""
  token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  access="$(gcloud auth print-access-token 2>/dev/null)" ||
    die "Run 'gcloud auth login' first."
  name="install_dev_on_iphone $(scutil --get ComputerName 2>/dev/null || hostname -s)"
  # The token goes in the body through stdin, never on a command line.
  status="$(printf '{"displayName":"%s","token":"%s"}' "${name//\"/}" "$token" |
    curl -sS -o /dev/null -w '%{http_code}' -X POST \
      -H "Authorization: Bearer $access" \
      -H "x-goog-user-project: $PROJECT" \
      -H 'Content-Type: application/json' --data-binary @- \
      "https://firebaseappcheck.googleapis.com/v1/projects/$PROJECT/apps/$DEV_APP_ID/debugTokens")"
  [[ "$status" == 200 ]] ||
    die "Registering the token failed (HTTP $status). See docs/PHONE_TESTING.md, 'App Check token by hand'."
  mkdir -p "$(dirname "$TOKEN_FILE")"
  (umask 077 && printf '%s' "$token" >"$TOKEN_FILE")
  unset token access
fi
echo "App Check debug token: ok ($TOKEN_FILE)"

# 3. Server --------------------------------------------------------------------
if curl -fsS --max-time 20 "${SERVER_URL%/}/health" >/dev/null 2>&1; then
  echo "Server: ok (${SERVER_URL%/})"
else
  warn "The server did not answer at ${SERVER_URL%/}/health. The app installs, but Ask, invites and joins will fail."
fi

# 4. Phones --------------------------------------------------------------------
if [[ ${#DEVICES[@]} -eq 0 ]]; then
  say "Looking for connected iPhones"
  while IFS= read -r id; do [[ -n "$id" ]] && DEVICES+=("$id"); done < <(
    flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
text = sys.stdin.read()
start = text.find("[")
for d in json.loads(text[start:]) if start >= 0 else []:
    if d.get("targetPlatform") == "ios" and not d.get("emulator"):
        print(d["id"])
        print("    %s (%s)" % (d.get("name"), d["id"]), file=sys.stderr)
')
fi
if [[ ${#DEVICES[@]} -eq 0 ]]; then
  die "No iPhone found. Plug it in with USB, unlock it, tap Trust, and turn on Developer Mode (docs/PHONE_TESTING.md)."
fi

if $PREPARE_ONLY; then
  say "Ready. Run again without --prepare to install."
  exit 0
fi

# 5. Build and install ---------------------------------------------------------
# The defines go through a private file, so the token is not on a command line.
defines_dir="$(mktemp -d)"
trap 'rm -rf "$defines_dir"' EXIT
(umask 077 && python3 - "$defines_dir/defines.json" "$SERVER_URL" "$TOKEN_FILE" <<'PY'
import json, sys
out, url, token_file = sys.argv[1:]
with open(token_file) as f:
    token = f.read().strip()
with open(out, "w") as f:
    json.dump({
        "XPENSE_ENV": "dev",
        "XPENSE_SERVER_URL": url,
        "XPENSE_APP_CHECK_DEBUG_TOKEN": token,
    }, f)
PY
)

cd "$ROOT/app"
failed=()
for device in "${DEVICES[@]}"; do
  say "Building and installing Xpense Dev on $device (the first build takes a few minutes)"
  if flutter run --release --no-resident --flavor dev -d "$device" \
    --dart-define-from-file="$defines_dir/defines.json"; then
    echo "Installed and opened on $device."
  else
    failed+=("$device")
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  cat >&2 <<EOF

Not finished on: ${failed[*]}
Most common causes (docs/PHONE_TESTING.md has the details):
  - "Untrusted Developer": the app is installed but iOS has not trusted you
    yet. On the phone: Settings > General > VPN & Device Management >
    your Apple ID > Trust. Then tap Xpense Dev; no need to run this again.
  - Developer Mode is off: Settings > Privacy & Security > Developer Mode.
  - The phone is locked, or "Trust This Computer" was not accepted.
  - Signing: open Xcode > Settings > Accounts and sign in with your Apple ID.
EOF
  exit 1
fi
say "Done. Profiles from a free team expire after 7 days: run this again to renew."
