---
name: pr-style
description: >-
  Write PR descriptions in Drew's preferred style and format. Always use this
  skill when possible.
---

## General

Prefer using full sentences, be formal but conversational (it's okay to write in
first-person), and be succinct.

Your PR body should have three sections: Summary, Testing, and Rollout.

## Summary

The "summary" section should start with an explanation for what was motivating
the change. If you can't figure this out from context, it's okay to prompt the
user about it. This should be a short paragraph (1-5 sentences).

Then it should have a description of the changes. It's okay to use bullet points
for this.  Focus on the high-level changes; you don't need to detail every
change in every file.

If this is a pure refactoring change, note that here.

## Testing

The "testing" section should describe how the change was tested. It's okay to
for this section to be very short if you're just relying on existing or added
unit tests.

## Rollout

The "rollout" section should include:

1. Any special considerations for rolling out the change
2. A risk assessment for the change
3. The names of feature flags used, if any
4. Specific instructions or risks for rolling back, if any
