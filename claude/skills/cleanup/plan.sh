#!/usr/bin/env bash
# plan.sh — resolve everything /cleanup would tear down, without changing
# anything. Prints the plan for the user and writes a JSON plan file that
# apply.sh executes once the user approves.
#
# Usage: plan.sh [--also-branch <name>]... [<branch-or-worktree>]
#
#   <branch-or-worktree>  a branch name, a worktree directory basename, or an
#                         absolute worktree path. Without it, the worktree
#                         containing the CWD is the primary target and the
#                         session's sub-agent and other-repo worktrees are
#                         swept too. From the parent repo with no arg, only
#                         the sweeps run.
#   --also-branch <name>  a branch the caller knows belongs to this session
#                         (e.g. a rename the recycled reflog lost). It goes
#                         through the same safety filters as the rest.
#
# Exit codes: 0 plan written, 1 no target could be resolved,
#             2 the primary worktree has uncommitted changes.

set -uo pipefail

if (( BASH_VERSINFO[0] < 5 )); then
  echo "plan.sh needs bash >= 5 (found $BASH_VERSION); on macOS: brew install bash" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX=drewinglis

ARG=""
ALSO=()
while (( $# )); do
  case $1 in
    --also-branch) ALSO+=("$2"); shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) ARG=$1; shift ;;
  esac
done

abort() { local code=$1; shift; printf '%s\n' "$@" >&2; exit "$code"; }

# Lines of "path<TAB>locked<TAB>branch" for every worktree of the repo at $1.
# Branch is last because it is empty for a detached HEAD and `read` would
# collapse the empty middle field.
worktree_records() {
  git -C "$1" worktree list --porcelain | awk '
    /^worktree /{ if (p != "") print p "\t" l "\t" b; p = substr($0, 10); b = ""; l = 0 }
    /^branch /{ b = substr($0, 8); sub("^refs/heads/", "", b) }
    /^locked/{ l = 1 }
    END{ if (p != "") print p "\t" l "\t" b }'
}

repo_parent() {  # $1 = any dir inside a repo → path of its main worktree
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$common"
}

