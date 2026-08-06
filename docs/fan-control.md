# Fan Quiet Setup (sysfs)

MSI B550 Gaming Plus (MS-7C56) — AMD Ryzen 5 5600X

> **Note:** The Flatpak `io.github.wiiznokes.fan-control` was installed but ultimately not used — it couldn't save behaviors properly. Fans are controlled directly via sysfs with systemd services instead.

## Problem

The Nuvoton fan controller chip (ID `0xd592`) on this board is not supported by the mainline Linux kernel. The `nct6775` module does not recognize it. The `nct6687d` out-of-tree DKMS driver is required.

## Driver Installation

The driver was built from [Fred78290/nct6687d](https://github.com/Fred78290/nct6687d) and installed via DKMS:

```bash
git clone https://github.com/Fred78290/nct6687d.git
cd nct6687d
sudo apt-get install -y build-essential linux-headers-$(uname -r) dkms dh-dkms
make deb
sudo dpkg -i ../nct6687d-dkms_*.deb
sudo modprobe nct6687
echo "nct6687" | sudo tee /etc/modules-load.d/nct6687.conf
```

## Fan Map

| pwm | Header | Fan | Control |
|-----|--------|-----|---------|
| pwm1 | CPU_FAN | CPU cooler fan #1 | BIOS auto (silent curve) |
| pwm2 | PUMP_FAN | CPU cooler fan #2 | Mirrors pwm1 every 2s |
| pwm3 | SYS_FAN #1 | Case fan | Manual 20% (51/255) |
| pwm4 | SYS_FAN #2 | Case fan | Manual 20% (51/255) |
| pwm5–8 | SYS_FAN #3–6 | Nothing connected | — |

The CPU cooler has two fans: one on CPU_FAN, one on PUMP_FAN. The pump header defaults to 100% in BIOS because it's intended for AIO pumps. The mirror timer keeps both fans at the same speed without needing to modify BIOS settings.

## Files

### `/usr/local/bin/fan-quiet.sh`

Runs once at boot. Sets pwm1 to BIOS auto, case fans to fixed 20%.

```bash
#!/bin/bash
for d in /sys/class/hwmon/*; do
  if [ "$(cat "$d/name")" = "nct6687" ]; then
    echo 99 > "$d/pwm1_enable"
    echo 1 > "$d/pwm3_enable"; echo 51 > "$d/pwm3"
    echo 1 > "$d/pwm4_enable"; echo 51 > "$d/pwm4"
    exit 0
  fi
done
exit 1
```

### `/usr/local/bin/fan-mirror.sh`

Runs every 2 seconds via systemd timer. Copies pwm1 value to pwm2.

```bash
#!/bin/bash
for d in /sys/class/hwmon/*; do
  if [ "$(cat "$d/name")" = "nct6687" ]; then
    val=$(cat "$d/pwm1")
    echo 1 > "$d/pwm2_enable"
    echo "$val" > "$d/pwm2"
    exit 0
  fi
done
exit 1
```

### Systemd units

- `/etc/systemd/system/fan-quiet.service` — oneshot, runs at boot
- `/etc/systemd/system/fan-mirror.service` — oneshot, called by timer
- `/etc/systemd/system/fan-mirror.timer` — runs `fan-mirror.service` every 2s

## Useful commands

```bash
# Check all fans and temps
sensors

# Check pwm state
for i in 1 2 3 4; do
  echo "pwm${i}: $(cat /sys/class/hwmon/hwmon1/pwm${i})/255 mode=$(cat /sys/class/hwmon/hwmon1/pwm${i}_enable)"
done

# Temporarily override a fan to manual
echo 1 | sudo tee /sys/class/hwmon/hwmon1/pwm2_enable
echo 128 | sudo tee /sys/class/hwmon/hwmon1/pwm2   # 50%

# Force a specific fan to full (identify which fan is which)
echo 255 | sudo tee /sys/class/hwmon/hwmon1/pwm2

# Return to BIOS auto
echo 99 | sudo tee /sys/class/hwmon/hwmon1/pwm1_enable

# Restore quiet settings
sudo systemctl restart fan-quiet.service
sudo systemctl restart fan-mirror.timer
```

## Tuning

Edit `51` (20%) in `/usr/local/bin/fan-quiet.sh` to change case fan speed. Values are 0–255:
- 25 = ~10% (stall risk)
- 51 = ~20% (quiet)
- 128 = ~50% (audible)
- 255 = 100% (loud)

Don't go below ~25 or fans may not spin.

The CPU fan curve (pwm1 auto) is controlled by the BIOS silent profile. To change it, reboot → Del → Hardware Monitor → adjust CPU fan curve.
