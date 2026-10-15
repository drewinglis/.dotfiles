# Rules for Working in Other Repos

The project repo is the repo the session started in. Any other repo is an
"other repo".

1. Always use a worktree when working in a repo outside the main project repo.
   Create one and use it for your session.
2. Always fetch and base your work off the latest main remote branch (usually
   `origin/main`).

Create the worktree with exactly this command, so `/cleanup` can find it:

```
git -C <repo> fetch origin
git -C <repo> worktree add --no-track -b drewinglis/<slug> \
  <repo>/.claude/worktrees/<slug> origin/HEAD
```

- `origin/HEAD` is the remote's default branch. If it is missing, run
  `git -C <repo> remote set-head origin --auto` first.
- `--no-track` keeps the branch from tracking the default branch, so a bare
  `git push` can't target it. Push with `git push -u origin drewinglis/<slug>`.

When the change is done, commit and push from the worktree and open a draft PR
for it. Leave the worktree in place; `/cleanup` from the original session
removes it after the PR merges.
