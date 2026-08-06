local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- GTK renders the titlebar, WezTerm the tab bar below.
-- Shared background so they read as one continuous header.
config.window_decorations = "RESIZE"
config.integrated_title_button_alignment = "Right"
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 999

config.window_background_image = '/home/caspar/.wezterm/bg1.jpg'

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
  font_size = 10.0,
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

-- Right status: workspace info
wezterm.on('update-right-status', function(window, pane)
  local workspace = window:active_workspace()
  local tabs = window:tabs()
  local active_idx = 1
  for _, t in ipairs(tabs) do
    if t.is_active then active_idx = t.tab_index + 1; break end
  end
  local total = #tabs
  local info
  if workspace and workspace ~= 'default' then
    info = workspace .. '  [' .. active_idx .. '/' .. total .. ']'
    window:set_title('WS: ' .. workspace)
  else
    info = '[' .. active_idx .. '/' .. total .. ']'
    window:set_title('')
  end
  window:set_right_status(wezterm.format({
    { Foreground = { Color = MUTED } },
    { Text = '  ' .. info .. '  ' },
  }))
end)

-- Custom tab titles (survive shell OSC title overrides)
local custom_tab_titles = {}

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

-- Tab formatting
wezterm.on('format-tab-title', function(tab, tabs, panes, cnf, hover, max_width)
  local title = custom_tab_titles[tab.tab_id] or tab.active_pane.title
  local left_pad = '  '
  local right_fill = string.rep(' ', math.max(0, max_width - #title - 4))
  return { { Text = left_pad .. title .. right_fill .. '  ' } }
end)

-- Rendering
config.front_end = "Software"

return config
