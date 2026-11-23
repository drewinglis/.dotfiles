---
name: wait-for-gonfalon-deploy
description: Wait for a launchdarkly/gonfalon commit (or a later one) to be deployed to an environment such as production or federal production, using a tested poll script instead of a hand-written loop. Use whenever you need to know when a merged gonfalon change is live, and for phrases like "let me know when this is deployed to production", "wait for the gonfalon deploy", "has this commit reached federal production", "tell me when my PR is in prod", or "is this live in EU yet".
---

# wait-for-gonfalon-deploy

Don't write your own poll loop. Run `poll.sh`, a sibling of this file. It
reads the environment's public, unauthenticated `/api/status` endpoint, whose
`.version` is the short SHA of the gonfalon backend being served, and asks
GitHub whether that version is the commit or a descendant of it. It runs from
any directory and needs only `gh`, `curl` and `jq`.

Each poll takes five samples and all five must contain the commit. A
blue/green deploy serves the old and new versions side by side for about ten
minutes, so a single matching sample doesn't mean the deploy has finished.

## Workflow

1. **Resolve the commit.** It must be a commit on gonfalon `main`.
   - A SHA (short or full): use it as is.
   - A PR URL or number: look up its merge commit.
     ```bash
     gh pr view <PR> --repo launchdarkly/gonfalon --json state,mergeCommit --jq '.state, .mergeCommit.oid'
     ```
     If the state isn't `MERGED`, stop and say so. There is nothing to wait
     for yet. Don't use the PR's head commit: squash merges leave it off
     `main`, and the script rejects it.
   - "This" with no PR or SHA: the current branch's PR, if the repo is
     gonfalon. Otherwise ask.

2. **Resolve the environments** from the table below. If the user names
   several ("production and then federal"), start one poll per environment so
   each reports on its own.

3. **Launch `poll.sh`** with the Bash tool and `run_in_background: true`, one
   call per environment:

   ```bash
   <skill-dir>/poll.sh [-t MAX_SECONDS] [-i INTERVAL] ENVIRONMENT COMMIT
   ```

   | Flag | Default | Meaning |
   |---|---|---|
   | `ENVIRONMENT` | required | A name from the table below, or a full `https://…/api/status` URL. |
   | `COMMIT` | required | The commit to wait for. Resolved to a full SHA once, against GitHub. |
   | `-t` | `14400` | Give up after this many seconds. |
   | `-i` | `120` | Seconds between polls. |

4. **Tell the user** in a sentence or two which commit and environments are
   being polled and when each poll gives up (clock time). Then end the turn.
   The harness wakes you when a script exits, so don't sleep or poll the task
   in the meantime.

5. **When a poll exits**, report that environment's outcome with the script's
   output:
   - `0`: deployed. Give the version now being served.
   - `2`: deadline reached and the commit isn't deployed. Show the last
     response and the version it reports, and offer to keep waiting.
   - `1`: error. Either the arguments were bad, the commit doesn't exist or
     isn't on `main`, or five checks in a row failed (the endpoint or the
     GitHub API errored or returned something unexpected). Show the error
     text from stderr; don't summarize it away.

## Environments

| Name | Status URL |
|---|---|
| `production` | `https://app.launchdarkly.com/api/status` |
| `eu-production` | `https://app.eu.launchdarkly.com/api/status` |
| `federal-production` | `https://app.launchdarkly.us/api/status` |
| `catamorphic` | `https://app.ld.catamorphic.com/api/status` |
| `staging` | `https://ld-stg.launchdarkly.com/api/status` |
| `federal-staging` | `https://app.stg.launchdarkly.us/api/status` |

Not covered: `dr`, `single-tenant-staging` and `single-tenant-catamorphic`.
Their status hosts haven't been confirmed. If the user knows one, pass the
full status URL in place of the name.

## Notes

- The script checks `.version`, the backend. The response also has
  `.frontendVersion`, which is deployed separately and isn't checked.
- "Deployed" means the environment serves the commit. It doesn't mean a
  feature flag gating the change is on.
- The compare result is cached per served version, so a long wait costs one
  GitHub API call per new version rather than five per poll.
- If the script itself seems wrong, run one poll with `-t 0` and read the
  output. Don't wrap it in another loop.
