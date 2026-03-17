# systemd-keyboard-backlight-idle-control

Systemd-managed keyboard backlight idle timeout script.

## Overview

On my GNOME system, the keyboard backlight was not turning off automatically,
even though the hardware supported it (and it worked in Windows).

This script turns off the keyboard backlight after a configurable idle period.
It monitors keyboard input using `libinput debug-events`.

## Disclaimer
Use at your own risk. I used AI to help code this and although I've been using it on my own system, it hasn't always been stable and I don't understand all of it. Used chatgpt first then Gemini. Gemini helped me fix a 100% cpu usage bug on resume from hibernate by changing from a standard pipe to a named pipe. 

Explanation from Gemini: "The 100% CPU bug happened because a standard pipe (|) crashes when the hardware vanishes during hibernation, leaving the script "spinning" in a broken loop. By switching to a Named Pipe (FIFO), we decoupled the script from the hardware; the script now waits safely at a persistent "file" in /tmp until the keyboard is re-detected, preventing the infinite loop."

I'm studying computer science but I'm pretty early in the education process so apologies for being a vibe coder. Still, I hope you find it useful, as it is now working perfectly for me and solved an issue with no dynamic keyboard backlight available in linux for my hardware.

---

## Requirements

- `libinput`
- A writable keyboard backlight brightness file under `/sys/class/leds`
- A system-level systemd service

---

## Step 1 - Download repository

```
git clone https://github.com/tangosox/systemd-keyboard-backlight-idle-control kbd-backlight
```

## Step 2 - Find Your Keyboard

Run:

```bash
libinput list-devices
```

Then press a key on your keyboard.
Note the keyboard name (for example in my case using input remapper `input-remapper AT Translated Set 2 keyboard forwarded`).

Update only the name as it matches above example with your device name in the script:

```
KEYBOARD="$(libinput list-devices | awk '
  /input-remapper AT Translated Set 2 keyboard forwarded/ {found=1}
  found && /Kernel:/ {print $2; exit}
')"
```

## Step 3 - Find Your Backlight Path and Test

Check available LED devices:

```
ls /sys/class/leds
```

The default path is usually:

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

## Step 4 Update script

Update this line in the script with tested path from previous step:

```
BRIGHTNESS="/sys/class/leds/platform::kbd_backlight/brightness"
```

## Step 5 - Update Service file

You probably do not need `After=input-remapper.service` unless you are also running input-remapper.
Make sure you look over this file, I can't be sure what you need here.  I made it more robust because 
it was failing to start after hibernate/sleep resume.


## Step 6 - Move Files To Their Respective Locations

Place `kbd-backlight-idle.sh` in the default location

```
/usr/local/bin/
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
sudo systemctl enable kbd-backlight-idle.service
```

Start the service:

```
sudo systemctl start kbd-backlight-idle.service
```

This must be installed as a system-level service, not a user service.

## Configuration

Inside the script:
```
TIMEOUT=5        # Idle seconds before turning off
ON_LEVEL=2       # Backlight brightness level
POLL=.2          # Polling interval
```
