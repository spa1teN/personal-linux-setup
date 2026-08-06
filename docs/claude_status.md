# Claude Code Custom Status Line

Custom bash status line that replicates the Starship prompt with git info and shows session tokens, cost, model, and DeepSeek balance.

## Configuration

**`~/.claude/settings.json`:**
```json
"statusLine": {
  "type": "command",
  "command": "/home/caspar/.claude/scripts/ds-statusline.sh"
}
```

## Files

| File | Purpose |
|------|---------|
| `~/.claude/scripts/ds-statusline.sh` | Main status line script |
| `~/.config/starship.toml` | Reference for prompt style (bg:#2a2d34, colors) |
| `~/.local/bin/git-status-prompt` | Starship custom module — git status as text |
| `/tmp/ds-balance-$(whoami)` | DeepSeek balance cache (60s TTL) |

## Output Format

```
~/setup on branch main ❨2 staged, 1 modified, 3 ahead❩
                               used 73K token (~$0.023) with deepseek-v4-pro[1m] - remaining balance: $2.64
```

### Line 1 — Starship-Style Prompt

Replicates [Starship](https://starship.rs) prompt from `~/.config/starship.toml`. All modules use **bg:#2a2d34** applied as a continuous background across the entire line via ANSI true color (`48;2;42;45;52`).

| Element | Color | ANSI | Condition |
|---------|-------|------|-----------|
| `user` | bold yellow | `1;33` | SSH or root only |
| `@` | default | — | SSH or root only |
| `host` | bold green | `1;32` | SSH only |
| `in` | default | — | SSH only |
| `~/dir` | bold cyan | `1;36` | always |
| `on branch` | default | — | git repo |
| `main` | bold purple | `1;35` | git branch |
| `[REBASE 1/3]` | bold yellow | `1;33` | git state (rebase/merge/cherry-pick/bisect/revert) |
| `❨2 staged, 1 modified❩` | bold red | `1;31` | git changes (from `git-status-prompt`) |

Git state detection:
- **REBASE** — `rebase-merge/` or `rebase-apply/` directory exists
- **MERGE** — `MERGE_HEAD` file exists
- **CHERRY-PICK** — `CHERRY_PICK_HEAD` file exists
- **REVERT** — `REVERT_HEAD` file exists
- **BISECT** — `BISECT_START` file exists

Git status delegates to `~/.local/bin/git-status-prompt` (Starship custom module), which outputs descriptive text like `❨2 staged, 1 modified, 3 ahead❩` using the ❨❩ Unicode brackets.

### Line 2 — Session Stats

Sentence format with only values colored, labels plain.

| Part | Color | Source |
|------|-------|--------|
| `used` | default | — |
| `73K token` | yellow `33` | `context_window.total_input_tokens + total_output_tokens` |
| `(~$0.023)` | green `32` | Calculated from per-model pricing |
| `with` | default | — |
| `deepseek-v4-pro[1m]` | magenta `35` | `model.id` or `model.display_name` |
| `remaining balance:` | default | Only for DeepSeek models |
| `$2.64` | cyan `36` | DeepSeek API `/user/balance` endpoint |

## Token Cost Calculation

Pricing per model in USD per 1M tokens:

| Model | Input ($/1M) | Output ($/1M) |
|-------|-------------|---------------|
| Opus | $15.00 | $75.00 |
| Sonnet | $3.00 | $15.00 |
| Haiku | $0.80 | $4.00 |
| DeepSeek | $0.28 | $1.10 |
| Fallback | $3.00 | $15.00 |

Formula: `cost = (input_tokens/1M) × price_input + (output_tokens/1M) × price_output`

Format: `~$0.023` (3 decimals under $1, 2 decimals above).

## DeepSeek Balance Cache

Balance is fetched from `https://api.deepseek.com/user/balance` using `$ANTHROPIC_AUTH_TOKEN` and cached for 60 seconds at `/tmp/ds-balance-$(whoami)` to avoid rate limiting. Shows `?` on fetch failure.

Balance is only displayed when the model contains "deepseek" (case-insensitive match).

## JSON Payload Fields

The script receives the full Claude Code status line JSON on stdin. Fields used:

| JSON Path | Usage |
|-----------|-------|
| `workspace.current_dir` | Directory display |
| `model.id` / `model.display_name` | Model name |
| `context_window.total_input_tokens` | Token count + cost calc |
| `context_window.total_output_tokens` | Token count + cost calc |

### Other Available Fields (not used)

| Field | Description |
|-------|-------------|
| `context_window.used_percentage` | Context window usage % |
| `context_window.remaining_percentage` | Context window remaining % |
| `context_window.current_usage` | Per-call token breakdown (cache reads/writes) |
| `cost.total_cost_usd` | Claude Code's own cost estimate |
| `cost.total_duration_ms` | Session wall-clock time |
| `cost.total_api_duration_ms` | Time waiting for API |
| `cost.total_lines_added` / `total_lines_removed` | Code change stats |
| `effort.level` | `low` / `medium` / `high` / `xhigh` / `max` |
| `thinking.enabled` | Extended thinking toggle |
| `session_name` | From `/rename` |
| `fast_mode` | Fast mode toggle |
| `vim.mode` | Vim mode (`NORMAL`, `INSERT`, etc.) |
| `rate_limits` | Claude.ai rate limit usage (5h + 7d windows) |
| `workspace.repo` | `{host, owner, name}` from origin remote |
| `workspace.added_dirs` | `/add-dir` directories |
| `workspace.git_worktree` | Linked worktree name |
| `worktree` | `--worktree` session details |
| `pr` | Open PR `{number, url, review_state}` |
| `agent` | Agent name when `--agent` |

Env vars `COLUMNS` and `LINES` are set for the script. Output is capped at `MAXW=80` to prevent truncation in the status area.

## Width Budget

The status area in Claude Code wraps at `$COLUMNS` but the effective display area is narrower than the terminal. The script caps output at 80 characters (`MAXW`). Line 2 is right-padded to this width so it flushes right.

## Dependencies

- `bash` — script interpreter
- `python3` — JSON parsing and cost math
- `curl` — DeepSeek balance API
- `git` — branch, state, and status info
- `~/.local/bin/git-status-prompt` — Starship custom git status module
- `$ANTHROPIC_AUTH_TOKEN` — DeepSeek API auth (same token as Anthropic API)
