# Usage Tracker Plugin

A Claude Code plugin for tracking and displaying Claude API usage metrics.

## Commands

### `/monthly-usage`

Displays your monthly Claude API usage statistics including:
- Total API requests
- Token consumption by model (input/output/cache)
- Cost breakdown by model
- Total monthly costs

## Setup

This command requires your Anthropic API key to be set in your environment:

```bash
export ANTHROPIC_API_KEY="your-api-key-here"
```

Get your API key from: https://console.anthropic.com/settings/keys

For persistent access, add the export to your `~/.zshrc` or `~/.bashrc`.

## Usage

Simply run:
```
/monthly-usage
```

The command will fetch your current month's usage data and display it in a formatted table.
