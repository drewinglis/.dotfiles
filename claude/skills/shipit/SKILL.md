---
name: shipit
description: >-
  Resolve a Jira issue (existing or newly created under an epic),
  commit staged changes, and open a draft PR on GitHub — all linked
  by the Jira ticket key. On a branch that already has a PR, skip
  Jira resolution and PR creation; just commit and push.
---

# Shipit

Resolve a Jira issue, commit staged/unstaged changes, and open a draft
GitHub PR — all linked with the Jira ticket key (e.g. `[ID-1234]`).
On a branch that already has an open/draft PR, skip Jira resolution
and PR creation and just commit and push to the existing PR.

## Usage

```
/shipit [<arg>] [--project <key>]
```

- `<arg>` (optional) — a Jira issue key (e.g. `ID-1234`), a Jira URL
  (`https://<jira_host>/browse/ID-1234`), or an epic name to resolve
  via `epic-cache.json`. If omitted, the skill infers from context.
- `--project <key>` — Jira project for epic-name lookup. Defaults to
  `config.default_project`.

If the current branch already has an open or draft PR, the skill runs
in **follow-up mode**: it commits, pushes, and reports the existing PR
URL. Jira resolution and PR creation are skipped. Any `<arg>` or
`--project` flag is ignored in that mode.

## Configuration

Two files sit next to this `SKILL.md`:

- **`config.json`** — environment-specific values used throughout the
  skill. Read it once at the start. Keys:
  - `jira_cloud_id` — passed to every Jira MCP call
  - `jira_host` — used for URL parsing and the final report (no scheme)
  - `default_project` — fallback when `--project` is not passed
  - `assignee_account_id` — assignee for newly-created Tasks
  - `sprint_field` — Jira custom field ID for the active sprint
- **`epic-cache.json`** — cache of resolved epic keys, mapping
  `<project>/<epic-name>` → epic issue key. Looked up before any JQL
  search; updated when a new epic is resolved.

References to config values below are written as `config.<key>`.

---

## Section 0: Gather context and detect mode

Goal: collect the diff context once, and decide whether this run is in
**initial mode** (no PR yet — full Jira + PR flow) or **follow-up
mode** (PR already exists — commit and push only).

Run in parallel:
1. `git status` — changed/untracked files
2. `git diff` — full diff (staged + unstaged)
3. `git log --oneline -5` — for commit message style
4. `gh pr view --json number,title,url --jq '{number,title,url}'` —
   detect an existing PR for the current branch

Hold the diff context — it's used in every later section (candidate
matching, Task drafting, commit message, PR body).

**Branch on the `gh pr view` exit code:**

- **Exit 0 (PR exists)** → **follow-up mode**:
  - Capture `number`, `title`, `url`.
  - Parse the Jira key from the PR title with the regex
    `\[([A-Z]+-\d+)\]`. If absent, fall back to the current branch
    name (e.g. `id-1234-foo` → `ID-1234`). If neither has one, proceed
    with no Jira prefix.
  - **Skip Section 1 entirely.**
  - In Section 2, draft the commit message from the diff with the
    captured Jira prefix (or none) — no Jira API call.
  - In Section 3, run only 3a (push) and 3e (report); skip 3b–3d.
  - In 3e, the PR URL is the captured `url`.

- **Non-zero exit (no PR)** → **initial mode**: continue to Section 1.

---

## Section 1: Resolve the Jira issue

Goal: produce a `(jira_key, summary)` pair for Sections 2 and 3.
**Skipped entirely in follow-up mode.**

### 1b. Determine the Jira key

**If the user passed an arg:**

- Looks like an issue key (`[A-Z]+-\d+`) or a
  `<config.jira_host>/browse/...` URL → extract the key, go to
  step 1c.
- Otherwise → treat as an **epic name**:
  - Read `epic-cache.json`. If `<project>/<epic-name>` is cached, use
    that key.
  - Else search Jira:
    ```
    project = <PROJECT> AND issuetype = Epic
      AND summary ~ "<epic-name>" ORDER BY created DESC
    ```
    Use the first result's key; write it to `epic-cache.json`.
  - If no epic is found, ask the user to clarify.
  - Go to step 1c with the epic key.

**If no arg was passed, infer a candidate** from:

- The current branch name (e.g. `id-1234-foo` → `ID-1234`)
- The conversation so far (e.g. user mentioned `ID-1234` or pasted a
  `/browse/...` link)
