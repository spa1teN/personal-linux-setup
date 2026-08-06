#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# install.sh — Personal dotfiles installer
#
# Copies configs from this repo into $HOME. Handles .bash_aliases as a
# template (renders to ~/.bash_aliases mode 600). Dependencies are installed
# automatically. If sudo is needed, the script tells you.
# Idempotent: safe to run multiple times. Existing files are backed up to
# ~/.dotfiles-backup/<timestamp>/ before being replaced.
#
# Usage: ./install.sh --help
# ==============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
INSTALLED=0
BACKED_UP=0
SKIPPED=0
UNINSTALLED=0

# Secrets passed via CLI flags (empty = prompt or reuse from existing file)
CLI_TOKEN=""
CLI_NEXTCLOUD_PW=""

# --- Config registry: name | source | home-relative target | kind ---
# kind: copy         = copy from repo into $HOME (src relative to repo, or absolute)
#       render       = template rendered to $HOME (for files with secrets)
#       multi        = multiple files (:: separator)
#       clone        = git clone into $HOME (src = URL, target = $HOME-relative path)
#       clone_copy   = clone repo from URL, copy subdir to target
#       binary_build = build from local source dir, copy binary + autostart to $HOME
#       headset_battery = headset battery tray (Cinnamon applet + GNOME extension)
#       fan_control  = fan control scripts + systemd units (requires sudo)
ITEMS=(
  "wezterm|dotfiles/.wezterm.lua|.wezterm.lua|copy"
  "tmux|dotfiles/.tmux.conf|.tmux.conf|copy"
  "bashrc|dotfiles/.bashrc|.bashrc|copy"
  "bash_aliases|dotfiles/.bash_aliases.template|.bash_aliases|render"
  "starship|dotfiles/.config/starship.toml::dotfiles/.config/starship-local.toml|.config/starship.toml::.config/starship-local.toml|multi"
  "claude-settings|dotfiles/.claude/settings.json::dotfiles/.claude/settings.local.json|.claude/settings.json::.claude/settings.local.json|multi"
  "claude-statusline|dotfiles/.claude/scripts/ds-statusline.sh|.claude/scripts/ds-statusline.sh|copy"
  "claude-plugins|dotfiles/.claude/plugins/installed_plugins.json|.claude/plugins/installed_plugins.json|copy"
  "claude-marketplaces|dotfiles/.claude/plugins/known_marketplaces.json|.claude/plugins/known_marketplaces.json|copy"
  "gpaste|https://github.com/spa1teN/GPaste-Reloaded-Cinnamon-Applet.git|.local/share/cinnamon/applets/gpaste-reloaded@feuerfuchs.eu|clone_copy|gpaste-reloaded@feuerfuchs.eu"
  "tailscale-tray|$HOME/Projects/tailscale-systray-fork|.local/bin/tailscale-systray|binary_build"
  "headset-battery|dotfiles/headset-battery|.local/share/cinnamon/applets/headset-battery@caspar|headset_battery"
  "fan-control|dotfiles/fan-control|fan-control|fan_control"
)

# --- Output helpers ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()    { printf "  ${GREEN}✓${NC} %s\n" "$1"; }
warn()   { printf "  ${YELLOW}⚠${NC} %s\n" "$1" >&2; }
error()  { printf "  ${RED}✗${NC} %s\n" "$1" >&2; }
info()   { printf "  ${CYAN}ℹ${NC} %s\n" "$1"; }

# ==============================================================================
# Help text
# ==============================================================================
show_help() {
  cat <<'EOF'
Usage: ./install.sh [OPTIONS] [CONFIG...]

Install dotfiles and configs from this repo into $HOME.
Idempotent — safe to run multiple times. Existing files are backed up to
~/.dotfiles-backup/<timestamp>/ before being replaced.
Dependencies are installed automatically. If sudo is needed, the script
will tell you.

Options:
  --help                   Show this help and exit
  --list                   List available configs and their install status
  --uninstall               Remove config(s); restore from backup if available
  --token TOKEN            ANTHROPIC_AUTH_TOKEN for bash_aliases (sk-...)
  --nextcloud-pw PASSWORD  NEXTCLOUD_PASSWORD for bash_aliases
  --enable                  Enable a config (persistent across reboots)
  --disable                 Disable a config (persistent across reboots)
  --store                   Copy local version back into the repo

Configs (colored = supports --enable/--disable):
  wezterm                  WezTerm terminal config
  tmux                     tmux config (mouse on)
  bashrc                   Bash config (Starship, NVM, fzf, ble.sh)
  bash_aliases             Bash aliases with secrets (rendered, mode 600)
  starship                 Starship prompt configs (SSH + local)
  claude-settings          Claude Code settings + settings.local
  claude-statusline        Claude Code status line script
  claude-plugins           Claude Code installed plugins
  claude-marketplaces      Claude Code known marketplaces
  gpaste                   GPaste-Reloaded Cinnamon applet (custom fork)
  headset-battery           Headset battery tray (Cinnamon + GNOME)
  fan-control               MSI B550 fan quiet setup (requires sudo)
EOF
  printf '  %b%s%b\n' "$CYAN" "tailscale-tray           Tailscale systray (custom fork, built from source)" "$NC"
}

# ==============================================================================
# Security check: scan repo for leaked secrets
# ==============================================================================
check_repo_secrets() {
  local leaks=0
  # Check tracked files
  if git -C "$REPO_DIR" grep -nE 'sk-[A-Za-z0-9]{20,}' HEAD -- 'dotfiles/' 2>/dev/null; then
    leaks=1
  fi
  if git -C "$REPO_DIR" grep -nE 'NEXTCLOUD_PASSWORD=[^{]\S' HEAD -- 'dotfiles/' 2>/dev/null; then
    leaks=1
  fi
  # Check working tree for stray rendered copies
  if grep -rEl 'sk-[A-Za-z0-9]{20,}' "$REPO_DIR/dotfiles/" 2>/dev/null | grep -v '.template'; then
    leaks=1
  fi
  if [[ $leaks -eq 1 ]]; then
    warn "SECURITY: Possible secrets found in repo files! Review the matches above."
    warn "Only {{ANTHROPIC_AUTH_TOKEN}} and {{NEXTCLOUD_PASSWORD}} placeholders are safe."
    return 1
  fi
  return 0
}

