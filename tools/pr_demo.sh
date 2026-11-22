#!/usr/bin/env bash
# Record a short iOS Simulator demo, turn it into a GIF, and attach it to a PR.
#
#   tools/pr_demo.sh start [device]      start recording (default: first booted simulator)
#   tools/pr_demo.sh stop                stop recording, write demo.gif (and demo.mp4)
#   tools/pr_demo.sh gif <in.mp4>        convert an existing recording to a GIF
#   tools/pr_demo.sh publish <pr> <file> [caption]
#                                        upload the GIF to the `pr-media` branch and
#                                        append it to the PR description
#
# The GIF lives on the orphan branch `pr-media` (never merged into main), at
# pr-<number>/<file>, and is embedded from raw.githubusercontent.com. That works
# because the repository is public.
#
# Defaults keep GIFs small: 360 px wide, 12 fps, at most 20 s. Override with
# PR_DEMO_WIDTH, PR_DEMO_FPS, PR_DEMO_MAX_SECONDS. Files go to $PR_DEMO_DIR
# (default .pr-demo/, which is git-ignored).
set -euo pipefail

DIR="${PR_DEMO_DIR:-.pr-demo}"
WIDTH="${PR_DEMO_WIDTH:-360}"
FPS="${PR_DEMO_FPS:-12}"
MAX_SECONDS="${PR_DEMO_MAX_SECONDS:-20}"
MEDIA_BRANCH="pr-media"

die() { echo "pr_demo: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required"; }

booted_device() {
  xcrun simctl list devices booted | sed -n 's/.*(\([0-9A-F-]\{36\}\)) (Booted).*/\1/p' | head -1
}

to_gif() {
  local in="$1" out="$2" palette
  need ffmpeg
  palette="$(mktemp -t pr_demo_palette).png"
  ffmpeg -loglevel error -y -t "$MAX_SECONDS" -i "$in" \
    -vf "fps=$FPS,scale=$WIDTH:-1:flags=lanczos,palettegen=stats_mode=diff" "$palette"
  ffmpeg -loglevel error -y -t "$MAX_SECONDS" -i "$in" -i "$palette" \
    -lavfi "fps=$FPS,scale=$WIDTH:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "$out"
  rm -f "$palette"
  echo "$out ($(du -h "$out" | cut -f1))"
}

repo_slug() { gh repo view --json nameWithOwner --jq .nameWithOwner; }

ensure_media_branch() {
  local slug="$1" tree commit
  if gh api "repos/$slug/git/ref/heads/$MEDIA_BRANCH" >/dev/null 2>&1; then return; fi
  # Orphan branch with a single README, so it shares no history with main.
  tree=$(gh api -X POST "repos/$slug/git/trees" \
    -f 'tree[][path]=README.md' -f 'tree[][mode]=100644' -f 'tree[][type]=blob' \
    -f 'tree[][content]=Demo GIFs for pull requests, written by tools/pr_demo.sh. Never merged into main.' \
    --jq .sha)
  commit=$(gh api -X POST "repos/$slug/git/commits" \
    -f message="pr-media: start branch for PR demo GIFs" -f tree="$tree" --jq .sha)
  gh api -X POST "repos/$slug/git/refs" -f ref="refs/heads/$MEDIA_BRANCH" -f sha="$commit" >/dev/null
}

publish() {
  local pr="$1" file="$2" caption="${3:-Demo}" slug name path payload sha url body
  [ -f "$file" ] && [ -n "$pr" ] || die "usage: publish <pr-number> <file> [caption]"
  need gh; need python3
  [ "$(du -k "$file" | cut -f1)" -le 10240 ] || die "$file is over 10 MB; lower PR_DEMO_WIDTH or PR_DEMO_FPS"
  slug=$(repo_slug)
  ensure_media_branch "$slug"
  name="$(date +%Y%m%d-%H%M%S)-$(basename "$file")"
  path="pr-$pr/$name"
  sha=$(gh api "repos/$slug/contents/$path?ref=$MEDIA_BRANCH" --jq .sha 2>/dev/null || true)
  payload=$(mktemp -t pr_demo_payload)
  python3 -I - "$file" "$path" "$MEDIA_BRANCH" "$pr" "$sha" >"$payload" <<'PY'
import base64, json, sys
f, path, branch, pr, sha = sys.argv[1:6]
body = {"message": f"pr-media: demo for #{pr}", "branch": branch,
        "content": base64.b64encode(open(f, "rb").read()).decode()}
if sha:
    body["sha"] = sha
print(json.dumps(body))
PY
  gh api -X PUT "repos/$slug/contents/$path" --input "$payload" >/dev/null
  rm -f "$payload"
  url="https://raw.githubusercontent.com/$slug/$MEDIA_BRANCH/$path"
  body=$(gh pr view "$pr" --json body --jq .body)
  gh pr edit "$pr" --body "$(printf '%s\n\n### %s\n\n![%s](%s)\n' "$body" "$caption" "$caption" "$url")" >/dev/null
  echo "attached to PR #$pr: $url"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  start)
    need xcrun
    device="${1:-$(booted_device)}"
    [ -n "$device" ] || die "no booted simulator; boot one or pass a device id"
    mkdir -p "$DIR"
    [ ! -f "$DIR/recording.pid" ] || die "already recording; run stop first"
    xcrun simctl io "$device" recordVideo --codec=h264 --force "$DIR/demo.mp4" >"$DIR/record.log" 2>&1 &
    echo $! >"$DIR/recording.pid"
    sleep 1
    echo "recording $device to $DIR/demo.mp4; run '$0 stop' when done"
    ;;
  stop)
    [ -f "$DIR/recording.pid" ] || die "not recording"
    pid=$(cat "$DIR/recording.pid"); rm -f "$DIR/recording.pid"
    kill -INT "$pid" 2>/dev/null || true
    for _ in $(seq 1 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    [ -s "$DIR/demo.mp4" ] || die "no video written; see $DIR/record.log"
    to_gif "$DIR/demo.mp4" "$DIR/demo.gif"
    ;;
  gif)
    [ -f "${1:-}" ] || die "usage: gif <in.mp4> [out.gif]"
    to_gif "$1" "${2:-${1%.*}.gif}"
    ;;
  publish)
    publish "${1:-}" "${2:-}" "${3:-Demo}"
    ;;
  *)
    sed -n '2,16p' "$0"; exit 1
    ;;
esac
