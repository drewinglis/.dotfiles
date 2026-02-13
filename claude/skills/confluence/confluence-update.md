# Confluence Update

Update an existing Confluence page from a markdown file.

## Usage

```
/confluence-update <file-path> <page-id-or-url> [options]
```

## Arguments

- `<file-path>` (required): Path to the markdown file with new content
- `<page-id-or-url>` (required): Confluence page ID (e.g., `4517560695`) or full page URL
- `--title <title>`: New title for the page (default: keep existing title or extract from H1)
- `--version-message <message>`: Version comment to explain the changes

## Instructions

1. **Read the file** at the provided file path

2. **Spell check the content**:
   - Run a spell check on the markdown content using available tools (aspell, ispell, or similar)
   - If spelling mistakes are found:
     - Present the mistakes to the user with context (show the line and the misspelled word)
     - Use `AskUserQuestion` to ask: "Found spelling mistakes in the file. Would you like to fix them before updating?"
     - Options: "Fix them now", "Update anyway", "Cancel"
     - If "Fix them now": highlight the mistakes and let the user know they should fix the file, then exit
     - If "Cancel": exit without updating
     - If "Update anyway": continue to the next step
   - If no mistakes are found, continue to the next step

3. **Extract page ID from input**:
   - If the second argument looks like a URL (contains `https://` or `/wiki/`), extract the page ID from it
   - Page IDs are typically in the URL pattern: `/pages/<page-id>/` or `/x/<short-id>`
   - If it's just a number, use it directly as the page ID

4. **Determine the title**:
   - If `--title` is provided, use that
   - Otherwise, look for the first H1 heading (`# Title`) in the markdown
   - If no H1 heading and no `--title`, keep the existing page title (don't change it)

5. **Get Confluence credentials**:
   - Call `mcp__Atlassian__getAccessibleAtlassianResources` to get the cloudId

6. **Get existing page info** (optional but helpful):
   - Call `mcp__Atlassian__getConfluencePage` with the page ID to verify it exists and get current details
   - Show the user what page they're about to update (current title, space, URL)
   - Use `AskUserQuestion` to confirm: "Update page '<current-title>' in space '<space-name>'?"
   - Options: "Yes, update it", "Cancel"
   - If "Cancel": exit without updating

7. **Update the page**:
   - Call `mcp__Atlassian__updateConfluencePage` with:
     - `cloudId`: from step 5
     - `pageId`: from step 3
     - `title`: from step 4 (omit if keeping existing title)
     - `body`: the full content of the markdown file (excluding the title line if it was extracted)
     - `contentFormat`: "markdown"
     - `versionMessage`: from `--version-message` option if provided

8. **Return the URL** to the updated Confluence page so the user can view the changes

## Example

```bash
/confluence-update ~/docs/architecture.md123456
/confluence-update ~/docs/runbook.md https://your-domain.atlassian.net/wiki/spaces/~user/pages/123456/Page+Title
/confluence-update ~/docs/api.md 123456 --title "API Documentation v2" --version-message "Updated API endpoints"
```