# ==============================================================================
# Copy a file or directory, backing up if needed
# $1 = absolute source path
# $2 = absolute destination path in $HOME
# ==============================================================================
copy_file() {
  local src="$1"
  local dst="$2"
  local dst_short="${dst#$HOME/}"

  # Safety: refuse to operate on $HOME itself
  if [[ "$dst" == "$HOME" ]] || [[ "$dst" == "$HOME/" ]] || [[ -z "$dst_short" ]]; then
    error "Refusing to copy: target resolves to HOME directory ($dst)"
    return 1
  fi

  # Ensure source exists
  if [[ ! -e "$src" ]]; then
    error "Source not found: $src"
    return 1
  fi

  mkdir -p "$(dirname "$dst")"

  # Already up to date?
  if [[ -f "$src" ]] && [[ -f "$dst" ]]; then
    if cmp -s "$src" "$dst" 2>/dev/null; then
      log "already up to date: $dst_short"
      ((SKIPPED++)) || true
      return 0
    fi
  elif [[ -d "$src" ]] && [[ -d "$dst" ]]; then
    if diff -rq "$src" "$dst" >/dev/null 2>&1; then
      log "already up to date: $dst_short"
      ((SKIPPED++)) || true
      return 0
    fi
  fi

  # Remove stale symlink if present
  if [[ -L "$dst" ]]; then
    rm "$dst"
  elif [[ -e "$dst" ]]; then
    # Real file/dir — back up before replacing
    local backup_dst="$BACKUP_DIR/$dst_short"
    mkdir -p "$(dirname "$backup_dst")"
    mv "$dst" "$backup_dst"
    log "backed up $dst_short → $backup_dst"
    ((BACKED_UP++)) || true
  fi

  if [[ -d "$src" ]]; then
    cp -r "$src" "$dst"
  else
    cp "$src" "$dst"
  fi
  log "copied $dst_short"
  ((INSTALLED++)) || true
  return 0
}

# ==============================================================================
# Extract a value from the existing ~/.bash_aliases
# $1 = target file to read from
# $2 = perl-compatible regex with \K (only the value after \K is returned)
# ==============================================================================
extract_existing_value() {
  grep -oP "$2" "$1" 2>/dev/null | head -1 || true
}

# ==============================================================================
# Render the bash_aliases template
# Accepts token/pw from environment or CLI globals; prompts only if missing.
# ==============================================================================
render_aliases() {
  local src="$REPO_DIR/dotfiles/.bash_aliases.template"
  local dst="$HOME/.bash_aliases"
  local dst_short="${dst#$HOME/}"

  local token="${CLI_TOKEN:-}"
  local nextcloud_pw="${CLI_NEXTCLOUD_PW:-}"

  # Also check environment variables
  if [[ -z "$token" ]]; then
    token="${ANTHROPIC_AUTH_TOKEN:-}"
  fi
  if [[ -z "$nextcloud_pw" ]]; then
    nextcloud_pw="${NEXTCLOUD_PASSWORD:-}"
  fi

  # Try to reuse existing values from an already-rendered file
  if [[ -z "$token" && -f "$dst" ]]; then
    token=$(extract_existing_value "$dst" 'ANTHROPIC_AUTH_TOKEN=\K[^ ]+')
  fi
  if [[ -z "$nextcloud_pw" && -f "$dst" ]]; then
    nextcloud_pw=$(extract_existing_value "$dst" 'NEXTCLOUD_PASSWORD=\K[^ ]+')
  fi

  # Prompt for any values still missing
  if [[ -z "$token" ]] || [[ "$token" == "{{ANTHROPIC_AUTH_TOKEN}}" ]]; then
    read -r -s -p "Enter ANTHROPIC_AUTH_TOKEN (sk-...): " token
    echo
  fi
  if [[ -z "$nextcloud_pw" ]] || [[ "$nextcloud_pw" == "{{NEXTCLOUD_PASSWORD}}" ]]; then
    read -r -s -p "Enter NEXTCLOUD_PASSWORD: " nextcloud_pw
    echo
  fi

  if [[ -z "$token" ]] || [[ -z "$nextcloud_pw" ]]; then
    error "Both ANTHROPIC_AUTH_TOKEN and NEXTCLOUD_PASSWORD are required."
    return 1
  fi

  # Back up existing file if it's a real file (not a symlink)
  if [[ -f "$dst" ]] && [[ ! -L "$dst" ]]; then
    local backup_dst="$BACKUP_DIR/$dst_short"
    mkdir -p "$(dirname "$backup_dst")"
    cp "$dst" "$backup_dst"
    log "backed up $dst_short → $backup_dst"
    ((BACKED_UP++)) || true
  elif [[ -L "$dst" ]]; then
    # Remove stale symlink
    rm "$dst"
  fi

  # Render: substitute placeholders, write to destination
  sed -e "s|{{ANTHROPIC_AUTH_TOKEN}}|$token|g" \
      -e "s|{{NEXTCLOUD_PASSWORD}}|$nextcloud_pw|g" \
      "$src" > "$dst"

  chmod 600 "$dst"

  # Validate: warn if any placeholders remain unfilled
  if grep -q '{{' "$dst" 2>/dev/null; then
    warn "WARNING: $dst_short still contains unfilled {{PLACEHOLDERS}}!"
  else
    log "rendered $dst_short (mode 600)"
    ((INSTALLED++)) || true
  fi
}

