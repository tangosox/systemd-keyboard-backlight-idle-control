#!/bin/bash
set -euo pipefail

# ==========================================
# CONFIGURATION (Edit these values)
# ==========================================
IDLE_TIMEOUT=5        # Seconds of inactivity before turning off
BRIGHTNESS_LEVEL=1    # 1 for ON, 0 for OFF (some laptops support higher)
LOG_TAG="kbd-idle"    # Tag for journalctl/logger
# ==========================================

BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"
LIBINPUT="/usr/bin/libinput"
LOGGER="/usr/bin/logger"

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

    FIFO="/tmp/kbd-backlight.$$.fifo"
    mkfifo -m 600 "$FIFO"
    exec 3<>"$FIFO"

    STATE="on"
    echo "$BRIGHTNESS_LEVEL" > "$BRIGHTNESS" || log "Warning: Initial write failed"

    # Start listener
    (
        $LIBINPUT debug-events --device "$KEYBOARD" 2>/dev/null | while read -r line; do
            if [[ "$line" == *"KEYBOARD_KEY"* && "$line" == *"pressed"* ]]; then
                echo "1" >&3 2>/dev/null
            fi
        done
    ) &
    WATCHER_PID=$!

    log "Daemon active on $KEYBOARD (PID: $WATCHER_PID)"

    # --- THE CLEAN LOOP ---
    while kill -0 "$WATCHER_PID" 2>/dev/null; do
        # This "read" blocks the CPU until activity happens OR timeout is reached
        if read -r -t "$IDLE_TIMEOUT" -u 3 _; then
            # Activity detected
            if [[ "$STATE" == "off" ]]; then
                echo "$BRIGHTNESS_LEVEL" > "$BRIGHTNESS" || true
                STATE="on"
                log "Activity: Backlight ON"
            fi
        else
            # Timeout reached (No activity for $IDLE_TIMEOUT seconds)
            if [[ "$STATE" != "off" ]]; then
                echo 0 > "$BRIGHTNESS" || true
                STATE="off"
                log "Idle: Backlight OFF"
            fi
        fi
    done

    log "Watcher lost. Cleaning up..."
    kill "$WATCHER_PID" 2>/dev/null || true
    exec 3>&-
    rm -f "$FIFO"
    sleep 2
done
