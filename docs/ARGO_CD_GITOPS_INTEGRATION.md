# Argo CD GitOps Integration

This document describes how to deploy the Tasky app using **Argo CD** in a GitOps workflow (Wiz Technical Exercise V4 – ticket: Argo CD GitOps Integration). The Kubernetes manifests in `kubernetes/` are the source of truth; Argo CD syncs the cluster state to match Git.

## Deployment options

| Method | When to use |
|--------|-------------|
| **Terraform** | Automated: set `argocd_enabled=true`, `tasky_enabled=false`, and `argocd_git_repo_url` in `terraform.tfvars`, then run `terraform apply`. Terraform installs Argo CD (with `--server-side --force-conflicts` to avoid CRD size limits), creates the tasky namespace and secret, and deploys the Argo CD Application. See [terraform/argocd.tf](../terraform/argocd.tf). |
| **Manual** | Run `./scripts/install-argocd.sh`, create the secret, then `kubectl apply -f argocd/application-tasky.yaml -n argocd`. See [Install Argo CD](#install-argo-cd) and below. |

## Overview

| Component | Purpose |
|-----------|---------|
| `kubernetes/` | Kustomize-based manifests (namespace, RBAC, Deployment, Service, Ingress). Single source of truth for GitOps. |
| `kubernetes/kustomization.yaml` | Kustomization and default image; image can be overridden by Argo CD. |
| `argocd/application-tasky.yaml` | Argo CD `Application` CR: points at this repo and `kubernetes/` path. |
| `argocd/project-tasky.yaml` | Optional `AppProject` for scoping Tasky. |

**Secrets:** The `tasky-secret` (MONGODB_URI, SECRET_KEY) is **not** stored in Git. Create it manually or via Terraform before Argo CD sync (see [Prerequisites](#prerequisites)).

## Prerequisites

- **GKE cluster** (e.g. created by Terraform in this repo) and `kubectl` access. When using private GKE nodes, **Cloud NAT** (`terraform/network.tf`) is required so nodes can pull images from quay.io and Artifact Registry; it is created by a standard `terraform apply` and removed by `terraform destroy`.
- **Argo CD** installed in the cluster (see [Install Argo CD](#install-argo-cd)).
- **Git repo** accessible from the cluster (e.g. public repo or Argo CD repo credentials).
- **Tasky image** built and pushed to Artifact Registry (e.g. `./scripts/build-and-push-tasky.sh`).
- **tasky-secret** created in namespace `tasky` (Argo CD does not create it):

  ```bash
  kubectl create namespace tasky
  kubectl create secret generic tasky-secret \
    --from-literal=MONGODB_URI="mongodb://todouser:PASSWORD@MONGO_IP:27017/tododb" \
    --from-literal=SECRET_KEY="your-jwt-secret-at-least-32-chars" \
    -n tasky
  ```

  Or use Terraform outputs and the same pattern as [APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md) to derive the URI.

## Install Argo CD

On your GKE cluster (or any Kubernetes cluster):

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for pods to be ready:

```bash
kubectl wait --for=condition=Available -n argocd deployment/argocd-server --timeout=300s
```

Get the initial admin password (then change it):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

(Optional) Expose the UI:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
# Then: kubectl get svc -n argocd argocd-server
```

Alternatively use the provided script: `./scripts/install-argocd.sh` (see [Scripts](#scripts)).

## Add the Git repository

If the repo is **private**, add it in Argo CD with credentials:

```bash
argocd repo add https://github.com/YOUR_ORG/Wiz \
  --username YOUR_GIT_USER \
  --password YOUR_TOKEN_OR_PASSWORD
```

For **public** repos, adding the Application is enough (Argo CD will use anonymous access where allowed).

## Configure and apply the Application

1. **Set your repo URL** in the Application manifest (and optionally image override):

   Edit `argocd/application-tasky.yaml`:

   - `spec.source.repoURL`: set to your Git repo URL (e.g. `https://github.com/your-org/Wiz`).
   - `spec.source.targetRevision`: branch or tag (e.g. `main`).
   - `spec.source.kustomize.images`: set the Tasky image for your environment, e.g.  
     `tasky:latest=us-west1-docker.pkg.dev/YOUR_PROJECT/tasky-repo/tasky:latest`.

2. **Apply the Application** (and optionally the AppProject):

   ```bash
   kubectl apply -f argocd/application-tasky.yaml -n argocd
   # Optional: kubectl apply -f argocd/project-tasky.yaml -n argocd
   # If using project-tasky, set spec.project: tasky in application-tasky.yaml
   ```

3. **Sync**

   Argo CD will sync automatically (sync policy is set in the manifest). To sync or refresh from the UI or CLI:

   ```bash
   argocd app sync tasky
   argocd app get tasky
   ```

## Verify

- In Argo CD UI: Application **tasky** should show **Synced** and **Healthy** (after pods are ready).
- From the cluster:

  ```bash
  kubectl get pods,svc,ingress -n tasky
  kubectl get ingress -n tasky   # external IP may take 5–10 min
  ```

- Open `http://<EXTERNAL_IP>` or use port-forward: `kubectl port-forward -n tasky svc/tasky 8080:8080`.

## Relation to Terraform and manual deploy

- **Terraform path** ([APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md](APPLICATION_DEPLOYMENT_TERRAFORM_K8S.md)): Terraform Kubernetes provider manages the same resources in `terraform/tasky_k8s.tf`. Use either Terraform **or** Argo CD for a given cluster to avoid conflicting updates.
- **Manual path** ([scripts/deploy-tasky-to-gke.sh](../scripts/deploy-tasky-to-gke.sh)): Uses the same `kubernetes/` manifests via Kustomize and creates the secret; no Argo CD.

For a **GitOps-only** flow: create the secret (or use External Secrets / Sealed Secrets), install Argo CD, add repo, apply the Application, and let Argo CD manage the rest from Git.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/install-argocd.sh` | Install Argo CD into the current cluster (namespace `argocd`). |
| `scripts/deploy-tasky-to-gke.sh` | Manual deploy using Kustomize (creates secret, applies `kubernetes/`); does not use Argo CD. |

## References

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Argo CD Installation](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/)
- [Argo CD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [Kustomize with Argo CD](https://argo-cd.readthedocs.io/en/stable/user-guide/kustomize/)
