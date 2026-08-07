local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- GTK renders the titlebar, WezTerm the tab bar below.
-- Shared background so they read as one continuous header.
config.window_decorations = "RESIZE"
config.integrated_title_button_alignment = "Right"
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 24
config.font_size = 12.0

-- Opacity + blur: native on Wayland; pre-blurred image on X11
if os.getenv('WAYLAND_DISPLAY') then
  config.window_background_opacity = 0.4
  config.wayland_window_background_blur = true
else
  -- X11: fake blur with a pre-blurred background of your wallpaper
  config.window_background_opacity = 0.95
  config.window_background_image = os.getenv('HOME') .. '/.wezterm/bg3.jpg'
end

-- Auto-detect colors from the current GTK theme
local function gtk_theme_color(var_name)
  local f = io.popen(
    'theme=$(gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null | ' ..
    "tr -d \"'\n\"); " ..
    'for d in "$HOME/.themes/$theme" "$HOME/.local/share/themes/$theme" ' ..
    '"/usr/share/themes/$theme"; do ' ..
    '[ -f "$d/gtk-3.0/gtk.css" ] && { grep -oP ' ..
    '"@define-color ' .. var_name .. ' \\K[#a-fA-F0-9]+" "$d/gtk-3.0/gtk.css" 2>/dev/null; break; }; ' ..
    'done'
  )
  local color = f:read('*a'):gsub('\n', '')
  f:close()
  return color ~= '' and color or nil
end

local BG = gtk_theme_color('theme_bg_color') or '#202020'
local FG = gtk_theme_color('theme_fg_color') or '#ffffff'
local function adjust_hex(hex, amount)
  local r = math.min(255, math.max(0, tonumber(hex:sub(2,3), 16) + amount))
  local g = math.min(255, math.max(0, tonumber(hex:sub(4,5), 16) + amount))
  local b = math.min(255, math.max(0, tonumber(hex:sub(6,7), 16) + amount))
  return string.format('#%02x%02x%02x', r, g, b)
end
local SURFACE = gtk_theme_color('insensitive_base_color') or adjust_hex(BG, 13)
local INACTIVE = adjust_hex(BG, 4)
local MUTED = gtk_theme_color('insensitive_fg_color')
if not MUTED or MUTED:match('rgba') then MUTED = '#8c8c8c' end

config.window_frame = {
  border_left_width = 0,
  border_right_width = 0,
  border_bottom_height = 0,
  border_top_height = 0,
  active_titlebar_bg = BG,
  inactive_titlebar_bg = INACTIVE,
  font = wezterm.font({ family = 'sans-serif', weight = 'Bold' }),
  font_size = 13.0,
}

config.colors = {
  background = BG,
  tab_bar = {
    background = BG,
    active_tab = { bg_color = SURFACE, fg_color = FG },
    inactive_tab = { bg_color = BG, fg_color = MUTED },
    inactive_tab_hover = { bg_color = INACTIVE, fg_color = FG },
    new_tab = { bg_color = BG, fg_color = MUTED },
    new_tab_hover = { bg_color = INACTIVE, fg_color = FG },
  },
}

-- Window title
wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local title = tab.active_pane.title or 'wezterm'
  local idx = tab.tab_index + 1
  return title .. '  [' .. idx .. '/' .. #tabs .. ']'
end)

-- Safe field access: PaneInformation in WezTerm 20240203 has a throwing
-- __index metamethod — unknown fields error instead of returning nil.
-- pcall the access to safely probe for optional methods/fields.
local function safe_field(obj, name)
  local ok, val = pcall(function() return obj[name] end)
  return ok and val or nil
end

-- Right status: workspace info
wezterm.on('update-right-status', function(window, pane)
  local workspace = window:active_workspace()
  local tabs = safe_field(window, 'tabs')
  local active_idx, total = 1, 1
  if tabs and type(tabs) == 'table' and #tabs > 0 then
    for _, t in ipairs(tabs) do
      if t.is_active then active_idx = t.tab_index + 1; break end
    end
    total = #tabs
  end
  local info
  if workspace and workspace ~= 'default' then
    info = workspace .. '  [' .. active_idx .. '/' .. total .. ']'
  else
    info = '[' .. active_idx .. '/' .. total .. ']'
    workspace = nil
  end
  -- set_title may not exist in older WezTerm
  local st = safe_field(window, 'set_title')
  if st then
    if workspace then
      pcall(st, window, 'WS: ' .. workspace)
    else
      pcall(st, window, '')
    end
  end
  window:set_right_status(wezterm.format({
    { Foreground = { Color = MUTED } },
    { Text = '  ' .. info .. '  ' },
  }))
end)

