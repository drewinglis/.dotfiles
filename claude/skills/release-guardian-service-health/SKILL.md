---
name: release-guardian-service-health
description: >-
  Fill out the weekly Release Guardian service health entry,
  pulling data from incident.io, Slack, and Datadog, and
  outputting formatted text to the terminal for copy-paste.
---

# Release Guardian Service Health

Gather data from incident.io, Slack, and Datadog, then output
a formatted service health entry to the terminal for the user
to copy into the Confluence page.

## Usage

```
/release-guardian-service-health
```

No arguments required. Uses the current user as the on-call
engineer and Friday of the current week as the meeting date.

## Saved context

Read from `config.json` (next to this SKILL.md) at the start of
every invocation. Update `config.json` when the quarterly page
rotates.

- **Confluence page ID**: `4441604179`
  (2026 Q1 RO Service Health)
- **incident.io schedule ID**: `01KJ8Y6XQEDEYC9NHW9Y5A6XK8`
  (Release Guardian)
- **incident.io escalation path ID**:
  `01KJ9MXZT017RB9G8QEBYZ8MW1` — Release Guardian (EP015)
- **On-call engineer Atlassian ID**:
  `712020:a11aa52a-a2d9-4758-8caa-f7bc3c91cf46` (Drew Inglis)
- **Datadog SLO query**: `owner:team-release-guardian`
  (`datadog.sloQuery` in `config.json`)
- **Datadog API credential**: read the PAT from `~/.env-datadog`
  (variable `DD_PAT`) and authenticate with the header
  `Authorization: Bearer $DD_PAT`. Load it with
  `set -a; source ~/.env-datadog; set +a`. **Never echo the token
  value** into the terminal or the output.

The incident.io MCP uses OAuth. If its tools are not yet
available, call `mcp__incident-io__authenticate` and ask the
user to complete the browser flow before continuing.

## Instructions

### Step 1: Compute dates

Run `compute-dates.sh`, which lives next to this SKILL.md.
Use the base directory provided when this skill is loaded to
construct the path (e.g. `<base-directory>/compute-dates.sh`).

It outputs key=value pairs:
- `MEETING_DATE` — this Friday as `YYYY-MM-DD`
- `MEETING_MS` — Friday as Unix milliseconds (for ADF date node)
- `MEETING_HUMAN` — e.g. `"Friday, March 20, 2026"` (for preview)
- `ONE_WEEK_AGO` — ISO 8601 datetime, 7 days ago
- `NOW` — current UTC datetime
- `THIS_FRI` — this Friday (start of next-on-call window)
- `NEXT_FRI` — next Friday (end of next-on-call window)

Parse each value and use them in subsequent steps.

### Step 2: Gather data in parallel

Read `config.json` and `team-cache.json` from the directory
containing this SKILL.md.

Make these calls in **two batches**.

**Batch 1** (parallel — no dependencies):

1. **Slack ops channels**: Use
   `mcp__plugin_slack_slack__slack_search_public_and_private`
   with `include_bots: true` to search the `ops-release-guardian`
   channels from the past week. Use a query like:
   `in:#ops-release-guardian-production after:<one-week-ago-date>`
   to find alerts, incidents, and pages.

   **`include_bots: true` is required** — the alerts in these
   channels are posted by the Datadog and Spinnaker bots, and
   the default search excludes bot messages (returns nothing).
   The channel prefix expands to env-suffixed channels:
   `-production` (most relevant), `-eu-production`, `-staging`,
   and `-catamorphic`; the bare `#ops-release-guardian` does not
   exist. Note that Datadog alert bodies render as Slack
   attachments whose text the search API returns empty — use the
   message timestamp/permalink (or correlate with the Datadog
   monitor and incident.io escalation data) to identify them.

