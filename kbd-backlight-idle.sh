#!/bin/bash
set -euo pipefail

BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"

# Use input-remapper forwarded device (event numbers may change; replace with your stable resolver if you have one)
KEYBOARD="$(libinput list-devices | awk '
  /input-remapper AT Translated Set 2 keyboard forwarded/ {found=1}
  found && /Kernel:/ {print $2; exit}
')"

TIMEOUT=5
ON_LEVEL=2
LOG_TAG="kbd-backlight-idle"

FIFO="/run/kbd-backlight-activity.fifo"
STATE="on"
WATCHER_PID=""
RUNNING=1

log() { logger -t "$LOG_TAG" "$*"; }

# Trap: only signal shutdown. Don't close fds here (prevents read: bad fd spam).
request_stop() { RUNNING=0; }
trap request_stop INT TERM

# Create FIFO and open it ONCE on fd 3 (read+write keeps it from EOF games)
rm -f "$FIFO"
mkfifo -m 600 "$FIFO"
exec 3<>"$FIFO"

# Ensure cleanup happens exactly once, after the loop ends
cleanup() {
  [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
  exec 3>&- 3<&-
  rm -f "$FIFO"
}
trap cleanup EXIT

# Start with backlight on
echo "$ON_LEVEL" > "$BRIGHTNESS"

# Watcher: on key press, write a token to fd 3 (inherited by the subshell)
(
  log "Watcher starting on $KEYBOARD"
  stdbuf -oL libinput debug-events --device "$KEYBOARD" 2>/dev/null |
  while read -r line; do
    if [[ "$line" == *"KEYBOARD_KEY"* && "$line" == *"pressed"* ]]; then
      # Write a token; never blocks because fd 3 is already open read+write
      printf '1\n' >&3 || true
    fi
  done
  log "Watcher exited"
) &
WATCHER_PID=$!

log "Daemon started. TIMEOUT=${TIMEOUT}s"

# Main loop: wait for activity token or TIMEOUT
while (( RUNNING )); do
  if IFS= read -r -t "$TIMEOUT" -u 3 _; then
    # Activity happened -> ensure ON
    if [[ "$STATE" == "off" ]]; then
      echo "$ON_LEVEL" > "$BRIGHTNESS"
      STATE="on"
      log "Backlight ON (activity)"
    fi

    # Drain queued tokens quickly
    while IFS= read -r -t 0 -u 3 _; do :; done
  else
    # Timeout -> turn OFF
    if [[ "$STATE" != "off" ]]; then
      echo 0 > "$BRIGHTNESS"
      STATE="off"
      log "Backlight OFF (idle ${TIMEOUT}s)"
    fi
  fi
done

log "Stopping"
