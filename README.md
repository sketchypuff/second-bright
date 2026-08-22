# SecondBright

A brightness slider for your external monitor, in the macOS menu bar.

Click the sun icon in the top bar, drag the slider, done — no reaching for the
buttons on the monitor itself. It changes **only** the external display; your
Mac's own screen is never touched.

## Install

**[⬇ Download SecondBright](https://github.com/sketchypuff/second-bright/releases/latest)**
— macOS 14 or later, on a Mac with Apple Silicon (M1 or newer).

Nothing else to install: the download contains the finished app.

1. Open the downloaded `.dmg` file.
2. Drag **SecondBright** onto the **Applications** folder.
3. Open SecondBright from your Applications folder.

### The first time you open it

macOS will refuse, and say it *"can't be opened because Apple cannot check it
for malicious software."* This is expected. It means the app hasn't been signed
with a paid Apple Developer certificate — not that anything is wrong with it.

To let it through:

1. Click **Done** on the warning.
2. Open **System Settings** → **Privacy & Security**.
3. Scroll to the bottom. There's a line saying SecondBright was blocked, with an
   **Open Anyway** button next to it. Click it.
4. Confirm with Touch ID or your password.

You only do this once. After that SecondBright opens normally, including
automatically at login if you turn that on.

### To uninstall

Click **Quit** in the popover, then drag SecondBright from your Applications
folder to the Trash.

## What it does

- A slider in the menu bar, plus 0 / 25 / 50 / 100% buttons. The full range:
  100% is your monitor's brightest, 0% is a black screen.
- Remembers the level for each monitor and sets it again when you log in.
- Notices when you unplug, replug, or wake the Mac, and puts your brightness
  back — monitors routinely forget it when they sleep.
- Can start automatically at login.
- Stays out of the way: no Dock icon, no app-switcher entry.

## How it changes the brightness

There are two ways to dim a monitor, and SecondBright picks whichever one your
screen allows, checking each time you plug it in.

**Turning the backlight down.** This is the real thing — exactly what the
buttons on the monitor do. It's what you want, and it's what the app uses
whenever the monitor permits it.

**Dimming the picture.** Some monitors don't let software touch their backlight.
For those, SecondBright darkens the image on that screen instead. It genuinely
looks dimmer, but the lamp behind the panel is still at full power, so it helps
less in a dark room. The popover tells you when this is what's happening, so
you're never left guessing.

Either way the slider goes all the way down. Turning the backlight down only
gets you so far — every monitor has a floor of its own, well above off — so at
the bottom of the range SecondBright darkens the picture as well, and the two
together take the screen to black.

How black is black? On a normal LCD the lamp behind the panel is still on, so
you'll see a faint glow rather than a screen that looks switched off. On an OLED
monitor it's properly black.

### Getting back from a black screen

Move your mouse onto the dark monitor and it comes back to 25%. That's a real
change, not a preview — the slider moves with it and it stays there until you
turn it down again. Your Mac's own screen is never dimmed, so the menu bar and
the slider are always where you left them too.

### If the slider doesn't seem to do much

You're probably on the second mode. Look through your monitor's own on-screen
menu for a setting called **DDC/CI** and turn it on — that's the switch that
lets a computer control the backlight, and plenty of monitors ship with it off.

SecondBright re-checks every time you replug the monitor or reopen the app, so
it'll pick up the change by itself and switch to real backlight control.

---

Building, design notes, and the reasoning behind how this works are in
[CONTRIBUTING.md](CONTRIBUTING.md).
