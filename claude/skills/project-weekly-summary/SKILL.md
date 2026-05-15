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

Generate a project-scoped weekly recap suitable for sharing with other
people at the company in Slack or a status update. The summary block is
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

Skim the results for **important discussion only**:

- Decisions ("we decided to...", "going with X")
- Announcements ("shipped", "rolling out", "deprecated")
- Escalations / incident threads
- Threads with notably high reaction or reply counts
- Cross-team or leadership-visible discussion

Explicitly skip: routine standup posts, banter, deploy bot noise,
greetings, and low-signal back-and-forth.

If nothing rises above the noise floor, **omit Slack entirely** — the
280-char budget cannot afford filler.

Capture: a few-word description and the Slack permalink for each kept
thread.

### Step 3: Synthesize the summary

Across all gathered items (Jira issues, GitHub PRs, Slack threads),
pick the **3-4 most newsworthy** items.

Prioritize in this order:
1. Shipped user-visible features or capabilities
2. Significant bug fixes (correctness, perf, security)
3. Infra / process / migration milestones
4. Notable internal discussion or decisions

Write each as a single short bullet, **past tense**, **project-focused**
(what happened, not who did it), prefixed by `- `. Strip any verbose
Jira summary phrasing — aim for the gist, not the title.

Optionally prepend one short summary sentence above the bullets. Only
include it if it adds context the bullets don't already convey
(e.g. a theme, a milestone). Omit it if it would just paraphrase.

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
- Bullets are past tense, project-focused, not person-focused.
- Don't pad with Slack content unless it's genuinely newsworthy.
- If a Jira key appears in a PR title but the issue is not in the
  configured epic's resolved set, ignore the PR. The epic is the
  source of truth.
- Word-boundary key matching only — `ID-1` ≠ `IDE-1`.
