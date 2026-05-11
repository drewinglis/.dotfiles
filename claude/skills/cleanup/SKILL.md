---
name: cleanup
description: >-
  After a PR is merged, clean up the local worktree, branch, and Claude
  session, and propose merging worktree-local .claude/settings.local.json
  changes back to the parent repo.
---

# Cleanup

Tear down everything that was set up for a now-merged PR: the git
worktree, the local branch, the Claude session(s), and reconcile any
worktree-local `.claude/settings.local.json` drift back into the parent
repo.

## Usage

```
/cleanup [<branch-or-worktree>]
```

- **No arg** → the skill assumes it's invoked from inside the worktree
  being cleaned up and infers everything from the current session.
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

Find the worktree where either:

- `branch refs/heads/<arg>` matches exactly, **or**
- the basename of the `worktree <path>` matches `<arg>` exactly.

If no match → abort:
> No worktree found matching `<arg>`. Run `git worktree list` to see
> available worktrees.

If the match resolves to `$PARENT` itself (the main worktree) → abort:
> `<arg>` resolves to the parent repo, not an auxiliary worktree.
> `/cleanup` is for tearing down worktrees only.

**If no argument was provided**:

Find the worktree whose path equals `git rev-parse --show-toplevel`
from CWD. If that path equals `$PARENT` → abort:
> No worktree specified, and the current directory is the parent
> repo. Either invoke `/cleanup` from inside the worktree, or pass
> `/cleanup <branch-or-worktree-name>` (recommended when you don't
> want to orphan this Claude Desktop session).

Set `$WT` to the matched worktree path and `$BR` to its branch name
(strip `refs/heads/` from the porcelain output).

#### 1.3 — Refresh PR state for the branch

Fetch the **current** PR state for `$BR` from GitHub. Cached session
metadata (`prState` from `list_sessions`) lags behind reality — a PR
that merged seconds ago can still appear OPEN. Always pull fresh.

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

### Step 2: Pre-flight safety check (read-only; abort on failure)

Only one check: the worktree must have no uncommitted/unstaged changes.

```
git -C $WT status --porcelain
```

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

### Step 3: Find sessions and compute settings diff (still read-only)

These two computations feed the summary in Step 4.

#### 3.1 — Sessions tied to this worktree

Call `mcp__ccd_session_mgmt__list_sessions` and filter results to those
whose project root path equals `$WT` (or whose encoded project dir
under `~/.claude/projects/` matches `$WT` with `/` and `.` replaced by
`-`).

Hold the list of session IDs for Step 8 and Step 10.

#### 3.2 — settings.local.json diff

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
  Branch:    $BR
  PR:        #<number> (<state><, draft if isDraft>) — <url>
             <or: "no PR found" / "unknown — <error>">

  Sessions to archive: <n>
    - <session-id-1> (<short label/timestamp if available>)
    - <session-id-2>
    ...
    <exclude the current session when running in the no-arg form;
     it will not be archived>


  settings.local.json additions to merge into parent:
    permissions.allow:
      + "Bash(...)"
      + "Bash(...)"
    permissions.deny:
      + "..."
    <or: "no changes">

  Bazel clean: <yes — `bazel clean --expunge` will run in $WT | n/a>

Proceed? (y/n)
```

If the PR state from Step 1.3 is anything other than `MERGED`, add
an explicit warning under the summary block:

> ⚠️  PR is still `<state>`. Cleanup deletes the local worktree and
> branch — the remote branch and PR on GitHub remain. Continue only
> if you don't need a local checkout to keep iterating.

Wait for an explicit affirmative. On no/anything-else, abort without
side effects.

### Step 5: Apply settings.local.json merge (if approved)

If the diff from Step 3.2 is non-empty:

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

### Step 6: Tear down the worktree

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

### Step 7: Delete the local branch

```
git -C $PARENT branch -D $BR
```

Use `-D` (force), not `-d`: most PRs are squash-merged, which produces
a different commit on the default branch than the local branch's tip,
so `git branch -d` will always refuse with "not fully merged" even
though the work is preserved on `main`. Since the user has explicitly
confirmed cleanup in Step 4 and the dirty-tree pre-flight in Step 2
caught any uncommitted work, `-D` is safe here.

### Step 8: Archive sessions tied to the worktree

**Never call `archive_session` with the literal session id `current`.**
That sentinel sometimes appears in the `list_sessions` output for the
live session and is not a valid argument to `archive_session`. Filter
any such entries out of the Step 3.1 list before doing anything else
in this step.

Archive every session in the filtered list via
`mcp__ccd_session_mgmt__archive_session` — **except the current
session, if it appears in the list**. When the no-arg form is used,
the current session is in the list (the skill is running inside the
worktree being torn down); skip it so the live session isn't killed
mid-skill. When invoked with an arg from a parent-repo session, the
current session isn't in the list, and all matched sessions are
archived.

### Step 9: Final report

Print a summary:

```
Cleanup complete:
  ✓ Worktree removed: $WT
  ✓ Branch deleted:   $BR
  ✓ Sessions archived: <n>
  ✓ Settings merged: <applied | declined | no-op>
  ✓ Bazel clean: <ran | failed: <error> | n/a>
```

When the no-arg form was used, append a final line reminding the
user that the current session was intentionally left running:

> Note: this session was not archived. Close it when you're done.
