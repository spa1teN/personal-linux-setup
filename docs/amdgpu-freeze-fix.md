# AMDGPU Freeze Fix (Panel Self Refresh)

AMD Ryzen AI 300 "Krackan Point" — Radeon 860M / 880M

## Problem

On laptops with AMD Ryzen AI 300 series APUs (Krackan Point, Radeon 860M/880M),
Linux freezes randomly — the mouse may still move but clicks and keyboard input
stop working. This affects all distros (Mint, Ubuntu, Fedora, Arch) with kernel
versions ≥ 6.12. It's a bug in the `amdgpu` display core driver related to
Panel Self Refresh (PSR).

**Affected hardware (confirmed):**
- Lenovo IdeaPad 5 2-in-1 14AKP10 (Ryzen AI 7 350, Radeon 860M)
- Other Krackan Point laptops (Radeon 860M / 880M)

Disabling Secure Boot does **not** help — this is a driver bug, not a firmware
signing issue.

## Fix

Add the kernel parameter `amdgpu.dcdebugmask=0x12` to disable Panel Self
Refresh in the amdgpu display core. This is an official driver debug option,
not a fragile hack — it's stable and safe for daily use. The only trade-off
is slightly higher power consumption (shorter battery life).

### Alternative values

| Value | Effect |
|-------|--------|
| `0x10` | Disable PSR only (less aggressive) |
| `0x12` | Disable PSR + related Panel Replay features (recommended) |

If `0x12` doesn't fully resolve the freezes, try `0x10` first — then fall
back to `0x12` if needed.

## Apply (Manual)

### One-time (test before making permanent)

At the GRUB boot menu, press `e` on the kernel line, add
`amdgpu.dcdebugmask=0x12` after `quiet splash`, then press `F10` or `Ctrl+X`
to boot.

### Permanent

```bash
sudo nano /etc/default/grub
```

Change:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
```
To:
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amdgpu.dcdebugmask=0x12"
```

Then:
```bash
sudo update-grub
sudo reboot
```

### Verify

```bash
cat /proc/cmdline
# Should show: ... amdgpu.dcdebugmask=0x12
```

## Automated install

This repo includes an `amdgpu-fix` config that adds the parameter and runs
`update-grub` automatically:

```bash
./install.sh amdgpu-fix          # Add kernel parameter + update-grub
./install.sh --uninstall amdgpu-fix  # Remove parameter + update-grub
./install.sh --list              # Check if fix is applied
```

The installer:
- Only applies if the `amdgpu` kernel module is loaded (AMD GPU present)
- Is idempotent — won't duplicate the parameter if already set
- Backs up `/etc/default/grub` before modifying
- Requires sudo for writing `/etc/default/grub` and running `update-grub`

## Upstream Status

The bug is tracked in the amdgpu driver GitLab and actively being worked on.
A future kernel update may fix the root cause, making this workaround
unnecessary. To test:

1. Remove the parameter: `sudo nano /etc/default/grub`, delete the
   `amdgpu.dcdebugmask=0x12`, `sudo update-grub`, reboot
2. Use the system normally for a day
3. If freezes return, re-apply the workaround

Regular `linux-firmware` updates (for amdgpu firmware blobs) have also
helped some users:

```bash
sudo apt update && sudo apt upgrade linux-firmware
```
