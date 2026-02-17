#!/bin/bash
# MongoDB installation and configuration startup script (Terraform-injected).
# Runs automatically on VM first boot. Logs to /var/log/mongodb-startup.log.
set -e
exec > >(tee /var/log/mongodb-startup.log) 2>&1

echo "Starting MongoDB setup at $(date)"

# Variables injected by Terraform
GCS_BACKUP_BUCKET="${gcs_backup_bucket}"
MONGO_ADMIN_USER="${mongo_admin_user}"
MONGO_ADMIN_PASSWORD="${mongo_admin_password}"
MONGO_APP_USER="${mongo_app_user}"
MONGO_APP_PASSWORD="${mongo_app_password}"

# --- Use Debian archive for EOL Buster so apt works ---
configure_apt_archive() {
  if [[ ! -f /etc/apt/sources.list.bak ]]; then
    cp -a /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
  fi
  echo "[*] Configuring Debian archive (Buster is EOL)..."
  cat > /etc/apt/sources.list << 'EOF'
deb http://archive.debian.org/debian buster main
deb http://archive.debian.org/debian-security buster/updates main
EOF
  for f in /etc/apt/sources.list.d/*.list; do
    [[ -f "$f" ]] && mv "$f" "$f.disabled" 2>/dev/null || true
  done
  # Disable Release file expiration check so apt update works against archive.debian.org
  echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until
}

# --- MongoDB 4.4 install (Debian 10 / Buster) ---
install_mongodb() {
  echo "[*] Installing MongoDB 4.4 (outdated - exercise requirement)..."
  export DEBIAN_FRONTEND=noninteractive
  configure_apt_archive
  apt-get update -qq
  apt-get install -y gnupg curl

  curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | \
    gpg --batch --yes -o /usr/share/keyrings/mongodb-server-4.4.gpg --dearmor

  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/debian buster/mongodb-org/4.4 main" | \
    tee /etc/apt/sources.list.d/mongodb-org-4.4.list

  apt-get update -qq
  apt-get install -y mongodb-org

  systemctl enable mongod
  systemctl start mongod
  echo "[*] MongoDB 4.4 installed and running."
}

# --- Enable auth and create admin user ---
enable_auth() {
  echo "[*] Enabling MongoDB auth and creating admin user..."
  systemctl stop mongod || true
  install -o mongodb -g mongodb -d /var/lib/mongodb 2>/dev/null || true
  chown -R mongodb:mongodb /var/lib/mongodb
  mongod --bind_ip_all --noauth --dbpath /var/lib/mongodb &
  local pid=$!
  sleep 5

  mongo --quiet --eval "
    db = db.getSiblingDB('admin');
    db.createUser({
      user: '$${MONGO_ADMIN_USER}',
      pwd: '$${MONGO_ADMIN_PASSWORD}',
      roles: [ { role: 'root', db: 'admin' } ]
    });
  "
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  sleep 1

  local conf=/etc/mongod.conf
  if ! grep -q 'authorization: enabled' "$conf" 2>/dev/null; then
    sed -i '/security:/,/^[^ ]/ s/^  *#* *security:.*/security:\n  authorization: enabled/' "$conf" || true
    if ! grep -q 'authorization: enabled' "$conf"; then
      echo 'security:' >> "$conf"
      echo '  authorization: enabled' >> "$conf"
    fi
  fi

  chown -R mongodb:mongodb /var/lib/mongodb
  systemctl start mongod 2>/dev/null || true
  echo "[*] Auth enabled and admin user created."
}

