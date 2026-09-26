# IpadTablet

Turns an iPad + Apple Pencil into a zero-latency absolute-position tablet for
osu!lazer on macOS, without video mirroring (Sidecar/Astropad add 10-30ms from
H.264 encode/decode — this bypasses that entirely by streaming raw coordinates
over a wired USB tunnel).

## How it works

- `ipad-client/`: a blank UIKit + SwiftUI app. `DigitizerViewController`
  listens on a TCP socket and reads Apple Pencil touches at full coalesced
  hardware resolution, normalizes them to (0.0-1.0) against a user-configurable
  active area, and streams them as 8-byte records. `SettingsView` (gear icon,
  top-right) lets you resize/reshape/reposition that active area and tune
  input smoothing, all live on-device.
- `mac-daemon/tablet_server.py`: shells out to `iproxy` (from
  [libimobiledevice](https://libimobiledevice.org)) to tunnel a TCP port over
  the paired USB/usbmuxd link, connects through it, enumerates your displays,
  and injects each coordinate as an absolute `CGEventMouseMoved` event via
  `CGEventPost(kCGHIDEventTap, ...)`, bypassing macOS pointer acceleration
  entirely.

Why TCP-over-USB instead of Wi-Fi/UDP: a Wi-Fi-only iPad has no Personal
Hotspot feature at all, so there's no way to get a real network interface
over the cable. `usbmuxd` (the same pairing mechanism Xcode itself uses to
talk to devices) doesn't have that limitation — it works over the cable
regardless of Wi-Fi/cellular capability, but only forwards TCP, hence the
switch from the datagram design.

## Setup

### 0. Prerequisites (one-time, on the Mac)

Xcode.app (the full app, not just Command Line Tools) must be installed from
the App Store, with its license accepted and an Apple ID signed in under
Xcode > Settings > Accounts (a free personal team is enough for local device
installs) — these two need the GUI and can't be scripted:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license
```

### 1. Run it

```
./setup.sh
```

This installs `xcodegen`/`libimobiledevice` via Homebrew if missing, builds
and installs the iPad app onto whichever connected+paired physical iPad it
finds (or specify one: `./ipad-client/deploy.sh <UDID>`), then starts the Mac
daemon in the foreground (Ctrl-C to stop — **not** `kill -9`, which would
orphan its `iproxy` child and break later runs; plain `kill`/Ctrl-C both
clean up correctly). Rerunning `./setup.sh` after code changes is safe and
idempotent.

First install on a given iPad needs two one-time approvals on the iPad
itself, then rerun `./setup.sh`:

- **Settings > Privacy & Security > Developer Mode** — enable, restart, confirm.
- **Settings > General > VPN & Device Management** — trust the developer
  certificate, shown the first time the app fails to launch with a signature
  error.

Grant the Mac daemon Accessibility permission too, or `CGEventPost` will
silently no-op: System Settings > Privacy & Security > Accessibility > add
your terminal app (or the `python3` binary at `mac-daemon/.venv/bin/python3`).

The daemon prints every active display with an index at startup and defaults
to the largest non-main one (i.e. an external monitor over the built-in
display, if both are present). Override with `./mac-daemon/run.sh --display N`.

### 2. Connect the devices

Plug the iPad into the Mac with a cable that actually carries data — many
charging-only cables (especially ones bundled with power banks/chargers)
won't. If the iPad charges but never shows a "Trust This Computer?" prompt
when unlocked, that's the tell; `idevice_id -l` will also show nothing.
Personal Hotspot / Wi-Fi are **not** used or needed.

### 3. Configure the active area on the iPad

Tap the gear icon in the app:

- **Width / Height** — the active tracking rectangle, in iPad points.
  Smaller means less physical pencil movement covers the full logical range
  (i.e. this *is* sensitivity — there's no separate gain setting).
- **Lock ratio** — turn on and set a ratio (e.g. `1.4`) to only need to
  adjust one of Width/Height; the other follows automatically.
- **Smoothing** — 0% by default (raw, lowest latency). Exponentially
  averages consecutive samples if you want less jitter at the cost of some
  responsiveness; always resets on a fresh pencil-down so a new stroke starts
  exactly at the contact point.
- Drag the dashed outline anywhere on screen with a finger to reposition the
  active area (fingers are otherwise ignored — only Pencil touches drive the
  cursor, so this can't conflict with tracking).

### 4. osu!lazer settings

- Settings > Input > turn **off** Raw Input (the daemon already posts
  absolute HID coordinates; raw input inside the game would double-process
  them and cause erratic movement).
- Keep tap bindings (Z/X) on your physical keyboard — the iPad surface only
  ever sends move events, never clicks, so there's no tap-conflict to work
  around.

## Known limits

- If you have multiple Mac displays, `--display` picks by index from the
  list the daemon prints at startup — it's a one-time choice per run, not
  something the iPad's settings UI can see or control (display selection is
  a Mac-side concern, same as any tablet driver).
- TCP guarantees ordering/delivery here (no dropped-sample risk like the
  original UDP design), at the cost of the daemon needing a short reconnect
  backoff to avoid spinning if the link blips — it has one (`RECONNECT_DELAY`
  in `tablet_server.py`).
