import evdev
import time
import selectors
import os

# --- Configuration ---
DEVICE_NAME = "input-remapper AT Translated Set 2 keyboard forwarded"
BACKLIGHT_PATH = "/sys/class/leds/platform::kbd_backlight/brightness"
IDLE_TIMEOUT = 5 # seconds

def set_backlight(level):
    try:
        with open(BACKLIGHT_PATH, 'w') as f:
            f.write(str(level))
    except Exception as e:
        print(f"Error writing to backlight: {e}")

def find_device():
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    for device in devices:
        if device.name == DEVICE_NAME:
            return device
    return None

def run_daemon():
    device = find_device()
    if not device:
        print("Keyboard not found. Retrying...")
        return False

    # Create a selector to monitor the device (0% CPU wait)
    selector = selectors.DefaultSelector()
    selector.register(device, selectors.EVENT_READ)
    
    state = "on"
    set_backlight(1)
    
    while True:
        # Wait for activity OR timeout
        events = selector.select(timeout=IDLE_TIMEOUT)
        
        if events:
            # Activity detected: drain the events
            for key, mask in events:
                for event in device.read():
                    pass # We just need to clear the buffer
            
            if state == "off":
                set_backlight(1)
                state = "on"
        else:
            # Timeout reached: no activity
            if state == "on":
                set_backlight(0)
                state = "off"

if __name__ == "__main__":
    while True:
        try:
            run_daemon()
        except Exception:
            time.sleep(5)