# --- Bind MongoDB so GKE pods can connect (0.0.0.0 = all interfaces) ---
configure_bind_ip() {
  echo "[*] Binding MongoDB to all interfaces (0.0.0.0) for GKE access..."
  local conf=/etc/mongod.conf
  if [[ ! -f "$conf" ]]; then
    install -o mongodb -g mongodb -d /var/lib/mongodb 2>/dev/null || true
    echo "net:" >> "$conf"
    echo "  port: 27017" >> "$conf"
    echo "  bindIp: 0.0.0.0" >> "$conf"
  elif grep -q '^net:' "$conf"; then
    sed -i "/^net:/,/^[^ ]/ s/bindIp:.*/bindIp: 0.0.0.0/" "$conf" || true
    grep -q "bindIp:" "$conf" || echo "  bindIp: 0.0.0.0" >> "$conf"
  else
    echo "net:" >> "$conf"
    echo "  port: 27017" >> "$conf"
    echo "  bindIp: 0.0.0.0" >> "$conf"
  fi
  systemctl restart mongod 2>/dev/null || true
  echo "[*] MongoDB bind_ip configured (restarted)."
  ensure_mongod_listening
}

# --- Create tododb, collection, sample document, and app user ---
create_tododb_and_app_user() {
  echo "[*] Creating tododb, sample data, and application user..."
  local mongo_auth="-u $${MONGO_ADMIN_USER} -p $${MONGO_ADMIN_PASSWORD} --authenticationDatabase admin"
  local creds_file="/etc/mongodb-app-credentials.conf"

  mongo $mongo_auth --quiet --eval "
    db = db.getSiblingDB('tododb');
    db.tasks.insertOne({ title: 'Welcome task', completed: false, createdAt: new Date() });
    if (db.tasks.countDocuments({}) !== 1) { throw new Error('Sample document insert failed'); }
  " || { echo "Error: Failed to create tododb or insert sample document." >&2; exit 1; }

  mongo $mongo_auth --quiet --eval "
    db = db.getSiblingDB('tododb');
    db.createUser({
      user: '$${MONGO_APP_USER}',
      pwd: '$${MONGO_APP_PASSWORD}',
      roles: [ { role: 'readWrite', db: 'tododb' } ]
    });
  " || { echo "Error: Failed to create application user." >&2; exit 1; }

  printf 'MONGO_APP_USER="%s"\nMONGO_APP_PASSWORD="%s"\n' "$MONGO_APP_USER" "$MONGO_APP_PASSWORD" > "$creds_file"
  chmod 600 "$creds_file"
  echo "[*] tododb and app user created. Credentials stored in $creds_file"
}

# --- Install Google Cloud SDK (gsutil) for backup uploads ---
install_gsutil() {
  if command -v gsutil &>/dev/null; then
    echo "[*] gsutil already available."
    return 0
  fi
  echo "[*] Installing Google Cloud SDK (gsutil)..."
  export CLOUDSDK_CORE_DISABLE_PROMPTS=1
  curl -sSL https://sdk.cloud.google.com | bash -s -- --install-dir=/opt --disable-prompts 2>/dev/null || true
  ln -sf /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil 2>/dev/null || true
  ln -sf /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud 2>/dev/null || true
  if command -v gsutil &>/dev/null; then
    echo "[*] gsutil installed."
  else
    echo "[!] Could not install gsutil; backup script will need it." >&2
  fi
}

