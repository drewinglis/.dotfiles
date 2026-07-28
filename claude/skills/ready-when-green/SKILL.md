---
name: ready-when-green
description: Poll a GitHub PR's CI once per minute and automatically mark it ready for review when CI is clean, giving up after a configurable maximum wait (default 1h). Use this skill whenever the user wants to defer a PR's ready-for-review flip until CI finishes — phrases like "mark this ready when CI is green", "wait for CI then take it out of draft", "mark ready when checks pass", or any variation that ties readiness to CI status. Defaults to a 1 hour maximum and the current branch's PR.
---

# ready-when-green

Poll a PR's CI once per minute in a detached background script. As soon as every
check has passed, mark the PR ready for review. If any check fails, or the
maximum wait elapses with checks still pending, leave it draft and report why.

## Workflow

1. **Resolve the PR number.**
   - If the user gave a bare integer argument (e.g. `63540`), use it.
   - Otherwise infer from the current branch:
     ```bash
     gh pr view --json number --jq .number
     ```
     If no PR exists for the current branch, stop and tell the user — there is
     nothing to poll.

2. **Resolve the maximum wait.**
   - Parse a duration argument: `20m`, `45min`, `1h`, `1hr`, `2h` all work.
   - Default to `3600` seconds (1 hour) if no duration is given.
   - Minimum 60 seconds. There is no upper cap — the poll runs as a detached
     script, not a scheduled wakeup.

3. **Sanity check the PR.**
   ```bash
   gh pr view <PR> --json isDraft,state,headRefName
   ```
   - Confirm the PR exists.
   - If `isDraft` is `false`, stop and tell the user — the PR is already ready
     for review, so there is nothing to poll for.

4. **Resolve keep-going.** By default the script exits on the first failed
   check. If the user indicates red CI may recover — they say auto-fix is
   enabled on the PR, mention Claude will push fixes, or ask to keep going /
   keep waiting on red — set `KEEP_GOING` to `true`, and the script polls
   through failures until the deadline. There is no way to detect the
   auto-fix setting programmatically, so only enable this when the user says
   so; when in doubt, leave it off.

5. **Launch the poll script** — `poll.sh`, a sibling of this SKILL.md — with
   the Bash tool and `run_in_background: true`:

   ```bash
   <path-to-this-skill-directory>/poll.sh <PR> <MAX_SECONDS> [KEEP_GOING]
   ```

   The script relies on `gh pr checks` exit codes: `0` = all checks passed
   (SUCCESS/NEUTRAL/SKIPPED), `8` = checks still pending, anything else =
   failed checks or an error (including a PR with no checks at all).

6. **Report to the user** in one or two sentences: which PR, that CI is being
   polled once per minute (and whether keep-going is on), the give-up deadline
   (clock time), and that the PR will be flipped to ready automatically. Then
   end the turn — do NOT sleep, poll the task, or schedule wakeups; the
   harness re-invokes you when the script exits.

7. **When the completion notification arrives**, read the script output and
   report the outcome in 2-3 sentences: marked ready (exit 0), CI failed with
   the offending checks (exit 1), deadline reached with CI still pending or
   red (exit 2), or cancelled because someone marked the PR ready out of band
   (exit 3). An "already marked as ready" error from `gh pr ready` is benign —
   surface it briefly and move on.

## Argument parsing

The skill accepts up to two positional arguments in any order. A bare integer
is treated as a PR number; anything with a time-unit suffix is treated as the
maximum wait.

| Invocation | PR | Max wait |
|---|---|---|
| `/ready-when-green` | current branch | 1 h |
| `/ready-when-green 20m` | current branch | 20 min |
| `/ready-when-green 63540` | 63540 | 1 h |
| `/ready-when-green 63540 45m` | 63540 | 45 min |
| `/ready-when-green 2h 63540` | 63540 | 2 h |

Keep-going is not positional — it is inferred from the user's phrasing
(step 4), e.g. `/ready-when-green 2h, auto-fix is on so don't bail on red`.

## Notes

- Polling and the ready flip both happen inside the deterministic script; the
  model is only involved at launch and at exit.
- By default the script stops at the first failed check rather than waiting
  out the deadline — a red CI run won't turn green on its own. `KEEP_GOING`
  exists for PRs where it can (auto-fix pushes new commits, which reset the
  checks to pending).
- Each iteration first checks the PR's draft status; if someone marks it ready
  out of band, the poll cancels itself instead of racing the human. A transient
  error on that draft check (e.g. network) is ignored and the loop continues.
- The skill does not push commits or modify the branch — it only flips the
  PR's draft status when CI is clean.
