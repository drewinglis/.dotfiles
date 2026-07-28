---
name: cleanup
description: >-
  After a PR is merged, clean up the local worktree and every branch
  tied to the session (including auto-generated branches the rename
  hook orphaned), and propose merging worktree-local
  .claude/settings.local.json changes back to the parent repo.
---

# Cleanup

Tear down everything that was set up for a now-merged PR: the git
worktree, every local branch tied to the session (the worktree's
current branch plus any auto-generated branches the `rename-auto-branch`
hook orphaned), and reconcile any worktree-local
`.claude/settings.local.json` drift back into the parent repo.

## Usage

```
/cleanup [<branch-or-worktree>]
```

- **No arg** → the skill assumes it's invoked from inside the worktree
  being cleaned up and infers everything from the current session. It
  ALSO sweeps up sub-agent worktrees (`.claude/worktrees/agent-*`,
  left behind by Agent-tool runs with `isolation: "worktree"`) — see
  Step 1.5. Invoked from the parent repo with no arg, it runs in
  sweep-only mode: no primary target, just the agent worktrees.
- **With arg** → `<branch-or-worktree>` is either a full branch name
  (e.g. `drewinglis/focused-raman-2b7522`) or the basename of a
  worktree directory (e.g. `focused-raman-2b7522`). Use this form when
  invoking from a parent-repo Claude Desktop session, so your session
  doesn't get orphaned when the worktree folder is deleted.

The skill aborts cleanly if it can't resolve a target worktree, or if
the working tree has uncommitted changes.

## Instructions

### Step 1: Resolve context (read-only)

The CWD must be inside some clone of the target repo (either the
parent or any of its worktrees). Always derive the parent repo path
and target worktree from `git worktree list --porcelain`.

#### 1.1 — Parent repo path

```
git rev-parse --path-format=absolute --git-common-dir
```

