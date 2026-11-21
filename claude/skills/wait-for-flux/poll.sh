#!/usr/bin/env bash
# Wait for Flux to roll out a commit, then for the named namespaces' workloads
# to become healthy.
# Usage: poll.sh [-r REMOTE] [-t MAX_SECONDS] [-i INTERVAL] [-n NAMESPACE]... [REF]
# Defaults: origin, 1200s max, 20s between polls, REMOTE's default branch.
# Exit codes: 0 = rolled out and healthy, 1 = a Kustomization, HelmRelease or
# workload failed, 2 = deadline reached with the rollout unfinished, 4 = error
# (bad remote or ref, cluster unreachable, three poll errors in a row).
set -uo pipefail

remote=origin max=1200 interval=20 namespaces=()
while getopts r:t:i:n: opt; do
  case $opt in
    r) remote=$OPTARG ;;
    t) max=$OPTARG ;;
    i) interval=$OPTARG ;;
    n) namespaces+=("$OPTARG") ;;
    *) exit 4 ;;
  esac
done
shift $((OPTIND - 1))

die() { echo "error: $*" >&2; exit 4; }

git fetch --quiet "$remote" || die "git fetch $remote failed"
ref=${1:-$remote/HEAD}
sha=$(git rev-parse --verify --quiet "$ref^{commit}") || die "unknown ref '$ref'"
kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o name >/dev/null ||
  die "can't list Flux Kustomizations (is KUBECONFIG set?)"

# Whether a commit Flux reports includes $sha. Flux often applies a later
# commit than the one being watched (its own image-automation commits land on
# top), so "applied" means $sha or any descendant of it.
includes() {
  local applied=$1
  [ "$applied" = "$sha" ] && return 0
  git cat-file -e "$applied^{commit}" 2>/dev/null || git fetch --quiet "$remote" || return 2
  git merge-base --is-ancestor "$sha" "$applied" 2>/dev/null
}

