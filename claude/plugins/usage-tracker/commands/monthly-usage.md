---
allowed-tools: Bash(curl:*)
description: Display monthly Claude API usage and cost metrics
---

## Your task

Fetch and display the user's monthly Claude API usage statistics using the Anthropic Usage API.

## Implementation

1. **Fetch usage data**: Make an API call to the Anthropic Usage API to retrieve monthly usage statistics. The API requires authentication via the ANTHROPIC_API_KEY environment variable.

2. **Display metrics**: Present the following information in a clear, readable format:
   - Total API requests for the current month
   - Tokens consumed (input/output) per model
   - Total costs for the current month
   - Cached tokens (read/write) if applicable
   - Cost breakdown by model

3. **Error handling**: If the API key is not configured or the request fails, provide clear instructions for setting up authentication.

## API Details

- **Endpoint**: `https://api.anthropic.com/v1/organization/usage`
- **Authentication**: Bearer token using `$ANTHROPIC_API_KEY`
- **Query Parameters**:
  - `start_date`: First day of current month (YYYY-MM-DD format)
  - `end_date`: Today's date (YYYY-MM-DD format)

## Implementation Steps

1. Calculate the date range (current month start to today)
2. Make the API request using curl
3. Parse and format the JSON response
4. Display metrics in a user-friendly format

## Example API call:

```bash
# Get the first day of current month
START_DATE=$(date -u "+%Y-%m-01")
# Get today's date
END_DATE=$(date -u "+%Y-%m-%d")

# Make the API request
curl -s -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  "https://api.anthropic.com/v1/organization/usage?start_date=${START_DATE}&end_date=${END_DATE}" \
  | jq '.'
```

## Output Format

Display the results in a clear, tabulated format showing:
- Date range covered
- Total requests
- Token usage by model (input, output, cache read, cache write)
- Cost breakdown by model
- Total monthly cost

If the API key is not set, instruct the user to:
1. Get their API key from https://console.anthropic.com/settings/keys
2. Set it in their environment: `export ANTHROPIC_API_KEY="your-key-here"`
3. Or add it to their shell profile for persistence
