#!/bin/bash
set -euo pipefail

# Use absolute paths for systemd reliability
BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"
LIBINPUT="/usr/bin/libinput"
LOGGER="/usr/bin/logger"
LOG_TAG="kbd-backlight-idle"

log() { $LOGGER -t "$LOG_TAG" "$*"; }

while true; do
    # 1. Detection
    KEYBOARD=""
    for i in {1..15}; do
        # We use the absolute path for libinput here
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

    # Use a unique FIFO name to prevent collisions on restart
    FIFO="/run/kbd-backlight-activity.$$.fifo"
    trap "rm -f $FIFO; exit" EXIT INT TERM
    mkfifo -m 600 "$FIFO"
    exec 3<>"$FIFO"

    WATCHER_PID=""
    STATE="on"
    TIMEOUT=5
    ON_LEVEL=1

    # Force light ON at start, but don't crash if it fails
    echo "$ON_LEVEL" > "$BRIGHTNESS" || log "Warning: Initial brightness write failed"

    (
        # If libinput exits, this subshell exits, which the main loop detects via 'kill -0'
        $LIBINPUT debug-events --device "$KEYBOARD" 2>/dev/null | while read -r line; do
            if [[ "$line" == *"KEYBOARD_KEY"* && "$line" == *"pressed"* ]]; then
                # Use a non-blocking write to the FIFO to prevent the watcher from hanging
                echo 1 > "$FIFO" 2>/dev/null || exit 1
            fi
        done
    ) &
    WATCHER_PID=$!

    log "Daemon active on $KEYBOARD (PID: $WATCHER_PID)"

    while kill -0 "$WATCHER_PID" 2>/dev/null; do
        if IFS= read -r -t "$TIMEOUT" -u 3 _; then
            if [[ "$STATE" == "off" ]]; then
                # Use || true to prevent script exit on hardware hiccup
                echo "$ON_LEVEL" > "$BRIGHTNESS" || true
                STATE="on"
                log "Backlight ON"
            fi
            while IFS= read -r -t 0 -u 3 _; do :; done
        else
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