# --- Deploy backup script and cron ---
setup_backup_cron() {
  local backup_script="/usr/local/bin/mongodb-backup-to-gcs.sh"
  local creds_file="/etc/mongodb-backup-credentials.conf"
  echo "[*] Deploying backup script and daily cron..."

  printf 'MONGO_BACKUP_USER="%s"\nMONGO_BACKUP_PASSWORD="%s"\n' "$MONGO_ADMIN_USER" "$MONGO_ADMIN_PASSWORD" > "$creds_file"
  chmod 600 "$creds_file"

  cat > "$backup_script" << 'BACKUPSCRIPT'
#!/usr/bin/env bash
# Daily MongoDB dump and upload to GCS. Uses VM service account (no key needed).
# PATH set for cron (minimal env); log to file for debugging.
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/google-cloud-sdk/bin:${PATH:-}"

BUCKET="{{GCS_BACKUP_BUCKET}}"
CREDS_FILE="/etc/mongodb-backup-credentials.conf"
DUMP_DIR="/tmp/mongodb-backup-$$"
LOG="/var/log/mongodb-backup.log"

mkdir -p "$DUMP_DIR"
trap "rm -rf $DUMP_DIR" EXIT

MONGO_AUTH=""
if [[ -f "$CREDS_FILE" ]]; then
  source "$CREDS_FILE"
  MONGO_AUTH="-u $MONGO_BACKUP_USER -p $MONGO_BACKUP_PASSWORD --authenticationDatabase admin"
fi

echo "$(date -Iseconds) Starting backup" >> "$LOG"
mongodump $MONGO_AUTH --out="$DUMP_DIR" >> "$LOG" 2>&1
tar -czf "$DUMP_DIR/../dump.tgz" -C "$DUMP_DIR" .
gsutil -q cp "$DUMP_DIR/../dump.tgz" "gs://$BUCKET/daily/mongodb-$(date +%Y%m%d-%H%M%S).tgz" >> "$LOG" 2>&1
echo "$(date -Iseconds) Backup done" >> "$LOG"
BACKUPSCRIPT
  sed -i "s|{{GCS_BACKUP_BUCKET}}|$GCS_BACKUP_BUCKET|g" "$backup_script"
  chmod +x "$backup_script"

  (crontab -l 2>/dev/null | grep -v mongodb-backup-to-gcs || true; echo "0 * * * * $backup_script") | crontab -
  echo "[*] Cron set: every hour at minute 0 (0 * * * *)."

  # Run one backup immediately so the bucket is not empty after first boot
  echo "[*] Running initial backup to GCS..."
  $backup_script || echo "[!] Initial backup failed; check $LOG. Cron will retry daily."
}

# --- Ensure MongoDB is listening on 27017 (fixes missing/failed systemd unit) ---
ensure_mongod_listening() {
  echo "[*] Ensuring MongoDB is listening on 27017..."
  if ss -tlnp 2>/dev/null | grep -q ":27017 "; then
    echo "[*] MongoDB already listening on 27017."
    return 0
  fi
  systemctl start mongod 2>/dev/null && sleep 2 && ss -tlnp | grep -q ":27017 " && return 0 || true
  # Fallback: create systemd unit if package did not (e.g. partial install)
  if [[ ! -f /lib/systemd/system/mongod.service ]] && [[ -x /usr/bin/mongod ]]; then
    mkdir -p /var/lib/mongodb
    chown -R mongodb:mongodb /var/lib/mongodb 2>/dev/null || true
    [[ -f /etc/mongod.conf ]] || { echo "net:" >> /etc/mongod.conf; echo "  port: 27017" >> /etc/mongod.conf; echo "  bindIp: 0.0.0.0" >> /etc/mongod.conf; }
    cat > /etc/systemd/system/mongod.service << 'UNIT'
[Unit]
Description=MongoDB Database Server
After=network.target

[Service]
User=mongodb
Group=mongodb
ExecStart=/usr/bin/mongod --config /etc/mongod.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable mongod 2>/dev/null || true
    systemctl start mongod
    sleep 2
  fi
  if ss -tlnp 2>/dev/null | grep -q ":27017 "; then
    echo "[*] MongoDB is now listening on 27017."
  else
    echo "[!] WARNING: MongoDB may not be listening on 27017. Check /var/log/mongodb-startup.log and /var/log/mongodb/mongod.log" >&2
  fi
}

# --- Main ---
install_mongodb
enable_auth
configure_bind_ip
# Backup cron is required; run it even if tododb/sample data fails (e.g. shell compatibility).
install_gsutil
setup_backup_cron
create_tododb_and_app_user || { echo "[!] Failed to create tododb/sample data; backup cron is active." >&2; }
ensure_mongod_listening
echo "[*] MongoDB setup and backup automation complete."
echo "[*] App user: $MONGO_APP_USER (password in /etc/mongodb-app-credentials.conf on this VM)."
echo "MongoDB setup completed at $(date)"
