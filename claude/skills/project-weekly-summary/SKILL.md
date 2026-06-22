---
name: project-weekly-summary
description: >-
  Generate a tight weekly summary (<280 chars) of activity on a
  software project, pulling resolved Jira issues from a configured
  epic, merged GitHub PRs that reference those issues, and important
  Slack discussion in configured channels. Outputs 3-4 bullets (with an
  optional one-sentence summary) plus raw source data to the terminal
  for copy-paste. Invoke as
  `/project-weekly-summary <project-name> [--days N]`.
---

# Project Weekly Summary

Generate a project-scoped weekly recap suitable for sharing with
management and engineers on adjacent teams. The summary block is
hard-capped at **280 characters** so it fits the kind of context where
brevity matters; the raw source data is printed below for verification
before copy-paste.

## Usage

```
/project-weekly-summary <project-name> [--days N]
```

- `<project-name>` — required. Must be a key in `projects.json`.
- `--days N` — optional. Look-back window in days. Defaults to `7`.

## Saved context

`projects.json` (next to this SKILL.md) has:

- `jira_cloud_id`: top-level Atlassian cloud id (UUID)
- `projects`: map of project name to its sources, where each entry has:
  - `jira_epic`: a single Jira epic key (e.g. `ID-1234`)
  - `github_repos`: list of `owner/repo` strings
  - `slack_channels`: list of channel names (no `#`)

## Instructions

### Step 1: Parse args and load config

1. Parse the project name (required) and the optional `--days N` flag
   (default `7`).
2. Read `projects.json` from the directory containing this SKILL.md.
   Capture the top-level `jira_cloud_id` and the `projects` map.
3. Look up the project entry under `projects.<name>`. If not found,
   print the list of valid project keys and stop.
4. Compute the date window via Bash:
   - `SINCE_ISO=$(date -u -v-${DAYS}d +%Y-%m-%dT%H:%M:%SZ)` (on macOS)
   - `SINCE_DATE=$(date -u -v-${DAYS}d +%Y-%m-%d)`
   - `NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)`

### Step 2: Gather data in parallel

Make all three calls in parallel — they have no dependencies on each
other.

**1. Jira: resolved issues in the epic**

Call `mcp__Atlassian__searchJiraIssuesUsingJql` with the `jira_cloud_id`
from the config and a JQL like:

```
parent = <jira_epic> AND resolved >= -<days>d ORDER BY resolved DESC
```

If `parent` doesn't return results (older Jira project), retry with:

```
"Epic Link" = <jira_epic> AND resolved >= -<days>d ORDER BY resolved DESC
```

Request fields: `summary`, `status`, `resolutiondate`, `assignee`,
`issuetype`, `priority`.

Capture: key, summary, status name, resolution date, assignee display
name. Also collect the **set of issue keys** for use in Step 2.2.

**2. GitHub: PRs merged in listed repos**

For each repo in `github_repos`, run:

```bash
gh pr list --repo <owner/repo> --state merged --limit 100 \
  --search "merged:>=<SINCE_DATE>" \
  --json number,title,body,mergedAt,author,url
```

Then filter to PRs whose `title` or `body` mentions any of the Jira
issue keys collected in Step 2.1. Use a **word-boundary, case-
insensitive** match so that `ID-1` does not match `IDE-1`. For
example, in a Python-ish regex: `\bID-1\b`. In `jq`:

```
select(.title + " " + .body | test("(?i)\\bID-1234\\b|\\bID-1235\\b"))
```

Drop any PR that does not reference at least one of the configured
epic's resolved Jira keys — epic scoping is authoritative.

Capture: PR number, title, author login, repo, merged date, URL, and
the matching Jira key(s).

**3. Slack: important discussion in listed channels**

For each channel in `slack_channels`, search recent messages via the
Slack MCP search tool (e.g.
`mcp__plugin_slack_slack__slack_search_public_and_private`) with a
query like:

```
in:#<channel> after:<SINCE_DATE>
```

Skim the results for threads that look substantive:

- High reply counts (5+)
- Decisions ("we decided to...", "going with X")
- Announcements ("shipped", "rolling out", "deprecated")
- Escalations / customer pressure / deadline mentions
- Cross-team or leadership-visible discussion

