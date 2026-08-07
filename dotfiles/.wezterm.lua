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
  config.window_background_image = os.getenv('HOME') .. '/.wezterm/bg1.jpg'
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
-- Strip tmux: prefix markers from a title (used by format-window-title
-- and format-tab-title). Handles up to 2 levels of nesting.
local function strip_context_prefix(title)
  for _ = 1, 2 do
    local stripped = title:match('^tmux:(.+)') or title:match('^ssh:(.+)')
    if stripped then title = stripped else break end
  end
  return title
end

wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local raw_title = tab.active_pane.title or 'wezterm'
  local title = strip_context_prefix(raw_title)
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

-- Per-pane SSH state: when we see a path with "in " prefix, we know this
-- pane is an SSH session. Subsequent command titles (which lack the prefix)
-- can still show the SSH icon by consulting this table.
local pane_ssh_state = {}

-- Per-pane device identity: when we know which Tailscale device a pane is
-- connected to, store its icon for display after the SSH icon.
local pane_device = {}

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
  ssh     = '\u{F08C0}', -- nf-fa-terminal (user-specified)
  -- SSH aliases from .bash_aliases
  stratoserver = '\u{F08C0}',
  himbeere     = '\u{F08C0}',
  mainpc       = '\u{F08C0}',
  laptop       = '\u{F08C0}',
  smartmatch   = '\u{F08C0}',
  hpicluster   = '\u{F08C0}',
  hpiclusterrun = '\u{F08C0}',
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
  -- Terminal multiplexer / AI tools
  tmux   = '\u{EBC8}',
  claude = '\u{EC82}',
  -- Network tools
  wget   = '\u{F19D0}',
  curl   = '\u{F19D0}',
  sftp   = '\u{EAE9}',
  scp    = '\u{EAE9}',
}

-- Device icons for Tailscale hosts (shown after SSH icon in tab titles)
local device_icons = {
  spa1lnx                 = '\u{F01C5}',
  ['pixel-7a-von-spa1ten'] = '\u{F10B}',
  himbeere                = '\u{F043F}',
  sadeniemi               = '\u{F0322}',
  stratoserver            = '\u{EB50}',
  mainpc                  = '\u{F01C5}',  -- alias for spa1lnx
  laptop                  = '\u{F0322}',   -- alias for sadeniemi
}

