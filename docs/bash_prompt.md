# Bash Prompt Setup

## Übersicht

Der Prompt besteht aus drei Komponenten:

| Komponente | Zweck |
|---|---|
| **Starship** | Prompt-Layout mit Powerline-Chevrons und dunklen Hintergründen |
| **ble.sh** | Inline-Autosuggestions aus der History + Syntax-Highlighting |
| **fzf** | Fuzzy History-Suche per `Ctrl+R` |

## 1. Starship (Prompt-Layout)

Installiert nach `~/.local/bin/starship`:

```bash
curl -sS https://starship.rs/install.sh | sh -s -- -b ~/.local/bin -y
```

In `~/.bashrc` geladen — mit SSH-/Lokal-Umschaltung:

```bash
# Starship prompt — Powerline: SSH-/Lokal-Config umschalten
if [[ -n "$SSH_CONNECTION" ]]; then
    export STARSHIP_CONFIG="$HOME/.config/starship.toml"
else
    export STARSHIP_CONFIG="$HOME/.config/starship-local.toml"
fi
eval "$(starship init bash)"
```

### Design: Pastel Powerline (dunkle Variante)

Zwei Configs für SSH- und Lokal-Modus, da die Format-Level-Chevrons nur bei durchgehend sichtbaren Modulen korrekt rendern.

Echte Powerline-Übergänge: `` hat `fg` = Hintergrundfarbe des vorherigen Segments, `bg` = Hintergrundfarbe des nächsten Segments.

Konnektor-Wörter (`@`, `in`, `on branch`) sind als separate Format-Level-Gruppen mit derselben BG wie das umgebende Modul gesetzt — Starship optimiert dann nur den fg-Wechsel, die BG bleibt durchgehend.

**Farbpalette:**

| Segment | Hintergrund | Inhalt | Textfarbe |
|---|---|---|---|
| User (SSH) | `#5C2D6B` (dunkel-lila) | `caspar` | Bold Yellow |
| `@` (SSH) | `#5C2D6B` | `@` | Bold White |
| Host (SSH) | `#5C2D6B` | `spa1lnx` | Bold Green |
| `in` (SSH) | `#6B4226` (dunkel-amber) | `in` | Bold White |
| Directory | `#6B4226` | `~/setup` | Bold Cyan |
| `on branch` | `#2D5F6B` (dunkel-slate) | `on branch` | Bold White |
| Branch Name | `#2D5F6B` | `main` | Gold `#FFB347` |
| Git Status | `#1A4A4A` (dunkel-teal) | `❨2 staged…❩` | Soft Red `#FF6B6B` |
| Git State | `#2D5F6B` | `REBASE 3/5` | Bold Yellow |
| Right Cap | — | `` | Matcht letzte BG |

### Prompt-Ausgabe

**Lokal (ohne Git):**
```
 /tmp 
❯
```

**Lokal (mit Git-Änderungen):**
```
 ~/setup  on branch main  ❨2 staged, 1 modified❩ 
❯
```

**SSH (mit Git-Änderungen):**
```
 caspar @ spa1lnx  in ~/setup  on branch main  ❨2 staged, 1 modified❩ 
❯
```

**SSH (während Rebase):**
```
 caspar @ spa1lnx  in ~/setup  on branch main REBASE 3/5 
❯
```

### Konfiguration: `~/.config/starship.toml` (SSH-Modus)

```toml
format = "[](fg:#5C2D6B)$username[ @ ](bg:#5C2D6B bold white)$hostname[](bg:#6B4226 fg:#5C2D6B)[ in ](bg:#6B4226 bold white)$directory$custom$line_break$character"

[username]
format = "[$user]($style)"
style_user = "bg:#5C2D6B bold yellow"

[hostname]
format = "[$hostname ]($style)"
style = "bg:#5C2D6B bold green"

[directory]
truncation_length = 0
truncate_to_repo = false
format = "[ $path ]($style)"
style = "bg:#6B4226 bold cyan"

[custom.git_section]
command = '~/.local/bin/git-prompt-section'
when = 'true'
shell = 'bash'
format = '$output'

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
```

### Konfiguration: `~/.config/starship-local.toml` (Lokal-Modus)

```toml
format = "[](fg:#6B4226)$directory$custom$line_break$character"

[username]
disabled = true

[hostname]
disabled = true

[directory]
truncation_length = 0
truncate_to_repo = false
format = "[ $path ]($style)"
style = "bg:#6B4226 bold cyan"

[custom.git_section]
command = '~/.local/bin/git-prompt-section'
when = 'true'
shell = 'bash'
format = '$output'

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
```

### Git-Section Script: `~/.local/bin/git-prompt-section`

Das Script gibt Raw-ANSI aus (Format `'$output'` in Starship) und steuert den gesamten Git-Teil des Prompts:

1. **Dir→Branch Chevron** — `` (fg=amber, bg=slate)
2. **Branch-Text** — ` on branch main ` (weiß + gold)
3. **Git-State** (optional) — `REBASE 3/5` (gelb)
4. **Branch→Status Chevron** (wenn dirty) — `` (fg=slate, bg=teal)
5. **Status-Text** (wenn dirty) — ` ❨2 staged❩` (soft-rot)
6. **Rechter Cap** — `` (fg=letzte BG, kein bg)

### Git-Status-Script: `~/.local/bin/git-status-prompt`

Parst `git status --porcelain` und zählt:
- `staged` — Änderungen im Index (M, A, D, R, C)
- `modified` — Änderungen im Working Tree
- `untracked` — Neue, nicht versionierte Dateien
- `deleted` — Gelöschte Dateien
- `renamed` — Umbenannte Dateien
- `conflicts` — Merge-Konflikte
- `ahead` / `behind` — Commits vor/hinter dem Remote-Branch

Ausgabe: `❨2 staged, 1 modified, 3 ahead❩` (oder `exit 1` bei sauberem Repo)

## 2. ble.sh (Autosuggestions + Highlighting)

Installation:

```bash
# Abhängigkeit
sudo apt install gawk

# Clonen und bauen
git clone --recursive --depth 1 https://github.com/akinomyoga/ble.sh.git ~/.local/share/ble.sh
make -C ~/.local/share/ble.sh
```

In `~/.bashrc` geladen (nach Starship, als letztes):

```bash
source ~/.local/share/ble.sh/out/ble.sh
```

### Verhalten

- Beim Tippen erscheinen graue Vorschläge aus der Shell-History
- Mit `→` (Rechtspfeil) oder `End` übernehmen
- Syntax-Highlighting beim Tippen (Befehle, Strings, Variablen etc.)

## 3. fzf (Fuzzy History-Suche)

Als Systempaket installiert:

```bash
sudo apt install fzf
```

In `~/.bashrc` geladen:

```bash
source /usr/share/doc/fzf/examples/key-bindings.bash
```

### Verhalten

- `Ctrl+R` öffnet interaktive History-Suche
- Echtzeit-Filterung während des Tippens
- `Enter` übernimmt den ausgewählten Befehl

## Zusammenspiel

ble.sh und fzf koexistieren problemlos:
- ble.sh übernimmt den Bash Line Editor (ersetzt readline)
- fzf-Keybindings greifen bei `Ctrl+R`, bevor ble.sh die Taste verarbeitet
- Starship läuft unabhängig davon und steuert nur das Prompt-Rendering

Die drei Tools zusammen ergeben: einen informativen Git-bewussten Prompt mit Powerline-Style, fish-artigen Autosuggestions und durchsuchbarer History.
