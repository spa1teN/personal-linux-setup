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

# --- Rainbow Powerline Line 1 ---
# Six segments matching ~/.config/starship.toml

# Background colors — $'...' produces actual ESC bytes, not literal \033
C1=$'\033[48;2;170;0;0m';       C2=$'\033[48;2;212;112;64m';   C3=$'\033[48;2;245;194;74m'
C4=$'\033[48;2;102;204;85m';    C5=$'\033[48;2;85;170;221m';    C6=$'\033[48;2;136;114;200m'
BG=$'\033[48;2;42;45;52m'
c1=$'\033[38;2;170;0;0m';       c2=$'\033[38;2;212;112;64m';    c3=$'\033[38;2;245;194;74m'
c4=$'\033[38;2;102;204;85m';    c5=$'\033[38;2;85;170;221m';    c6=$'\033[38;2;136;114;200m'
black=$'\033[38;2;24;24;24m\033[1m';      white=$'\033[38;2;255;255;255m\033[1m'
white_bg=$'\033[48;2;255;255;255m'
user_fg=$'\033[38;2;255;255;255m\033[1m'
host_fg=$'\033[38;2;180;240;255m\033[1m'; path_fg=$'\033[38;2;24;24;24m\033[1m'
gh_fg=$'\033[38;2;80;60;15m\033[1m';      branch_fg=$'\033[38;2;30;75;25m\033[1m'
release_fg=$'\033[38;2;55;90;40m\033[1m'; status_fg=$'\033[38;2;20;55;85m\033[1m'
ram_fg=$'\033[38;2;24;24;24m\033[1m';     state_fg=$'\033[38;2;30;70;80m\033[1m'
reset=$'\033[0m'
defbg=$'\033[49m'   # default background

is_ssh() { [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; }
is_root() { [ "$(id -u)" -eq 0 ]; }

# ── OS logo ─────────────────────────────────────────────────────────────
if [ -f /proc/device-tree/model ] && grep -qi 'raspberry pi' /proc/device-tree/model 2>/dev/null; then
    os_logo=$'\U0000E722'    #  nf-dev-raspberry_pi
elif [ -f /etc/os-release ]; then
    . /etc/os-release 2>/dev/null
    case "${ID,,}" in
        linuxmint) os_logo=$'' ;;  ubuntu) os_logo=$'\U0000F31B' ;;
        *)         os_logo=$'\U0000F31A' ;;
    esac
else os_logo=$'\U0000F31A'; fi

# ── Directory icon substitution ─────────────────────────────────────────
declare -A icons=(
    [Downloads]=$'\U000F01DA'   [Documents]=$'\U000F0219'   [Dokumente]=$'\U000F0219'
    [Pictures]=$'\U0000F03E'    [Bilder]=$'\U0000F03E'      [Videos]=$'\U000F0567'
    [Music]=$'\U000F075A'       [Desktop]=$'\U0000F108'     [Telegram]=$'\U0000E217'
    [Screenshots]=$'\U0000F50C' [Backups]=$'\U000F006F'    [Backup]=$'\U000F006F'
    [Kontakte]=$'\U0001F04CB'   [Hörbücher]=$'\U0000E638'  [Notizen]=$'\U000F039A'
    [Folien]=$'\U0000E67D'      [setup]=$'\U0000EB51'       [storage]=$'\U0000F1C0'
    [ISOs]=$'\U000F11F0'       [SteamLibrary]=$'\U0000ED29'
    [Woelkchen]=$'\U0000F0C2'   [nextcloud]=$'\U0000F0C2'
    [roaringbot]=$'\U0000EB1E'  [Tausendsassa]=$'\U0000F1FF' [dashboard]=$'\U0000EACD'
    [website]=$'\U0001F059F'    [Uni]=$'\U0000F19C'
)
IFS='/' read -ra pp <<< "$dir_short"; pres=(); picon=()
for p in "${pp[@]}"; do
    if [ -n "$p" ] && [ -n "${icons[$p]:-}" ]; then pres+=("${icons[$p]}"); picon+=('1')
    else pres+=("$p"); picon+=('0'); fi