`$PARENT` = `dirname` of that output, as an absolute path. (If the
command fails, CWD isn't in a git repo — abort with that message.)

#### 1.2 — Target worktree

Run `git worktree list --porcelain`. The output is a sequence of
records, each with `worktree <path>`, `HEAD <sha>`, and
`branch refs/heads/<name>` lines.

**If an argument was provided** (`/cleanup <arg>`):

Find the worktree where any of these match:

- `branch refs/heads/<arg>` matches exactly, **or**
- the basename of the `worktree <path>` matches `<arg>` exactly, **or**
- `<arg>`, after stripping any leading `drewinglis/`, matches the
  basename of the `worktree <path>` exactly.

The third rule handles the `rename-auto-branch` case: the worktree was
created on branch `drewinglis/<basename>`, then the hook renamed it to
a human-friendly slug via `git checkout -b`. The worktree's *current*
branch is now the slug, so passing the **original** auto branch name
(`/cleanup drewinglis/nice-jemison-08d72d`) would otherwise fail to
resolve — but its basename still matches the worktree directory.

If no match → abort:
> No worktree found matching `<arg>`. Run `git worktree list` to see
> available worktrees.

If the match resolves to `$PARENT` itself (the main worktree) → abort:
> `<arg>` resolves to the parent repo, not an auxiliary worktree.
> `/cleanup` is for tearing down worktrees only.

**If no argument was provided**:

Find the worktree whose path equals `git rev-parse --show-toplevel`
from CWD; that is the **primary target** — set `$WT` to its path and
`$BR` to its branch name (strip `refs/heads/` from the porcelain
output). If that path equals `$PARENT`, there is **no primary
target** — continue in sweep-only mode (Step 1.5 may still find
agent worktrees). Abort only if Step 1.5 then finds nothing either:
> No worktree specified, the current directory is the parent repo,
> and there are no sub-agent worktrees to sweep. Pass
> `/cleanup <branch-or-worktree-name>` to target a specific worktree.

#### 1.3 — Refresh PR state for the branch

Only applicable if the `origin` remote is GitHub. Check first:

```
git -C $WT remote get-url origin
```

If this fails (no `origin` remote), or the URL host isn't
`github.com` (covers `https://github.com/...`,
`git@github.com:...`, and GitHub Enterprise isn't assumed unless the
host literally is `github.com`), skip this step entirely and record
"PR state: n/a — origin is not GitHub" for Step 4.

Otherwise, fetch the **current** PR state for `$BR` from GitHub.
Cached session metadata (`prState` from `list_sessions`) lags behind
reality — a PR that merged seconds ago can still appear OPEN. Always
pull fresh.

```
( cd $WT && gh pr list --head $BR --state all \
    --json number,state,url,isDraft,mergedAt --jq '.[0]' )
```

`--state all` is required to surface MERGED and CLOSED PRs;
the `gh pr` default is `open` only.

Cases:

- **Returns a PR object** → capture `number`, `state` (`OPEN`,
  `MERGED`, `CLOSED`), `url`, `isDraft`, `mergedAt`. Hold for Step 4.
- **Returns empty/null** → record "no PR found" for Step 4.
- **`gh` errors** (auth, network, etc.) → record
  "PR state: unknown — \<error\>" for Step 4 and continue.

Never abort on this step. The PR state is informational — the user's
explicit approval in Step 4 is the safety gate. The refresh ensures
the plan summary reflects the *current* state (e.g. just-merged), not
stale session metadata or conversation context.

#### 1.4 — All branches tied to the worktree

`$BR` (the worktree's *current* branch) is often **not** the only
branch that belongs to this session. The `rename-auto-branch` hook
renames a session's branch with `git checkout -b drewinglis/<slug>`,
which creates a new branch and switches the worktree to it but **leaves
the original auto-generated branch behind**. So the original
`drewinglis/<adjective>-<surname>-<hex>` branch (and any intermediate
renames) linger as orphaned local refs that earlier cleanups, which
deleted only `$BR`, never reaped.

Build `$BRANCHES` — the set of local branches to delete — by unioning
three sources:

1. **Current branch** — `$BR` (from Step 1.2).
2. **Original auto branch reconstructed from the worktree name** —
   Claude Code creates each worktree at `<repo>/.claude/worktrees/<name>`
   on branch `drewinglis/<name>`, so the original branch is
   `drewinglis/$(basename "$WT")`. This recovers the original even if
   the reflog (source 3) has been pruned.
3. **Rename chain from the worktree's HEAD reflog** — each
   `git checkout -b` records a
   `checkout: moving from <old> to <new>` reflog entry:

   ```
   git -C "$WT" reflog --format='%gs' \
     | sed -n 's/^checkout: moving from \(.*\) to \(.*\)$/\1 -> \2/p'
   ```

   Do **not** take every branch name that appears. Walk the entries
   newest-first and keep only the contiguous chain that ends at
   `$BR`: seed the chain with `{$BR}`; for each entry whose "to"
   name is already in the chain, add its "from" name. Stop extending
   the chain when the links break (an entry whose "to" is not
   already in the chain) or when the chain reaches the worktree's
   original creation branch (the source-2 name:
   `drewinglis/<worktree-basename>`, or `worktree-agent-<basename>`
   for agent worktrees). This still catches multi-rename chains
   (auto → slug → slug2), including orphaned intermediate slugs
   that don't match the auto pattern.

   ⚠️ **Recycled worktree slots:** Claude Code reuses worktree slot
   paths (e.g. `.claude/worktrees/vigorous-lamarr-4576d9`) across
   sessions, and a recycled slot's HEAD reflog retains checkout
   entries from previous occupant sessions. Those branches often
   still exist locally and are checked out nowhere, so the
   keep-filters below do NOT exclude them — taking the raw reflog
   would force-delete other sessions' branches in Step 7. Anything
   in the reflog beyond the chain boundary above belongs to a
   previous occupant and must never become a deletion candidate.

   Recycling can also leave the chain **incomplete**: a rename made
   before the slot was recycled may not appear in the new reflog at
   all. The executing agent MAY add a branch it positively knows
   belongs to the current session from its own conversation
   history, recording that provenance ("recovered from session
   history") in the Step 4 plan like the other per-branch reasons.

Then **keep a candidate only if all hold** (so the set is safe to
force-delete):

- It exists locally:
  `git -C "$PARENT" show-ref --verify --quiet refs/heads/<name>`.
  (Drops detached-HEAD SHAs that the reflog may surface.)
- It is **not** checked out by another worktree. From
  `git worktree list --porcelain`, collect every `branch refs/heads/<x>`
  whose `worktree <path>` is **not** `$WT`, and exclude those names.
  This protects the parent repo's branch (e.g. `main`) and any sibling
  worktree's branch.

`$BR` always survives these filters (it's checked out by `$WT` itself,
not another worktree). If filtering somehow leaves the set empty, fall
back to `{$BR}`. Record, per branch, why it's included (current /
original-auto / rename-chain / recovered from session history) for
the Step 4 summary. Hold `$BRANCHES` for Step 4 and Step 7.

#### 1.5 — Sub-agent worktree sweep (no-arg form only)

Agent-tool runs with `isolation: "worktree"` leave their worktrees
behind whenever they committed anything (the harness auto-removes
only unchanged ones). Sweep them up alongside the primary target:

**Only sweep sub-agents spawned by the CURRENT session** — other
live sessions may have their own agent worktrees in flight. The
ownership record is the session's subagents directory:

```
~/.claude/projects/<encoded-project-dir>/<session-id>/subagents/
```

where `<encoded-project-dir>` is the session's project root path
with `/` and `.` replaced by `-`, and `<session-id>` is the current
session's UUID (it appears as a path component of the session
scratchpad directory). That folder contains `agent-<id>.jsonl` for
exactly the agents this session spawned.

From the Step 1.2 `git worktree list --porcelain` output, collect
every worktree whose path matches `$PARENT/.claude/worktrees/agent-*`
(excluding `$WT` itself if the primary happens to be one), then
**keep only those whose basename `agent-<id>` has a matching
`agent-<id>.jsonl` in the current session's `subagents/` directory**.
Agent worktrees owned by other sessions are ignored entirely — no
mention in the plan or report. If the subagents directory can't be
located, sweep nothing and say so — don't fall back to sweeping
unowned worktrees. For each owned target, build the same tuple as
the primary: PR state per Step 1.3 and `$BRANCHES` per Step 1.4.

Notes specific to agent worktrees:

- They are created on branch `worktree-agent-<id>` (basename of the
  worktree path), NOT `drewinglis/<basename>` — so Step 1.4's
  source 2 reconstruction won't exist for them (harmless; it gets
  filtered), and the original branch is instead
  `worktree-agent-$(basename "$WT")` plus whatever the reflog chain
  (source 3) surfaces. Add `worktree-agent-<basename>` as an extra
  source-2-style candidate for these targets.
