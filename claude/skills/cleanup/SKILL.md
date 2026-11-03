---
name: cleanup
description: >-
  After a PR is merged, clean up the local worktree and every branch
  tied to the session (including auto-generated branches the rename
  hook orphaned), plus any worktrees the session created in other
  repos, and propose merging worktree-local
  .claude/settings.local.json changes back to the parent repo.
---

# Cleanup

Tear down everything that was set up for a now-merged PR: the git
worktree, every local branch tied to the session (the current branch
plus any auto-generated branches the `rename-auto-branch` hook
orphaned), sub-agent and other-repo worktrees the session created,
and worktree-local `.claude/settings.local.json` additions.

All resolution and teardown logic lives in two scripts next to this
file. Run them; do not reimplement their steps with ad-hoc git
commands.

## Usage

```
/cleanup [<branch-or-worktree>]
```

- **No arg** → the worktree containing the CWD is the primary target,
  and the session's sub-agent worktrees (`.claude/worktrees/agent-*`)
  and other-repo worktrees (see `~/.claude/working-in-other-repos.md`)
  are swept too. From the parent repo it runs sweep-only.
- **With arg** → a branch name (`drewinglis/focused-raman-2b7522`), a
  worktree basename (`focused-raman-2b7522`), or an absolute worktree
  path (works from any repo). Use this from a parent-repo session so
  that session is not orphaned when the worktree folder is deleted.
  Sweeps are skipped in this form.

## Instructions

1. **Plan** (read-only). Run, with the Bash tool:

   ```
   <base-directory>/plan.sh [<branch-or-worktree>]
   ```

   It prints the plan and the exact `apply.sh` command, and writes a
   plan JSON file. Exit 1 means no target could be resolved and exit 2
   means the primary worktree is dirty; in both cases relay the
   script's message verbatim and stop.

   If the conversation shows a branch of this session that the plan
   missed (a rename a recycled reflog lost), re-run with
   `--also-branch <name>`; it is filtered like every other candidate.

2. **Approve.** Show the plan output to the user unchanged, including
   any ⚠️ PR-state warning. Ask one question that covers everything:
   proceed, and, when the plan lists settings additions, whether to
   merge them into the parent too. Invite them to name sweep targets
   to exclude. Wait for an explicit yes; on anything else, stop
   without side effects.

3. **Apply.** Run the `Apply with:` command the plan printed, adding
   `--merge-settings` only if the user approved the settings merge and
   `--exclude <worktree>` for each target they excluded. Keep the
   leading `cd <parent>`: in the no-arg form the shell is inside the
   worktree being removed.

4. **Report.** Relay the script's `Cleanup complete:` block unchanged.
   A non-zero exit means something failed; the block names it
   (`✗` lines). Never retry `git worktree remove` with `--force` —
   ask the user how to proceed.

## What the scripts do

`plan.sh` resolves the parent repo and target worktree from
`git worktree list --porcelain`, keeps (rather than removes) a locked
primary worktree, fetches the branch's current PR state with `gh`
(GitHub origins) or `tea` (any other host), builds the branch set
from the current branch plus the rename chain in the worktree's HEAD
reflog plus the creation branch when the reflog confirms it or is
empty, keeps only branches that exist and are not checked out by
another worktree, computes an additions-only diff of the worktree's
`.claude/settings.local.json` over the parent's (primary and other-repo
targets only; sub-agent settings are never merged), and detects Bazel
marker files. Sweeps use the session's transcript directory
(`~/.claude/projects/<encoded-cwd>/$CLAUDE_CODE_SESSION_ID`) as the
ownership record; dirty or locked sweep targets are skipped and reported.

`apply.sh` runs `bazel clean --expunge` where applicable, `git
worktree remove` (never forced) and `prune`, `git branch -D` for each
planned branch, and the settings merge when asked. Failures are
reported per target and the rest continues.
