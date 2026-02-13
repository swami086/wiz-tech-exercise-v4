# MongoDB Setup & Backup Automation

This document covers the **MongoDB Setup & Backup Automation** ticket: installing an outdated MongoDB on the VM, enabling auth, and configuring daily backups to the GCS bucket.

## Prerequisites

- [Infrastructure Deployment](INFRASTRUCTURE_DEPLOYMENT.md) completed (VPC, GKE, MongoDB VM, backup GCS bucket).
- Terraform outputs: `mongodb_vm_name`, `mongodb_vm_zone`, `mongodb_backup_bucket`, `mongodb_vm_internal_ip`.
- SSH access to the MongoDB VM via **IAP tunnel** (VM has no external IP; use `gcloud compute ssh --tunnel-through-iap`).

## 1. Get bucket name and VM details

From the repo root (after `terraform apply`):

```bash
cd terraform
BUCKET=$(terraform output -raw mongodb_backup_bucket)
VM_NAME=$(terraform output -raw mongodb_vm_name)
ZONE=$(terraform output -raw mongodb_vm_zone)
echo "Bucket: $BUCKET  VM: $VM_NAME  Zone: $ZONE"
```

## 2. Run the install script (password required)

Authentication is **required**. You must provide a strong admin password. The script installs MongoDB 4.4, enables auth, creates the `tododb` database and application user, binds MongoDB to the VM internal IP, and sets up daily backups.

**Run via gcloud (IAP tunnel for SSH)**

```bash
# From repo root; admin password required
export GCP_PROJECT_ID="your-project-id"
./scripts/run-mongodb-setup.sh '<YOUR_MONGO_ADMIN_PASSWORD>'
# Optional: set app user password (default: generated and stored on VM)
./scripts/run-mongodb-setup.sh '<ADMIN_PASSWORD>' '<APP_USER_PASSWORD>'
```

Or copy and run on the VM manually:

```bash
gcloud compute scp scripts/mongodb-install.sh "${VM_NAME}:~/mongodb-install.sh" --zone="$ZONE" --project="$GCP_PROJECT_ID"
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap -- \
  "sudo bash ~/mongodb-install.sh $BUCKET '<YOUR_MONGO_ADMIN_PASSWORD>'"
```

Replace `<YOUR_MONGO_ADMIN_PASSWORD>` with a strong password. The script creates an `admin` user (role `root` on `admin`) and enforces `security.authorization: enabled` in `/etc/mongod.conf`.

## 3. What the script does

| Step | Description |
|------|-------------|
| MongoDB 4.4 | Adds official MongoDB 4.4 repo for Debian Buster and installs `mongodb-org`. |
| Auth | Creates admin user and sets `security.authorization: enabled` in `/etc/mongod.conf`. |
| bindIp | Sets `net.bindIp` in `/etc/mongod.conf` to `127.0.0.1,<VM_internal_IP>` so MongoDB is reachable from GKE and localhost only; firewall allows 27017 only from GKE subnet. |
| tododb & app user | Creates database `tododb`, at least one collection (e.g. `tasks`) with a sample document, and an application user with `readWrite` on `tododb`. Credentials are stored in `/etc/mongodb-app-credentials.conf` on the VM (and app password is generated if not provided). |
| gsutil | Installs Google Cloud SDK so the VM can upload to GCS using its service account (no key file). |
| Backup cron | Installs `/usr/local/bin/mongodb-backup-to-gcs.sh` and cron `0 2 * * *` (daily at 02:00). |

The VM’s service account has `roles/storage.objectCreator` on the backup bucket (see `terraform/backup_bucket.tf`), so uploads work without extra credentials.

## 4. Application user and connection strings

- **Admin user**: `admin` (password: the one you passed to the script). Use for backup and admin tasks.
- **Application user**: `todouser` by default (or set `MONGO_APP_USER`). Password is in `/etc/mongodb-app-credentials.conf` on the VM, or the one you passed as the third argument.

**Recommended connection string for the todo app (use app user, not admin):**

```text
MONGO_URI=mongodb://todouser:<APP_PASSWORD>@<MONGODB_VM_INTERNAL_IP>:27017/tododb
```

Internal IP: `terraform output -raw mongodb_vm_internal_ip`.

To read the app password from the VM (after setup):

```bash
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap -- \
  "sudo cat /etc/mongodb-app-credentials.conf"
```

## 5. Network and firewall

- **MongoDB VM** has **no external IP**. SSH is via **IAP tunnel** (`gcloud compute ssh ... --tunnel-through-iap`).
- **MongoDB (27017)** is bound to the VM’s internal IP (and 127.0.0.1). Firewall allows 27017 only from the GKE subnet and pod range; it is not exposed to the internet.
- Expected reachability: GKE workloads and the VM itself (localhost). Use `mongodb_vm_internal_ip` from Terraform output for `MONGO_URI`.

## 6. Verify

- **MongoDB**: From the VM, `sudo systemctl status mongod` and `mongo -u admin -p ... --authenticationDatabase admin --eval 'db.runCommand({ping:1})'`.
- **tododb**: `mongo -u todouser -p <APP_PASSWORD> --authenticationDatabase tododb --eval 'db.tasks.find()'` (from VM or app).
- **Backup**: Run once manually: `sudo /usr/local/bin/mongodb-backup-to-gcs.sh`, then check `gsutil ls gs://$BUCKET/daily/`.
- **Cron**: `sudo crontab -l` should show the 02:00 job.

## Intentional choices (exercise)

- **MongoDB 4.4**: Outdated version for security/demo purposes.
- **Daily backup to GCS**: Bucket has public read/list (see [INFRASTRUCTURE_DEPLOYMENT.md](INFRASTRUCTURE_DEPLOYMENT.md)); backups are automated and stored in that bucket.
