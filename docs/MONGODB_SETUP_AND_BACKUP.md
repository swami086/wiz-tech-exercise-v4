# MongoDB Setup & Backup Automation

This document covers **MongoDB Setup & Backup Automation**: an outdated MongoDB 4.4 on the VM with auth enabled and daily backups to the GCS bucket.

## Automated setup (Terraform startup script)

MongoDB is **installed and configured automatically** when the MongoDB VM is created by Terraform. No manual SSH or script execution is required.

### Prerequisites

- [Infrastructure Deployment](INFRASTRUCTURE_DEPLOYMENT.md) completed (VPC, GKE, MongoDB VM, backup GCS bucket).
- In `terraform.tfvars` you must set **MongoDB passwords** (required by the startup script):
  - `mongodb_admin_password` – admin user password
  - `mongodb_app_password` – application user (todouser) password  
  Generate with: `openssl rand -base64 32`

### What runs on first boot

The VM runs `terraform/scripts/mongodb-startup.sh.tpl` (injected as `metadata_startup_script`). It:

- Installs MongoDB 4.4, enables auth, creates admin and app users
- Binds MongoDB to the VM internal IP (GKE subnet only)
- Creates `tododb` and `tasks` with a sample document
- Deploys `/usr/local/bin/mongodb-backup-to-gcs.sh` and cron every hour (at minute 0)

Logs: `/var/log/mongodb-startup.log`.

### Connection string and credentials

After `terraform apply`, use the Terraform output for the app connection string:

```bash
cd terraform
terraform output -raw mongodb_connection_string
# Use this value for tasky_mongodb_uri or MONGO_URI
```

App credentials on the VM: `/etc/mongodb-app-credentials.conf` (see output `mongodb_credentials_path`).

## Optional: manual re-run (without recreating VM)

If you need to re-run the install logic **without** recreating the VM (e.g. to change passwords or fix state), you can still use the manual script over SSH:

- Terraform outputs: `mongodb_vm_name`, `mongodb_vm_zone`, `mongodb_backup_bucket`, `mongodb_vm_internal_ip`.
- SSH via **IAP tunnel**: `gcloud compute ssh ... --tunnel-through-iap`.

```bash
export GCP_PROJECT_ID="your-project-id"
./scripts/run-mongodb-setup.sh '<ADMIN_PASSWORD>' '[APP_PASSWORD]'
```

Or copy and run on the VM manually:

```bash
BUCKET=$(terraform output -raw mongodb_backup_bucket)
VM_NAME=$(terraform output -raw mongodb_vm_name)
ZONE=$(terraform output -raw mongodb_vm_zone)
gcloud compute scp scripts/mongodb-install.sh "${VM_NAME}:~/mongodb-install.sh" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap --internal-ip
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap --internal-ip -- \
  "sudo bash ~/mongodb-install.sh $BUCKET '<ADMIN_PASSWORD>'"
```

## What the script does

| Step | Description |
|------|-------------|
| MongoDB 4.4 | Adds official MongoDB 4.4 repo for Debian Buster and installs `mongodb-org`. |
| Auth | Creates admin user and sets `security.authorization: enabled` in `/etc/mongod.conf`. |
| bindIp | Sets `net.bindIp` in `/etc/mongod.conf` to `127.0.0.1,<VM_internal_IP>` so MongoDB is reachable from GKE and localhost only; firewall allows 27017 only from GKE subnet. |
| tododb & app user | Creates database `tododb`, at least one collection (e.g. `tasks`) with a sample document, and an application user with `readWrite` on `tododb`. Credentials are stored in `/etc/mongodb-app-credentials.conf` on the VM (and app password is generated if not provided). |
| gsutil | Installs Google Cloud SDK so the VM can upload to GCS using its service account (no key file). |
| Backup cron | Installs `/usr/local/bin/mongodb-backup-to-gcs.sh` and cron `0 * * * *` (every hour at minute 0). |

The VM’s service account has `roles/storage.objectCreator` on the backup bucket (see `terraform/backup_bucket.tf`), so uploads work without extra credentials.

## Application user and connection strings

- **Admin user**: `admin` (password: `mongodb_admin_password` in tfvars). Use for backup and admin tasks.
- **Application user**: `todouser` (password: `mongodb_app_password` in tfvars). Stored on VM at `/etc/mongodb-app-credentials.conf`.

**Connection string:** use `terraform output -raw mongodb_connection_string` or:

```text
MONGO_URI=mongodb://todouser:<APP_PASSWORD>@<MONGODB_VM_INTERNAL_IP>:27017/tododb
```

Internal IP: `terraform output -raw mongodb_vm_internal_ip`.

To read the app password from the VM (after setup):

```bash
gcloud compute ssh "$VM_NAME" --zone="$ZONE" --project="$GCP_PROJECT_ID" --tunnel-through-iap -- \
  "sudo cat /etc/mongodb-app-credentials.conf"
```

## Network and firewall

- **MongoDB VM** has **no external IP**. SSH is via **IAP tunnel** (`gcloud compute ssh ... --tunnel-through-iap`).
- **MongoDB (27017)** is bound to the VM’s internal IP (and 127.0.0.1). Firewall allows 27017 only from the GKE subnet and pod range; it is not exposed to the internet.
- Expected reachability: GKE workloads and the VM itself (localhost). Use `mongodb_vm_internal_ip` from Terraform output for `MONGO_URI`.

## Verify

- **MongoDB**: From the VM, `sudo systemctl status mongod` and `mongo -u admin -p ... --authenticationDatabase admin --eval 'db.runCommand({ping:1})'`.
- **tododb**: `mongo -u todouser -p <APP_PASSWORD> --authenticationDatabase tododb --eval 'db.tasks.find()'` (from VM or app).
- **Backup**: Run once manually: `sudo /usr/local/bin/mongodb-backup-to-gcs.sh`, then check `gsutil ls gs://$BUCKET/daily/`.
- **Cron**: `sudo crontab -l` should show the hourly job (`0 * * * *`).

## Intentional choices (exercise)

- **MongoDB 4.4**: Outdated version for security/demo purposes.
- **Daily backup to GCS**: Bucket has public read/list (see [INFRASTRUCTURE_DEPLOYMENT.md](INFRASTRUCTURE_DEPLOYMENT.md)); backups are automated and stored in that bucket.
