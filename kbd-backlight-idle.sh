#!/bin/bash
set -euo pipefail

BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"
LIBINPUT="/usr/bin/libinput"
LOGGER="/usr/bin/logger"
LOG_TAG="kbd-backlight-idle"

log() { $LOGGER -t "$LOG_TAG" "$*"; }

while true; do
    # 1. Detection
    KEYBOARD=""
    for i in {1..15}; do
        KEYBOARD=$($LIBINPUT list-devices | awk '/input-remapper AT Translated Set 2 keyboard forwarded/ {found=1} found && /Kernel:/ {print $2; exit}')
        if [[ -n "$KEYBOARD" ]]; then break; fi
        log "Waiting for keyboard... ($i/15)"
        sleep 1
    done

    if [[ -z "$KEYBOARD" ]]; then
        log "Keyboard not found. Retrying in 5s."
        sleep 5
        continue
    fi

    # Use /tmp for broader compatibility, unique name per PID
    FIFO="/tmp/kbd-backlight.$$.fifo"
    mkfifo -m 600 "$FIFO"
    
    # Open for reading AND writing (3<>) to prevent EOF "spin"
    exec 3<>"$FIFO"

    STATE="on"
    TIMEOUT=5
    ON_LEVEL=1

    echo "$ON_LEVEL" > "$BRIGHTNESS" || log "Warning: Initial brightness write failed"

    # Background the libinput listener
    (
        $LIBINPUT debug-events --device "$KEYBOARD" 2>/dev/null | while read -r line; do
            if [[ "$line" == *"KEYBOARD_KEY"* && "$line" == *"pressed"* ]]; then
                echo "1" >&3 2>/dev/null
            fi
        done
    ) &
    WATCHER_PID=$!

    log "Daemon active on $KEYBOARD (PID: $WATCHER_PID)"

    # --- THE FIXED LOOP ---
    while kill -0 "$WATCHER_PID" 2>/dev/null; do
        # Use a real timeout (-t 5) to block (0% CPU) until data or 5 seconds pass
        if read -r -t "$TIMEOUT" -u 3 line; then
            if [[ "$STATE" == "off" ]]; then
                echo "$ON_LEVEL" > "$BRIGHTNESS" || true
                STATE="on"
                log "Backlight ON"
            fi
            # We don't need the 'read -t 0' loop anymore. 
            # The next 'read -t 5' will handle the next event.
        else
            # If we reach here, it means 5 seconds passed with no input
            if [[ "$STATE" != "off" ]]; then
                echo 0 > "$BRIGHTNESS" || true
                STATE="off"
                log "Backlight OFF"
            fi
        fi
    done

    log "Watcher lost. Cleaning up..."
    kill "$WATCHER_PID" 2>/dev/null || true
    exec 3>&-
    rm -f "$FIFO"
    sleep 2
done
