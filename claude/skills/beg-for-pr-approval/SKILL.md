---
name: beg-for-pr-approval
disable-model-invocation: true
---

# Beg for PR Approval

Look up the teams whose review is requested on a GitHub PR, map each
team to its Slack ask-channel, and post one approval-request message
per channel.

## Usage

```
/beg-for-pr-approval [<pr>]
```

- `<pr>` (optional) — a PR number or a GitHub PR URL. If omitted, use
  the PR for the current branch.

## Configuration

`config.json` sits next to this `SKILL.md`. Read it once at the start.
Keys:

- `mappings` — object keyed by team slug **without the org prefix**
  (e.g. `team-flag-delivery`, not `launchdarkly/team-flag-delivery`).
  Each value is either:
  - `{ "channel": "#ask-...", "id": "C..." , "note": "..."? }` — a
    known Slack channel (`note` is optional caveat text; surface it to
    the user when present), or
  - `null` — a team known to have no ask-channel (searched before and
    not found).

**This file is a learned cache.** Whenever you discover a new
team → channel mapping (step 3), or confirm a team has no channel,
write it back to `config.json` so future runs skip the search.

---

## Step 1: Determine the target PR

- Arg is a number or URL → use it directly with `gh` (`gh pr view <arg>`).
- No arg → `gh pr view` for the current branch. If there is no PR for
  the branch, stop and tell the user.

Capture the PR URL for the message.

## Step 2: Get requested reviewer teams

```
gh pr view <pr> --json reviewRequests
```

Keep entries where `__typename == "Team"`. Slugs come back like
`launchdarkly/team-flag-delivery` — strip the org prefix to get the
config key (`team-flag-delivery`). Ignore individual-user requests.

If no teams are requested, report that and stop — there's nothing to
beg for.

## Step 3: Map teams to Slack channels

For each team slug, look it up in `config.mappings`:

- **Mapped to a channel** → add the channel to the send list. If the
  entry has a `note`, keep it for the summary/warnings.
- **Mapped to `null`** → previously searched, no channel exists. Add
  to the "no known channel" list; don't re-search.
- **Not in the config** → search Slack with the `slack_search_channels`
  MCP tool:
  1. Try `ask-<team name>` first (drop the `team-`/`div-` prefix, e.g.
     `team-flag-delivery` → `ask-flag-delivery`).
  2. If that misses, try abbreviations and variants of the team name —
     e.g. observability → `#ask-o11y`, cloud engineering →
     `#ask-cloud-eng`, sdk → `#ask-sdks`, the AI teams →
     `#ask-agentcontrol`. Use judgment; a couple of searches is
     enough.
  3. **Found** → add `"<slug>": { "channel": "#<name>", "id": "<ID>" }`
     to `config.json`, and add the channel to the send list.
  4. **Not found** → add `"<slug>": null` to `config.json` and add the
     team to the "no known channel" list.

**Dedupe the send list by channel ID** — multiple teams often share a
channel (e.g. the AI teams, the security teams). Each channel gets
exactly one message, regardless of how many teams map to it.

## Step 4: Post the messages

The message text is this template with the PR URL appended:

> hi all, i need a CODEOWNERS approval on this PR (sorry if this is
> the wrong channel, i'm not 100% sure where all the github teams
> mapped to): <PR URL>

For each channel in the deduped send list, call `slack_send_message`
with:

- the channel ID from the mapping
- text: the message above
- `unfurl_app_links: true` (so the PR link unfurls)

**Do not abort on a failed send** — record the failure and continue
with the remaining channels. Handle these errors specifically:

- `not_in_channel` — the user must join the channel before posting.
  Collect all such channels, tell the user to join them, and offer to
  retry those sends afterward.
- `restricted_action` — the channel restricts who can post (known for
  `#ask-sdks`; see the mapping's `note`). Report it and suggest the
  user post there manually.
- Anything else — report the raw error for that channel.

## Step 5: Summarize

End with a summary:

- **Posted** — each channel messaged, with a link to the message when
  the send result provides one.
- **Failed** — channels that errored, grouped by reason
  (`not_in_channel` with the join-then-retry offer,
  `restricted_action` with the post-manually suggestion, other).
- **No known channel** — teams mapped to `null`; the user needs to
  find these teams another way. Include the message that would have
  been sent (template + PR URL) so the user can copy-paste it wherever
  they end up asking.