# Sets PR_JSON (object or null) and PR_NOTE for branch $2 of worktree $1.
pr_lookup() {
  local wt=$1 br=$2 url host out
  PR_JSON=null; PR_NOTE=""
  url=$(git -C "$wt" remote get-url origin 2>/dev/null) \
    || { PR_NOTE="n/a — no origin remote"; return; }
  host=$(printf '%s' "$url" | sed -E 's#^[a-z+]+://([^@/]+@)?##; s#^[^@/]+@##; s#[:/].*$##')
  if [[ $host == github.com ]]; then
    command -v gh >/dev/null || { PR_NOTE="unknown — gh not installed"; return; }
    if ! out=$(cd "$wt" && gh pr list --head "$br" --state all \
        --json number,state,url,isDraft,mergedAt --jq '.[0] // empty' 2>&1); then
      PR_NOTE="unknown — ${out//$'\n'/ }"; return
    fi
  else
    command -v tea >/dev/null || { PR_NOTE="unknown — tea not installed"; return; }
    if ! out=$(cd "$wt" && tea pulls list --state all --limit 50 \
        --fields index,state,url,head,title --output json 2>&1); then
      PR_NOTE="unknown — ${out//$'\n'/ }"; return
    fi
    out=$(printf '%s' "$out" | jq -c --arg br "$br" '
      [.[] | select(.head == $br)][0] // empty
      | {number: .index, state: (.state | ascii_upcase), url,
         isDraft: (.title | test("^(WIP:|\\[WIP\\])"))}' 2>&1) \
      || { PR_NOTE="unknown — ${out//$'\n'/ }"; return; }
  fi
  if [[ -n $out ]]; then PR_JSON=$out; else PR_NOTE="no PR found"; fi
}

# Prints "name<TAB>reason" for every local branch to delete for one target.
# $1 wt, $2 current branch, $3 parent repo, $4 keep (0/1), $5.. creation
# branch candidates. ALSO[] is applied only when ALSO_OK=1.
collect_branches() {
  local wt=$1 br=$2 parent=$3 keep=$4; shift 4
  local -a origs=("$@") order=()
  local -A reason=() chain=() elsewhere=()
  add() { [[ -n ${reason[$1]:-} ]] && return; reason[$1]=$2; order+=("$1"); }
  is_orig() { local o; for o in "${origs[@]}"; do [[ $1 == "$o" ]] && return 0; done; return 1; }

  add "$br" "current"

  # Walk the HEAD reflog newest-first, keeping only the contiguous rename
  # chain that ends at the current branch. Anything past a broken link or
  # the creation branch belongs to a previous occupant of a recycled slot.
  chain[$br]=1
  # Detached-HEAD hops log the full SHA as "from" but a short SHA as "to".
  chain_has() {
    [[ -n ${chain[$1]:-} ]] && return 0
    [[ $1 =~ ^[0-9a-f]{7,40}$ ]] || return 1
    local k; for k in "${!chain[@]}"; do [[ $k == "$1"* || $1 == "$k"* ]] && return 0; done
    return 1
  }
  local line from to entries=0
  while IFS= read -r line; do
    entries=1
    from=${line%% -> *}; to=${line##* -> }
    chain_has "$to" || break
    chain[$from]=1
    add "$from" "rename-chain — orphaned"
    is_orig "$from" && break
  done < <(git -C "$wt" reflog --format='%gs' 2>/dev/null \
    | sed -n 's/^checkout: moving from \(.*\) to \(.*\)$/\1 -> \2/p')

  # The creation branch reconstructed from the worktree name is only trusted
  # when the reflog chain reaches it, or when the reflog has no checkout
  # entries at all (pruned). In a recycled slot that name can belong to a
  # previous occupant.
  local o
  for o in "${origs[@]}"; do
    if [[ -n ${chain[$o]:-} ]]; then
      [[ $o != "$br" ]] && reason[$o]="original auto branch — orphaned by rename"
    elif (( ! entries )); then add "$o" "original auto branch — reconstructed from worktree name"
    fi
  done

  if (( ALSO_OK )); then
    local a; for a in "${ALSO[@]}"; do add "$a" "recovered from session history"; done
  fi

  local path b l
  while IFS=$'\t' read -r path l b; do
    [[ $path != "$wt" && -n $b ]] && elsewhere[$b]=1
  done < <(worktree_records "$parent")

  local -a kept=()
  local name
  for name in "${order[@]}"; do
    git -C "$parent" show-ref --verify --quiet "refs/heads/$name" || continue
    [[ -n ${elsewhere[$name]:-} ]] && continue
    kept+=("$name")
  done
  (( ${#kept[@]} )) || kept=("$br")
  for name in "${kept[@]}"; do
    (( keep )) && [[ $name == "$br" ]] && continue
    printf '%s\t%s\n' "$name" "${reason[$name]}"
  done
}

# Sets ADDITIONS to the additions-only diff of worktree settings over parent
# settings (JSON, or null) and SETTINGS_NOTE on parse failure.
settings_additions() {
  local wt=$1 parent=$2 a b
  SETTINGS_NOTE=""; ADDITIONS=null
  a=$wt/.claude/settings.local.json; b=$parent/.claude/settings.local.json
  [[ -f $a ]] || a=/dev/null
  [[ -f $b ]] || b=/dev/null
  ADDITIONS=$(jq -n --slurpfile a "$a" --slurpfile b "$b" '
    def additions($a; $b):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($a | keys[]) as $k ({};
          if ($b | has($k)) then
            additions($a[$k]; $b[$k]) as $d | if $d == null then . else .[$k] = $d end
          else .[$k] = $a[$k] end)
        | if . == {} then null else . end
      elif ($a | type) == "array" and ($b | type) == "array" then
        [$a[] | select(. as $x | any($b[]; . == $x) | not)]
        | if . == [] then null else . end
      else null end;
    additions($a[0] // {}; $b[0] // {})' 2>/dev/null) \
    || { SETTINGS_NOTE="could not parse a settings.local.json"; ADDITIONS=null; }
}

skip() {  # $1 kind, $2 wt, $3 reason
  SKIPPED+=("$(jq -nc --arg kind "$1" --arg wt "$2" --arg reason "$3" '{kind: $kind, wt: $wt, reason: $reason}')")
}

# Emits one target as a JSON object, or records it as skipped (dirty, or a
# locked sweep target). A detached-HEAD worktree is removed without deleting
# any branch, since there is no current branch to trace a rename chain from.
# $1 kind, $2 wt, $3 branch, $4 parent, $5 locked, $6.. creation candidates.
build_target() {
  local kind=$1 wt=$2 br=$3 parent=$4 locked=$5; shift 5
  local dirty
  dirty=$(git -C "$wt" status --porcelain 2>/dev/null)
  if [[ -n $dirty ]]; then
    if [[ $kind == primary ]]; then
      abort 2 "Worktree has uncommitted/unstaged changes. Commit, stash, or discard them before running /cleanup. Output:" "" "$dirty"
    fi
    skip "$kind" "$wt" "dirty — $(printf '%s\n' "$dirty" | grep -c .) uncommitted file(s)"
    return
  fi
  if [[ $kind != primary && $locked == 1 ]]; then
    skip "$kind" "$wt" "locked"
    return
  fi
  local keep=0; [[ $kind == primary && $locked == 1 ]] && keep=1
  [[ $kind == primary ]] && ALSO_OK=1 || ALSO_OK=0
  local branches bazel=false
  if [[ -z $br ]]; then
    PR_JSON=null; PR_NOTE="n/a — detached HEAD"; branches='[]'
  else
    pr_lookup "$wt" "$br"
    branches=$(collect_branches "$wt" "$br" "$parent" "$keep" "$@" \
      | jq -Rn '[inputs | split("\t") | {name: .[0], reason: .[1]}]')
  fi
  if [[ $kind == agent ]]; then ADDITIONS=null; SETTINGS_NOTE=""
  else settings_additions "$wt" "$parent"; fi
  [[ -e $wt/WORKSPACE || -e $wt/WORKSPACE.bazel || -e $wt/MODULE.bazel ]] && bazel=true
  TARGETS+=("$(jq -nc --arg kind "$kind" --arg wt "$wt" --arg branch "$br" --arg parent "$parent" \
    --argjson keep "$([[ $keep == 1 ]] && echo true || echo false)" \
    --argjson branches "$branches" --argjson pr "$PR_JSON" --arg pr_note "$PR_NOTE" \
    --argjson bazel "$bazel" --argjson settings "$ADDITIONS" --arg settings_note "$SETTINGS_NOTE" \
    '{kind: $kind, wt: $wt, branch: $branch, parent: $parent, keep: $keep, branches: $branches,
      pr: $pr, pr_note: $pr_note, bazel: $bazel, settings_additions: $settings,
      settings_note: $settings_note}')")
}

TARGETS=(); SKIPPED=(); NOTES=()

# --- Resolve the parent repo and the primary target ------------------------
if [[ -n $ARG && $ARG == /* && -d $ARG ]]; then GITDIR=$ARG; else GITDIR=$PWD; fi
PARENT=$(repo_parent "$GITDIR") || abort 1 "Not inside a git repository: $GITDIR"
RECORDS=$(worktree_records "$PARENT")

WT=""; BR=""; LOCKED=0
if [[ -n $ARG ]]; then
  stripped=${ARG#"$PREFIX"/}
  while IFS=$'\t' read -r path l b; do
    base=$(basename "$path")
    if [[ $b == "$ARG" || $path == "$ARG" || $base == "$ARG" || $base == "$stripped" ]]; then
      WT=$path; BR=$b; LOCKED=$l; break
    fi
  done <<< "$RECORDS"
  [[ -n $WT ]] || abort 1 "No worktree found matching \`$ARG\`. Run \`git worktree list\` to see available worktrees."
  [[ $WT != "$PARENT" ]] || abort 1 "\`$ARG\` resolves to the parent repo, not an auxiliary worktree. /cleanup is for tearing down worktrees only."
else
  TOP=$(git rev-parse --show-toplevel 2>/dev/null) || abort 1 "Not inside a git repository: $PWD"
  if [[ $TOP != "$PARENT" ]]; then
    while IFS=$'\t' read -r path l b; do
      [[ $path == "$TOP" ]] && { WT=$path; BR=$b; LOCKED=$l; break; }
    done <<< "$RECORDS"
    [[ -n $WT ]] || abort 1 "Current directory $TOP is not a registered worktree of $PARENT."
  fi
fi

if [[ -n $WT ]]; then
  build_target primary "$WT" "$BR" "$PARENT" "$LOCKED" "$PREFIX/$(basename "$WT")"
fi

# --- Sweeps (no-arg form only) ----------------------------------------------
if [[ -z $ARG ]]; then
  SESSION=${CLAUDE_CODE_SESSION_ID:-}
  if [[ -z $SESSION ]]; then
    NOTES+=("Sub-agent and other-repo sweeps skipped: CLAUDE_CODE_SESSION_ID is not set.")
  else
    PROJ_DIR=$HOME/.claude/projects/$(printf '%s' "$TOP" | sed 's/[^A-Za-z0-9]/-/g')
    SUBAGENTS=$PROJ_DIR/$SESSION/subagents
    TRANSCRIPT=$PROJ_DIR/$SESSION.jsonl

    if [[ -d $SUBAGENTS ]]; then
      while IFS=$'\t' read -r path l b; do
        [[ $path == "$PARENT"/.claude/worktrees/agent-* && $path != "$WT" ]] || continue
        id=$(basename "$path")
        [[ -f $SUBAGENTS/$id.jsonl ]] || continue
        build_target agent "$path" "$b" "$PARENT" "$l" "worktree-$id" "$PREFIX/$id"
      done <<< "$RECORDS"
    else
      NOTES+=("Sub-agent sweep: this session has no subagents directory ($SUBAGENTS); nothing to sweep.")
    fi

    if [[ -f $TRANSCRIPT ]]; then
      if ! PARSED=$(python3 -I "$SCRIPT_DIR/transcript-worktrees.py" "$TRANSCRIPT" "$SUBAGENTS"/*.jsonl 2>&1); then
        NOTES+=("Other-repo sweep skipped: transcript parser failed — ${PARSED##*$'\n'}")
        PARSED=""
      fi
      seen=()
      while IFS=$'\t' read -r repo path b; do
        [[ -n $repo && -n $path ]] || continue
        px=$(repo_parent "$repo") || continue
        [[ $px != "$PARENT" ]] || continue
        [[ " ${seen[*]:-} " == *" $path "* ]] && continue
        seen+=("$path")
        while IFS=$'\t' read -r rpath rl rb; do
          [[ $rpath == "$path" && $rpath != "$px" ]] || continue
          build_target other-repo "$rpath" "$rb" "$px" "$rl" ${b:+"$b"}
        done < <(worktree_records "$px")
      done <<< "$PARSED"
    else
      NOTES+=("Other-repo sweep skipped: transcript not found at $TRANSCRIPT.")
    fi
  fi
fi

if (( ${#TARGETS[@]} == 0 && ${#SKIPPED[@]} == 0 )); then
  abort 1 "No worktree specified, the current directory is the parent repo, and there are no sub-agent or other-repo worktrees to sweep. Pass /cleanup <branch-or-worktree-name> to target a specific worktree."
fi

# --- Write the plan and render it -------------------------------------------
PLAN_FILE=${CLEANUP_PLAN_FILE:-$(mktemp "${TMPDIR:-/tmp}/cleanup-plan.XXXXXX")}
jq -n --arg arg "$ARG" --arg parent "$PARENT" \
  --argjson targets "$(printf '%s\n' "${TARGETS[@]}" | jq -s .)" \
  --argjson skipped "$(printf '%s\n' "${SKIPPED[@]}" | jq -s .)" \
  --argjson notes "$(printf '%s\n' "${NOTES[@]}" | jq -R . | jq -s 'map(select(. != ""))')" \
  '{arg: $arg, parent: $parent, targets: $targets, skipped: $skipped, notes: $notes}' \
  > "$PLAN_FILE"

jq -r --arg plan "$PLAN_FILE" --arg script_dir "$SCRIPT_DIR" '
  def pr_line: if .pr then "#\(.pr.number) (\(.pr.state)\(if .pr.isDraft then ", draft" else "" end)) — \(.pr.url)" else .pr_note end;
  def settings_lines(indent):
    if .settings_additions == null then "\(indent)\(if .settings_note != "" then .settings_note else "no changes" end)"
    else (.settings_additions
          | [paths(scalars) as $p | select(getpath($p[:-1]) | type != "array")
              | "\(indent)\($p | map(tostring) | join(".")): + \(getpath($p) | tojson)"]
          + [paths(type == "array") as $p | getpath($p)[] | "\(indent)\($p | map(tostring) | join(".")): + \(tojson)"]
          | join("\n"))
    end;
  def branch_label: if .branch == "" then "detached HEAD" else "branch \(.branch)" end;
  def sweep(kind; title):
    [.targets[] | select(.kind == kind)] as $t | [.skipped[] | select(.kind == kind)] as $s |
    "  \(title): \($t | length)",
    ($t[] | "    - \(.wt)  \(branch_label)  (\(.branches | length) branch(es))  PR \(pr_line)",
            (select(kind == "other-repo") | "      repo \(.parent)"),
            (select(kind == "other-repo") | settings_lines("      settings +"))),
    ($s[] | "    skipped: \(.wt) — \(.reason)");
  ([.targets[] | select(.kind == "primary")][0]) as $p |
  "About to clean up:", "",
  (if $p then
    "  Worktree:  \($p.wt)\(if $p.keep then "  (kept — locked)" else "" end)",
    (if $p.keep then "  Kept branch: \($p.branch)" else empty end),
    "  Branches to delete: \($p.branches | length)",
    ($p.branches[] | "    - \(.name)  (\(.reason))"),
    "  PR:        \($p | pr_line)",
    "", "  settings.local.json additions to merge into parent:",
    ($p | settings_lines("    ")),
    "", "  Bazel clean: \(if $p.bazel then "yes — bazel clean --expunge will run in the worktree" else "n/a" end)"
   else "  Primary target: none (invoked from the parent repo — sweep only)" end),
  (if .arg == "" then "", sweep("agent"; "Sub-agent worktrees to sweep"), "", sweep("other-repo"; "Other-repo worktrees to sweep") else empty end),
  (.notes[] | "", "  Note: \(.)"),
  ([.targets[] | select(((.pr_note | startswith("n/a")) | not) and (.pr.state // "") != "MERGED")] | if length > 0 then
    "", "⚠️  PR is not MERGED for: \(map(.wt | split("/") | last) | join(", ")). Cleanup deletes the local worktree and branches — the remote branch and PR remain. Continue only if you do not need a local checkout to keep iterating."
   else empty end),
  "", "Plan file: \($plan)",
  "Apply with: cd \(.parent) && \($script_dir)/apply.sh \($plan) [--merge-settings] [--exclude <worktree>]..."
' "$PLAN_FILE"