- Recent commits or staged file paths, if they suggest a key

If a candidate is found, fetch it via `getJiraIssue` (using
`config.jira_cloud_id`) and compare its summary/description against
the staged diff:

- **Clear match** → use it, go to step 1c.
- **Unclear** → ask the user to confirm or supply a different key.

If no candidate is found, ask the user for either a Jira key/URL or an
epic name, and re-run the dispatch above.

### 1c. Fetch the issue and branch on type

`getJiraIssue` with `config.jira_cloud_id`.

- **`issuetype` is `Epic`:**
  1. From the Section 0 context, draft:
     - Jira task summary (imperative, <80 chars)
     - 1-2 sentence Jira description
  2. Look up the current sprint:
     ```
     project = <PROJECT> AND sprint in openSprints()
       ORDER BY created DESC
     ```
     Read `config.sprint_field` from the first result for the sprint ID.
  3. Create a Task with:
     - `summary`: drafted summary
     - `description`: drafted description
     - `parent`: the epic key
     - `assignee`: `config.assignee_account_id`
     - `config.sprint_field`: sprint ID as a **bare integer**, not a
       string or object — the API rejects anything else
  4. Use the new task's key as `jira_key`; the drafted summary becomes
     `summary` for Sections 2 and 3.

- **Any other `issuetype`** (Task, Story, Bug, …):
  - Use the issue's key as `jira_key` and its `summary` field as
    `summary`.

---

## Section 2: Create the git commit

Goal: stage and commit, producing a commit hash for Section 3. **No
approval gate** — commit immediately.

### 2a. Draft the commit message

- **Epic path from Section 1** → reuse the drafted summary/description.
- **Existing-issue path** → draft:
  - **Title:** `[<JIRA-KEY>] <summary>`. Start from the Jira issue's
    `summary`, but **override based on the diff** if the staged work
    has diverged meaningfully from it.
  - **Body:** optional 1–3 sentence description derived from the
    Section 0 `git diff` context.
- **Follow-up mode** (Section 0 found an existing PR) → draft from
  the diff:
  - **Title:** `[<JIRA-KEY>] <diff-derived summary>` using the Jira
    key parsed in Section 0; if no key was found, just
    `<diff-derived summary>`.
  - **Body:** optional 1–3 sentence description derived from the
    Section 0 `git diff` context.

### 2b. Stage files

Stage the modified/untracked files relevant to the change. Prefer
naming specific files over `git add -A` to avoid sweeping in stray
files (`.env`, build artifacts, scratch files). Skip if everything is
already staged.

### 2c. Commit

Use a HEREDOC for the message:

```
[<JIRA-KEY>] <summary>

<optional longer description>

<standard Co-Authored-By footer for the current model>
```

The Co-Authored-By footer follows the harness's standard git-commit
convention (current model name); don't hardcode a version here.

### 2d. Output

The commit hash, fed into Section 3.

---

## Section 3: Push (and PR if needed)

In **follow-up mode** (Section 0 found an existing PR), run only **3a
and 3e**; skip 3b–3d. The existing PR's body is left untouched. In
**initial mode**, run all of 3a–3e.

### 3a. Push the branch

```
git push -u origin <branch>
```

Always use `-u`, even if the upstream is already set.

### 3b. Load PR-style guidance

**Before writing the PR body**, invoke the `pr-style` skill via the
Skill tool (`Skill` with `skill: "pr-style"`). This loads Drew's PR
body conventions into context.

### 3c. Write the PR body

Following the `pr-style` instructions, write a PR body informed by the
Section 0 diff context. Append this footer to the body:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 3d. Create the draft PR

```
gh pr create --draft \
  --title "[<JIRA-KEY>] <summary>" \
  --body "<body>"
```

Always attempt creation — don't check for an existing PR first. If one
already exists, let `gh` error out and surface the message.

The title matches the commit title verbatim.

### 3e. Report results and offer to open

Output a summary block:

- **Jira:** `https://<config.jira_host>/browse/<KEY>` — omit this line
  in follow-up mode if no Jira key was found.
- **PR:** the GitHub URL — from `gh pr create` in initial mode, or
  the `url` captured in Section 0 in follow-up mode.
- **Commit:** the hash from Section 2.

Then ask the user if they'd like to open the PR in the browser. If
yes, run `open <PR-URL>`.
