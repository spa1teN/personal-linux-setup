# Headset Battery Tray Indicator

Shows battery level for wireless headsets in the Cinnamon/GNOME panel.
Uses custom PNG icons to distinguish headset-with-mic from headphones-only.

## Supported headsets

| Headset                         | Connection | Battery source       | Charging detect |
| ------------------------------- | ---------- | -------------------- | --------------- |
| HyperX Cloud II Wireless        | USB dongle | `headsetcontrol`     | yes             |
| spa1teN headphones (Bose)       | Bluetooth  | BlueZ D-Bus          | no              |

Bluetooth is checked first each poll cycle. If the Bluetooth headset is
connected, it is shown. Otherwise the code falls back to `headsetcontrol`
for the HyperX.

## Locations

| Desktop   | Path                                                             |
| --------- | ---------------------------------------------------------------- |
| GNOME 45+ | `~/.local/share/gnome-shell/extensions/headset-battery@caspar/`  |
| Cinnamon  | `~/.local/share/cinnamon/applets/headset-battery@caspar/`        |

Each directory contains:

| File               | Purpose                                    |
| ------------------ | ------------------------------------------ |
| `extension.js` / `applet.js` | Indicator code                              |
| `metadata.json`    | Shell integration (UUID, name, description) |
| `with-mic.png`     | Icon when mic is connected (128×128 PNG)    |
| `without-mic.png`  | Icon when mic is disconnected (128×128 PNG) |

## Dependencies

| Tool             | Path / package        | Purpose                              |
| ---------------- | --------------------- | ------------------------------------ |
| `headsetcontrol` | `/usr/bin/headsetcontrol` (apt) | Battery level from USB HID headsets |
| BlueZ            | system D-Bus          | Battery level from Bluetooth headsets |

`headsetcontrol` is installed via apt (package version `4.0.0-1`, API 1.4).
The indicator probes both `/usr/local/bin` (source builds) and `/usr/bin`
(apt) before falling back to `PATH`. Built from
[Sapd/HeadsetControl](https://github.com/Sapd/HeadsetControl).

## Indicator states

| State              | Panel label                                  | Visibility |
| ------------------ | -------------------------------------------- | ---------- |
| Charging (USB)     | icon + *88%* (percentage green `#00cc00`)    | visible    |
| Normal             | icon + 75% (theme text color)                | visible    |
| Bluetooth          | icon + 60% (theme text color, no charging)   | visible    |
| Offline            | —                                            | hidden     |
| Error              | icon + ?                                     | visible    |

- **Charging**: only detected for USB headsets via `headsetcontrol`
  (`battery.status == "BATTERY_CHARGING"`). Bluetooth headsets do not
  expose charging state via BlueZ `Battery1`.
- **Mic toggle**: a "Mic connected" switch in the menu swaps between
  `with-mic.png` and `without-mic.png`. The HyperX USB dongle does not
  expose physical mic presence, and Bluetooth headsets don't reliably
  report it either — so the toggle is manual.
- **Offline**: the indicator is hidden entirely (`this.visible = false` on
  GNOME, `this.actor.hide()` on Cinnamon).
- **Error**: shown when no headset source is available or
  `headsetcontrol` fails.

## Menu (click on indicator)

```
Device: spa1teN headphones          ← which headset is active
HyperX Cloud II Wireless: 88% (charging) — mic on — updated 14:32:05
Mic connected  [========] ON        ← manual toggle
──────────────────────────────────
Refresh now
```

- **Device** line shows which headset is being displayed.
- **Mic connected** switch toggles between `with-mic.png` / `without-mic.png`.
- **Refresh now** forces an immediate poll.

## Polling

Polls every **60 seconds**. Each cycle:

1. Queries BlueZ D-Bus for the Bluetooth headset (`2C:41:A1:4E:F8:9D`):
   - Checks `org.bluez.Device1.Connected`
   - Reads `org.bluez.Battery1.Percentage`
   - If connected and reporting battery → display immediately
2. If Bluetooth is not connected, runs `headsetcontrol -o JSON -b`
3. Updates icon (`with-mic.png` / `without-mic.png` based on menu toggle)
4. Updates label text and color (`#00cc00` if charging)
5. Shows or hides the indicator

## Bluetooth — BlueZ D-Bus

```
Address:  2C:41:A1:4E:F8:9D
Name:     spa1teN headphones
Path:     /org/bluez/hci0/dev_2C_41_A1_4E_F8_9D
```

Queried via `Gio.DBus.system.call_sync()`:

```
org.freedesktop.DBus.Properties.Get("org.bluez.Device1", "Connected")
org.freedesktop.DBus.Properties.Get("org.bluez.Battery1", "Percentage")
```

## headsetcontrol JSON schema

```json
{
  "name": "HeadsetControl",
  "version": "0.0.0-unknown",
  "api_version": "1.4",
  "device_count": 1,
  "devices": [
    {
      "status": "success",
      "device": "HyperX Cloud II Wireless (Kingston)",
      "vendor": "Kingston",
      "product": "HyperX Cloud II Wireless",
      "id_vendor": "0x0951",
      "id_product": "0x1718",
      "capabilities": ["CAP_SIDETONE", "CAP_BATTERY_STATUS", "CAP_INACTIVE_TIME"],
      "battery": {
        "status": "BATTERY_CHARGING",
        "level": 88
      }
    }
  ]
}
```

Battery status values: `BATTERY_CHARGING`, `BATTERY_AVAILABLE`,
`BATTERY_UNAVAILABLE`.

## Restarting after edits

| Desktop  | Method                                          |
| -------- | ----------------------------------------------- |
| Cinnamon | `Alt+F2`, type `r`, press Enter                 |
| Cinnamon | Right-click panel → Applets → toggle off/on     |
| GNOME    | `Alt+F2`, type `r`, press Enter                 |

The DBus method `org.Cinnamon.ReloadXlet` exists but returns an internal
error ("type is undefined") on this system.