For any thread that looks substantive, **read the full thread** using
`mcp__plugin_slack_slack__slack_read_thread` before drawing conclusions
about what was decided. Do not summarize a thread from the preview
alone — decisions are often reached at the end of a long discussion.

After reading, extract:
- Decisions made (the conclusion, not the deliberation)
- Customer or external pressure signals
- Blocking issues or risks
- Shipping plans or timeline commitments

Also search Confluence for any decision docs or meeting notes posted in
the same period:

```
mcp__Atlassian__searchConfluenceUsingCql: space = <relevant space> AND
  lastmodified >= "<SINCE_DATE>" AND text ~ "<project keywords>"
```

If a substantive discussion thread ends with people jumping on a call
(e.g. "let's chat live", "zoom link", "we're in here"), and no
post-call summary appears in Slack or Confluence, **flag this** in the
raw source section: "Note: a live sync occurred on <date> — decisions
from that call may not be reflected here."

Explicitly skip: routine standup posts, banter, deploy bot noise,
greetings, and low-signal back-and-forth.

### Step 3: Synthesize the summary

Across all gathered items, pick the **3-4 most newsworthy** items.

**Priority order:**

1. Decisions — what the team resolved to do, and why it matters
2. Project status — how far along vs the milestone; risks or blockers
3. Shipped user-visible features or capabilities
4. Significant bug fixes (correctness, perf, security)
5. Infra / process / migration milestones

Shipped work should be framed as *evidence of progress* toward the
milestone, not as a changelog. Skip implementation details (individual
Jira task titles, code identifiers, internal component names) unless
they are meaningful to someone not on the team.

Write each bullet in plain English, **past tense**, **project-focused**
(what happened, not who did it), prefixed by `- `. Translate technical
names into what they do, not what they're called. Strip Jira summary
phrasing — aim for the gist.

Optionally prepend one short summary sentence above the bullets. Only
include it if it adds context the bullets don't already convey
(e.g. a theme, a milestone, an overall status). Omit it if it would
just paraphrase the bullets.

**Verify the summary block is < 280 characters, including newlines.**
Use `wc -c` on the exact text. If it's over:

1. Drop the weakest bullet, or
2. Shorten phrasing (trim adjectives, drop articles, use abbreviations)

Iterate until under 280.

### Step 4: Print output to the terminal

Print to stdout in this exact structure:

```
=== Summary (<N> chars) ===
<optional one-sentence summary>
- <bullet 1>
- <bullet 2>
- <bullet 3>
- <bullet 4 (optional)>

=== Raw source data ===

Jira (epic <jira_epic>, resolved last <days> days):
- <KEY>  <summary>  (<status>, <assignee>)
- ...

GitHub PRs (merged last <days> days, referencing epic issues):
- #<NNN>  <title>  (<author>, <owner/repo>)  <url>
- ...

Slack discussion (last <days> days):
- <thread description>  <permalink>
- (or: <none — omitted from summary>)
- (flag if applicable: "Note: live sync on <date> — decisions may not be captured")

Confluence (last <days> days):
- <page title>  <url>
- (or: <none found>)
```

Notes on the output:

- The summary block above `=== Raw source data ===` is the part the user
  copies. Make sure the char count in the header is accurate (matches
  `wc -c` of just the bullets + optional summary line, not counting the
  `=== Summary ===` header itself).
- If a section in the raw data has no items, say `(none)` rather than
  omitting the section, so the user can tell the source was checked.

### Reminders for the model

- The 280-char cap is **hard**. Verify with `wc -c` after composing.
- Decisions and status come before shipped work. Shipped work is
  evidence of progress, not the headline.
- Plain English only — no Jira ticket names, no internal component
  names, no code identifiers in the summary bullets.
- Read full threads before concluding what was decided. A thread that
  looks inconclusive from the preview often has a resolution at the end.
- Flag live-call gaps explicitly rather than silently omitting them.
- If a Jira key appears in a PR title but the issue is not in the
  configured epic's resolved set, ignore the PR. The epic is the
  source of truth.
- Word-boundary key matching only — `ID-1` ≠ `IDE-1`.