2. **incident.io on-call schedule**:
   ```
   mcp__incident-io__schedule_show
     id: <incidentio.scheduleId from config.json>
   ```
   This returns:
   - `current_shifts[].start_at` and `.user_name` — the
     current on-call and their shift `start` time (used as
     the `since` boundary for pages in Batch 2).
   - `next_shifts[].start_at` / `.end_at` and `.user_name` —
     the next on-call and their shift date range (used in
     Step 6).

3. **Datadog paging monitors**:
   ```
   mcp__datadog__search_datadog_monitors
     query: release-guardian
   ```
   This is the broad **paging-monitor** scan — it surfaces every
   monitor that pages this rotation (SLO alerts *and* non-SLO
   monitors: Lambda errors, DLQ depth, panics, DAG failures, CI).
   Its alert/warn results feed the suggested notes in Step 5. The
   authoritative **Non-green SLOs** section comes from the SLO API
   in Step 3, not from this scan.

   **Do not use `tag:"owner:team-release-guardian"`** — several
   SLOs that page this rotation are *not* owner-tagged (e.g.
   `gonfalon-release-policies` and `gonfalon-progressive-rollouts`
   success-rate burn-rate alerts, and the Guarded Rollouts
   worker-queue monitors). They route to `@slack-ops-release-guardian-*`
   but carry a different (or no) `owner` tag, so the owner-tag
   query silently drops them. The free-text `release-guardian`
   query matches on the `@slack-ops-release-guardian-*`
   notification handle in the monitor body, so it catches every
   monitor that pages this rotation plus the owner-tagged ones.

   This query is **paginated** — keep calling with an increasing
   `start_at` (0, then the next batch offset) until the response
   is no longer truncated, and union all batches before filtering.

   Each monitor has a `status`: `"OK"`/`"No Data"` = green,
   `"Alert"` = red, `"Warn"` = yellow. Treat `"No Data"` as green —
   these are idle Lambda/CI monitors in non-prod envs. Any monitor
   in `"Alert"`/`"Warn"` is a candidate note for Step 5.

   **Out of scope:** the sibling team `team-release-monitoring`
   (Slack `@slack-ops-guardian-monitoring-*`, subteam
   `S096FK0KQMT`) owns a separate set — feature-monitoring,
   notification-subscriptions, adaptive-triggers, qualitative
   feedback, and the RUM "Release Monitoring" web-vitals SLOs.
   Those page a different rotation; the `release-guardian` query
   above excludes them by design. If Release Guardian ever
   absorbs that rotation, add `guardian-monitoring` as a second
   query.

**Batch 2** (after Batch 1 — depends on on-call result):

4. **incident.io escalations** (pages):
   ```
   mcp__incident-io__escalation_list
     escalation_path: <incidentio.escalationPathIds from config.json>
     created_after: <one-week-ago date>
     page_size: 50
   ```
   Each result has `title`, `priority.name`, `status`, and
   `created_at`. Apply these filters when deciding what counts
   as a page for the entry:
   - **Priority**: keep only `priority.name == "Urgent"` —
     these actually paged the on-call. `"Low"` escalations are
     non-paging warnings (they typically `expire`) and should
     be omitted.
   - **Current shift only**: keep only escalations with
     `created_at` >= the current shift `start_at` from item 2.
     Earlier ones belong to the previous week's entry.
   - **Exclude tests**: drop any title containing `[TEST]`.
   Note that environments other than production (e.g.
   `catamorphic`, `staging`) are internal — call these out so
   the user can decide whether to include them.

   Optionally also check `mcp__incident-io__incident_list`
   (`team_part_of` or `query: "release guardian"`,
   `created_after: <one-week-ago>`) for any declared incidents
   to mention alongside the pages.

### Step 3: SLO status (Datadog SLO API)

Get the team's SLO status from the Datadog SLO API. This is the
**authoritative** source for the "Non-green SLOs" section. It is
owner-scoped (`datadog.sloQuery` = `owner:team-release-guardian`),
so it is a narrower, SLO-only list than the Step 2 paging-monitor
scan — and it catches sustained error-budget burn that a recovered
burn-rate *monitor* no longer shows (e.g. a burn-rate monitor can
read `OK` on its short window while the SLO budget is still in
`warning`).

