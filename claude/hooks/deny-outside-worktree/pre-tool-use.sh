#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit.
#
# Denies the tool call when the target file belongs to the same git repository
# as the session worktree but lives outside that worktree (e.g. the main
# checkout or a sibling worktree), or when it lives in the main checkout of a
# different repository (see ~/.claude/working-in-other-repos.md). Files in
# other repositories' worktrees and non-git paths are allowed. When the session
# is NOT inside a worktree, files in the session's own repository are allowed.
#
# Fails open: any unexpected error (missing field, git failure, python
# failure) allows the tool through rather than blocking editing entirely.

set -uo pipefail

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
file=$(printf '%s' "$input" \
  | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

# Missing required fields → allow.
[[ -n "$cwd" && -n "$file" ]] || exit 0

# Resolve symlinks + relative paths against $cwd. BSD realpath (macOS)
# rejects non-existent paths, so we walk up to the first existing
# ancestor, realpath that, and reattach the unresolved tail.
resolve_path() {
  local p="$1" tail="" parent
  [[ "$p" = /* ]] || p="$cwd/$p"
  while [[ ! -e "$p" && "$p" != "/" ]]; do
    tail="/$(basename "$p")$tail"
    parent=$(dirname "$p")
    [[ "$parent" == "$p" ]] && break
    p="$parent"
  done
  local head
  if [[ -e "$p" ]]; then
    head=$(realpath -- "$p" 2>/dev/null) || head="$p"
  else
    head="$p"
  fi
  printf '%s%s' "$head" "$tail"
}

abs_file=$(resolve_path "$file")
[[ -n "$abs_file" ]] || exit 0

# Inside ~/.claude (harness-managed: plans/, projects/, sessions/, tasks/) → allow.
# ~/.claude is a symlink into this dotfiles repo, so realpath resolves it to
# a path without a literal `.claude` segment — matched here by prefix, not by
# the segment check below.
abs_claude=$(resolve_path "$HOME/.claude")
if [[ -n "$abs_claude" ]] && \
   [[ "$abs_file" == "$abs_claude" || "$abs_file" == "$abs_claude"/* ]]; then
  exit 0
fi

# Inside any .claude directory → allow, even when it sits outside the session
# worktree (e.g. the parent checkout's .claude/settings.local.json).
if [[ "$abs_file" == *"/.claude" || "$abs_file" == *"/.claude/"* ]]; then
  exit 0
fi

# Walk up to the nearest existing directory so new (not-yet-created) files
# resolve to a directory git can inspect.
file_dir=$abs_file
while [[ ! -d "$file_dir" && "$file_dir" != "/" ]]; do
  file_dir=$(dirname "$file_dir")
done

# Not in a git repo → allow.
file_git_dir=$(git -C "$file_dir" rev-parse --absolute-git-dir 2>/dev/null) \
  || exit 0
file_common_dir=$(git -C "$file_dir" rev-parse --path-format=absolute \
  --git-common-dir 2>/dev/null) || exit 0

# The session's repository comes from the project dir, not $cwd, so that
# cd-ing into another repo's checkout doesn't make it look like the session's.
session_dir=${CLAUDE_PROJECT_DIR:-$cwd}
common_dir=$(git -C "$session_dir" rev-parse --path-format=absolute \
  --git-common-dir 2>/dev/null) || common_dir=""

# Different repository: deny only its main checkout (git dir == common dir).
if [[ -z "$common_dir" ]] || \
   [[ "$(resolve_path "$file_common_dir")" != "$(resolve_path "$common_dir")" ]]
then
  [[ "$file_git_dir" == "$file_common_dir" ]] || exit 0
  jq -nc \
    --arg reason "File '$abs_file' is in the main checkout of another repository. Create a worktree for it as described in ~/.claude/working-in-other-repos.md. Blocked by deny-outside-worktree hook." \
    '{hookSpecificOutput: {hookEventName: "PreToolUse",
                            permissionDecision: "deny",
                            permissionDecisionReason: $reason}}'
  exit 0
fi

top=$(git -C "$session_dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
git_dir=$(git -C "$session_dir" rev-parse --absolute-git-dir 2>/dev/null) \
  || exit 0

# Session is in its main checkout (git_dir == common_dir) → no worktree in use
# → allow.
[[ "$git_dir" != "$common_dir" ]] || exit 0

# Inside the worktree → allow.
abs_top=$(resolve_path "$top")
if [[ "$abs_file" == "$abs_top" || "$abs_file" == "$abs_top"/* ]]; then
  exit 0
fi

# Same repository, outside the worktree → deny with a structured reason.
jq -nc \
  --arg reason "File '$abs_file' is outside the session worktree ('$abs_top') but in the same repository. Blocked by deny-outside-worktree hook." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse",
                          permissionDecision: "deny",
                          permissionDecisionReason: $reason}}'
exit 0
