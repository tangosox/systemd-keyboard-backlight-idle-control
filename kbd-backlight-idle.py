#!/usr/bin/python3
import evdev
import time
import selectors
import os

# --- Configuration ---
DEVICE_NAME = "input-remapper AT Translated Set 2 keyboard forwarded"
BACKLIGHT_PATH = "/sys/class/leds/platform::kbd_backlight/brightness"
IDLE_TIMEOUT = 5  # seconds

def set_backlight(level):
    """Writes 0 or 1 to the sysfs brightness file."""
    try:
        with open(BACKLIGHT_PATH, 'w') as f:
            f.write(str(level))
    except Exception as e:
        print(f"Error writing to backlight: {e}")

def find_device():
    """Scans for the keyboard and returns the device object."""
    attempt = 0
    while True:
        try:
            for path in evdev.list_devices():
                dev = evdev.InputDevice(path)
                if dev.name == DEVICE_NAME:
                    print(f"Connected to {dev.name}")
                    return dev
                dev.close()
        except Exception as e:
            print(f"Scan error: {e}")

        # Backoff logic so we don't spam the CPU if the device is missing
        wait_time = min(10, (2 ** attempt)) if attempt > 0 else 1
        print(f"Keyboard not found. Retrying in {wait_time}s...")
        time.sleep(wait_time)
        attempt += 1

def run_daemon():
    while True:
        try:
            device = find_device()
            selector = selectors.DefaultSelector()
            selector.register(device, selectors.EVENT_READ)

            state = "on"
            set_backlight(1)

            while True:
                events = selector.select(timeout=IDLE_TIMEOUT)

                # Wait for keyboard event or timeout
                if events:
                    time.sleep(0.05)

                    # Drain the buffer in one quick burst
                    for key, mask in events:
                        try:
                            for event in device.read():
                                pass
                        except BlockingIOError:
                            pass

                    if state == "off":
                        set_backlight(1)
                        state = "on"
                else:
                    # IDLE TIMEOUT
                    if state == "on":
                        set_backlight(0)
                        state = "off"

        except (OSError, FileNotFoundError):
            time.sleep(2)


if __name__ == "__main__":
    # Ensure we start with the light on
    set_backlight(1)
    run_daemon()
