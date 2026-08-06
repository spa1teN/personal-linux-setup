#!/bin/bash
input=$(cat)

# Parse JSON with python3
parse() { python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get($1,'') or '')" 2>/dev/null; }

# --- Directory ---
dir=$(echo "$input" | parse "'workspace',{}")
dir=$(echo "$dir" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('current_dir','') or '')" 2>/dev/null)
[ -z "$dir" ] && dir=$(pwd)

home_esc=$(printf '%s' "$HOME" | sed 's/[\/&]/\\&/g')
dir_short=$(printf '%s' "$dir" | sed "s|^$home_esc|~|")

# --- Starship-style Line 1 ---
# Replicates format from ~/.config/starship.toml with bg:#2a2d34 on the whole line
BG='48;2;42;45;52'
is_ssh() { [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; }
is_root() { [ "$(id -u)" -eq 0 ]; }

# Open background for the entire first line
line1=$(printf "\033[${BG}m")

if is_ssh || is_root; then
    line1="${line1}$(printf "\033[1;33m%s\033[22;39m" "$(whoami)") @ "
    if is_ssh; then
        line1="${line1}$(printf "\033[1;32m%s\033[22;39m" "$(hostname -s)") in "
    fi
fi
line1="${line1}$(printf "\033[1;36m%s\033[22;39m" "$dir_short")"

# --- Git info (starship-style) ---
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    # Branch (bold purple), with latest tag in braces if present
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        line1="${line1} on branch $(printf "\033[1;35m%s\033[22;39m" "$branch")"
        tag=$(git -C "$dir" describe --tags --abbrev=0 2>/dev/null) && [[ -n "$tag" ]] && \
            line1="${line1} $(printf '(\033[1;35m%s\033[22;39m)' "${tag#v}")"
    fi

    # State: rebase/merge/cherry-pick/bisect/revert (bold yellow)
    gdir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
    state=""
    if [ -d "$gdir/rebase-merge" ] || [ -d "$gdir/rebase-apply" ]; then
        # Try to get progress
        state="REBASE"
        [ -f "$gdir/rebase-merge/msgnum" ] && state="REBASE $(cat "$gdir/rebase-merge/msgnum")/$(cat "$gdir/rebase-merge/end" 2>/dev/null || echo '?')"
    elif [ -f "$gdir/MERGE_HEAD" ]; then
        state="MERGE"
    elif [ -f "$gdir/CHERRY_PICK_HEAD" ]; then
        state="CHERRY-PICK"
    elif [ -f "$gdir/REVERT_HEAD" ]; then
        state="REVERT"
    elif [ -f "$gdir/BISECT_START" ]; then
        state="BISECT"
    fi
    if [ -n "$state" ]; then
        line1="${line1} $(printf "\033[1;33m[%s]\033[22;39m" "$state")"
    fi

    # Status: use starship custom git-status-prompt (bold red)
    git_status_text=$(cd "$dir" && ~/.local/bin/git-status-prompt 2>/dev/null)
    if [ -n "$git_status_text" ]; then
        line1="${line1} $(printf "\033[1;31m%s\033[22;39m" "$git_status_text")"
    fi
fi

# Close background
line1="${line1}"$(printf "\033[0m")

# --- Model name ---
model=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    m = (d.get('model') or {}).get('id') or (d.get('model') or {}).get('display_name') or ''
    print(m)
except: print('')
" 2>/dev/null)

# --- Session tokens and cost ---
stats=$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
cw = d.get('context_window') or {}
tin = cw.get('total_input_tokens') or 0
tout = cw.get('total_output_tokens') or 0
if tin == 0 and tout == 0:
    print('')
    sys.exit()
model = (d.get('model') or {}).get('display_name') or (d.get('model') or {}).get('id') or ''
m = model.lower()
if 'opus' in m: pin, pout = 15.0, 75.0
elif 'sonnet' in m: pin, pout = 3.0, 15.0
elif 'haiku' in m: pin, pout = 0.8, 4.0
elif 'deepseek' in m: pin, pout = 0.28, 1.10
else: pin, pout = 3.0, 15.0
cost = (tin/1e6)*pin + (tout/1e6)*pout
cost_s = f'\${cost:.3f}' if cost < 1 else f'\${cost:.2f}'
total = tin + tout
if total >= 1e6: tok_s = f'{total/1e6:.1f}M'
elif total >= 1e3: tok_s = f'{total/1e3:.0f}K'
else: tok_s = str(total)
print(f'{tok_s} token')
print(f'~{cost_s}')
" 2>/dev/null)
[ -z "$stats" ] && stats=""

# --- Balance: cached for 60s ---
cache="/tmp/ds-balance-$(whoami)"
if [ ! -f "$cache" ] || [ "$(($(date +%s)-$(stat -c%Y "$cache" 2>/dev/null || echo 0)))" -gt 60 ]; then
  curl -sf -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" \
    "https://api.deepseek.com/user/balance" 2>/dev/null \
    | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    v = d.get('balance','') or str(d.get('balance_infos',[{}])[0].get('total_balance',''))
    if isinstance(v,(int,float)): v = f'{v:.2f}'
    cur = d.get('balance_infos',[{}])[0].get('currency','')
    sym = {'CNY':'¥','USD':'\$'}.get(cur, cur + ' ' if cur else '')
    print((sym + v) if v else '?')
except: print('?')
" 2>/dev/null > "$cache"
  [ -s "$cache" ] || echo "?" > "$cache"
fi
bal=$(cat "$cache" 2>/dev/null || echo "?")

# --- Assemble Line 2 ---
strip() { printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'; }
MAXW=80

line2=""
if [ -n "$stats" ]; then
    tok_part=$(echo "$stats" | head -1)
    cost_part=$(echo "$stats" | tail -1)

    line2="used $(printf '\033[33m%s\033[0m' "$tok_part") ($(printf '\033[32m%s\033[0m' "$cost_part"))"
    if [ -n "$model" ]; then
        line2="${line2} with $(printf '\033[35m%s\033[0m' "$model")"
    fi

    # Show balance only for DeepSeek models
    if [ -n "$model" ] && echo "$model" | grep -qi "deepseek"; then
        if [ "$bal" != "?" ] && [ -n "$bal" ]; then
            line2="${line2} - remaining balance: $(printf '\033[36m%s\033[0m' "$bal")"
        fi
    fi
fi

# --- Output ---
printf '%s\n' "$line1"

if [ -n "$line2" ]; then
    r2s=$(strip "$line2")
    pad=$(( MAXW - ${#r2s} ))
    [ $pad -lt 0 ] && pad=0
    printf '%*s%s\n' "$pad" '' "$line2"
fi
