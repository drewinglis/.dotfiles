# Confluence Create

Create a new Confluence page from a markdown file.

## Usage

```
/confluence-create <file-path> [options]
```

## Arguments

- `<file-path>` (required): Path to the markdown file to publish
- `--space <space-key-or-id>`: Confluence space to publish to (default: your personal space)
- `--title <title>`: Custom title (default: extracted from first H1 heading or filename)
- `--parent <page-id>`: Parent page ID for nesting the new page

## Instructions

1. **Read the file** at the provided file path
2. **Spell check the content**:
   - Run a spell check on the markdown content using available tools (aspell, ispell, or similar)
   - If spelling mistakes are found:
     - Present the mistakes to the user with context (show the line and the misspelled word)
     - Use `AskUserQuestion` to ask: "Found spelling mistakes in the file. Would you like to fix them before publishing?"
     - Options: "Fix them now", "Publish anyway", "Cancel"
     - If "Fix them now": highlight the mistakes and let the user know they should fix the file, then exit
     - If "Cancel": exit without publishing
     - If "Publish anyway": continue to the next step
   - If no mistakes are found, continue to the next step
3. **Extract the title**:
   - If `--title` is provided, use that
   - Otherwise, look for the first H1 heading (`# Title`) in the markdown and use that
   - If no H1 heading exists, use the filename (without extension) as the title
4. **Get Confluence credentials**:
   - Call `mcp__Atlassian__getAccessibleAtlassianResources` to get the cloudId
5. **Determine the target space**:
   - If `--space` is provided, use that space key or ID
   - Otherwise, find the user's personal Confluence space by calling `mcp__Atlassian__searchConfluenceUsingCql` with the query: `type = space AND space.type = personal AND creator = currentUser()`
   - Get the space ID using `mcp__Atlassian__getConfluenceSpaces` if needed
6. **Publish the page**:
   - Call `mcp__Atlassian__createConfluencePage` with:
     - `cloudId`: from step 4
     - `spaceId`: from step 5
     - `title`: from step 3
     - `body`: the full content of the markdown file (excluding the title line if it was extracted)
     - `contentFormat`: "markdown"
     - `parentId`: if `--parent` was provided
7. **Return the URL** to the newly created Confluence page so the user can view it

## Example

```bash
/confluence-create ~/docs/architecture.md
/confluence-create ~/docs/runbook.md --space ENG --title "Production Runbook"
/confluence-create ~/docs/child-page.md --parent 123456789
```
