#!/usr/bin/env bash
# Claude Code status line: model name + context usage progress bar

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

if [ -n "$used" ]; then
  # Build a 20-char progress bar
  filled=$(printf "%.0f" "$(echo "$used * 20 / 100" | bc -l)")
  empty=$((20 - filled))
  bar=$(printf '%0.s█' $(seq 1 $filled 2>/dev/null))
  bar="${bar}$(printf '%0.s░' $(seq 1 $empty 2>/dev/null))"
  pct=$(printf "%.0f" "$used")
  printf "\033[0;36m%s\033[0m  \033[0;33m[%s]\033[0m \033[0;37m%s%%\033[0m" \
    "$model" "$bar" "$pct"
else
  printf "\033[0;36m%s\033[0m" "$model"
fi
