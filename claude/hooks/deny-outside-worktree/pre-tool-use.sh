#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit.
#
# Denies the tool call when the target file belongs to the same git repository
# as the session worktree but lives outside that worktree (e.g. the main
# checkout or a sibling worktree). Files in unrelated repositories or non-git
# paths are allowed, as are all files when the session is NOT inside a worktree
# (main checkout, or a non-git directory).
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

# Inside the worktree → allow.
if [[ "$abs_file" == "$abs_top" || "$abs_file" == "$abs_top"/* ]]; then
  exit 0
fi

# Outside the worktree. Only block when the file belongs to the SAME git
# repository as the session (shares its common git dir) — e.g. the main
# checkout or a sibling worktree. Edits to unrelated repos or non-repo paths
# are allowed. Walk up to the nearest existing directory so new (not-yet-
# created) files resolve to a directory git can inspect.
file_dir=$abs_file
while [[ ! -d "$file_dir" && "$file_dir" != "/" ]]; do
  file_dir=$(dirname "$file_dir")
done
file_common_dir=$(git -C "$file_dir" rev-parse --path-format=absolute \
  --git-common-dir 2>/dev/null) || exit 0

# Different repository (or not a repo) → allow.
[[ "$(resolve_path "$file_common_dir")" == "$(resolve_path "$common_dir")" ]] \
  || exit 0

# Same repository, outside the worktree → deny with a structured reason.
jq -nc \
  --arg reason "File '$abs_file' is outside the session worktree ('$abs_top') but in the same repository. Blocked by deny-outside-worktree hook." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse",
                          permissionDecision: "deny",
                          permissionDecisionReason: $reason}}'
exit 0
