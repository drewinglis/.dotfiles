# Confluence Pull

Fetch a Confluence page and save it as a local markdown file.

## Usage

```
/confluence-pull <page-id-or-url> [output-path]
```

## Arguments

- `<page-id-or-url>` (required): Confluence page ID (e.g., `4517560695`) or full page URL
- `[output-path]` (optional): Path where the markdown file should be saved
  - If not provided, creates a file in the current directory named after the page title (e.g., `page-title.md`)
  - If a directory is provided, creates the file inside that directory
  - If a full file path is provided, uses that exact path

## Instructions

1. **Extract page ID from input**:
   - If the first argument looks like a URL (contains `https://` or `/wiki/`), extract the page ID from it
   - Page IDs are typically in the URL pattern: `/pages/<page-id>/` or `/x/<short-id>`
   - If it's just a number, use it directly as the page ID

2. **Get Confluence credentials**:
   - Call `mcp__Atlassian__getAccessibleAtlassianResources` to get the cloudId

3. **Fetch the page**:
   - Call `mcp__Atlassian__getConfluencePage` with:
     - `cloudId`: from step 2
     - `pageId`: from step 1
     - `contentFormat`: "markdown" (to get markdown content)

4. **Determine the output path**:
   - Get the page title from the response
   - If `output-path` was not provided:
     - Sanitize the page title to create a valid filename (lowercase, replace spaces with hyphens, remove special characters)
     - Use the current working directory
     - Create filename: `<sanitized-title>.md`
   - If `output-path` is a directory (ends with `/` or is an existing directory):
     - Use the sanitized title as the filename inside that directory
   - If `output-path` is a full file path:
     - Use that path exactly

5. **Prepare the content**:
   - Start with the title as an H1 heading: `# <page-title>`
   - Add a blank line
   - Append the page body content (already in markdown format from step 3)

6. **Write the file**:
   - Use the `Write` tool to save the content to the determined path
   - If the file already exists, ask the user for confirmation:
     - Use `AskUserQuestion`: "File '<filename>' already exists. Overwrite it?"
     - Options: "Yes, overwrite", "Cancel"
     - If "Cancel": exit without saving

7. **Confirm success**:
   - Show the user where the file was saved
   - Show a preview of the first few lines or summary of what was saved

## Example

```bash
# Pull to current directory with auto-generated filename
/confluence-pull 123456

# Pull to specific file
/confluence-pull 123456 ~/docs/architecture.md

# Pull to directory (auto-generate filename)
/confluence-pull https://your-domain.atlassian.net/wiki/spaces/~/pages/123456/Page+Title ~/docs/
```