-- File extension --> Nerd Font icon. All codepoints are from families proven
-- to render in this config (devicons E7xx, seti E6xx, fa Fxxx).
-- Verify at nerdfonts.com/cheat-sheet if any glyphs are missing.
local ext_icons = {
  json    = '\u{F0626}',
  py      = '\u{E73C}',
  js      = '\u{E718}',
  mjs     = '\u{E718}',
  ts      = '\u{E628}',
  tsx     = '\u{E628}',
  jsx     = '\u{E7BA}',
  html    = '\u{E60E}',
  htm     = '\u{E60E}',
  css     = '\u{E6B8}',
  scss    = '\u{E6B8}',
  md      = '\u{EB1D}',
  mdx     = '\u{EB1D}',
  rs      = '\u{E7A8}',
  go      = '\u{E724}',
  rb      = '\u{E791}',
  java    = '\u{E738}',
  lua     = '\u{E620}',
  cpp     = '\u{E646}',
  cc      = '\u{E646}',
  cxx     = '\u{E646}',
  hpp     = '\u{E646}',
  hxx     = '\u{E646}',
  c       = '\u{E61E}',
  h       = '\u{E61E}',
  toml    = '\u{E615}',
  yaml    = '\u{E615}',
  yml     = '\u{E615}',
  ini     = '\u{E615}',
  cfg     = '\u{E615}',
  conf    = '\u{E615}',
  sh      = '\u{E795}',
  bash    = '\u{E795}',
  zsh     = '\u{E795}',
  vim     = '\u{E7C5}',
  tex     = '\u{E69B}',
  ltx     = '\u{E69B}',
  latex   = '\u{E69B}',
  csv     = '\u{EEFC}',
  tar     = '\u{EAEF}',
  zip     = '\u{EAEF}',
  gz      = '\u{EAEF}',
  xz      = '\u{EAEF}',
  bz2     = '\u{EAEF}',
  ['7z']  = '\u{EAEF}',
  rar     = '\u{EAEF}',
  txt     = nil,
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

-- Truncate a UTF-8 string to at most maxchars code points, appending ...
local function truncate_utf8(s, maxchars)
  if maxchars < 1 then return '...' end
  local count = 0
  for pos, cp in s:gmatch('()([%z\1-\127\194-\244][\128-\191]*)') do
    count = count + 1
    if count > maxchars then return s:sub(1, pos - 1) .. '...' end
  end
  return s
end

-- Split a string into whitespace-delimited tokens
local function split_tokens(s)
  local out = {}
  for t in s:gmatch('%S+') do out[#out+1] = t end
  return out
end

-- Derive a stable key for a pane (falls back to tab_id)
local function pane_key(pane, tab)
  local id = safe_field(pane, 'pane_id')
  if id then return id end
  return tab.tab_id
end

-- Programs where the filename matters more than the program name
local show_file_only = {
  nvim = true, vim = true, vi = true, emacs = true,
  nano = true, code = true, less = true, man = true,
}

-- Collect program icons (first 3 meaningful tokens) and file-extension icons
-- (all tokens). Returns {icons}, last_prog_index, show_file_bool.
local MAX_PROG_TOKENS = 3
local function collect_icons(tokens)
  local icons, seen, last_prog = {}, {}, nil
  -- Program scan: first MAX_PROG_TOKENS tokens only, skip flags/URLs/paths
  local limit = math.min(MAX_PROG_TOKENS, #tokens)
  for i = 1, limit do
    local t = tokens[i]:lower()
    if t:sub(1,1) ~= '-' and not t:find('[/=:%%%*%?%[]]') then
      local ic = prog_icons[t]
      if ic and not seen[ic] then
        seen[ic] = true
        icons[#icons+1] = ic
        last_prog = i
      end
    end
  end
  local show_file = last_prog and show_file_only[tokens[last_prog]:lower()]
  -- Extension scan: all tokens, skip flags and URLs
  for _, t in ipairs(tokens) do
    if t:sub(1,1) ~= '-' and t:sub(1,1) ~= '*' and not t:find('://') then
      local ext = t:match('%.([%a%d]+)$')
      if ext then
        local ic = ext_icons[ext]
        if ic and not seen[ic] then
          seen[ic] = true
          icons[#icons+1] = ic
        end
      end
    end
  end
  return icons, last_prog, show_file
end

-- SSH domains (from ~/.bash_aliases) — appear in launcher, type name to connect
config.ssh_domains = {
  { name = 'himbeere',      remote_address = 'himbeere',                        multiplexing = 'WezTerm' },
  { name = 'mainpc',        remote_address = 'spa1lnx',                         multiplexing = 'WezTerm' },
  { name = 'laptop',        remote_address = 'sadeniemi',                       multiplexing = 'WezTerm' },
  { name = 'stratoserver',  remote_address = 'casparsadenius.de', username = 'root', multiplexing = 'WezTerm' },
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

  -- Does the title look like a path? (may include "in " prefix from SSH;
  -- may include "tmux:" prefix from tmux set-titles-string)
  -- 1. Strip tmux: prefix so "tmux:in ~/foo" parses correctly
  local tmux_in_path = false
  local path_title = pane_title
  for _ = 1, 2 do
    local stripped = path_title:match('^tmux:(.+)')
    if stripped then
      tmux_in_path = true
      path_title = stripped
    else
      break
    end
  end

  -- 2. Detect SSH "in " prefix on the cleaned title
  local ssh_prefix = path_title:match('^in ')
  local path_candidate = ssh_prefix and path_title:sub(4) or path_title
  if path_candidate:match('^~') or path_candidate:match('^/') then
    local domain = safe_field(pane, 'domain_name') or 'local'
    local is_ssh = (ssh_prefix ~= nil) or (domain ~= 'local')

    -- Write per-pane SSH state (only set true on "in " prefix — never
    -- clear it from a bare path, since the remote PRECMD fires first and
    -- sends a path *without* "in " before prompt-seg2-path can correct it)
    local pk = pane_key(pane, tab)
    if is_ssh then
      pane_ssh_state[pk] = true
      -- Try to identify the device from the domain name
      local dom = safe_field(pane, 'domain_name')
      if dom then
        local dev = device_icons[dom] or (dom:match('^[^.]+') and device_icons[dom:match('^[^.]+')])
        if dev then pane_device[pk] = dev end
      end
    end

    -- Build context icon prefix (SSH → device → tmux order)
    local context_icons = {}
    if is_ssh and prog_icons.ssh then
      context_icons[#context_icons+1] = prog_icons.ssh
    end
    local dev_icon = pane_device[pk]
    if dev_icon then
      context_icons[#context_icons+1] = dev_icon
    end
    if tmux_in_path and prog_icons.tmux then
      context_icons[#context_icons+1] = prog_icons.tmux
    end

    -- Inside tmux, cwd from pane is stale (tmux doesn't forward OSC 7);
    -- always use the path from the title. Outside tmux, prefer OSC 7 cwd.
    local cwd = tmux_in_path and nil or safe_field(pane, 'current_working_dir')
    local path_str
    if cwd and type(cwd) == 'table' and cwd.path and cwd.scheme == 'file' then
      path_str = format_path_for_tab(cwd.path, false)
    else
      path_str = format_path_for_tab(path_candidate, false)
    end

    local title
    if #context_icons > 0 then
      title = table.concat(context_icons, ' ') .. ' ' .. path_str
    else
      title = path_str
    end
    local cw = utf8_len(title)
    return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
  end

  -- Not a path → collect all program + file-type icons
  -- 1. Strip tmux: prefix (set by .tmux.conf set-titles-string)
  local tmux_active = false
  local rest_title = pane_title
  for _ = 1, 2 do
    local stripped = rest_title:match('^tmux:(.+)')
    if stripped then
      tmux_active = true
      rest_title = stripped
    else
      break
    end
  end

  -- 2. Tokenize the command
  local tokens = split_tokens(rest_title)

  -- 3. Proactive SSH state: running ssh/sftp/scp marks the pane as SSH;
  -- exit/logout clears it. Also track which device we connected to.
  local pk_cmd = pane_key(pane, tab)
  if #tokens > 0 then
    local first = tokens[1]:lower()
    if first == 'ssh' or first == 'sftp' or first == 'scp' then
      pane_ssh_state[pk_cmd] = true
      -- Look up device icon from hostname argument
      if #tokens > 1 then
        local dev = device_icons[tokens[2]] or device_icons[tokens[2]:lower()]
        if dev then pane_device[pk_cmd] = dev end
      end
    elseif first == 'exit' or first == 'logout' then
      pane_ssh_state[pk_cmd] = false
      pane_device[pk_cmd] = nil
    end
    -- Also detect SSH aliases (stratoserver, himbeere, etc.) that are
    -- in prog_icons with the SSH icon → treat as ssh to that device
    if prog_icons[first] == prog_icons.ssh then
      local dev = device_icons[first] or device_icons[tokens[1]]
      if dev then pane_device[pk_cmd] = dev end
    end
  end

  local is_ssh_cmd = pane_ssh_state[pk_cmd] == true

  -- 4. Collect matching icons
  local icons, last_prog, show_file = collect_icons(tokens)

  if #icons > 0 then
    -- Build ordered icon list: context (SSH → tmux) → programs → file type
    local all_icons, seen = {}, {}
    local ssh_icon = prog_icons.ssh
    local tmux_icon = prog_icons.tmux

    if is_ssh_cmd and ssh_icon and not seen[ssh_icon] then
      seen[ssh_icon] = true
      all_icons[#all_icons+1] = ssh_icon
    end
    -- Device icon (specific Tailscale host we're connected to)
    local dev_icon = pane_device[pk_cmd]
    if dev_icon and not seen[dev_icon] then
      seen[dev_icon] = true
      all_icons[#all_icons+1] = dev_icon
    end
    if tmux_active and tmux_icon and not seen[tmux_icon] then
      seen[tmux_icon] = true
      all_icons[#all_icons+1] = tmux_icon
    end
    for _, ic in ipairs(icons) do
      if not seen[ic] then
        seen[ic] = true
        all_icons[#all_icons+1] = ic
      end
    end

    -- Build text portion
    local text
    if show_file and last_prog then
      -- Editor/pager with filename: show basename of last token
      local last_token = tokens[#tokens]
      text = last_token:match('[^/]+$') or last_token
    elseif last_prog and last_prog < #tokens then
      -- Show remaining args after last matched program
      local rest_parts = {}
      for i = last_prog + 1, #tokens do
        rest_parts[#rest_parts+1] = tokens[i]
      end
      text = table.concat(rest_parts, ' ')
    elseif last_prog then
      -- Single program, no args: show program name
      text = tokens[last_prog]:lower()
    else
      text = rest_title
    end

    local icon_str = table.concat(all_icons, ' ')
    local avail = math.max(0, max_width - utf8_len(icon_str) - 4)
    if utf8_len(text) > avail then
      text = truncate_utf8(text, math.max(1, avail - 1))
    end
    local full_title = icon_str .. ' ' .. text
    local cw = utf8_len(full_title)
    return { { Text = '  ' .. full_title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
  end

  -- No icons matched → legacy fallback (kept for forward-compat with newer
  -- WezTerm versions that expose get_foreground_process_name)
  local get_proc_fn = safe_field(pane, 'get_foreground_process_name')
  local fg_name = nil
  if get_proc_fn and type(get_proc_fn) == 'function' then
    local proc_ok, proc = pcall(get_proc_fn, pane)
    if proc_ok and proc then
      fg_name = (proc:match('[^/]+$') or proc):lower()
    end
  end

  -- Legacy single-icon fallback
  local first_word, rest = rest_title:match('^(%w+)%s+(.*)')
  if not first_word then
    first_word = rest_title:match('^(%w+)')
  end
  if first_word then
    local pname = first_word:lower()
    local icon = prog_icons[pname] or (fg_name and prog_icons[fg_name])
    local display_name = icon and (prog_icons[pname] and pname or fg_name) or nil
    if icon then
      if show_file_only[display_name] and rest and rest ~= '' then
        local last_arg = rest:match('%S+$') or rest
        local display = last_arg:match('[^/]+$') or last_arg
        local title = icon .. ' ' .. display
        local cw = utf8_len(title)
        return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
      else
        local title = icon .. ' ' .. display_name
        if rest and rest ~= '' then
          title = title .. ' ' .. rest
        end
        local cw = utf8_len(title)
        return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
      end
    end
  end

  -- Foreground process fallback (works on newer WezTerm versions)
  if fg_name and prog_icons[fg_name] then
    local title = prog_icons[fg_name] .. ' ' .. rest_title
    local cw = utf8_len(title)
    return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
  end

  -- Last resort
  local title = rest_title ~= '' and rest_title or 'wezterm'
  local cw = utf8_len(title)
  return { { Text = '  ' .. title .. '  ' .. string.rep(' ', math.max(0, max_width - cw - 4)) } }
end)

config.front_end = "WebGpu"

return config
