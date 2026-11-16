---
name: wait-for-ci
description: Wait for CI on a pushed commit to finish, on either a GitHub or a Gitea remote, using a tested poll script instead of a hand-written loop. Use whenever you need to wait for checks, workflows, Gitea Actions, or post-merge statuses such as deploys to complete — after pushing a branch, before merging, or on a merge commit on main — and for phrases like "wait for CI", "poll until green", "let me know when the checks finish", or "watch the apply".
---

# wait-for-ci

Don't write your own poll loop. Run `poll.sh`, a sibling of this file. It
works out the forge from the git remote, confirms the commit is on the remote,
and polls the commit's statuses (plus check-runs on GitHub) until everything
finishes. It exits loudly on API errors and when no checks ever show up, so a
broken check can't look like "still pending".

## Usage

```bash
<skill-dir>/poll.sh [-r REMOTE] [-t MAX_SECONDS] [-g GRACE_SECONDS] [-i INTERVAL] [REF]
```

| Flag | Default | Meaning |
|---|---|---|
| `REF` | `HEAD` | Any commit-ish. Resolved to a SHA once, locally. |
| `-r` | `origin` | Remote whose host picks the forge. |
| `-t` | `1800` | Give up after this many seconds. |
| `-g` | `300` | Exit 3 if no check has appeared after this long. |
| `-i` | `30` | Seconds between polls. |

Run it from inside the repo. Use `run_in_background: true` for anything that
may take more than a minute or two, then end the turn; the harness wakes you
when it exits. Don't sleep or poll the task in the meantime.

Exit codes:

- `0`: every check passed.
- `1`: a check failed. The script exits on the first failure without waiting
  for the rest, and prints the failed and still-pending checks.
- `2`: deadline reached with checks still pending.
- `3`: no checks reported within the grace period. Either this commit doesn't
  trigger CI, or nothing has picked it up yet.
- `4`: error: bad remote or ref, commit not pushed, unknown forge, or three
  poll errors in a row. The error text is on stderr.

Report the outcome to the user with the script's output. For a non-zero exit,
show the failing or pending checks; don't summarize them away.

## Forges

- **github.com** uses `gh api`: combined commit statuses plus check-runs,
  paginated.
- **Any other host** goes through the `tea` login whose URL host or SSH host
  matches the remote, so a separate SSH host still finds the right login.
  It reads the combined `/status`, which already collapses each context
  to its latest state, so older pending entries don't count.

## Notes

- **Post-merge statuses** (deploys, applies, and other bots that report on
  main) land on the **merge commit**, not the PR. To wait for them, run
  `git fetch origin && poll.sh origin/main`. They are included automatically,
  but they can show up after the Actions checks have passed, so if you need a
  specific one, confirm its context is in the output.
- A commit that doesn't touch anything CI watches (e.g. some Renovate bumps)
  gets no statuses at all and exits 3. That's expected, not a failure. Say so.
- Because the commit has to exist on the remote, push before polling.
- If the script itself seems wrong, run one poll with `-t 0` and read the
  output. Don't wrap it in another loop.
