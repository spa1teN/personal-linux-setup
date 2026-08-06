# Tailscale Systray — Custom Fork

Fork of [C10udburst/tailscale-systray](https://github.com/C10udburst/tailscale-systray)  
Local working copy: `~/Projects/tailscale-systray-fork/`

## Overview

This fork adds device status indicators, IP-to-clipboard copying, a flat device list, left-click menu support on Linux, and fixes for autostart persistence. The original project is an unofficial cross-platform system tray app written in Go for managing Tailscale.

## Changes

### 1. Flat device list with online/offline indicators

**File:** `main.go` — `setDeviceList()`

- Devices now appear directly in the tray root menu instead of nested under "Device List"
- Each device is prefixed with `●` (online) or `○` (offline)
- Offline devices are greyed out (disabled)
- Each device is a submenu containing:
  - **IP display** — shows the device's Tailscale IP (disabled, informational)
  - **Copy IP** — copies the IP to the system clipboard with a desktop notification
  - **Open in Admin Console** — opens the device's page in the Tailscale admin console (preserves original behavior)

### 2. Clipboard helper

**File:** `clipboard.go` (new)

Zero-dependency clipboard support using OS shell commands:

| Platform | Command |
|---|---|
| Linux (Wayland) | `wl-copy` |
| Linux (X11) | `xclip -selection clipboard` |
| macOS | `pbcopy` |
| Windows | `powershell -NoProfile -Command "$input \| Set-Clipboard"` |

Uses `Set-Clipboard` on Windows (not `clip.exe`) because `clip.exe` uses the OEM code page and garbles non-ASCII UTF-8 text. On Linux, tries `wl-copy` first, then falls back to `xclip`.

### 3. Left-click menu on Linux

Two patches were needed — both are required for left-click to work on Cinnamon (and other DEs that use `xapp-sn-watcher`).

**Files:**
- `vendor/fyne.io/systray/internal/generated/notifier/status_notifier_item.go` (patch 1)
- `vendor/fyne.io/systray/systray_unix.go` (patch 2)

#### Problem (two layers)

**Layer 1 — DBus method returns error:** `fyne.io/systray` v1.10.0 implements the DBus StatusNotifierItem protocol. Its `Activate` method returns `&dbus.ErrMsgUnknownMethod`, telling the tray host "I don't handle left-click."

**Layer 2 — xapp-sn-watcher never shows the menu on left-click:** Even after fixing `Activate` to return `nil`, Cinnamon's `xapp-sn-watcher` (`sn-item.c`) handles left-click and right-click differently for regular SNI items:
- Left-click → calls `Activate()` **fire-and-forget** — never shows the menu regardless of the return value
- Right-click → sets the Dbusmenu as `secondary_menu` — the panel shows it

For **AppIndicator** items (detected by an `/org/ayatana/NotificationItem/` object path prefix), xapp sets the Dbusmenu as the **primary menu** (left-click shows it). Regular SNI items only get the secondary menu assignment, so left-click never shows the menu.

Applications like Nextcloud work because they use Qt/KDE's SNI implementation which already uses the Ayatana path convention, or because KDE Plasma handles left-click differently from Cinnamon.

#### Fix 1 — `Activate` returns success

Changed `UnimplementedStatusNotifierItem.Activate()` to return `nil` (success) instead of `&dbus.ErrMsgUnknownMethod`. This tells the tray host the left-click was handled.

#### Fix 2 — Ayatana path prefix

Changed the SNI object path from `/StatusNotifierItem` to `/org/ayatana/NotificationItem/StatusNotifierItem` in `systray_unix.go`. This makes xapp-sn-watcher detect the item as an AppIndicator (`is_ai = TRUE`), which causes it to set the Dbusmenu as the primary menu (left-click). It also sets it as the secondary menu (right-click), so both clicks work.

The library is vendored (`go mod vendor`) so both patches survive `go mod tidy` and dependency resolution.

### 4. Fixed autostart on Linux

**File:** `install.txt`

**Problem:** On this machine, the official `tailscale` package created a systemd user service at `~/.config/systemd/user/tailscale-systray.service` running `/usr/bin/tailscale systray`. This service:
- Uses `WantedBy=default.target` — starts before the graphical session is ready
- Has `Restart=no` — never retries on failure
- Fails every boot with: `The name org.kde.StatusNotifierWatcher was not provided`
- Potentially blocks the custom tray from registering its own DBus name

The XDG autostart `.desktop` file created by the original install script was valid but missing several keys.

**Fixes:**
- Install script now detects and disables the conflicting official systemd service (`systemctl --user disable --now tailscale-systray.service`)
- `.desktop` file improvements:
  - `StartupNotify=false` — prevents DE timeout treating the tray as a failed window launch
  - `Terminal=false` — explicit terminal declaration
  - `X-GNOME-Autostart-Delay=5` — small delay ensures tailscaled and DBus are ready
  - `Comment=Tailscale system tray icon` — metadata
- `sudo tailscale set --operator` failure now prints a clear warning instead of silently continuing
- Install confirmation summary printed on success

## Build

```bash
cd ~/Projects/tailscale-systray-fork
docker run --rm -v "$PWD":/app -w /app golang:1.20 \
  go build -buildvcs=false -mod=vendor -o tailscale-systray .
```

Or with a local Go installation:

```bash
cd ~/Projects/tailscale-systray-fork
go build -mod=vendor -o tailscale-systray .
```

The `-mod=vendor` flag is required to use the patched `fyne.io/systray` library.

## Install

```bash
# Kill old instance
killall tailscale-systray 2>/dev/null

# Install binary
cp ~/Projects/tailscale-systray-fork/tailscale-systray ~/.local/bin/tailscale-systray

# Fix autostart (one-time)
systemctl --user disable --now tailscale-systray.service 2>/dev/null

# Launch
~/.local/bin/tailscale-systray &
```

The existing `~/.config/autostart/tailscale-systray.desktop` already points to `~/.local/bin/tailscale-systray`, so the new binary will start automatically on next login.

## Dependencies

- `wl-copy` (from `wl-clipboard`) or `xclip` — required on Linux for the clipboard feature
- `tailscale` — the official Tailscale client must be installed and running (`tailscaled`)
- The current user must be set as tailscale operator: `sudo tailscale set --operator $(whoami)`

## Updating from upstream

```bash
cd ~/Projects/tailscale-systray-fork
git fetch origin                    # origin = C10udburst/tailscale-systray
git merge origin/master             # merge upstream changes
# Resolve any conflicts, then:
go mod vendor                       # re-vendor dependencies

# Re-apply both patches if the vendored files changed:

# Patch 1: Make Activate() return nil (status_notifier_item.go)
# Find: func (*UnimplementedStatusNotifierItem) Activate(x int32, y int32) (err *dbus.Error) {
# Change the line below from: err = &dbus.ErrMsgUnknownMethod
#                         to: return nil

# Patch 2: Use Ayatana path prefix (systray_unix.go)
# Change: path = "/StatusNotifierItem"
#     to: path = "/org/ayatana/NotificationItem/StatusNotifierItem"

docker run --rm -v "$PWD":/app -w /app golang:1.20 \
  go build -buildvcs=false -mod=vendor -o tailscale-systray .
```

## Files

| File | Purpose |
|---|---|
| `main.go` | Systray menu, device list, preferences, exit nodes |
| `admin.go` | Tailscale up/down, exit node switching |
| `utils.go` | URL opening, peer naming, traffic formatting |
| `clipboard.go` | Cross-platform clipboard copy |
| `install.txt` | Polyglot install script (Bash + PowerShell) |
| `vendor/` | Vendored Go dependencies with two patched fyne.io/systray files |
| `vendor/…/status_notifier_item.go` | Patch 1: `Activate()` returns `nil` instead of error |
| `vendor/…/systray_unix.go` | Patch 2: Ayatana path prefix for left-click menu |
