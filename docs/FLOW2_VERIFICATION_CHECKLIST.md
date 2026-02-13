# Flow 2 Verification: Infrastructure Deployment (Manual Phase)

Checklist for the **Infrastructure Deployment (Manual Phase)** ticket (Epic: Collaborative Feature Development Workflow). Project: **wizdemo-487311**.

---

## Acceptance Criteria

| # | Criterion | How to verify |
|---|-----------|----------------|
| 1 | VPC exists with public and private subnets (correct CIDR ranges) | `gcloud compute networks subnets list --network=wiz-exercise-vpc --project=wizdemo-487311` — expect `wiz-exercise-gke` (10.0.1.0/24), `wiz-exercise-vm` (10.0.2.0/24). |
| 2 | GKE cluster deployed with private nodes (no direct public exposure) | `gcloud container clusters describe wiz-exercise-gke --region=us-central1 --project=wizdemo-487311 --format="yaml(privateClusterConfig)"` — `enablePrivateNodes: true`. |
| 3 | Kubernetes control plane accessible from laptop via authorized/restricted access | Cluster has `master_authorized_networks_config`; kubectl works after `gcloud container clusters get-credentials`. |
| 4 | kubectl can connect and list nodes | `gcloud container clusters get-credentials wiz-exercise-gke --region=us-central1 --project=wizdemo-487311` then `kubectl get nodes`. |
| 5 | Compute Engine VM with 1+ year outdated OS | VM `wiz-exercise-mongodb` uses image `debian-cloud/debian-10-buster-v*` (Debian 10 EOL). |
| 6 | VM has external IP, SSH from public internet | VM has `access_config`; firewall `wiz-exercise-allow-ssh-vm` allows TCP 22 from 0.0.0.0/0. |
| 7 | VM has overly permissive IAM (can create VMs) | SA `mongodb-vm-sa@wizdemo-487311.iam.gserviceaccount.com` has `roles/compute.admin`. |
| 8 | Cloud Storage bucket with public read + public listing | Bucket `wizdemo-487311-mongodb-backups-wiz-exercise`; `gsutil iam get gs://BUCKET` shows allUsers objectViewer + legacyBucketReader. |
| 9 | Firewall allows SSH from 0.0.0.0/0 (intentional) | `gcloud compute firewalls describe wiz-exercise-allow-ssh-vm --project=wizdemo-487311` — sourceRanges 0.0.0.0/0. |
| 10 | All intentional misconfigurations marked in Terraform | See comments in `firewall.tf`, `mongodb_vm.tf`, `backup_bucket.tf`, `network.tf`, `gke.tf`. |
| 11 | Terraform state in GCS backend | `terraform init -backend-config="bucket=wizdemo-487311-tfstate-wiz-exercise"`; state in GCS. |
| 12 | Infrastructure stable (no unexpected drift) | `terraform plan` shows no changes after apply. |
| 13 | All Terraform code committed to GitHub | `git status` clean; pushed to origin. |
| 14 | Screenshots of deployed resources in GCP Console | Capture manually: VPC, GKE cluster, VM, bucket, firewall rules. |

---

## Quick validation commands

```bash
export PROJECT=wizdemo-487311
unset GOOGLE_APPLICATION_CREDENTIALS

# VPC & subnets
gcloud compute networks subnets list --network=wiz-exercise-vpc --project=$PROJECT

# GKE
gcloud container clusters get-credentials wiz-exercise-gke --region=us-central1 --project=$PROJECT
kubectl get nodes

# VM
gcloud compute instances describe wiz-exercise-mongodb --zone=us-central1-a --project=$PROJECT --format="yaml(name,networkInterfaces,metadata)"

# Bucket
gsutil iam get gs://wizdemo-487311-mongodb-backups-wiz-exercise

# Terraform
cd terraform && terraform state list && terraform plan
```

---

## Intentional misconfigurations (in code)

- **firewall.tf**: SSH from 0.0.0.0/0 to MongoDB VM.
- **mongodb_vm.tf**: Outdated Debian 10; SA with roles/compute.admin.
- **backup_bucket.tf**: allUsers objectViewer + legacyBucketReader (public read/list).
- **network.tf**: VM subnet allows external IP for SSH.
- **gke.tf**: master_authorized_networks 0.0.0.0/0 for demo (restrict in production).

When all items are verified and screenshots captured, Flow 2 is complete. Proceed to **MongoDB Setup & Backup Automation**.
