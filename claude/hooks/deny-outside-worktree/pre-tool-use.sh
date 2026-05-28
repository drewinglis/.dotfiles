#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit.
#
# Denies the tool call when the target file lives outside the git worktree
# the session is running in. When the session is NOT inside a worktree
# (main checkout, or a non-git directory), the hook is a no-op.
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

# Not in a git repo → allow.
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
git_dir=$(git -C "$cwd" rev-parse --absolute-git-dir 2>/dev/null) || exit 0
common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir \
  2>/dev/null) || exit 0

# Main checkout (git_dir == common_dir) → no worktree in use → allow.
[[ "$git_dir" != "$common_dir" ]] || exit 0

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

abs_top=$(resolve_path "$top")
abs_file=$(resolve_path "$file")
[[ -n "$abs_top" && -n "$abs_file" ]] || exit 0

# Inside ~/.claude (harness-managed: plans/, projects/, sessions/, tasks/) → allow.
abs_claude=$(resolve_path "$HOME/.claude")
if [[ -n "$abs_claude" ]] && \
   [[ "$abs_file" == "$abs_claude" || "$abs_file" == "$abs_claude"/* ]]; then
  exit 0
fi

# Inside the worktree → allow.
if [[ "$abs_file" == "$abs_top" || "$abs_file" == "$abs_top"/* ]]; then
  exit 0
fi

# Outside the worktree → deny with a structured reason.
jq -nc \
  --arg reason "File '$abs_file' is outside the session worktree ('$abs_top'). Blocked by deny-outside-worktree hook." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse",
                          permissionDecision: "deny",
                          permissionDecisionReason: $reason}}'
exit 0
