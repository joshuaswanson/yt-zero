#!/bin/bash
# Opens WatchBar in its own window. Closing the window stops the server and
# any downloads still running.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PORT=8765
URL="http://127.0.0.1:$PORT/"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE="$HOME/Library/Application Support/WatchBar/Chrome"

if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null; then
  echo "Something is already using port $PORT. Stop it, then open WatchBar again."
  exit 1
fi

# Job control puts the server in its own process group, so killing the group
# also stops the yt-dlp and ffmpeg processes it started.
set -m
server=""
chrome=""
cleanup() {
  [ -n "$chrome" ] && kill "$chrome" 2>/dev/null
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

"$CHROME" --app="$URL" --user-data-dir="$PROFILE" --no-first-run \
  --no-default-browser-check --window-size=1440,900 >/dev/null 2>&1 &
chrome=$!

# The server exits when the page closes. Quitting this Chrome instance ends
# the loop too.
while kill -0 "$server" 2>/dev/null && kill -0 "$chrome" 2>/dev/null; do
  sleep 1
done
