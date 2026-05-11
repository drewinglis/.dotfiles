# Skills
- When creating a new skill, if it's primarily about interacting with a company,
    organization, or tool, start the skill name with the company, org, or tool.
    (E.g. for a skill to create a PR on GitHub, use "/github-create-pr".)

# Code Style
- I prefer to use a soft-limit of 80 characters for line length and a hard limit
    of 120 characters. Don't wrap existing code unless you're already changing
    that line.

If a project has a BUILD.bazel file, use bazel instead of the normal language
build tools.

# Worktrees
- When creating a worktree (the `EnterWorktree` tool), always pass an explicit
    `name` derived from the user's prompt — short kebab-case (≤40 chars;
    letters, digits, and dashes only), summarizing the task. Don't fall back to
    the auto-generated random name unless the prompt provides no useful signal.
