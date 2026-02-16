# Argo CD use case and best practices (this repo)

This document aligns our Argo CD setup with [Argo CD best practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/) and common GitOps patterns.

---

## How we use Argo CD

- **IaC (wiz-iac):** Installs Argo CD and creates the `tasky` namespace + `tasky-secret`. It does **not** create the Argo CD Application.
- **App repo (this repo):** The Deploy workflow applies the Argo CD Application (`argocd/application-tasky.yaml`) with:
  - **Source:** this repo, path `kubernetes/`, Kustomize with image override.
  - **targetRevision:** the commit SHA we just built (immutable sync).
  - **Image:** the Artifact Registry image we just pushed.
- Argo CD then syncs that commit’s `kubernetes/` manifests into the cluster; CI runs `kubectl rollout restart` so new pods pull the new image.

So: **Git is the source of truth for manifests; CI builds the image and pins the Application to the commit that was built.**

---

## Best practices we follow

### 1. Immutable targetRevision (commit SHA)

Argo CD recommends using a **specific Git tag or commit SHA** for `targetRevision`, not `HEAD` or a moving branch, so that the meaning of “what’s deployed” doesn’t change without an explicit deploy.

We set **targetRevision to the commit SHA** in the Deploy workflow when applying the Application (`github.sha` or `workflow_run.head_sha`). Each deploy therefore syncs the exact commit that was built.

References:
- [Argo CD best practices – immutability](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/#ensuring-manifests-at-git-revisions-are-truly-immutable)
- [Codefresh – targetRevision for promotions](https://codefresh.io/blog/argocd-application-target-revision-field/)

### 2. Sync policy

- **automated:** sync when drift is detected.
- **prune: true:** remove resources that are no longer in Git.
- **selfHeal: true:** revert manual cluster changes to match Git.
- **syncOptions:**
  - **CreateNamespace=true:** create the destination namespace if missing.
  - **PruneLast=true:** delete resources after new ones are healthy.
  - **ApplyOutOfSyncOnly=true:** only apply when there is drift (reduces unnecessary full syncs).

References:
- [Argo CD sync options](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/)
- [Codefresh – sync policies](https://codefresh.io/learn/argo-cd/argocd-sync-policies-a-practical-guide/)

### 3. ignoreDifferences (leave room for imperativeness)

Argo CD allows “imperative” or automated changes that shouldn’t be overwritten by Git:

- **Secret `/data`:** The `tasky-secret` is created by IaC (MongoDB URI, secret key). We don’t store secret data in Git; Argo CD ignores drift on Secret data.
- **Deployment `restartedAt`:** CI runs `kubectl rollout restart` to pull the new image. Argo CD ignores this annotation so it doesn’t revert the rollout.

References:
- [Argo CD best practices – leaving room for imperativeness](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/#leaving-room-for-imperativeness)

### 4. Retry and finalizer

- **retry** with backoff (limit 5, duration 5s, factor 2, maxDuration 3m) so transient failures don’t leave the app stuck.
- **resources-finalizer.argocd.argoproj.io** so deleting the Application cleans up the resources it created.

### 5. Application owned by the app repo

The **Application** manifest lives in this repo and is applied by the **Deploy** workflow (not by IaC). That keeps “what to deploy and from where” in the app repo and avoids IaC needing to know repo URLs or image names. IaC only installs Argo CD and prepares namespace + secret.

---

## Trade-off: single repo for app + manifests

Argo CD recommends a **separate Git repository** for Kubernetes manifests (config) vs application source code, to:

- Avoid triggering full CI on manifest-only changes (e.g. replica count).
- Keep a cleaner audit trail for config changes.
- Support multi-service apps built from multiple repos.
- Allow different access to “source” vs “config” repos.
- Avoid CI pushing to the same repo and triggering an infinite loop of builds.

In this exercise we use a **single repo** with `kubernetes/` for manifests and `tasky-main/` for source. That’s a common simplification for one app. Our CI does **not** push new commits to the repo when deploying; it only applies the Application YAML and runs `rollout restart`, so we don’t hit the “infinite loop” case. For a larger or multi-service setup, consider a dedicated “gitops” or “deploy” repo for manifests.

Reference:
- [Argo CD best practices – separating config vs source](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/#separating-config-vs-source-code-repositories)

---

## Summary

| Practice                         | How we do it                                                                 |
|----------------------------------|-------------------------------------------------------------------------------|
| Immutable targetRevision         | Deploy workflow sets targetRevision to commit SHA when applying Application. |
| Sync policy                      | automated, prune, selfHeal; CreateNamespace, PruneLast, ApplyOutOfSyncOnly.  |
| ignoreDifferences                | Secret `/data` (IaC-managed); Deployment `restartedAt` (CI rollout).         |
| Application ownership           | App repo applies Application; IaC only installs Argo CD + namespace/secret.|
| Config vs source repo            | Single repo for this exercise; optional separate manifest repo at scale.     |