# ==============================================================================
# Install system dependencies for a config
# $1 = config name
# ==============================================================================
install_deps() {
  local filter="$1"
  local installed_any=0

  needs_sudo() {
    if [[ $EUID -eq 0 ]]; then
      return 1
    fi
    return 0
  }

  _apt_install() {
    local pkg="$1"
    if dpkg -s "$pkg" &>/dev/null; then
      log "already installed: $pkg"
      return 0
    fi
    info "installing $pkg..."
    if needs_sudo; then
      warn "sudo required for: apt install $pkg"
    fi
    sudo apt install -y "$pkg" && log "installed $pkg" || warn "failed to install $pkg"
    installed_any=1
  }

  case "$filter" in
    bashrc|bash_aliases)
      _apt_install gawk
      if [[ ! -f /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
        _apt_install fzf
      else
        log "already installed: fzf"
      fi
      # starship (shared with starship config)
      if ! command -v starship &>/dev/null; then
        info "installing starship to ~/.local/bin..."
        mkdir -p "$HOME/.local/bin"
        curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin" -y && \
          log "installed starship" || warn "failed to install starship"
        installed_any=1
      else
        log "already installed: starship ($(starship --version 2>/dev/null || true))"
      fi
      # ble.sh
      if [[ -f "$HOME/.local/share/ble.sh/out/ble.sh" ]]; then
        log "already installed: ble.sh"
      elif [[ -d "$HOME/.local/share/ble.sh" ]]; then
        warn "ble.sh directory exists but not built — building..."
        make -C "$HOME/.local/share/ble.sh" && log "built ble.sh" || warn "failed to build ble.sh"
        installed_any=1
      else
        info "cloning and building ble.sh..."
        git clone --recursive --depth 1 https://github.com/akinomyoga/ble.sh \
          "$HOME/.local/share/ble.sh" && \
          make -C "$HOME/.local/share/ble.sh" && \
          log "installed ble.sh" || warn "failed to install ble.sh"
        installed_any=1
      fi
      ;;
    starship)
      if ! command -v starship &>/dev/null; then
        info "installing starship to ~/.local/bin..."
        mkdir -p "$HOME/.local/bin"
        curl -sS https://starship.rs/install.sh | sh -s -- -b "$HOME/.local/bin" -y && \
          log "installed starship" || warn "failed to install starship"
        installed_any=1
      else
        log "already installed: starship ($(starship --version 2>/dev/null || true))"
      fi
      ;;
    gpaste)
      if ! command -v gpaste-client &>/dev/null; then
        _apt_install gpaste
        _apt_install gpaste-applet
        _apt_install gir1.2-gpaste-4.0
      else
        log "already installed: gpaste"
      fi
      ;;
    headset-battery)
      if [[ -f /usr/local/bin/headsetcontrol ]]; then
        log "already installed: headsetcontrol"
      else
        warn "headsetcontrol not found at /usr/local/bin/headsetcontrol"
        info "Build from: https://github.com/Sapd/HeadsetControl"
      fi
      ;;
    fan-control)
      if lsmod | grep -q nct6687; then
        log "nct6687 module loaded"
      else
        warn "nct6687 module not loaded — fan control won't work"
        info "DKMS driver: https://github.com/Fred78290/nct6687d"
      fi
      ;;
    tailscale-tray)
      if command -v wl-copy &>/dev/null; then
        log "already installed: wl-clipboard"
      elif command -v xclip &>/dev/null; then
        log "already installed: xclip"
      else
        info "installing wl-clipboard (for clipboard support)..."
        _apt_install wl-clipboard || _apt_install xclip
      fi
      info "checking tailscale operator status..."
      if tailscale status &>/dev/null; then
        if needs_sudo; then
          warn "sudo required to set tailscale operator: sudo tailscale set --operator $(whoami)"
        fi
        sudo tailscale set --operator "$(whoami)" 2>/dev/null && \
          log "tailscale operator set to $(whoami)" || \
          warn "tailscale operator not set — tray may not work without it"
      else
        warn "tailscale not running — operator check skipped"
      fi
      ;;
  esac

  if [[ $installed_any -eq 0 ]]; then
    log "all dependencies already satisfied"
  fi
}

# ==============================================================================
# Clone a git repo into $HOME (with optional subpath symlink)
# $1 = git URL, $2 = absolute path in $HOME (destination)
# $3 = optional subpath within repo to symlink to $2
# ==============================================================================
clone_repo() {
  local url="$1"
  local dst="$2"
  local sub="$3"
  local dst_short="${dst#$HOME/}"
  local clone_dir="$dst"

  # If a subpath is specified, clone to a persistent source dir and symlink
  if [[ -n "$sub" ]]; then
    local repo_name
    repo_name="$(basename "${url%.git}")"
    clone_dir="$HOME/src/$repo_name"

    # Ensure the source repo exists
    if [[ ! -d "$clone_dir/.git" ]]; then
      if [[ -d "$clone_dir" ]]; then
        warn "$clone_dir exists but is not a git repo — cannot clone"
        return 1
      fi
      mkdir -p "$(dirname "$clone_dir")"
      git clone "$url" "$clone_dir" || { error "clone failed for $url"; return 1; }
    else
      log "pulling $repo_name..."
      git -C "$clone_dir" pull --ff-only 2>/dev/null || true
    fi

    # Now symlink the subpath to the target
    local src_dir="$clone_dir/$sub"
    if [[ ! -d "$src_dir" ]]; then
      error "subpath '$sub' not found in cloned repo ($clone_dir)"
      return 1
    fi
    copy_file "$src_dir" "$dst"
    return $?
  fi

  # No subpath — clone directly into destination
  if [[ -d "$dst/.git" ]]; then
    log "already cloned: $dst_short (pulling...)"
    git -C "$dst" pull --ff-only 2>/dev/null || warn "pull failed for $dst_short — manual check needed"
    ((INSTALLED++)) || true
    return 0
  elif [[ -d "$dst" ]]; then
    warn "$dst_short exists but is not a git repo — skipping"
    printf "       To replace: rm -rf ~/%s && ./install.sh\n" "$dst_short"
    ((SKIPPED++)) || true
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  git clone "$url" "$dst" && log "cloned $dst_short" && ((INSTALLED++)) || true
}

