Add the following to your settings.json:

```
  "hooks": [
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/rename-auto-branch/user-prompt-submit.sh"
          }
        ]
      }
    ]
  ]
```