done
pjoin=''
for ((i=0; i<${#pres[@]}; i++)); do
    if [ "$i" -eq 0 ]; then pjoin="${pres[$i]}"
    else s='/'; [[ "${picon[$i-1]}" == '1' ]] && s=' /'; pjoin="${pjoin}${s}${pres[$i]}"; fi
done

# ── GitHub user ─────────────────────────────────────────────────────────
github_user=''
[ -f ~/.config/gh/hosts.yml ] && github_user=$(grep -oP '^\s*user:\s*\K\S+' ~/.config/gh/hosts.yml 2>/dev/null || true)
if [ -z "$github_user" ] && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    for remote in origin $(git -C "$dir" remote 2>/dev/null); do
        url=$(git -C "$dir" config --get "remote.${remote}.url" 2>/dev/null) || continue
        [[ "$url" =~ git@github\.com:([^/]+) ]] && { github_user="${BASH_REMATCH[1]}"; break; }
        [[ "$url" =~ github\.com/([^/]+) ]] && { github_user="${BASH_REMATCH[1]}"; break; }
    done
fi
[ -z "$github_user" ] && github_user=$(git config --global user.name 2>/dev/null || true)
[ -z "$github_user" ] && github_user="${GITHUB_USER:-}"

# ── Git info ────────────────────────────────────────────────────────────
branch=''; tag=''; git_state=''; git_status_text=''
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=":$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)"
    tag=$(git -C "$dir" describe --tags --abbrev=0 2>/dev/null || true)
    gdir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null)
    if [ -d "$gdir/rebase-merge" ] || [ -d "$gdir/rebase-apply" ]; then
        git_state="REBASE"
        [ -f "$gdir/rebase-merge/msgnum" ] && git_state="REBASE $(cat "$gdir/rebase-merge/msgnum")/$(cat "$gdir/rebase-merge/end" 2>/dev/null || echo '?')"
    elif [ -f "$gdir/MERGE_HEAD" ]; then git_state="MERGE"
    elif [ -f "$gdir/CHERRY_PICK_HEAD" ]; then git_state="CHERRY-PICK"
    elif [ -f "$gdir/REVERT_HEAD" ]; then git_state="REVERT"
    elif [ -f "$gdir/BISECT_START" ]; then git_state="BISECT"
    fi
    staged=0 modified=0 untracked=0 deleted=0 renamed=0 conflicted=0
    while IFS= read -r line; do
        xy="${line:0:2}"; x="${xy:0:1}"; y="${xy:1:1}"
        [[ "$x$y" = "??" || "$x$y" = "!!" ]] && { ((untracked++)); continue; }
        [[ "$x" = "u" || "$y" = "u" || "$x" = "U" || "$y" = "U" ]] && { ((conflicted++)); continue; }
        case "$x" in M|A|D|R|C) ((staged++)) ;; esac
        case "$y" in M) ((modified++)) ;; D) ((deleted++)) ;; esac
        case "$x" in R|C) ((renamed++)) ;; esac
    done < <(git -C "$dir" status --porcelain 2>/dev/null)
    ahead=0 behind=0
    ab=$(git -C "$dir" rev-list --left-right --count @{upstream}...HEAD 2>/dev/null) && {
        behind=$(echo "$ab" | awk '{print $1}'); ahead=$(echo "$ab" | awk '{print $2}')
    }
    sp=()
    ((staged))    && sp+=("$staged+");    ((modified))  && sp+=("$modified~")
    ((untracked)) && sp+=("$untracked?"); ((deleted))   && sp+=("$deleted-")
    ((renamed))   && sp+=("$renamed»");   ((conflicted)) && sp+=("$conflicted!")
    ((ahead))     && sp+=("${ahead}↑");   ((behind))    && sp+=("${behind}↓")
    if (( ${#sp[@]} )); then IFS=' '; git_status_text="${sp[*]}"; fi
fi

# ── RAM usage ───────────────────────────────────────────────────────────
# (removed — RAM replaced by clock in segment 6)

# ── Assemble Line 1 ─────────────────────────────────────────────────────
line1="${c1}${C1}"
if is_ssh || is_root; then
    line1+="${user_fg}$(whoami) ${white}${os_logo}  ${host_fg}$(hostname -s) "
else
    line1+=" ${white}${os_logo} "
fi
line1+=" ${C2}${c1} "
is_ssh && line1+="${black} in ${path_fg}${pjoin} " || line1+="${path_fg}${pjoin} "
line1+=" ${C3}${c2}"
if [ -n "$github_user" ]; then line1+=" ${black}"$'\U0000EB00'" ${gh_fg}${github_user} "; else line1+=" "; fi
line1+="${C4}${c3}"
if [ -n "$branch" ]; then
    line1+=" ${black}"$'\U000F062C'" ${branch_fg}${branch} "
    [ -n "$tag" ] && line1+="${release_fg}(${tag}) "
else line1+=" "; fi
line1+="${C5}${c4}"
if [ -n "$git_status_text" ]; then
    line1+="${status_fg} ${git_status_text} "
    [ -n "$git_state" ] && line1+="${state_fg}[${git_state}] "
elif [ -n "$git_state" ]; then
    line1+="${state_fg} [${git_state}] "
else line1+=" "; fi
line1+="${C6}${c5}"
line1+=" ${black}"$'\U000F017'" ${ram_fg}$(date +%H:%M) "
line1+="${defbg}${c6}${reset}"

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
if cost < 1: cost_s = f'{cost*100:.1f}¢'    # cents
else:     cost_s = f'\${cost:.2f}'
total = tin + tout
if total >= 1e6: tok_s = f'{total/1e6:.1f}M'
elif total >= 1e3: tok_s = f'{total/1e3:.0f}K'
else: tok_s = str(total)
print(f'{tok_s} tok.')
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
ESC=$'\033'
strip() { printf '%s' "$1" | sed "s/${ESC}\[[0-9;]*m//g"; }

line2=""
if [ -n "$stats" ]; then
    tok_part=$(echo "$stats" | head -1)
    cost_part=$(echo "$stats" | tail -1)

    line2="$(printf '\033[33m%s\033[0m' "$tok_part")/$(printf '\033[32m%s\033[0m' "$cost_part")"
    if [ -n "$model" ]; then
        model_short=$(printf '%s' "$model" | sed 's/[Dd][Ee][Ee][Pp][Ss][Ee][Ee][Kk]/ds/')
        line2="${line2} ($(printf '\033[35m%s\033[0m' "$model_short"))"
    fi

    # Show balance only for DeepSeek models
    if [ -n "$model" ] && echo "$model" | grep -qi "deepseek"; then
        if [ "$bal" != "?" ] && [ -n "$bal" ]; then
            line2="${line2}, bal. $(printf '\033[36m%s\033[0m' "$bal")"
        fi
    fi
fi

# --- Output ---
min_gap=5
safety=3
if [ -n "$line2" ]; then
    l1s=$(strip "$line1")
    l2s=$(strip "$line2")
    tw=${COLUMNS:-$(tput cols < /dev/tty 2>/dev/null || echo 80)}
    available=$(( tw - ${#l1s} - ${#l2s} ))
    if [ $available -lt $(( min_gap + safety )) ]; then
        # Terminal too narrow for single row — use two lines
        printf '%s\n%s\n' "$line1" "$line2"
    else
        pad=$(( available - safety ))
        printf '%s%*s%s\n' "$line1" "$pad" '' "$line2"
    fi
else
    printf '%s\n' "$line1"
fi
