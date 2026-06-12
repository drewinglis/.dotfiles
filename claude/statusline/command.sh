#!/usr/bin/env bash
# Claude Code status line: model name + context usage progress bar + plan usage

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Plan rate-limit usage; only present on metered Claude.ai plans (Pro/Max)
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

now=$(date +%s)
fmt_remaining() {
  local secs=$(( $1 - now ))
  (( secs < 0 )) && secs=0
  local d=$((secs / 86400)) h=$((secs % 86400 / 3600)) m=$((secs % 3600 / 60))
  if (( d > 0 )); then echo "${d}d${h}h"; else echo "${h}h${m}m"; fi
}

plan=""
if [ -n "$five_h" ]; then
  plan="5h: $(printf '%.0f' "$five_h")%"
  [ -n "$five_h_reset" ] && plan="$plan ↻$(fmt_remaining "$five_h_reset")"
fi
if [ -n "$week" ]; then
  plan="${plan:+$plan }7d: $(printf '%.0f' "$week")%"
  if [ -n "$week_reset" ]; then
    # Show reset time only if usage is ahead of elapsed time in the 7d window
    week_elapsed_pct=$(( (604800 - (week_reset - now)) * 100 / 604800 ))
    if [ "$(jq -n "$week > $week_elapsed_pct")" = "true" ]; then
      plan="$plan ↻$(fmt_remaining "$week_reset")"
    fi
  fi
fi

if [ -n "$used" ]; then
  # Build a 20-char progress bar
  filled=$(jq -n "$used * 20 / 100 | round")
  empty=$((20 - filled))
  bar=$(printf '%0.s█' $(seq 1 $filled 2>/dev/null))
  bar="${bar}$(printf '%0.s░' $(seq 1 $empty 2>/dev/null))"
  pct=$(printf "%.0f" "$used")
  printf "\033[0;36m%s\033[0m  \033[0;33m[%s]\033[0m \033[0;37m%s%%\033[0m" \
    "$model" "$bar" "$pct"
else
  printf "\033[0;36m%s\033[0m" "$model"
fi

[ -n "$plan" ] && printf "  \033[0;35m%s\033[0m" "$plan"