1. Run `slo-status.sh`, which lives next to this SKILL.md.
   Construct the path from the base directory provided when this
   skill is loaded (e.g. `<base-directory>/slo-status.sh`). It
   evaluates the **7d** window by default (pass a timeframe as the
   first arg to override, e.g. `slo-status.sh 30d`):

   ```
   <base-directory>/slo-status.sh
   ```

   The script reads `DD_PAT` from `~/.env-datadog` and the query /
   endpoint from `config.json`, fetches all owner-scoped SLOs, and
   emits JSON to stdout. **Do not inline the PAT or the curl — use
   the script.** It fails loudly (non-zero exit, message on stderr)
   if the credential is missing or the API returns non-200.

2. The JSON has:
   - `timeframe` — the evaluation window (e.g. `"7d"`)
   - `all_green` — `true` when no SLO is `warning`/`breached`
   - `non_green[]` — the SLOs to report, each with `name`, `state`,
     `emoji` (🔴 `breached` / 🟡 `warning`), `error_budget_remaining`
     (percent), `target`, and `url`
   - `slos[]` — every SLO (sorted worst-first) and `counts` per
     state, for cross-checking
   - `no_data` / `no_window` states are treated as green (idle SLOs)

3. Present the `non_green` SLOs to the user — name, state, the
   `error_budget_remaining`, and the SLO `url` — and ask if they'd
   like to adjust anything. Also give the dashboard link
   (`datadog.sloDashboardUrl`) for manual verification:
   `https://app.datadoghq.com/slo/manage?query=owner%3Ateam-release-guardian`

4. If `all_green` is `true`, the entry shows "All green!" instead
   of individual SLO bullets.

### Step 4: Review pages from incident.io and Slack

Apply the Step 2 (item 4) filters — `priority.name == "Urgent"`,
current shift only, exclude `[TEST]` — to get the pages.

Present them with: date, title, priority, and status (e.g.
resolved / expired / triggered).

Also include any relevant **Slack ops channel messages**.

Ask the user:
- "Which pages should be included in the entry?"
- "Are there any additional incidents to add?"

For each included page, capture:
- A short description (one line)
- Optional: a link (incident.io escalation/incident URL,
  Slack thread, etc.)

### Step 5: Prompt for notes and action items

Pre-populate suggested notes from:
- Any non-green SLOs from Step 3 (SLO API)
- Any Datadog paging monitors in alert/warn state from Step 2
- Any patterns observed in the incident.io/Slack data

Ask the user:
1. "Any additional notes on service health observations this
   week?" (the user can add, edit, or remove the suggestions)
2. "Any action items to record? (Format: description, and
   optionally @name if assigned to someone specific)"

### Step 6: Confirm next on-call

Present the next on-call engineer found via incident.io in
Step 2 (`next_shifts`). Show their name and the date range of
their shift.

Ask the user to confirm or provide a different name.

### Step 7: Output to terminal

Output the formatted entry to the terminal for the user to
copy-paste into the Confluence page. Use bulleted lists for
all sections except "Next on call".

Format:

```
## Pages
- <description> (<link>)
- (or: None this week.)

## Non-green SLOs
- 🎉 All green!
- (or individual SLOs with status emoji:)
- 🟡 <SLO name> (<link>)
- 🔴 <SLO name> (<link>)

## Notes
- <note 1>
- <note 2>

## Action Items
- <action 1>
- (or: None.)

## Next on call
@<next oncall name>
```

Rules:
- The "Pages" section is always included.
- The "Non-green SLOs" section is always included.
- The "Notes" section is only included if there are notes.
- The "Action Items" section is only included if there are
  action items.
- The "Next on call" section is always included. It uses a
  plain paragraph (not a bullet) with the person's name.
