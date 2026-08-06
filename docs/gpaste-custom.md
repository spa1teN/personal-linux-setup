# GPaste Reloaded — Custom Fork

Fork of [Feuerfuchs/GPaste-Reloaded-Cinnamon-Applet](https://github.com/Feuerfuchs/GPaste-Reloaded-Cinnamon-Applet)  
My fork: [spa1teN/GPaste-Reloaded-Cinnamon-Applet](https://github.com/spa1teN/GPaste-Reloaded-Cinnamon-Applet)

## Overview

Adds image preview support to the GPaste Cinnamon applet, plus UI improvements for menu scrolling and hover styling.

## Changes from upstream

### 1. Image previews in clipboard history

**Files:** `GPasteHistoryItem.js`, `6.4/GPasteHistoryItem.js`

- Added imports: `GdkPixbuf`, `Cogl`, `GPaste`
- New `imagePreview` actor (`Clutter.Actor`) alongside the text label
- `_displayItem()` / `_displayByKind()` detect images via `GPaste.ItemKind.IMAGE` (value `3`)
- `_loadImagePreview()` gets the cached PNG path from `Client.get_raw_element()` — for images this returns a file path like `~/.local/share/gpaste/images/<hash>.png`
- `_renderThumbnail()` loads with `GdkPixbuf.Pixbuf.new_from_file()`, scales down to fit menu width (never upscales), renders via `Clutter.Image.set_data()`
- Hidden actors collapsed (`set_content(null)`, `set_size(0,0)`) to avoid consuming layout space

### 2. Menu scrolling

**Files:** `applet.js`, `6.4/applet.js`

- `_setupMenuScrolling()` wraps `this.menu.box` in `St.ScrollView`
- Called after `_populateMenus()` in the async client init callback
- Prevents menu overflow when many image thumbnails are shown

### 3. Square hover highlight corners

**Files:** `stylesheet.css`, `6.4/stylesheet.css`

- CSS rules for `.popup-menu-item` with all pseudo-classes (`:active`, `:checked`, `:hover`, `:selected`, `:focus`)
- `border-radius: 0 !important` overrides the Cinnamon theme default of `8px`

## Installation

### From the fork

```bash
# Clone the fork
git clone git@github.com:spa1teN/GPaste-Reloaded-Cinnamon-Applet.git ~/Projects/GPaste-Reloaded-Cinnamon-Applet

# Symlink into Cinnamon applets
ln -s ~/Projects/GPaste-Reloaded-Cinnamon-Applet/gpaste-reloaded@feuerfuchs.eu \
      ~/.local/share/cinnamon/applets/gpaste-reloaded@feuerfuchs.eu

# Restart Cinnamon
# Alt+F2, type r, hit Enter
```

### Post-install

The applet icon should appear. If missing, enable it in Cinnamon applet settings. Re-add to panel if needed.

### Text length

GPaste's `element-size` gsettings key controls characters per entry (default 30):

```bash
gsettings set org.gnome.GPaste element-size 120
```

## Getting it working again (2026-08-06)

After deleting the applet and reinstalling from the fork, the tray icon was missing with no errors in Looking Glass. This section documents what was needed.

### Problem 1: Missing `__init__.js` in `6.4/`

**Error:** `[requireModule] Path does not exist: .../6.4/__init__.js`

The fork only had our modified files in `6.4/` (`GPasteHistoryItem.js`, `applet.js`, `stylesheet.css`). The `6.4/applet.js` uses `require('./__init__')._` but `__init__.js` wasn't there.

**Fix:** Copied `__init__.js` from the top-level directory into `6.4/`.

### Problem 2: Missing module files in `6.4/`

After fixing `__init__.js`, all the `require('./...')` calls in `6.4/applet.js` were still broken because `GPasteSearchItem.js`, `GPasteHistoryListItem.js`, `GPasteNewItemDialog.js`, and `GPasteNotInstalledDialog.js` were missing from `6.4/`. The top-level versions don't have `module.exports` — they use the old `AppletDir.*` pattern. Simple copying didn't work initially because GJS's `require` system resolves differently from Node.js, but the files are actually compatible (GJS makes top-level function/class names available as module properties).

**Fix:** Fetched the original `6.4/` files from [Cinnamon Spices](https://github.com/linuxmint/cinnamon-spices-applets/tree/master/gpaste-reloaded%40feuerfuchs.eu/files/gpaste-reloaded%40feuerfuchs.eu/6.4):
- `__init__.js`
- `GPasteSearchItem.js`
- `GPasteHistoryListItem.js`
- `GPasteNewItemDialog.js`
- `GPasteNotInstalledDialog.js`

### Problem 3: Re-applying `_setupMenuScrolling` to `6.4/applet.js`

Fetching the original `6.4/applet.js` overwrote our modified version, losing the `_setupMenuScrolling` method. Had to re-add the method and its call site after `_populateMenus()`.

### Problem 4: Missing `settings-schema.json` and `metadata.json` in `6.4/`

No error, but the tray icon was invisible. The `6.4/` directory has its own `settings-schema.json` which includes the `always-show-icon` key (default `true`). Without it, `this.alwaysShowIcon` was `undefined`, and `this.actor.visible = undefined` in `_onDisplaySettingsUpdated()` hid the icon.

**Fix:** Fetched `settings-schema.json` and `metadata.json` from Cinnamon Spices.

### Root cause

Cinnamon's multiversion system (`"multiversion": "true"` in metadata.json) makes Cinnamon 6.4+ load from the `6.4/` subdirectory instead of the top-level. This directory had been created by the original spices install but wasn't part of the fork's git history. When rebuilding from the fork, every file the `6.4/` version needs must be present — the multiversion directory is self-contained and doesn't fall back to the top-level.

### Reference: Cinnamon Spices source

```
https://raw.githubusercontent.com/linuxmint/cinnamon-spices-applets/master/gpaste-reloaded@feuerfuchs.eu/files/gpaste-reloaded@feuerfuchs.eu/6.4/
```

## GPaste image internals

- `Client.get_element_kind(uuid)` returns `GPaste.ItemKind.IMAGE = 3` for images
- `Client.get_raw_element(uuid)` for images returns a **file path** (string) to `~/.local/share/gpaste/images/<hash>.png` — not raw bytes
- Images are cached by the GPaste daemon when copied to the clipboard