# ==============================================================================
# Build binary from local source and install to ~/.local/bin + autostart
# $1 = source directory (local fork path)
# $2 = absolute path in $HOME for binary target
# ==============================================================================
install_binary_build() {
  local src_dir="$1"
  local dst="$2"
  local dst_short="${dst#$HOME/}"
  local binary_name
  binary_name="$(basename "$dst")"
  local desktop_file="$HOME/.config/autostart/${binary_name}.desktop"

  # Expand ~ in source path if present
  src_dir="${src_dir/#\$HOME/$HOME}"
  src_dir="${src_dir/#\~/$HOME}"

  if [[ ! -d "$src_dir" ]]; then
    # Auto-clone from GitHub if the local directory doesn't exist
    local clone_url="https://github.com/spa1teN/tailscale-systray.git"
    local clone_dir="$HOME/src/tailscale-systray"
    if [[ ! -d "$clone_dir" ]]; then
      info "cloning tailscale-systray fork..."
      mkdir -p "$(dirname "$clone_dir")"
      git clone "$clone_url" "$clone_dir" || {
        error "Clone failed — clone manually:"
        printf "       git clone %s %s\n" "$clone_url" "$src_dir"
        return 1
      }
      log "cloned tailscale-systray → ~/src/tailscale-systray"
    fi
    src_dir="$clone_dir"
  fi

  local built_binary="$src_dir/$binary_name"

  # Build if the binary doesn't exist in the source dir
  if [[ ! -f "$built_binary" ]]; then
    info "building $binary_name from source..."
    if command -v go &>/dev/null; then
      (cd "$src_dir" && go build -mod=vendor -o "$binary_name" .) && \
        log "built $binary_name (local Go)" || {
          error "local Go build failed"
          return 1
        }
    elif command -v docker &>/dev/null; then
      docker run --rm -v "$src_dir":/app -w /app golang:1.20 \
        go build -buildvcs=false -mod=vendor -o "$binary_name" . && \
        log "built $binary_name (docker)" || {
          error "Docker build failed"
          return 1
        }
    else
      error "Neither Go nor Docker found — cannot build $binary_name"
      printf "       Install Go or Docker and try again.\n"
      return 1
    fi
  else
    log "binary already built: $src_dir/$binary_name"
  fi

  # Install binary
  mkdir -p "$(dirname "$dst")"
  cp "$built_binary" "$dst"
  chmod +x "$dst"
  log "installed $dst_short"
  ((INSTALLED++)) || true

  # Create/update autostart .desktop file
  if [[ "$binary_name" == "tailscale-systray" ]]; then
    # Disable conflicting official systemd service
    if systemctl --user is-enabled tailscale-systray.service &>/dev/null 2>&1; then
      info "disabling conflicting tailscale-systray.service..."
      systemctl --user disable --now tailscale-systray.service 2>/dev/null && \
        log "disabled tailscale-systray.service" || \
        warn "could not disable tailscale-systray.service"
    fi

    mkdir -p "$(dirname "$desktop_file")"
    if [[ ! -f "$desktop_file" ]]; then
      cat > "$desktop_file" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Tailscale Systray
Comment=Tailscale system tray icon
Exec=$dst
StartupNotify=false
Terminal=false
X-GNOME-Autostart-Delay=5
DESKTOP_EOF
      log "created autostart: ~/.config/autostart/${binary_name}.desktop"
    else
      log "autostart entry already exists: ~/.config/autostart/${binary_name}.desktop"
    fi
  fi
}

# ==============================================================================
# Clone repo from URL and copy subdirectory to target
# $1 = git URL, $2 = absolute path in $HOME (destination), $3 = subpath within repo
# ==============================================================================
install_clone_copy() {
  local url="$1"
  local dst="$2"
  local sub="$3"
  local dst_short="${dst#$HOME/}"
  local repo_name
  repo_name="$(basename "${url%.git}")"
  local clone_dir="$HOME/src/$repo_name"

  # Clone/pull the repo
  if [[ -d "$clone_dir/.git" ]]; then
    log "pulling $repo_name..."
    git -C "$clone_dir" pull --ff-only 2>/dev/null || true
  else
    if [[ -d "$clone_dir" ]]; then
      warn "$clone_dir exists but is not a git repo — cannot clone"
      return 1
    fi
    mkdir -p "$(dirname "$clone_dir")"
    git clone "$url" "$clone_dir" || { error "clone failed for $url"; return 1; }
    log "cloned $repo_name → ~/src/$repo_name"
  fi

  local src_dir="$clone_dir/$sub"
  if [[ ! -d "$src_dir" ]]; then
    error "subpath '$sub' not found in cloned repo ($clone_dir)"
    return 1
  fi

  # Skip pull messages from counting
  local before_installed=$INSTALLED
  copy_file "$src_dir" "$dst"
  # copy_file incremented INSTALLED or SKIPPED — leave it
}

# ==============================================================================
# Install headset battery tray (Cinnamon applet + GNOME extension)
# $1 = source dir in repo (dotfiles/headset-battery)
# ==============================================================================
install_headset_battery() {
  local src="$REPO_DIR/$1"
  local cinnamon_dst="$HOME/.local/share/cinnamon/applets/headset-battery@caspar"
  local gnome_dst="$HOME/.local/share/gnome-shell/extensions/headset-battery@caspar"

  if [[ ! -d "$src" ]]; then
    error "Source not found: $src"
    return 1
  fi

  local installed=0

  # Cinnamon applet
  if [[ -d "$cinnamon_dst" ]]; then
    if diff -rq "$src/cinnamon" "$cinnamon_dst" >/dev/null 2>&1 && \
       cmp -s "$src/with-mic.png" "$cinnamon_dst/with-mic.png" 2>/dev/null && \
       cmp -s "$src/without-mic.png" "$cinnamon_dst/without-mic.png" 2>/dev/null; then
      log "already up to date: cinnamon applet"
    else
      local backup_dst="$BACKUP_DIR/.local/share/cinnamon/applets/headset-battery@caspar"
      mkdir -p "$(dirname "$backup_dst")"
      cp -r "$cinnamon_dst" "$backup_dst" 2>/dev/null || true
      rm -rf "$cinnamon_dst"
      mkdir -p "$cinnamon_dst"
      cp "$src/cinnamon/applet.js" "$src/cinnamon/metadata.json" "$cinnamon_dst/"
      cp "$src/with-mic.png" "$src/without-mic.png" "$cinnamon_dst/"
      log "copied cinnamon applet: headset-battery@caspar"
      installed=1
    fi
  else
    mkdir -p "$cinnamon_dst"
    cp "$src/cinnamon/applet.js" "$src/cinnamon/metadata.json" "$cinnamon_dst/"
    cp "$src/with-mic.png" "$src/without-mic.png" "$cinnamon_dst/"
    log "copied cinnamon applet: headset-battery@caspar"
    installed=1
  fi

  # GNOME extension
  if [[ -d "$gnome_dst" ]]; then
    if diff -rq "$src/gnome" "$gnome_dst" >/dev/null 2>&1 && \
       cmp -s "$src/with-mic.png" "$gnome_dst/with-mic.png" 2>/dev/null && \
       cmp -s "$src/without-mic.png" "$gnome_dst/without-mic.png" 2>/dev/null; then
      log "already up to date: gnome extension"
    else
      local backup_dst="$BACKUP_DIR/.local/share/gnome-shell/extensions/headset-battery@caspar"
      mkdir -p "$(dirname "$backup_dst")"
      cp -r "$gnome_dst" "$backup_dst" 2>/dev/null || true
      rm -rf "$gnome_dst"
      mkdir -p "$gnome_dst"
      cp "$src/gnome/extension.js" "$src/gnome/metadata.json" "$gnome_dst/"
      cp "$src/with-mic.png" "$src/without-mic.png" "$gnome_dst/"
      log "copied gnome extension: headset-battery@caspar"
      installed=1
    fi
  else
    mkdir -p "$gnome_dst"
    cp "$src/gnome/extension.js" "$src/gnome/metadata.json" "$gnome_dst/"
    cp "$src/with-mic.png" "$src/without-mic.png" "$gnome_dst/"
    log "copied gnome extension: headset-battery@caspar"
    installed=1
  fi

  if [[ $installed -gt 0 ]]; then
    ((INSTALLED++)) || true
  else
    ((SKIPPED++)) || true
  fi
}