# Prints a JSON array of {name, state: pass|fail|pending, detail} for every
# Kustomization built from a Git source; others have no commit to compare.
kustomizations() {
  local ks rows=() line name ready reason applied attempted msg state
  ks=$(kubectl get kustomizations.kustomize.toolkit.fluxcd.io -A -o json) || return 1
  while IFS=$'\t' read -r name ready reason applied attempted msg; do
    applied=${applied##*:} attempted=${attempted##*:}
    if [ "$ready" = True ] && [ -n "$applied" ] && includes "$applied"; then
      state=pass
    elif [ "$ready" = False ] && [ -n "$attempted" ] && includes "$attempted" &&
      ! [[ $reason =~ ^(DependencyNotReady|Progressing|ProgressingWithRetry)$ ]]; then
      state=fail
    else
      state=pending
    fi
    rows+=("$(jq -cn --arg n "$name" --arg s "$state" --arg d "$reason: $msg" \
      '{name: $n, state: $s, detail: $d}')")
  done < <(jq -r '.items[]
    | select(.spec.suspend != true)
    | select((.status.lastAttemptedRevision // .status.lastAppliedRevision // "") | test("sha1:"))
    | (.status.conditions // [] | map(select(.type == "Ready")) | first // {}) as $r
    | ["ks/\(.metadata.namespace)/\(.metadata.name)", ($r.status // "Unknown"),
       ($r.reason // ""), (.status.lastAppliedRevision // ""),
       (.status.lastAttemptedRevision // ""), ($r.message // "" | gsub("[\t\n]"; " "))]
    | @tsv' <<<"$ks")
  printf '%s\n' "${rows[@]}" | jq -s .
}

# HelmReleases: Ready on their current spec. Meaningful only once the
# Kustomizations have applied, since that is what changes the spec.
helmreleases() {
  kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o json | jq '
    [ .items[] | select(.spec.suspend != true)
      | (.status.conditions // [] | map(select(.type == "Ready")) | first // {}) as $r
      | {name: "hr/\(.metadata.namespace)/\(.metadata.name)",
         detail: "\($r.reason // ""): \($r.message // "")",
         state: (if (.status.observedGeneration // -1) < .metadata.generation then "pending"
                 elif $r.status == "True" then "pass"
                 elif $r.status == "False" and ($r.reason | IN("DependencyNotReady", "Progressing") | not)
                 then "fail" else "pending" end)} ]'
}

# Deployments, StatefulSets and DaemonSets in a namespace fully rolled out, and
# no pod stuck in a state that won't clear on its own. CreateContainerConfigError
# stays pending: it is what a pod shows while ESO is still writing its Secret.
workloads() {
  local ns=$1 found w p
  found=$(kubectl get namespace "$ns" -o name --ignore-not-found) || return 1
  if [ -z "$found" ]; then
    jq -n --arg ns "$ns" '[{name: "ns/\($ns)", state: "fail", detail: "namespace does not exist"}]'
    return
  fi
  w=$(kubectl get deployments,statefulsets,daemonsets -n "$ns" -o json) || return 1
  p=$(kubectl get pods -n "$ns" -o json) || return 1
  jq -n --slurpfile w <(printf '%s' "$w") --slurpfile p <(printf '%s' "$p") --arg ns "$ns" '
    $w[0] as $w | $p[0] as $p
    | [ ($w.items[] | .status as $s
        | (if .kind == "DaemonSet" then $s.desiredNumberScheduled // 0 else .spec.replicas // 1 end) as $want
        | {name: "\(.kind | ascii_downcase)/\($ns)/\(.metadata.name)",
           ok: (if ($s.observedGeneration // -1) < .metadata.generation then false
                elif .kind == "Deployment" then
                  ($s.updatedReplicas // 0) == $want and ($s.availableReplicas // 0) == $want
                  and ($s.replicas // 0) == $want
                elif .kind == "StatefulSet" then
                  ($s.updatedReplicas // 0) == $want and ($s.readyReplicas // 0) == $want
                  and $s.currentRevision == $s.updateRevision
                else
                  ($s.updatedNumberScheduled // 0) == $s.desiredNumberScheduled
                  and ($s.numberAvailable // 0) == $s.desiredNumberScheduled end),
           detail: ("updated \($s.updatedReplicas // $s.updatedNumberScheduled // 0)/\($want), "
             + "ready \($s.readyReplicas // $s.numberReady // 0)/\($want), "
             + "total \($s.replicas // $s.currentNumberScheduled // 0)")}
        | {name, detail, state: (if .ok then "pass" else "pending" end)}),
      ($p.items[] | . as $pod
        | [(.status.initContainerStatuses // []), (.status.containerStatuses // [])] | add
        | map(select(.state.waiting.reason // "" | IN("CrashLoopBackOff", "ImagePullBackOff",
            "ErrImagePull", "InvalidImageName", "CreateContainerError", "RunContainerError")))
        | select(length > 0)
        | {name: "pod/\($ns)/\($pod.metadata.name)", state: "fail",
           detail: map("\(.name): \(.state.waiting.reason) (restarts \(.restartCount))") | join(", ")}),
      (if ($w.items | length) == 0
       then {name: "ns/\($ns)", state: "pending", detail: "no workloads yet"} else empty end) ]'
}

fetch() {
  local k h rows
  k=$(kustomizations) || return 1
  [ "$(jq length <<<"$k")" -gt 0 ] || { echo "no Git-sourced Kustomizations found" >&2; return 1; }
  rows=$k
  if jq -e 'all(.state == "pass")' <<<"$k" >/dev/null; then
    h=$(helmreleases) || return 1
    rows=$(jq -s add <<<"$rows $h")
    for ns in "${namespaces[@]}"; do
      h=$(workloads "$ns") || return 1
      rows=$(jq -s add <<<"$rows $h")
    done
  fi
  echo "$rows"
}

echo "Waiting for Flux to roll out ${sha:0:10}${namespaces[*]:+ and workloads in ${namespaces[*]}}" \
  "(every ${interval}s, max ${max}s)."
start=$(date +%s) errors=0 last="" checks="[]"
report() { jq -r '.[] | select(.state != "pass") | "  \(.state)\t\(.name)\t\(.detail)"' <<<"$checks"; }
while :; do
  elapsed=$(( $(date +%s) - start ))
  if ! next=$(fetch); then
    errors=$((errors + 1))
    echo "poll error ($errors/3) at ${elapsed}s" >&2
    [ "$errors" -ge 3 ] && die "giving up after 3 consecutive poll errors"
  else
    errors=0 checks=$next
    read -r total pass fail pending < <(jq -r '[length,
      (map(select(.state == "pass")) | length),
      (map(select(.state == "fail")) | length),
      (map(select(.state == "pending")) | length)] | @tsv' <<<"$checks")
    line="$pass pass, $fail fail, $pending pending"
    [ "$line" != "$last" ] && echo "[${elapsed}s] $line" && last=$line
    if [ "$fail" -gt 0 ]; then
      echo "Rollout of ${sha:0:10} failed:"; report; exit 1
    elif [ "$pending" -eq 0 ]; then
      echo "Rolled out ${sha:0:10}: all $total checks healthy."; exit 0
    fi
  fi
  if [ "$elapsed" -ge "$max" ]; then
    echo "Deadline reached after ${elapsed}s with the rollout unfinished:"; report; exit 2
  fi
  sleep "$interval"
done
