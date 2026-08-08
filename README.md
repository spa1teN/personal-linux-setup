# personal-linux-setup

My personal dotfiles and configuration for Linux machines.

**What's configured:**
- **Terminal:** WezTerm with GTK theme auto-detection and workspace switching
- **Shell:** Bash with Starship prompt (SSH/local variants), ble.sh autosuggestions, fzf
- **Claude Code:** Custom DeepSeek status line, WhiteSur-dark theme, plugin setup
- **Hardware:** HyperX Cloud II Wireless battery tray
- **Kernel/GPU:** AMD GPU freeze fix (amdgpu PSR workaround)
- **Systray:** GPaste clipboard manager applet (custom fork), Tailscale tray (custom fork)

## Quick Start

```bash
cd ~/setup
./install.sh --help          # Show all options
./install.sh --list          # See what's installed
```

The script is idempotent — safe to run multiple times. Dependencies are
installed automatically. If sudo is needed, the script will tell you.
Use `--remove` to remove configs and restore backups.

### Common Commands

```bash
./install.sh wezterm tmux                # Install specific configs
./install.sh bashrc                      # Dependencies installed automatically
./install.sh --remove gpaste             # Remove gpaste applet
./install.sh --set wezterm                # Copy local version back into repo (then push!)
./install.sh --update                    # Update all active configs after a pull
```

## What Gets Installed

| Config | Target | Method |
|---|---|---|
| `wezterm` | `~/.wezterm.lua` | copy |
| `tmux` | `~/.tmux.conf` | copy |
| `bashrc` | `~/.bashrc` | copy |
| `bash_aliases` | `~/.bash_aliases` | **rendered** (mode 600) |
| `starship` | `~/.config/starship.toml` + `starship-local.toml` + `git-prompt-section` + `git-status-prompt` | copy (4 files) |
| `claude-settings` | `~/.claude/settings.json` + `settings.local.json` | copy (both) |
| `claude-statusline` | `~/.claude/scripts/ds-statusline.sh` | copy |
| `claude-plugins` | `~/.claude/plugins/installed_plugins.json` | copy |
| `claude-marketplaces` | `~/.claude/plugins/known_marketplaces.json` | copy |
| `gpaste` | `~/.local/share/cinnamon/applets/gpaste-reloaded@feuerfuchs.eu/` | clone + copy |
| `tailscale-tray` | `~/.local/bin/tailscale-systray` | build from source |
| `headset-battery` | `~/.local/share/cinnamon/applets/headset-battery@caspar/` + GNOME ext | copy |
| `amdgpu-fix` | `/etc/default/grub` (kernel param) | edit (sudo) |

## Secrets

`bash_aliases` is stored as a template with `{{ANTHROPIC_AUTH_TOKEN}}` and
`{{NEXTCLOUD_PASSWORD}}` placeholders. On first install you'll be prompted
for these values. On subsequent runs, the script extracts existing values
automatically — no re-prompting. After install, edit `~/.bash_aliases`
directly to set them permanently.

You can also set them via environment variables: `ANTHROPIC_AUTH_TOKEN` and
`NEXTCLOUD_PASSWORD`.

The rendered file lives **only** at `~/.bash_aliases` (mode 600) and is
never committed to the repo.

## Backup & Restore

Existing files are backed up to `~/.dotfiles-backup/<timestamp>/` before
being replaced. To restore:

```bash
cp ~/.dotfiles-backup/<timestamp>/.bashrc ~/.bashrc
# ... etc.
```

## Docs

- [bash_prompt.md](docs/bash_prompt.md) — Bash prompt setup (Starship, ble.sh, fzf)
- [claude_status.md](docs/claude_status.md) — Claude Code custom status line
- [headset-battery-tray.md](docs/headset-battery-tray.md) — HyperX headset battery tray
- [gpaste-custom.md](docs/gpaste-custom.md) — GPaste-Reloaded Cinnamon applet
- [tailscale-tray-custom.md](docs/tailscale-tray-custom.md) — Tailscale systray fork
- [amdgpu-freeze-fix.md](docs/amdgpu-freeze-fix.md) — AMD GPU freeze fix (amdgpu PSR)