# ==============================================================================
# Install fan control scripts and systemd units (requires sudo)
# $1 = source dir in repo (dotfiles/fan-control)
# ==============================================================================
install_fan_control() {
  local src="$REPO_DIR/$1"

  if [[ ! -d "$src" ]]; then
    error "Source not found: $src"
    return 1
  fi

  if [[ $EUID -ne 0 ]]; then
    warn "fan-control needs sudo to install system files"
  fi

  local installed=0

  # Scripts to /usr/local/bin/
  for script in fan-quiet.sh fan-mirror.sh; do
    if cmp -s "$src/$script" "/usr/local/bin/$script" 2>/dev/null; then
      log "already up to date: /usr/local/bin/$script"
    else
      sudo cp "$src/$script" "/usr/local/bin/$script"
      sudo chmod 755 "/usr/local/bin/$script"
      log "installed /usr/local/bin/$script"
      installed=1
    fi
  done

  # Systemd units
  for unit in fan-quiet.service fan-mirror.service fan-mirror.timer; do
    if cmp -s "$src/$unit" "/etc/systemd/system/$unit" 2>/dev/null; then
      log "already up to date: /etc/systemd/system/$unit"
    else
      sudo cp "$src/$unit" "/etc/systemd/system/$unit"
      log "installed /etc/systemd/system/$unit"
      installed=1
    fi
  done

  # Enable and start the timer
  if ! systemctl is-enabled fan-mirror.timer &>/dev/null; then
    sudo systemctl enable --now fan-mirror.timer 2>/dev/null && \
      log "enabled fan-mirror.timer" || warn "failed to enable fan-mirror.timer"
    installed=1
  else
    log "fan-mirror.timer already enabled"
  fi

  if ! systemctl is-enabled fan-quiet.service &>/dev/null; then
    sudo systemctl enable fan-quiet.service 2>/dev/null && \
      log "enabled fan-quiet.service" || warn "failed to enable fan-quiet.service"
  else
    log "fan-quiet.service already enabled"
  fi

  if [[ $installed -gt 0 ]]; then
    ((INSTALLED++)) || true
  else
    ((SKIPPED++)) || true
  fi
}

# ==============================================================================
# Parse one ITEMS entry and return fields
# $1 = item string, outputs globals: _name, _src, _target, _kind, _clone_sub
# ==============================================================================
parse_item() {
  local item="$1"
  _name="${item%%|*}"
  local rest="${item#$_name|}"
  _src="${rest%%|*}"
  rest="${rest#$_src|}"
  _target="${rest%%|*}"
  local kind_rest="${rest#$_target|}"
  _kind="${kind_rest%%|*}"
  _clone_sub=""
  if [[ "$kind_rest" == *"|"* ]]; then
    _clone_sub="${kind_rest#$_kind|}"
  fi
}