- A **dirty** agent worktree (uncommitted changes) is NOT an abort:
  exclude it from the sweep, and list it in the Step 4 plan under
  "skipped (dirty)" so the user knows it needs manual attention.
- Removing an agent worktree discards the ability to resume that
  agent by ID with its worktree context — fine once its PR is
  merged/closed, worth the ⚠️ warning otherwise.

Hold the sweep targets (each with its own `$WT`/`$BR`/`$BRANCHES`/PR
state) for Steps 4, 6, and 7. In the arg form, this step is skipped
entirely — the arg names one worktree, agent or otherwise.

### Step 2: Pre-flight safety check (read-only; abort on failure)

Only one check: the worktree must have no uncommitted/unstaged changes.

```
git -C $WT status --porcelain
```

This abort applies to the **primary target only**; dirty sweep
targets from Step 1.5 are excluded and reported, never fatal.

Must produce no output. If any lines come back, abort:

> Worktree has uncommitted/unstaged changes. Commit, stash, or discard
> them before running `/cleanup`. Output:
>
> ```
> <git status --porcelain output>
> ```

This is intentionally the only pre-flight check. Step 1.3 surfaces
the PR state in Step 4 for visibility, but it never aborts: the
merge check is too easy to get wrong (auto-deleted head branches,
squash-merges, just-merged-but-not-yet-synced, etc.). The user's
explicit approval in Step 4 is the real safety gate.

### Step 3: Compute settings diff (still read-only)

This computation feeds the summary in Step 4.

Read both files using the **Read** tool:

- `$WT/.claude/settings.local.json` (worktree)
- `$PARENT/.claude/settings.local.json` (parent)

If either is missing, treat it as `{}`. If both are missing or the
parsed JSON is identical, record "no changes" and skip the merge step
in Step 5.

Otherwise, compute **additions only** — entries present in worktree
but not parent:

- For object keys at any nesting level: any key in worktree but not
  parent → propose to add.
- For array values (most importantly `permissions.allow` and
  `permissions.deny`): any element in the worktree array but not the
  parent array → propose to append.
- **Never propose deletions or modifications** to existing parent
  values. This is a propose-only-additions diff.

Hold the proposed additions for Step 4 and Step 5.

### Step 4: Show plan and gather approval

Print a single summary block to the user:

```
About to clean up:

  Worktree:  $WT
  Branches to delete: <n>
    - $BR  (current)
    - drewinglis/<original>  (original auto branch — orphaned by rename)
    - drewinglis/<slug>      (rename-chain — orphaned)
    ...
  PR:        #<number> (<state><, draft if isDraft>) — <url>
             <or: "no PR found" / "unknown — <error>">

  settings.local.json additions to merge into parent:
    permissions.allow:
      + "Bash(...)"
      + "Bash(...)"
    permissions.deny:
      + "..."
    <or: "no changes">

  Bazel clean: <yes — `bazel clean --expunge` will run in $WT | n/a>

  Sub-agent worktrees to sweep: <n>
    - agent-<id>  branch <br> (+ worktree-agent-<id>)  PR #<n> <state>
    ...
    skipped (dirty): agent-<id> — <m> uncommitted files
    <or: "none found" — omit the section in the arg form>

Proceed? (y/n)
```