-- Custom tab titles (survive shell OSC title overrides)
local custom_tab_titles = {}

-- Path icon substitutions — mirrors prompt-seg2-path for tab titles
local path_icons = {
  Downloads    = '\u{F01DA}',
  Documents    = '\u{F0219}',
  Dokumente     = '\u{F0219}',
  Pictures     = '\u{F03E}',
  Bilder       = '\u{F03E}',
  Videos       = '\u{F0567}',
  Music        = '\u{F075A}',
  Desktop      = '\u{F108}',
  Telegram     = '\u{E217}',
  Screenshots  = '\u{F50C}',
  Backups      = '\u{F006F}',
  Backup       = '\u{F006F}',
  Kontakte     = '\u{1F04CB}',
  ['Hörbücher'] = '\u{E638}',
  Notizen      = '\u{F039A}',
  Folien       = '\u{E67D}',
  setup        = '\u{EB51}',
  storage      = '\u{F1C0}',
  ISOs         = '\u{F11F0}',
  SteamLibrary = '\u{ED29}',
  Woelkchen    = '\u{F0C2}',
  nextcloud    = '\u{F0C2}',
  roaringbot   = '\u{EB1E}',
  Tausendsassa = '\u{F1FF}',
  dashboard    = '\u{EACD}',
  website      = '\u{1F059F}',
  Uni          = '\u{F19C}',
}

-- Program → Nerd Font icon for tab titles (shown when a command is running)
-- nil value means "show the path instead" (used for shells at idle prompt)
local prog_icons = {
  -- Editors
  nvim  = '\u{E7C5}',   -- nf-cod-vm
  vim   = '\u{E7C5}',
  vi    = '\u{E7C5}',
  nano  = '\u{E795}',   -- nf-cod-pencil
  emacs = '\u{E632}',   -- nf-seti-emacs
  code  = '\u{E70C}',   -- nf-dev-visual_studio
  -- System monitors
  htop  = '\u{F32E}',   -- nf-mdi-chart_areaspline
  btop  = '\u{F32E}',
  top   = '\u{F32E}',
  -- Languages / runtimes
  python  = '\u{E73C}', -- nf-dev-python
  python3 = '\u{E73C}',
  node    = '\u{E718}', -- nf-dev-nodejs_small
  ruby    = '\u{E791}', -- nf-cod-ruby
  java    = '\u{E738}', -- nf-dev-java
  rustc   = '\u{E7A8}', -- nf-cod-rust
  go      = '\u{E724}', -- nf-dev-go
  lua     = '\u{E620}', -- nf-seti-lua
  -- Tools
  git     = '\u{E702}', -- nf-dev-git
  docker  = '\u{E7B0}', -- nf-dev-docker
  npm     = '\u{E71E}', -- nf-dev-npm
  cargo   = '\u{E7A8}', -- nf-cod-rust
  make    = '\u{E779}', -- nf-cod-terminal_bash
  gcc     = '\u{E77A}', -- nf-cod-terminal_powershell
  ['g++'] = '\u{E77A}',
  ssh     = '\u{F08B9}', -- nf-fa-terminal (user-specified)
  -- SSH aliases from .bash_aliases
  stratoserver = '\u{F08B9}',
  himbeere     = '\u{F08B9}',
  mainpc       = '\u{F08B9}',
  laptop       = '\u{F08B9}',
  smartmatch   = '\u{F08B9}',
  hpicluster   = '\u{F08B9}',
  hpiclusterrun = '\u{F08B9}',
  sudo    = '\u{F489}',
  su      = '\u{F489}',
  -- File viewers / pagers
  less    = '\u{F0349}', -- nf-fa-eye (user-specified)
  man     = '\u{F02D}', -- nf-fa-book
  bat     = '\u{F002}', -- nf-fa-search
  -- Package managers
  apt     = '\u{EB29}', -- nf-cod-package
  -- Shells → nil means "show the path instead" (idle at prompt)
  bash    = nil,
  zsh     = nil,
  fish    = nil,
  sh      = nil,
  dash    = nil,
}

