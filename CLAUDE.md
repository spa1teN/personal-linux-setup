# CLAUDE.md

This is a personal dotfiles repository. Claude works within this repo to
maintain configs and the installer script.

## Repo Layout

```
install.sh              # CLI-driven dotfiles installer (see --help)
.gitignore              # Prevents accidental secret commits
dotfiles/               # Mirrors $HOME — config sources copied into place
  .wezterm.lua          # WezTerm terminal config
  .tmux.conf            # tmux config
  .bashrc               # Bash config (Starship, NVM, fzf, ble.sh)
  .bash_aliases.template # Template with {{PLACEHOLDERS}} for secrets
  .config/              # Starship prompt configs
  .claude/              # Claude Code configs (settings, themes, plugins, scripts)
docs/                   # Markdown documentation
```

## Hard Rules

1. **NEVER** write real `sk-…` tokens or Nextcloud passwords into any file in
   this repo. The only authorized forms are `{{ANTHROPIC_AUTH_TOKEN}}` and
   `{{NEXTCLOUD_PASSWORD}}` inside `dotfiles/.bash_aliases.template`.

2. **install.sh** must stay idempotent — safe to run multiple times. Must back
   up existing files before replacing (backups go to `~/.dotfiles-backup/`,
   never into the repo). Must never modify the repo during install.

3. **settings.json** paths: `dotfiles/.claude/settings.json` has an absolute
   path in `statusLine.command` (`/home/caspar/.claude/scripts/ds-statusline.sh`).
   The same applies to `installLocation` fields in `known_marketplaces.json`.
   If this repo is cloned under a different username, these paths would need
   templating.

## File Handling

- **copy** — Most configs are copied from `dotfiles/` into `$HOME`.
  `dotfiles/` mirrors the home directory layout exactly:
  `dotfiles/<path>` → `$HOME/<path>`. Use `--store` to copy changes back.

- **rendered** — `dotfiles/.bash_aliases.template` is never symlinked. The
  installer renders it to `~/.bash_aliases` with real secrets filled in
  (mode 600). The template uses `{{ANTHROPIC_AUTH_TOKEN}}` and
  `{{NEXTCLOUD_PASSWORD}}` placeholders.

## Dependencies

- `ds-statusline.sh` reads `$ANTHROPIC_AUTH_TOKEN` from the environment at
  runtime — it depends on `bash_aliases` being installed.
- `.bashrc` sources `~/.bash_aliases` and references starship, NVM, fzf, ble.sh.

## Docs Language

The four docs in `docs/` are a mix of German (`bash_prompt.md`) and English
(the others). Preserve the existing language of each document — don't translate.