# ==============================================================================
# Install one item by name (deps always installed first)
# ==============================================================================
install_item() {
  local name="$1"

  # Always install dependencies first
  install_deps "$name"

  for item in "${ITEMS[@]}"; do
    parse_item "$item"
    if [[ "$_name" != "$name" ]]; then
      continue
    fi

    local abs_src="$_src"
    local abs_dst="$HOME/$_target"

    # Resolve $HOME in source paths
    abs_src="${abs_src//\$HOME/$HOME}"

    case "$_kind" in
      copy)
        # Absolute source path (e.g. $HOME/Projects/...) bypasses repo prefix
        if [[ "$abs_src" == /* ]]; then
          copy_file "$abs_src" "$abs_dst"
        else
          copy_file "$REPO_DIR/$abs_src" "$abs_dst"
        fi
        ;;
      render)
        render_aliases
        ;;
      multi)
        IFS=';' read -ra srcs <<< "${_src//::/;}"
        IFS=';' read -ra dsts <<< "${_target//::/;}"
        for i in "${!srcs[@]}"; do
          copy_file "$REPO_DIR/${srcs[$i]}" "$HOME/${dsts[$i]}"
        done
        ;;
      clone)
        clone_repo "$_src" "$abs_dst" "$_clone_sub"
        ;;
      clone_copy)
        install_clone_copy "$_src" "$abs_dst" "$_clone_sub"
        ;;
      binary_build)
        install_binary_build "$_src" "$abs_dst"
        ;;
      headset_battery)
        install_headset_battery "$_src"
        ;;
      fan_control)
        install_fan_control "$_src"
        ;;
      *)
        error "Unknown kind '$_kind' for $name"
        ;;
    esac
    return
  done
  error "Unknown config: $name"
}

# ==============================================================================
# Uninstall one item by name
# ==============================================================================
uninstall_item() {
  local name="$1"
  for item in "${ITEMS[@]}"; do
    parse_item "$item"
    if [[ "$_name" != "$name" ]]; then
      continue
    fi

    local abs_dst="$HOME/$_target"
    local dst_short="${abs_dst#$HOME/}"

    case "$_kind" in
      copy)
        if [[ -e "$abs_dst" ]]; then
          rm -rf "$abs_dst"
          log "removed: $dst_short"
          ((UNINSTALLED++)) || true
        else
          info "not installed: $dst_short"
        fi
        ;;
      render)
        if [[ -f "$abs_dst" ]]; then
          rm "$abs_dst"
          log "removed: $dst_short"
          ((UNINSTALLED++)) || true
        else
          info "not installed: $dst_short"
        fi
        ;;
      multi)
        IFS=';' read -ra dsts <<< "${_target//::/;}"
        for d in "${dsts[@]}"; do
          local sd="$HOME/$d"
          if [[ -e "$sd" ]]; then
            rm -rf "$sd"
            log "removed: ${sd#$HOME/}"
            ((UNINSTALLED++)) || true
          else
            info "not installed: ${sd#$HOME/}"
          fi
        done
        ;;
      clone)
        if [[ -d "$abs_dst/.git" ]]; then
          rm -rf "$abs_dst"
          log "removed: $dst_short"
          ((UNINSTALLED++)) || true
        elif [[ -d "$abs_dst" ]]; then
          warn "$dst_short exists but is not a git repo — not removing"
        else
          info "not installed: $dst_short"
        fi
        ;;
      clone_copy)
        if [[ -e "$abs_dst" ]]; then
          rm -rf "$abs_dst"
          log "removed: $dst_short"
          ((UNINSTALLED++)) || true
        else
          info "not installed: $dst_short"
        fi
        ;;
      binary_build)
        if [[ -f "$abs_dst" ]]; then
          rm "$abs_dst"
          log "removed binary: $dst_short"
          ((UNINSTALLED++)) || true
        else
          info "not installed: $dst_short"
        fi
        local binary_name
        binary_name="$(basename "$abs_dst")"
        local desktop_file="$HOME/.config/autostart/${binary_name}.desktop"
        if [[ -f "$desktop_file" ]]; then
          rm "$desktop_file"
          log "removed autostart: ~/.config/autostart/${binary_name}.desktop"
        fi
        ;;
      headset_battery)
        local cinnamon_dst="$HOME/.local/share/cinnamon/applets/headset-battery@caspar"
        local gnome_dst="$HOME/.local/share/gnome-shell/extensions/headset-battery@caspar"
        local removed=0
        if [[ -d "$cinnamon_dst" ]]; then
          rm -rf "$cinnamon_dst"
          log "removed cinnamon applet: headset-battery@caspar"
          removed=1
        fi
        if [[ -d "$gnome_dst" ]]; then
          rm -rf "$gnome_dst"
          log "removed gnome extension: headset-battery@caspar"
          removed=1
        fi
        if [[ $removed -gt 0 ]]; then
          ((UNINSTALLED++)) || true
        else
          info "not installed"
        fi
        ;;
      fan_control)
        warn "fan-control uses system files — uninstall stops timer but keeps files"
        warn "Use './install.sh --store fan-control' first if you want to save changes"
        if systemctl is-enabled fan-mirror.timer &>/dev/null; then
          sudo systemctl disable --now fan-mirror.timer 2>/dev/null && \
            log "disabled fan-mirror.timer" || warn "failed to disable fan-mirror.timer"
        fi
        if systemctl is-enabled fan-quiet.service &>/dev/null; then
          sudo systemctl disable fan-quiet.service 2>/dev/null && \
            log "disabled fan-quiet.service" || warn "failed to disable fan-quiet.service"
        fi
        # Remove system files
        for f in /usr/local/bin/fan-quiet.sh /usr/local/bin/fan-mirror.sh \
                 /etc/systemd/system/fan-quiet.service /etc/systemd/system/fan-mirror.service \
                 /etc/systemd/system/fan-mirror.timer; do
          if [[ -f "$f" ]]; then
            sudo rm "$f"
            log "removed $f"
          fi
        done
        sudo systemctl daemon-reload 2>/dev/null || true
        ((UNINSTALLED++)) || true
        ;;
      *)
        error "Unknown kind '$_kind' for $name"
        return 1
        ;;
    esac

    # Try to restore from most recent backup
    _restore_from_backup "$dst_short" "$abs_dst"
    return
  done
  error "Unknown config: $name"
}

# ==============================================================================
# Try to restore a file from the most recent backup
# ==============================================================================
_restore_from_backup() {
  local dst_short="$1"
  local abs_dst="$2"
  local latest_backup
  latest_backup=$(ls -dt "$HOME/.dotfiles-backup/"*/ 2>/dev/null | head -1 || true)

  if [[ -z "$latest_backup" ]]; then
    return 0
  fi

  local backup_path="$latest_backup/$dst_short"
  if [[ -f "$backup_path" ]] && [[ ! -e "$abs_dst" ]]; then
    mkdir -p "$(dirname "$abs_dst")"
    cp "$backup_path" "$abs_dst"
    log "restored from backup: $dst_short"
  elif [[ -d "$backup_path" ]] && [[ ! -e "$abs_dst" ]]; then
    mkdir -p "$(dirname "$abs_dst")"
    cp -r "$backup_path" "$abs_dst"
    log "restored from backup: $dst_short"
  fi
}

