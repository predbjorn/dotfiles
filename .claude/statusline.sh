#!/usr/bin/env bash
# Claude Code status line script
# Receives JSON on stdin; outputs a single status line

input=$(cat)

# Model display name (shortened)
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
# Strip "Claude " prefix to save space
model="${model#Claude }"

# Working directory (basename only)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir=$(basename "$cwd")

# Detect git: branch, dirty, and whether we're in a linked worktree.
# In a linked worktree, git-dir != git-common-dir.
dir_icon="📁"
git_str=""
if [ -n "$cwd" ] && branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  dirty=""
  if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
    dirty="*"
  fi
  git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
  git_common=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
  # Normalize to absolute for comparison
  [ -n "$git_dir" ] && git_dir=$(cd "$cwd" && cd "$(dirname "$git_dir")" 2>/dev/null && pwd)/$(basename "$git_dir")
  [ -n "$git_common" ] && git_common=$(cd "$cwd" && cd "$(dirname "$git_common")" 2>/dev/null && pwd)/$(basename "$git_common")
  if [ -n "$git_dir" ] && [ -n "$git_common" ] && [ "$git_dir" != "$git_common" ]; then
    dir_icon="🌳"
    # Project name = parent of the main .git dir, prepended as "project/worktree"
    project=$(basename "$(dirname "$git_common")")
    [ -n "$project" ] && dir="${project}/${dir}"
  fi
  git_str=" 🌿 ${branch}${dirty}"
fi

# Context window info
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
total=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
used_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')

# Build context string with color based on usage
# Green: < 30% used (plenty of room)
# Yellow: 30-60% used (watch it)
# Red: > 60% used (the "dumb zone" — coherence degrades)
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

color_for_pct() {
  local p=$1
  if   [ "$(awk "BEGIN{print ($p < 30)}")" = "1" ]; then printf "%s" "$GREEN"
  elif [ "$(awk "BEGIN{print ($p < 60)}")" = "1" ]; then printf "%s" "$YELLOW"
  else printf "%s" "$RED"
  fi
}

ctx=""
if [ -n "$used_tokens" ] && [ -n "$total" ] && [ -n "$used_pct" ]; then
  used_k=$(awk "BEGIN {printf \"%.0fk\", $used_tokens/1000}")
  total_k=$(awk "BEGIN {printf \"%.0fk\", $total/1000}")
  remaining_pct_fmt=$(printf "%.0f" "$remaining_pct")
  color=$(color_for_pct "$used_pct")
  ctx="🧠 ${color}${used_k}/${total_k} (${remaining_pct_fmt}% left)${RESET}"
elif [ -n "$used_pct" ]; then
  remaining_pct_fmt=$(printf "%.0f" "$remaining_pct")
  color=$(color_for_pct "$used_pct")
  ctx="🧠 ${color}${remaining_pct_fmt}% left${RESET}"
else
  ctx="🧠 --"
fi

# Effort level (if present)
effort=$(echo "$input" | jq -r '.effort.level // empty')
effort_str=""
[ -n "$effort" ] && effort_str=" | ⚡ ${effort}"

# Lines changed this session (from cost block)
added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')
lines_str=""
if [ -n "$added" ] || [ -n "$removed" ]; then
  lines_str=" | ±+${added:-0}/-${removed:-0}"
fi

# Rate limits — 5h and weekly (key name varies: seven_day / weekly)
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // .rate_limits.weekly.used_percentage // .rate_limits.seven_day_opus.used_percentage // empty')
rate_str=""
[ -n "$five_pct" ] && rate_str="${rate_str} | ⏱️ 5h: $(printf '%.0f' "$five_pct")%"
[ -n "$week_pct" ] && rate_str="${rate_str} | 📅 wk: $(printf '%.0f' "$week_pct")%"

printf "%s %s%s | 🤖 %s%s\n%s%s%s" "$dir_icon" "$dir" "$git_str" "$model" "$effort_str" "$ctx" "$lines_str" "$rate_str"
