#!/bin/bash
set -euo pipefail

BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"
KEYBOARD="/dev/input/event20"
TIMEOUT=5                 # seconds
ON_LEVEL=2                # 0/1/2 on my machine
POLL=.2

STATE="on"
TS_FILE="/run/kbd-backlight-last-activity"
LOG_TAG="kbd-backlight-idle"

log() { logger -t "$LOG_TAG" "$*"; }

# Initialize activity timestamp
date +%s > "$TS_FILE"
echo "$ON_LEVEL" > "$BRIGHTNESS"

# Start event watcher in the background
(
  log "Watcher starting on $KEYBOARD"
  # stdbuf helps line-buffering so we see events promptly
  stdbuf -oL libinput debug-events --device "$KEYBOARD" 2>/dev/null |
  while read -r line; do
    # Any key press counts (pressed only)
    if [[ "$line" == *"KEYBOARD_KEY"* && "$line" == *"pressed"* ]]; then
      date +%s > "$TS_FILE"
    fi
  done
  log "Watcher exited"
) &

WATCHER_PID=$!

cleanup() {
  kill "$WATCHER_PID" 2>/dev/null || true
  rm -f "$TS_FILE"
}
trap cleanup EXIT INT TERM

log "Daemon started. TIMEOUT=${TIMEOUT}s"

# Timer loop
while true; do
  NOW=$(date +%s)
  LAST=$(cat "$TS_FILE" 2>/dev/null || echo "$NOW")
  IDLE=$((NOW - LAST))

  if (( IDLE >= TIMEOUT )); then
    if [[ "$STATE" != "off" ]]; then
      echo 0 > "$BRIGHTNESS"
      STATE="off"
      log "Backlight OFF (idle ${IDLE}s)"
    fi
  else
    if [[ "$STATE" == "off" ]]; then
      echo "$ON_LEVEL" > "$BRIGHTNESS"
      STATE="on"
      log "Backlight ON (idle ${IDLE}s)"
    fi
  fi

  sleep "$POLL"
done