# ==============================================================================
# List all configs and their install status
# ==============================================================================
list_items() {
  printf "\n  %-25s %-10s %s\n" "CONFIG" "KIND" "STATUS / TARGET"
  printf "  %-25s %-10s %s\n" "──────" "────" "──────────────"
  for item in "${ITEMS[@]}"; do
    parse_item "$item"
    local status=""
    local dst="$HOME/$_target"

    case "$_kind" in
      copy)
        local src_full="$REPO_DIR/$_src"
        if [[ "$_src" == /* ]] || [[ "$_src" == \$HOME* ]]; then
          src_full="${_src//\$HOME/$HOME}"
        fi
        if [[ -f "$dst" ]] && cmp -s "$src_full" "$dst" 2>/dev/null; then
          status="installed"
        elif [[ -d "$dst" ]] && diff -rq "$src_full" "$dst" >/dev/null 2>&1; then
          status="installed"
        elif [[ -e "$dst" ]]; then
          status="modified"
        else
          status="not installed"
        fi
        ;;
      render)
        if [[ -f "$dst" ]] && [[ ! -L "$dst" ]]; then
          if grep -q '{{' "$dst" 2>/dev/null; then
            status="rendered (has placeholders!)"
          else
            status="rendered"
          fi
        elif [[ -e "$dst" ]]; then
          status="exists (unexpected)"
        else
          status="not installed"
        fi
        ;;
      multi)
        local count_ok=0 count_total=0
        IFS=';' read -ra dsts <<< "${_target//::/;}"
        IFS=';' read -ra srcs <<< "${_src//::/;}"
        count_total=${#dsts[@]}
        for i in "${!dsts[@]}"; do
          local sd="$HOME/${dsts[$i]}"
          if cmp -s "$REPO_DIR/${srcs[$i]}" "$sd" 2>/dev/null; then
            ((count_ok++)) || true
          fi
        done
        status="$count_ok/$count_total installed"
        ;;
      clone)
        if [[ -d "$dst/.git" ]]; then
          status="cloned"
        elif [[ -d "$dst" ]]; then
          status="exists (not git)"
        else
          status="not installed"
        fi
        ;;
      clone_copy)
        if [[ -d "$dst" ]] && [[ ! -L "$dst" ]]; then
          status="installed"
        elif [[ -e "$dst" ]]; then
          status="exists (unexpected)"
        else
          status="not installed"
        fi
        ;;
      binary_build)
        if [[ -f "$dst" ]]; then
          status="installed"
        else
          status="not installed"
        fi
        ;;
      headset_battery)
        local c_dst="$HOME/.local/share/cinnamon/applets/headset-battery@caspar"
        local g_dst="$HOME/.local/share/gnome-shell/extensions/headset-battery@caspar"
        local has_c=0 has_g=0
        [[ -d "$c_dst" ]] && has_c=1
        [[ -d "$g_dst" ]] && has_g=1
        if [[ $has_c -eq 1 ]] && [[ $has_g -eq 1 ]]; then
          status="installed (cinnamon + gnome)"
        elif [[ $has_c -eq 1 ]]; then
          status="installed (cinnamon only)"
        elif [[ $has_g -eq 1 ]]; then
          status="installed (gnome only)"
        else
          status="not installed"
        fi
        ;;
      fan_control)
        if [[ -f /usr/local/bin/fan-quiet.sh ]] && systemctl is-enabled fan-mirror.timer &>/dev/null; then
          status="installed"
        elif [[ -f /usr/local/bin/fan-quiet.sh ]]; then
          status="scripts present (timer not enabled)"
        else
          status="not installed"
        fi
        ;;
      *)
        status="unknown kind"
        ;;
    esac
    printf "  %-25s %-10s %s → ~/%s\n" "$_name" "$_kind" "$status" "$_target"
  done
  echo
}

# ==============================================================================
# Store — copy local version back into the repo
# Only works for copy/multi kinds with repo-relative sources.
# ==============================================================================
store_item() {
  local name="$1"
  for item in "${ITEMS[@]}"; do
    parse_item "$item"
    if [[ "$_name" != "$name" ]]; then
      continue
    fi

    case "$_kind" in
      copy)
        # Only repo-relative sources can be stored back
        if [[ "$_src" == /* ]] || [[ "$_src" == \$HOME* ]]; then
          error "Cannot store '$name' — source is outside the repo"
          return 1
        fi
        local repo_dst="$REPO_DIR/$_src"
        local home_src="$HOME/$_target"
        if [[ ! -f "$home_src" ]] && [[ ! -d "$home_src" ]]; then
          error "Nothing to store: $home_src does not exist"
          return 1
        fi
        mkdir -p "$(dirname "$repo_dst")"
        if [[ -d "$home_src" ]]; then
          cp -r "$home_src" "$repo_dst"
        else
          cp "$home_src" "$repo_dst"
        fi
        log "stored $HOME/$_target → dotfiles/$_src"
        ;;
      multi)
        IFS=';' read -ra srcs <<< "${_src//::/;}"
        IFS=';' read -ra dsts <<< "${_target//::/;}"
        for i in "${!srcs[@]}"; do
          local repo_dst="$REPO_DIR/${srcs[$i]}"
          local home_src="$HOME/${dsts[$i]}"
          if [[ ! -f "$home_src" ]]; then
            error "Nothing to store: $home_src does not exist"
            return 1
          fi
          mkdir -p "$(dirname "$repo_dst")"
          cp "$home_src" "$repo_dst"
          log "stored ${dsts[$i]} → dotfiles/${srcs[$i]}"
        done
        ;;
      headset_battery)
        local src="$REPO_DIR/$_src"
        local c_dst="$HOME/.local/share/cinnamon/applets/headset-battery@caspar"
        local g_dst="$HOME/.local/share/gnome-shell/extensions/headset-battery@caspar"
        if [[ -d "$c_dst" ]]; then
          mkdir -p "$src/cinnamon"
          cp "$c_dst/applet.js" "$c_dst/metadata.json" "$src/cinnamon/"
          cp "$c_dst/with-mic.png" "$c_dst/without-mic.png" "$src/"
          log "stored cinnamon applet → dotfiles/headset-battery/"
        fi
        if [[ -d "$g_dst" ]]; then
          mkdir -p "$src/gnome"
          cp "$g_dst/extension.js" "$g_dst/metadata.json" "$src/gnome/"
          cp "$g_dst/with-mic.png" "$g_dst/without-mic.png" "$src/"
          log "stored gnome extension → dotfiles/headset-battery/"
        fi
        if [[ ! -d "$c_dst" ]] && [[ ! -d "$g_dst" ]]; then
          error "Nothing to store — headset-battery not installed"
          return 1
        fi
        ;;
      fan_control)
        local src="$REPO_DIR/$_src"
        if [[ ! -f /usr/local/bin/fan-quiet.sh ]]; then
          error "Nothing to store — fan-control not installed"
          return 1
        fi
        mkdir -p "$src"
        for f in fan-quiet.sh fan-mirror.sh; do
          sudo cp "/usr/local/bin/$f" "$src/$f"
          log "stored /usr/local/bin/$f → dotfiles/fan-control/"
        done
        for f in fan-quiet.service fan-mirror.service fan-mirror.timer; do
          sudo cp "/etc/systemd/system/$f" "$src/$f"
          log "stored /etc/systemd/system/$f → dotfiles/fan-control/"
        done
        ;;
      clone_copy)
        error "Cannot store '$name' — config is cloned from git, not stored in repo"
        return 1
        ;;
      *)
        error "Cannot store '$name' — only copy/multi configs support --store"
        return 1
        ;;
    esac
    return
  done
  error "Unknown config: $name"
}

# ==============================================================================
# Enable/disable tailscale-tray autostart and running process
# ==============================================================================
_tailscale_tray_enable() {
  local binary="$HOME/.local/bin/tailscale-systray"
  local desktop="$HOME/.config/autostart/tailscale-systray.desktop"
  local disabled="$HOME/.config/autostart/tailscale-systray.desktop.disabled"

  if [[ ! -f "$binary" ]]; then
    error "tailscale-systray binary not found at $binary"
    info "Run './install.sh tailscale-tray' first to install it."
    return 1
  fi

  # Restore autostart from disabled state
  if [[ -f "$disabled" ]] && [[ ! -f "$desktop" ]]; then
    mv "$disabled" "$desktop"
    log "autostart re-enabled: ~/.config/autostart/tailscale-systray.desktop"
  elif [[ -f "$desktop" ]]; then
    log "autostart already enabled"
  else
    # Desktop file missing entirely — recreate it
    mkdir -p "$(dirname "$desktop")"
    cat > "$desktop" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Name=Tailscale Systray
Comment=Tailscale system tray icon
Exec=$binary
StartupNotify=false
Terminal=false
X-GNOME-Autostart-Delay=5
DESKTOP_EOF
    log "autostart created: ~/.config/autostart/tailscale-systray.desktop"
  fi

  # Start the process if not already running
  if ! pgrep -x tailscale-systray >/dev/null 2>&1; then
    nohup "$binary" >/dev/null 2>&1 &
    log "started tailscale-systray"
  else
    log "tailscale-systray already running"
  fi
}

_tailscale_tray_disable() {
  local desktop="$HOME/.config/autostart/tailscale-systray.desktop"
  local disabled="$HOME/.config/autostart/tailscale-systray.desktop.disabled"

  # Kill running process
  if pgrep -x tailscale-systray >/dev/null 2>&1; then
    killall tailscale-systray 2>/dev/null && log "stopped tailscale-systray" || true
  else
    info "tailscale-systray not running"
  fi

  # Disable autostart
  if [[ -f "$desktop" ]]; then
    mv "$desktop" "$disabled"
    log "autostart disabled (renamed to .desktop.disabled)"
  elif [[ -f "$disabled" ]]; then
    log "autostart already disabled"
  else
    info "no autostart file found"
  fi
}

# ==============================================================================
# Enable/disable dispatcher
# ==============================================================================
enable_item() {
  case "$1" in
    tailscale-tray) _tailscale_tray_enable ;;
    *)
      error "Cannot enable '$1' — only tailscale-tray supports --enable/--disable"
      return 1
      ;;
  esac
}

disable_item() {
  case "$1" in
    tailscale-tray) _tailscale_tray_disable ;;
    *)
      error "Cannot disable '$1' — only tailscale-tray supports --enable/--disable"
      return 1
      ;;
  esac
}

# ==============================================================================
# Main
# ==============================================================================
main() {
  local ACTION=""
  local -a CONFIGS=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --list|-l)
        ACTION="list"
        shift
        ;;
      --uninstall|-u)
        ACTION="uninstall"
        shift
        while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
          CONFIGS+=("$1")
          shift
        done
        ;;
      --store|-s)
        ACTION="store"
        shift
        while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
          CONFIGS+=("$1")
          shift
        done
        ;;
      --enable)
        ACTION="enable"
        shift
        while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
          CONFIGS+=("$1")
          shift
        done
        ;;
      --disable)
        ACTION="disable"
        shift
        while [[ $# -gt 0 ]] && [[ "$1" != --* ]]; do
          CONFIGS+=("$1")
          shift
        done
        ;;
      --token)
        CLI_TOKEN="$2"
        shift 2
        ;;
      --nextcloud-pw)
        CLI_NEXTCLOUD_PW="$2"
        shift 2
        ;;
      --*)
        error "Unknown option: $1"
        echo "Run './install.sh --help' for usage."
        exit 1
        ;;
      *)
        # Positional arg = config name to install
        if [[ -z "$ACTION" ]]; then
          ACTION="install"
        fi
        CONFIGS+=("$1")
        shift
        ;;
    esac
  done

  # Default action: if nothing specified, show help
  if [[ -z "$ACTION" ]]; then
    show_help
    exit 0
  fi

  # Validate config names
  local -a valid_names=()
  for item in "${ITEMS[@]}"; do
    valid_names+=("${item%%|*}")
  done

  for cfg in "${CONFIGS[@]}"; do
    local found=0
    for vn in "${valid_names[@]}"; do
      if [[ "$cfg" == "$vn" ]]; then
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      error "Unknown config: $cfg"
      echo "Run './install.sh --list' to see available configs."
      exit 1
    fi
  done

  # Run security check (unless just listing)
  if [[ "$ACTION" != "list" ]]; then
    check_repo_secrets || true
  fi

  # Dispatch
  case "$ACTION" in
    list)
      list_items
      ;;

    install)
      for cfg in "${CONFIGS[@]}"; do
        install_item "$cfg"
      done
      _print_summary
      ;;

    uninstall)
      for cfg in "${CONFIGS[@]}"; do
        uninstall_item "$cfg"
      done
      if (( UNINSTALLED > 0 )); then
        echo
        echo "  Uninstalled: $UNINSTALLED"
      fi
      if (( UNINSTALLED == 0 )); then
        echo "  Nothing to uninstall."
      fi
      echo
      ;;

    store)
      for cfg in "${CONFIGS[@]}"; do
        store_item "$cfg"
      done
      echo
      ;;

    enable)
      for cfg in "${CONFIGS[@]}"; do
        enable_item "$cfg"
      done
      echo
      ;;

    disable)
      for cfg in "${CONFIGS[@]}"; do
        disable_item "$cfg"
      done
      echo
      ;;
  esac
}

# ==============================================================================
# Print summary after install
# ==============================================================================
_print_summary() {
  echo
  echo "  ─────────────────────────────────────────────"
  if (( INSTALLED > 0 )); then
    echo "  Installed:  $INSTALLED"
  fi
  if (( SKIPPED > 0 )); then
    echo "  Skipped:    $SKIPPED (already installed)"
  fi
  if (( BACKED_UP > 0 )); then
    echo "  Backed up:  $BACKED_UP → $BACKUP_DIR"
  fi
  if (( INSTALLED == 0 && SKIPPED == 0 )); then
    echo "  No changes made."
  fi
  if (( INSTALLED > 0 )); then
    echo
    echo "  Tip: start a new shell or run 'source ~/.bashrc' to pick up changes."
  fi
  echo
}

main "$@"