-- Format a path like the bash prompt: ~ for HOME, icon substitutions, spaced slashes
local function format_path_for_tab(path_str, is_ssh)
  local home = os.getenv('HOME') or ''
  if home ~= '' and path_str:sub(1, #home) == home then
    path_str = '~' .. path_str:sub(#home + 1)
  end

  -- Split into components and substitute icons
  local parts = {}
  for part in path_str:gmatch('[^/]+') do
    table.insert(parts, part)
  end

  local result_parts = {}
  local icon_flags = {}
  for i, part in ipairs(parts) do
    local icon = path_icons[part]
    if icon then
      result_parts[i] = icon
      icon_flags[i] = true
    else
      result_parts[i] = part
      icon_flags[i] = false
    end
  end

  -- Rejoin with tight slashes (no spaces — the tab bar is too compact for them)
  local result = result_parts[1] or ''
  for i = 2, #result_parts do
    result = result .. '/' .. result_parts[i]
  end

  if is_ssh then
    result = 'in ' .. result
  end

  return result
end

-- Count UTF-8 characters (not bytes) for accurate tab-width padding
local function utf8_len(s)
  local _, count = s:gsub('[%z\1-\127\194-\244][\128-\191]*', '')
  return count
end

-- SSH domains (from ~/.bash_aliases) — appear in launcher, type name to connect
config.ssh_domains = {
  { name = 'himbeere',      remote_address = 'caspar@himbeere',                multiplexing = 'WezTerm' },
  { name = 'mainpc',        remote_address = 'caspar@spa1lnx',                 multiplexing = 'WezTerm' },
  { name = 'laptop',        remote_address = 'caspar@sadeniemi',               multiplexing = 'WezTerm' },
  { name = 'stratoserver',  remote_address = 'root@casparsadenius.de',         multiplexing = 'WezTerm' },
}

-- Launcher menu: press Ctrl+Shift+P, type "shortcuts"
config.launch_menu = {
  {
    label = 'shortcuts — List all keybindings',
    args = { 'bash', '-c', [[
echo
echo "  Custom keybindings"
echo "  =================="
echo "  Alt+1 .. Alt+4     Switch workspace 1–4"
echo "  Alt+W              Workspace picker"
echo "  Ctrl+Shift+P       Command launcher"
echo "  Ctrl+Shift+N       Name / create workspace"
echo "  Ctrl+Shift+T       Create + name new tab"
echo "  Ctrl+Shift+E       Rename current tab"
echo "  Ctrl+Shift+R       Reload config"
echo
echo "  Press enter to close"
read
]] },
  },
}

-- Keybindings
config.keys = {
  -- Launcher (launch menu items only, not cluttered with tabs/workspaces)
  {
    key = 'p', mods = 'CTRL|SHIFT',
    action = wezterm.action.ShowLauncher,
  },
  { key = 'r', mods = 'CTRL|SHIFT', action = wezterm.action.ReloadConfiguration },
  { key = '1', mods = 'ALT', action = wezterm.action.SwitchToWorkspace { name = '1' } },
  { key = '2', mods = 'ALT', action = wezterm.action.SwitchToWorkspace { name = '2' } },
  { key = '3', mods = 'ALT', action = wezterm.action.SwitchToWorkspace { name = '3' } },
  { key = '4', mods = 'ALT', action = wezterm.action.SwitchToWorkspace { name = '4' } },
  {
    key = 'w', mods = 'ALT',
    action = wezterm.action.ShowLauncherArgs { flags = 'FUZZY|WORKSPACES' },
  },
  {
    key = 'n', mods = 'CTRL|SHIFT',
    action = wezterm.action.PromptInputLine {
      description = 'Workspace name:',
      action = wezterm.action_callback(function(window, pane, line)
        if line then
          window:perform_action(wezterm.action.SwitchToWorkspace { name = line }, pane)
        end
      end),
    },
  },
  {
    key = 't', mods = 'CTRL|SHIFT',
    action = wezterm.action.PromptInputLine {
      description = 'New tab name:',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then
          window:perform_action(wezterm.action.SpawnTab('CurrentPaneDomain'), pane)
          local tab = window:active_tab()
          tab:set_title(line)
          custom_tab_titles[tab:tab_id()] = line
        end
      end),
    },
  },
  {
    key = 'e', mods = 'CTRL|SHIFT',
    action = wezterm.action.PromptInputLine {
      description = 'Rename tab:',
      action = wezterm.action_callback(function(window, pane, line)
        if line and line ~= '' then
          local tab = window:active_tab()
          tab:set_title(line)
          custom_tab_titles[tab:tab_id()] = line
        end
      end),
    },
  },
}

-- Minimal base64 decoder (WezTerm 20240203 may not have wezterm.b64_decode)
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64_index = {}
for i = 1, #b64chars do
  b64_index[b64chars:sub(i, i)] = i - 1
end
b64_index['='] = 0
local function b64_decode(data)
  data = data:gsub('[^A-Za-z0-9+/=]', '')
  local out, n = {}, 0
  for i = 1, #data, 4 do
    n = b64_index[data:sub(i,i)]   * 262144
      + b64_index[data:sub(i+1,i+1)] * 4096
      + b64_index[data:sub(i+2,i+2)] * 64
      + b64_index[data:sub(i+3,i+3)]
    out[#out+1] = string.char(math.floor(n / 65536) % 256)
    if data:sub(i+2,i+2) ~= '=' then
      out[#out+1] = string.char(math.floor(n / 256) % 256)
      if data:sub(i+3,i+3) ~= '=' then
        out[#out+1] = string.char(n % 256)
      end
    end
  end
  return table.concat(out)
end

-- Tab formatting:
--   - Custom name (Ctrl+Shift+E) always wins
--   - If pane title looks like a path → shell at prompt → format with icons
--   - Foreground process detection for running programs (nvim, htop, etc.)
--   - Fallback → raw pane title or "wezterm"
wezterm.on('format-tab-title', function(tab, tabs, panes, cnf, hover, max_width)
  if custom_tab_titles[tab.tab_id] then
    local title = custom_tab_titles[tab.tab_id]
    local cw = utf8_len(title)
    return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
  end

  local pane = tab.active_pane
  if not pane then
    return { { Text = '  wezterm  ' .. string.rep(' ', math.max(0, max_width - 11)) } }
  end

  local pane_title = pane.title or ''

  -- Does the title look like a path? (may include "in " prefix from SSH)
  local ssh_prefix = pane_title:match('^in ')
  local path_candidate = ssh_prefix and pane_title:sub(4) or pane_title
  if path_candidate:match('^~/') or path_candidate:match('^/') then
    local domain = safe_field(pane, 'domain_name') or 'local'
    local is_ssh = (ssh_prefix ~= nil) or (domain ~= 'local')
    local cwd = safe_field(pane, 'current_working_dir')
    local title
    if cwd and type(cwd) == 'table' and cwd.path and cwd.scheme == 'file' then
      title = format_path_for_tab(cwd.path, is_ssh)
    else
      title = format_path_for_tab(path_candidate, is_ssh)
    end
    local cw = utf8_len(title)
    return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
  end

  -- Not a path → get foreground process (may help identify aliased commands)
  local get_proc_fn = safe_field(pane, 'get_foreground_process_name')
  local fg_name = nil
  if get_proc_fn and type(get_proc_fn) == 'function' then
    local proc_ok, proc = pcall(get_proc_fn, pane)
    if proc_ok and proc then
      fg_name = (proc:match('[^/]+$') or proc):lower()
    end
  end

  -- Not a path → check if we can show a program icon
  local first_word, rest = pane_title:match('^(%w+)%s+(.*)')
  if not first_word then
    first_word = pane_title:match('^(%w+)')
  end
  if first_word then
    local pname = first_word:lower()
    -- Icon from pane title first, or from foreground process (catches aliases)
    local icon = prog_icons[pname] or (fg_name and prog_icons[fg_name])
    local display_name = icon and (prog_icons[pname] and pname or fg_name) or nil
    if icon then
      -- Programs where filename matters more than program name (editors, pagers)
      local show_file_only = { nvim = true, vim = true, vi = true, emacs = true, nano = true, code = true, less = true }
      local title
      if show_file_only[display_name] and rest and rest ~= '' then
        -- Extract basename from the last argument (not the full command-line path)
        local last_arg = rest:match('%S+$') or rest
        local display = last_arg:match('[^/]+$') or last_arg
        title = icon .. ' ' .. display
      else
        title = icon .. ' ' .. display_name
        if rest and rest ~= '' then
          title = title .. ' ' .. rest
        end
      end
      local cw = utf8_len(title)
      return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
    end
  end

  -- No icon match, but foreground process has an icon → show it with pane title
  if fg_name and prog_icons[fg_name] then
    local title = prog_icons[fg_name] .. ' ' .. pane_title
    local cw = utf8_len(title)
    return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
  end

  -- Last resort
  local title = pane_title ~= '' and pane_title or 'wezterm'
  local cw = utf8_len(title)
  return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
end)

return config
