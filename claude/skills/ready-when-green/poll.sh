#!/usr/bin/env bash
# Poll a PR's CI once per minute; mark it ready for review when green.
# Usage: poll.sh <PR_NUMBER> <MAX_SECONDS> [KEEP_GOING]
# KEEP_GOING=true keeps polling through red CI (e.g. auto-fix is enabled on
# the PR and may push fixes) instead of exiting on the first failed check.
# Exit codes: 0 = marked ready, 1 = CI failed, 2 = deadline reached with CI
# still pending or red, 3 = PR was marked ready out of band.
set -u

PR=$1
MAX_SECONDS=$2
KEEP_GOING=${3:-false}
DEADLINE=$(( $(date +%s) + MAX_SECONDS ))

while true; do
  if [ "$(gh pr view "$PR" --json isDraft --jq .isDraft 2>/dev/null)" = "false" ]; then
    echo "PR #$PR was marked ready for review out of band — stopping the poll."
    exit 3
  fi
  checks=$(gh pr checks "$PR" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "All checks passed on PR #$PR — marking ready for review."
    gh pr ready "$PR"
    exit 0
  elif [ "$rc" -ne 8 ] && [ "$KEEP_GOING" != "true" ]; then
    echo "CI is not clean on PR #$PR — leaving it in draft:"
    echo "$checks"
    exit 1
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "Gave up on PR #$PR: CI still not clean at the deadline:"
    echo "$checks"
    exit 2
  fi
  sleep 60
done
