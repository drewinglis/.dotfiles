---
name: wait-for-flux
description: Wait for Flux to roll out a merged commit to a Kubernetes cluster and for the affected workloads to come up healthy, using a tested poll script instead of a hand-written loop. Use whenever you need to watch a GitOps rollout after merging to a Flux-managed repo, and for phrases like "watch the rollout", "wait for Flux", "make sure it comes up healthy", "wait for the deploy", or "is the new app running yet".
---

# wait-for-flux

Don't write your own poll loop. Run `poll.sh`, a sibling of this file, from
inside the repo Flux syncs from. It waits until every Git-sourced Flux
Kustomization has applied the commit, then until every HelmRelease is Ready
on its current spec, then until the workloads in the namespaces you name are
fully rolled out.

The key check: a Kustomization counts as rolled out once it has applied the
commit **or any descendant of it**. Flux often applies a later commit than the
merge, for example its own image-automation commits that land on top. A loop
that waits for the exact merge SHA in `lastAppliedRevision` never matches and
hangs silently.

## Usage

```bash
<skill-dir>/poll.sh [-r REMOTE] [-t MAX_SECONDS] [-i INTERVAL] [-n NAMESPACE]... [REF]
```

| Flag | Default | Meaning |
|---|---|---|
| `REF` | `REMOTE/HEAD` | The commit to wait for, usually the merge commit. The script fetches first, so the default is the remote's latest default branch. |
| `-r` | `origin` | Remote to fetch, to resolve `REF` and the commits Flux reports. |
| `-t` | `1200` | Give up after this many seconds. |
| `-i` | `20` | Seconds between polls. |
| `-n` | none | A namespace whose Deployments, StatefulSets, DaemonSets and pods must be healthy. Repeat it for several. Pass the namespace of each app the change touched. |

`kubectl` must reach the cluster: set `KUBECONFIG` first (in the home repo,
`terraform/talos/kubeconfig`). Run it with `run_in_background: true` and end
the turn. The harness wakes you when it exits, so don't sleep or poll the task
in the meantime.

Exit codes:

- `0`: the commit is applied everywhere, and every HelmRelease and named
  workload is healthy.
- `1`: something failed. Either a Kustomization or HelmRelease is failing on
  the new revision, a named namespace doesn't exist after the apply, or a pod
  is in `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull` or a similar
  state that won't clear on its own. The script exits on the first failure and
  prints everything not yet passing.
- `2`: deadline reached with the rollout unfinished. It prints what is still
  pending.
- `4`: error. Either the ref is bad, the cluster is unreachable, no
  Git-sourced Kustomizations were found, or three polls in a row errored.
  The error text is on stderr.

Report the outcome with the script's output. For a non-zero exit, show the
failing or pending lines, don't summarize them away.

## What counts as pending

- **`DependencyNotReady` and `Progressing` Kustomizations** are pending, not
  failed. After a merge, most Kustomizations go through `DependencyNotReady`
  while their dependencies reconcile one after another. That's the normal
  rollout.
- **A Kustomization failing on an older revision** is pending. It fails the
  rollout only once its last attempted revision includes `REF`.
- **`CreateContainerConfigError`** is pending. A new app's pod shows it while
  External Secrets Operator is still writing its Secret.
- **Workloads are checked only after every Kustomization has applied.**
  Before that, a namespace still shows the old, healthy state.

## After it passes

The script checks that the rollout completed and pods are Ready. It doesn't
check that the app works. For an exporter, confirm Prometheus scrapes it. For
a web app, hit its endpoint.