The single approval covers the primary target AND all listed sweep
targets; invite the user to name any sweep targets to exclude
before confirming.

If the PR state for the primary target or any sweep target is
anything other than `MERGED` or `n/a` (non-GitHub origin), add an
explicit warning under the summary block:

> ⚠️  PR is still `<state>`. Cleanup deletes the local worktree and
> branches — the remote branch and PR on GitHub remain. Continue only
> if you don't need a local checkout to keep iterating.

Wait for an explicit affirmative. On no/anything-else, abort without
side effects.

### Step 5: Apply settings.local.json merge (if approved)

If the diff from Step 3 is non-empty:

1. Re-confirm with the user that they want the proposed additions
   applied to the parent file. (The Step 4 summary already showed the
   list, but settings drift can be sensitive — e.g. a worktree-only
   permission may have been intentional.)
2. If approved: read the parent `$PARENT/.claude/settings.local.json`
   again (in case it changed), apply the additions in-place using the
   **Edit** tool where possible (append entries to the relevant arrays;
   add new top-level keys with their full subtree). If the file
   structure makes targeted edits awkward, fall back to **Write** with
   the merged JSON, preserving 2-space indentation.
3. If the user declines: skip — do not block the rest of the cleanup.

### Step 6: Tear down the worktree(s)

Run 6.1–6.2 for the primary target, then repeat for every approved
sweep target from Step 1.5. Step 7 likewise loops over each target's
`$BRANCHES` after its worktree is removed. If one sweep target fails
to tear down, report it and continue with the rest.

#### 6.1 — Bazel clean (if applicable)

If the worktree uses Bazel — i.e. any of `WORKSPACE`,
`WORKSPACE.bazel`, or `MODULE.bazel` exists at `$WT` root — run:

```
( cd $WT && bazel clean --expunge )
```

This shuts down the worktree's Bazel server and reclaims its output
base (often many GB on disk). It can take several seconds. Different
worktrees have separate output bases keyed by workspace path, so this
won't touch the parent repo's outputs.

If `bazel` is not on PATH or the command fails, surface the error
but **do not abort** — proceed to 6.2. Disk cleanup is a nice-to-have;
worktree removal is the load-bearing step.

Skip this entire substep when no Bazel marker file is present.

#### 6.2 — Remove the worktree

If the current working directory is inside `$WT`, `cd $PARENT` first
— otherwise `git worktree remove` will fail or leave the shell in a
deleted directory. (Only matters when invoked with no arg; when the
arg form is used from a parent-repo session, CWD is already outside
`$WT`.)

```
git -C $PARENT worktree remove $WT
```

If this fails (e.g. leftover state), surface the error verbatim and
stop — do **not** auto-pass `--force`. Ask the user how to proceed.

After successful removal:

```
git -C $PARENT worktree prune
```

(cleans up the `.git/worktrees/<name>` admin entry).

### Step 7: Delete the local branches

Delete **every** branch in `$BRANCHES` (from Step 1.4), not just `$BR`.
This is the step that reaps the original auto branch the
`rename-auto-branch` hook orphaned. Run one delete per branch:

```
for br in $BRANCHES; do git -C $PARENT branch -D "$br"; done
```

Use `-D` (force), not `-d`: most PRs are squash-merged, which produces
a different commit on the default branch than the local branch's tip,
so `git branch -d` will always refuse with "not fully merged" even
though the work is preserved on `main`. Since the user has explicitly
confirmed cleanup in Step 4 and the dirty-tree pre-flight in Step 2
caught any uncommitted work, `-D` is safe here.

The worktree must already be removed (Step 6.2) before deleting `$BR` —
git refuses to delete a branch still checked out by a live worktree.
If an individual delete fails, surface the error for that branch and
continue with the rest; report which branches were deleted and which
failed in Step 8 rather than aborting the whole cleanup.

### Step 8: Final report

Print a summary:

```
Cleanup complete:
  ✓ Worktree removed: $WT
  ✓ Branches deleted: <n> — <br1>, <br2>, ...
    <list any that failed to delete, with the error>
  ✓ Settings merged: <applied | declined | no-op>
  ✓ Bazel clean: <ran | failed: <error> | n/a>
  ✓ Sub-agent worktrees swept: <n> — agent-<id1>, agent-<id2>, ...
    <per-target failures and dirty-skips listed here>
```
