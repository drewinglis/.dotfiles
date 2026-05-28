Add the following to your `~/.claude/settings.json`:

```
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/deny-outside-worktree/pre-tool-use.sh"
          }
        ]
      }
    ]
  },
```
