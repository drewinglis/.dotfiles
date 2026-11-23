#!/usr/bin/env bash
# Poll an environment's gonfalon status endpoint until the backend version it
# serves is a given launchdarkly/gonfalon commit or a descendant of it.
# Usage: poll.sh [-t MAX_SECONDS] [-i INTERVAL] ENVIRONMENT|STATUS_URL COMMIT
# Defaults: 86400s max, 120s between polls.
# Exit codes: 0 = deployed, 2 = deadline reached with the commit not deployed,
# 1 = error (bad arguments, unknown commit, commit not on main, or five failed
# checks in a row).
set -euo pipefail

repo=launchdarkly/gonfalon
max=86400 interval=120 samples=5 max_failures=5
usage="usage: poll.sh [-t MAX_SECONDS] [-i INTERVAL] ENVIRONMENT|STATUS_URL COMMIT"

die() { echo "error: $*" >&2; exit 1; }

while getopts t:i: opt; do
  case $opt in
    t) max=$OPTARG ;;
    i) interval=$OPTARG ;;
    *) die "$usage" ;;
  esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || die "$usage"
target=$1 ref=$2

case $target in
  production) url=https://app.launchdarkly.com/api/status ;;
  eu-production) url=https://app.eu.launchdarkly.com/api/status ;;
  federal-production) url=https://app.launchdarkly.us/api/status ;;
  catamorphic) url=https://app.ld.catamorphic.com/api/status ;;
  staging) url=https://ld-stg.launchdarkly.com/api/status ;;
  federal-staging) url=https://app.stg.launchdarkly.us/api/status ;;
  https://*) url=$target ;;
  *) die "unknown environment '$target' (expected production, eu-production, federal-production, catamorphic, staging, federal-staging, or an https:// status URL)" ;;
esac

commit=$(gh api "repos/$repo/commits/$ref" --jq .sha) ||
  die "commit '$ref' not found in $repo"
on_main=$(gh api "repos/$repo/compare/$commit...main" --jq .status) ||
  die "could not compare $commit with main"
case $on_main in
  ahead|identical) ;;
  *) die "$commit is not on $repo main (compare status '$on_main'); pass the merge commit, not a PR branch commit" ;;
esac

failures=0
last="(no response yet)"
contains_cache=""

# contains VERSION: 0 if VERSION is the commit or a descendant of it, 1 if
# not, 2 if the comparison failed.
contains() {
  local version=$1 status
  case " $contains_cache " in
    *" $version=yes "*) return 0 ;;
    *" $version=no "*) return 1 ;;
  esac
  status=$(gh api "repos/$repo/compare/$commit...$version" --jq .status) || return 2
  case $status in
    ahead|identical) contains_cache="$contains_cache $version=yes"; return 0 ;;
    behind|diverged) contains_cache="$contains_cache $version=no"; return 1 ;;
    *) echo "unexpected compare status for $version: '$status'" >&2; return 2 ;;
  esac
}

# check: 0 if every sample serves a version containing the commit, 1 if any
# does not, 2 if a response was missing or malformed. A blue/green deploy
# serves the old and new versions side by side for about ten minutes, so one
# matching sample is not enough.
check() {
  local i version rc
  versions=""
  for i in $(seq "$samples"); do
    last=$(curl -sS -m 15 "$url") || return 2
    version=$(jq -er '.version | select(type == "string" and test("^[0-9a-f]{7,40}$"))' <<<"$last") || return 2
    versions="$versions $version"
    rc=0; contains "$version" || rc=$?
    if [ "$rc" -ne 0 ]; then return "$rc"; fi
  done
}

echo "Polling $url for $repo@${commit:0:10} every ${interval}s (max ${max}s)."
start=$(date +%s) shown=""
while :; do
  rc=0; check || rc=$?
  elapsed=$(( $(date +%s) - start ))
  case $rc in
    0)
      echo "[${elapsed}s] serving$versions"
      echo "Deployed: all $samples samples contain ${commit:0:10}. Last response: ${last:0:500}"
      exit 0 ;;
    1)
      failures=0
      if [ "$versions" != "$shown" ]; then
        echo "[${elapsed}s] serving$versions (not yet)"
        shown=$versions
      fi ;;
    *)
      failures=$((failures + 1))
      echo "check failed ($failures/$max_failures) at ${elapsed}s. Last response: ${last:0:500}" >&2
      if [ "$failures" -ge "$max_failures" ]; then
        die "giving up after $max_failures consecutive failed checks"
      fi ;;
  esac
  if [ "$elapsed" -ge "$max" ]; then
    echo "Deadline reached after ${elapsed}s with ${commit:0:10} not deployed. Last response: ${last:0:500}"
    exit 2
  fi
  sleep "$interval"
done
