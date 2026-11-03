#!/usr/bin/env bash
# apply.sh — execute a plan written by plan.sh after the user approved it.
#
# Usage: apply.sh <plan.json> [--merge-settings] [--exclude <worktree>]...
#
#   --merge-settings      also append the plan's settings.local.json
#                         additions to each target's parent repo file
#   --exclude <worktree>  skip a listed target (absolute path or basename);
#                         repeatable
#
# For each target: bazel clean (if the worktree uses Bazel), git worktree
# remove (never --force), prune, then force-delete its branches. A target
# whose removal fails is reported and its branches are left alone. Exits
# non-zero if anything failed.

set -uo pipefail

if (( BASH_VERSINFO[0] < 5 )); then
  echo "apply.sh needs bash >= 5 (found $BASH_VERSION); on macOS: brew install bash" >&2
  exit 1
fi

PLAN=""; MERGE=0; EXCLUDE=()
while (( $# )); do
  case $1 in
    --merge-settings) MERGE=1; shift ;;
    --exclude) EXCLUDE+=("$2"); shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) PLAN=$1; shift ;;
  esac
done
[[ -n $PLAN && -f $PLAN ]] || { echo "usage: apply.sh <plan.json> [--merge-settings] [--exclude <worktree>]..." >&2; exit 1; }

excluded() {
  local e; for e in "${EXCLUDE[@]}"; do [[ $1 == "$e" || $(basename "$1") == "$e" ]] && return 0; done
  return 1
}

FAILED=0
REPORT=()
say() { REPORT+=("$*"); }

merge_settings() {  # $1 parent, $2 additions JSON → "applied" or "failed: ..."
  local file=$1/.claude/settings.local.json out
  [[ -f $file ]] || { mkdir -p "$1/.claude" && printf '{}\n' > "$file"; }
  out=$(jq --argjson a "$2" '
    def merge($p; $a):
      if ($a | type) == "object" and ($p | type) == "object" then
        reduce ($a | keys[]) as $k ($p; .[$k] = merge($p[$k]; $a[$k]))
      elif ($a | type) == "array" and ($p | type) == "array" then $p + $a
      elif $p == null then $a else $p end;
    merge(.; $a)' "$file" 2>&1) || { echo "failed: $out"; return; }
  printf '%s\n' "$out" > "$file" && echo applied || echo "failed: could not write $file"
}

SWEPT_AGENT=(); SWEPT_OTHER=()
while IFS= read -r t; do
  kind=$(jq -r .kind <<< "$t"); wt=$(jq -r .wt <<< "$t"); br=$(jq -r .branch <<< "$t")
  parent=$(jq -r .parent <<< "$t"); keep=$(jq -r .keep <<< "$t"); bazel=$(jq -r .bazel <<< "$t")
  label=$(basename "$wt")

  if excluded "$wt"; then say "– Excluded: $wt"; continue; fi

  if [[ $keep == true ]]; then
    say "✓ Worktree kept (locked): $wt, branch $br"
  else
    if [[ $bazel == true ]]; then
      if ! command -v bazel >/dev/null; then say "✗ Bazel clean: failed: bazel not on PATH ($label)"
      elif out=$(cd "$wt" && bazel clean --expunge 2>&1); then say "✓ Bazel clean: ran ($label)"
      else say "✗ Bazel clean: failed: ${out##*$'\n'} ($label)"; fi
    fi
    cd "$parent" || { say "✗ Cannot cd to $parent"; FAILED=1; continue; }
    if ! out=$(git -C "$parent" worktree remove "$wt" 2>&1); then
      say "✗ Worktree remove failed: $wt — ${out//$'\n'/ } (branches left alone; not retrying with --force)"
      FAILED=1; continue
    fi
    git -C "$parent" worktree prune
    say "✓ Worktree removed: $wt"
  fi

  deleted=(); failed_br=()
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    if out=$(git -C "$parent" branch -D "$name" 2>&1); then deleted+=("$name")
    else failed_br+=("$name — ${out//$'\n'/ }"); FAILED=1; fi
  done < <(jq -r '.branches[].name' <<< "$t")
  say "✓ Branches deleted ($label): ${#deleted[@]}${deleted[*]:+ — ${deleted[*]}}"
  for f in "${failed_br[@]}"; do say "✗ Branch delete failed: $f"; done

  additions=$(jq -c .settings_additions <<< "$t")
  if [[ $additions == null ]]; then say "✓ Settings merged ($label): no-op"
  elif (( MERGE )); then say "✓ Settings merged ($label): $(merge_settings "$parent" "$additions")"
  else say "✓ Settings merged ($label): declined"; fi

  case $kind in
    agent) SWEPT_AGENT+=("$label") ;;
    other-repo) SWEPT_OTHER+=("$wt") ;;
  esac
done < <(jq -c '.targets[]' "$PLAN")

echo "Cleanup complete:"
printf '  %s\n' "${REPORT[@]}"
if jq -e '.arg == ""' "$PLAN" >/dev/null; then
  echo "  ✓ Sub-agent worktrees swept: ${#SWEPT_AGENT[@]}${SWEPT_AGENT[*]:+ — ${SWEPT_AGENT[*]}}"
  echo "  ✓ Other-repo worktrees swept: ${#SWEPT_OTHER[@]}${SWEPT_OTHER[*]:+ — ${SWEPT_OTHER[*]}}"
fi
jq -r '.skipped[] | "  – Skipped: \(.wt) — \(.reason)"' "$PLAN"
exit $FAILED
