#!/bin/bash
# Opens WatchBar in a new Safari window. Closing the window stops the server
# and any downloads still running.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PORT=8765
URL="http://127.0.0.1:$PORT/"

open_window() {
  osascript -e "tell application \"Safari\"" \
    -e "make new document with properties {URL:\"$URL\"}" \
    -e "activate" -e "end tell" >/dev/null
}

if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null; then
  echo "WatchBar is already running. Opening another window."
  open_window
  exit 0
fi

# Job control puts the server in its own process group, so killing the group
# also stops the yt-dlp and ffmpeg processes it started.
set -m
server=""
cleanup() {
  [ -n "$server" ] && kill -TERM -- "-$server" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT HUP TERM

WATCHBAR_WEB_NO_BROWSER=1 WATCHBAR_EXIT_WHEN_CLOSED=1 uv run server.py &
server=$!

until curl -s -o /dev/null "$URL"; do
  kill -0 "$server" 2>/dev/null || exit 1
  sleep 0.5
done

open_window
wait "$server"
