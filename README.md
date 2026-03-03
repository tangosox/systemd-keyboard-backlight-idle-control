# systemd-keyboard-backlight-idle-control

Systemd-managed keyboard backlight idle timeout script.

## Overview

On my GNOME system, the keyboard backlight was not turning off automatically,
even though the hardware supported it (and it worked in Windows).

This script turns off the keyboard backlight after a configurable idle period.
It monitors keyboard input using `libinput debug-events`.

---

## Requirements

- `libinput`
- A writable keyboard backlight brightness file under `/sys/class/leds`
- A system-level systemd service

---

## Step 1 Download repository

```
git clone https://github.com/tangosox/systemd-keyboard-backlight-idle-control kbd-backlight
```

## Step 2 — Find Your Keyboard Event Device

Run:

```bash
libinput debug-events
```

Then press a key on your keyboard.
Note the event device (for example `/dev/input/event20`).

Update this line in the script:

```
KEYBOARD="/dev/input/event20"
```

## Step 3 — Find Your Backlight Path and Test

Check available LED devices:

```
ls /sys/class/leds
```

default path:

```
/sys/class/leds/platform::kbd_backlight/brightness
```

Turn backlight ON:

```
echo 1 | sudo tee /sys/class/leds/platform::kbd_backlight/brightness
```

Turn backlight OFF:

```
echo 0 | sudo tee /sys/class/leds/platform::kbd_backlight/brightness
```

Note: sudo echo 1 > file will NOT work because shell redirection happens before sudo.
If this works edit the path of 

## Step 4 Update script

Update this line in the script with path from previous step:

```
BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"
```

## Step 5 — Move Files To Their Respective Locations

place `kbd-backlight-idle.sh` in default location

```
~/.local/bin/
```

Or update the device path and script location in the service file for a
custom path.

Place the service file `kbd-backlight-idle.service` in:

```
/etc/systemd/system/
```

Place `kbd-backlight` sleep restart hook in
```
/usr/lib/systemd/system-sleep/
```

Reload systemd:

```
sudo systemctl daemon-reload
```

Enable the service:

```
sudo systemctl enable your-service-name.service
```

Start the service:

```
sudo systemctl start your-service-name.service
```

This must be installed as a system-level service, not a user service.

## Configuration

Inside the script:
```
TIMEOUT=5        # Idle seconds before turning off
ON_LEVEL=2       # Backlight brightness level
POLL=.2          # Polling interval
```
