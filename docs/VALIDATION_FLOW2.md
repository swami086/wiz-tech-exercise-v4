# Flow 2 Validation: Infrastructure Deployment (Manual Phase)

Use this checklist to confirm all acceptance criteria for the **Infrastructure Deployment (Manual Phase)** ticket.

## Terraform

- [ ] **Backend**  
  Terraform state is in GCS (`terraform init` with `-backend-config` or `backend.tf`).  
  `terraform state list` shows resources (after apply).

- [ ] **Plan/Apply**  
  `terraform plan` runs without errors.  
  `terraform apply` completes and creates VPC, GKE, VM, bucket, firewalls.

## VPC and networking

- [ ] **VPC**  
  Custom VPC exists (e.g. `wiz-exercise-vpc`).  
  No default subnet; subnets created by Terraform.

- [ ] **GKE subnet**  
  Subnet has secondary ranges for pods and services.  
  GKE cluster uses this subnet and has private nodes.

- [ ] **VM subnet**  
  MongoDB VM is in the VM subnet and has a private IP (and optional public IP for SSH).

## GKE

- [ ] **Private cluster**  
  Cluster has `enable_private_nodes = true`.  
  Nodes have only private IPs (in private subnet).

- [ ] **kubectl**  
  `gcloud container clusters get-credentials ...` succeeds.  
  `kubectl get nodes` shows the node pool.

## MongoDB VM

- [ ] **Outdated OS**  
  VM uses an image that is 1+ year outdated (e.g. Debian 10 buster).

- [ ] **SSH exposed**  
  Firewall allows TCP 22 from `0.0.0.0/0` to the VM (or to the VM’s network tag).

- [ ] **Overly permissive IAM**  
  VM’s service account has a broad role (e.g. `roles/compute.admin` – able to create VMs).

- [ ] **MongoDB access**  
  Firewall allows TCP 27017 only from GKE subnet/pod range to the VM.  
  (MongoDB installation and auth are in the MongoDB Setup ticket.)

## Backup bucket

- [ ] **Bucket exists**  
  GCS bucket for MongoDB backups exists (see `terraform output mongodb_backup_bucket`).

- [ ] **Public read and list**  
  Bucket allows public read and public listing (intentional for exercise).  
  e.g. `gsutil iam get gs://BUCKET_NAME` shows `allUsers` with objectViewer/legacyBucketReader.

## Quick commands

```bash
# Terraform (from repo root; unset GOOGLE_APPLICATION_CREDENTIALS to use ADC)
cd terraform && unset GOOGLE_APPLICATION_CREDENTIALS && terraform state list

# GKE (project wizdemo-487311)
gcloud container clusters get-credentials wiz-exercise-gke --region=us-central1 --project=wizdemo-487311
gcloud container clusters describe wiz-exercise-gke --region=us-central1 --project=wizdemo-487311 --format="yaml(privateClusterConfig)"
kubectl get nodes

# VM
gcloud compute instances describe wiz-exercise-mongodb --zone=us-central1-a --project=wizdemo-487311 --format="yaml(name,networkInterfaces[0].networkIP,metadata)"

# Bucket
terraform output mongodb_backup_bucket
gsutil iam get gs://$(terraform output -raw mongodb_backup_bucket)
```

When all items are checked, Flow 2 (Infrastructure Deployment) is complete. Proceed to **MongoDB Setup & Backup Automation**.

See also:
- **[FLOW2_VERIFICATION_CHECKLIST.md](FLOW2_VERIFICATION_CHECKLIST.md)** – Acceptance-criteria mapping and quick commands (project wizdemo-487311).
- **[INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md](INFRASTRUCTURE_REPRODUCIBILITY_AND_LIFECYCLE.md)** – Lifecycle validation (no drift) and reproducibility (destroy + re-apply); run `./scripts/validate-terraform-lifecycle.sh plan` from repo root to confirm no drift.
