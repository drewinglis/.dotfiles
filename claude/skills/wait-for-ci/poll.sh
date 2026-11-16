#!/usr/bin/env bash
# Poll a commit's CI on a GitHub or Gitea remote until every check finishes.
# Usage: poll.sh [-r REMOTE] [-t MAX_SECONDS] [-g GRACE_SECONDS] [-i INTERVAL] [REF]
# Defaults: origin, 1800s max, 300s grace for the first check to appear,
# 30s between polls, HEAD.
# Exit codes: 0 = all checks passed, 1 = a check failed, 2 = deadline reached
# with checks still pending, 3 = no checks reported within the grace period,
# 4 = error (bad remote or ref, commit not on the remote, API errors).
set -uo pipefail

remote=origin max=1800 grace=300 interval=30
while getopts r:t:g:i: opt; do
  case $opt in
    r) remote=$OPTARG ;;
    t) max=$OPTARG ;;
    g) grace=$OPTARG ;;
    i) interval=$OPTARG ;;
    *) exit 4 ;;
  esac
done
shift $((OPTIND - 1))
ref=${1:-HEAD}

die() { echo "error: $*" >&2; exit 4; }

url=$(git remote get-url "$remote") || die "no remote '$remote'"
path=${url%.git}
case $path in
  *://*) rest=${path#*://}; rest=${rest#*@}; host=${rest%%/*}; host=${host%%:*}; repo=${rest#*/} ;;
  *@*:*) rest=${path#*@}; host=${rest%%:*}; repo=${rest#*:} ;;
  *) die "can't parse remote URL '$url'" ;;
esac
sha=$(git rev-parse --verify --quiet "$ref^{commit}") || die "unknown ref '$ref'"

# Each fetcher prints a JSON array of {name, state: pass|fail|pending, detail}
# and returns non-zero on any API error or unexpected response.
if [ "$host" = github.com ]; then
  forge=GitHub
  gh api "repos/$repo/commits/$sha" --jq .sha >/dev/null ||
    die "$sha not found on $repo at github.com (not pushed?)"
  fetch() {
    local s r
    s=$(gh api "repos/$repo/commits/$sha/status?per_page=100" --jq \
      '{total_count, statuses: [.statuses[] | {context, state, description}]}') || return 1
    r=$(gh api --paginate "repos/$repo/commits/$sha/check-runs?per_page=100" \
      --jq '.check_runs[] | {name, status, conclusion}' | jq -s .) || return 1
    printf '%s\n%s\n' "$s" "$r" | jq -s '
      .[0] as $s | .[1] as $r
      | if ($s.statuses | length) != $s.total_count
      then error("got \($s.statuses | length) of \($s.total_count) statuses")
      else . end
      | [ ($s.statuses[] | {name: .context, detail: (.description // ""),
            state: ({success: "pass", pending: "pending"}[.state] // "fail")}),
          ($r[] | {name, detail: (.conclusion // .status),
            state: (if .status != "completed" then "pending"
                    elif (.conclusion | IN("success", "neutral", "skipped"))
                    then "pass" else "fail" end)}) ]'
  }
else
  forge=Gitea
  login=$(tea login list --output json | jq -r --arg h "$host" '
    .[] | select((.url | sub("^https?://"; "") | sub("[:/].*"; "")) == $h
                 or .ssh_host == $h) | .name' | head -n1)
  [ -n "$login" ] || die "no GitHub host or tea login matches '$host'"
  found=$(tea api --login "$login" "repos/$repo/git/commits/$sha" | jq -r .sha) ||
    die "commit lookup on $host failed"
  [ "$found" = "$sha" ] || die "$sha not found on $repo at $host (not pushed?)"
  fetch() {
    local s
    s=$(tea api --login "$login" "repos/$repo/commits/$sha/status?limit=100") || return 1
    jq '
      if (.state | type) != "string" then error("unexpected response: \(tojson)")
      elif ((.statuses // []) | length) != .total_count
      then error("got \(.statuses | length) of \(.total_count) statuses")
      else . end
      | [ (.statuses // [])[] | {name: .context, detail: (.description // ""),
            state: ({success: "pass", skipped: "pass", pending: "pending",
                     running: "pending"}[.status] // "fail")} ]' <<<"$s"
  }
fi

echo "Polling $forge CI for $repo@${sha:0:10} every ${interval}s (max ${max}s)."
start=$(date +%s) errors=0 last=""
report() { jq -r '.[] | select(.state != "pass") | "  \(.state)\t\(.name)\t\(.detail)"' <<<"$checks"; }
while :; do
  elapsed=$(( $(date +%s) - start ))
  if ! checks=$(fetch); then
    errors=$((errors + 1))
    echo "poll error ($errors/3) at ${elapsed}s" >&2
    [ "$errors" -ge 3 ] && die "giving up after 3 consecutive poll errors"
  else
    errors=0
    read -r total pass fail pending < <(jq -r '[length,
      (map(select(.state == "pass")) | length),
      (map(select(.state == "fail")) | length),
      (map(select(.state == "pending")) | length)] | @tsv' <<<"$checks")
    line="$pass pass, $fail fail, $pending pending"
    [ "$line" != "$last" ] && echo "[${elapsed}s] $line" && last=$line
    if [ "$total" -eq 0 ]; then
      if [ "$elapsed" -ge "$grace" ]; then
        echo "No checks reported on ${sha:0:10} after ${elapsed}s."
        exit 3
      fi
    elif [ "$fail" -gt 0 ]; then
      echo "CI failed on ${sha:0:10}:"; report; exit 1
    elif [ "$pending" -eq 0 ]; then
      echo "All $total checks passed on ${sha:0:10}."; exit 0
    fi
  fi
  if [ "$elapsed" -ge "$max" ]; then
    echo "Deadline reached after ${elapsed}s with CI unfinished:"; report; exit 2
  fi
  sleep "$interval"
done
