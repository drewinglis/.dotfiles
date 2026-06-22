#!/usr/bin/env bash
# UserPromptSubmit hook — rename auto-generated worktree branches.
#
# When the session sits on an auto-generated branch (Docker namesgenerator
# style: drewinglis/<adjective>-<surname>-<6 hex>, e.g.
# drewinglis/goofy-ptolemy-6a6741), inject a directive telling Claude to rename
# the branch to a slug derived from the current prompt before doing anything
# else.
#
# Fires on every prompt but self-silences once renamed: the guard only matches
# the auto pattern, so after the rename it emits nothing. Hand-named branches
# under drewinglis/ (e.g. drewinglis/pr-transforms) never match. The pattern
# mirrors bin/auto-branches.
#
# Fails open: any missing field or git error exits 0 with no output.

set -uo pipefail

# Anchored both ends so a hand-named branch can't partially match.
AUTO_BRANCH_RE='^drewinglis/[a-z]+-[a-z]+-[a-f0-9]{6}$'

input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')

# No cwd → nothing to inspect.
[[ -n "$cwd" ]] || exit 0

# Not a git repo → git fails; detached HEAD → empty branch. Either way, skip.
branch=$(git -C "$cwd" branch --show-current 2>/dev/null) || exit 0
[[ -n "$branch" ]] || exit 0

# Hand-named or already-renamed branch → emit nothing.
[[ "$branch" =~ $AUTO_BRANCH_RE ]] || exit 0

context="This session is on an auto-generated worktree branch: \`${branch}\`. "
context+="Before responding to this prompt, rename the branch to a short "
context+="kebab-case slug derived from it — run "
context+="\`git checkout -b drewinglis/<slug>\`, keeping the \`drewinglis/\` "
context+="prefix — then proceed with the request."

jq -nc --arg ctx "$context" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit",
                         additionalContext: $ctx}}'
exit 0
