#!/usr/bin/env bash
# MongoDB 4.4 install on Debian 10 (Buster) for Wiz Technical Exercise V4.
# Run once on the MongoDB VM (e.g. via SSH or as startup script).
# Installs outdated MongoDB 4.4, enables auth, and sets up daily backup cron to GCS.
set -euo pipefail

# --- Config (override via env or pass as args) ---
GCS_BACKUP_BUCKET="${GCS_BACKUP_BUCKET:-}"
MONGO_ADMIN_USER="${MONGO_ADMIN_USER:-admin}"
MONGO_ADMIN_PASSWORD="${MONGO_ADMIN_PASSWORD:-}"
MONGO_APP_USER="${MONGO_APP_USER:-todouser}"
MONGO_APP_PASSWORD="${MONGO_APP_PASSWORD:-}"

if [[ $# -ge 1 ]]; then
  GCS_BACKUP_BUCKET="$1"
fi
if [[ $# -ge 2 ]]; then
  MONGO_ADMIN_PASSWORD="$2"
fi
if [[ $# -ge 3 ]]; then
  MONGO_APP_PASSWORD="$3"
fi

if [[ -z "$GCS_BACKUP_BUCKET" ]]; then
  echo "Usage: $0 <GCS_BACKUP_BUCKET> <MONGO_ADMIN_PASSWORD> [MONGO_APP_PASSWORD]" >&2
  echo "  Or set GCS_BACKUP_BUCKET, MONGO_ADMIN_PASSWORD, and optionally MONGO_APP_PASSWORD (default app user: todouser)." >&2
  exit 1
fi

if [[ -z "$MONGO_ADMIN_PASSWORD" ]]; then
  echo "Error: MONGO_ADMIN_PASSWORD is required (pass as second argument or set MONGO_ADMIN_PASSWORD env)." >&2
  echo "  Authentication is enforced; provide a strong admin password." >&2
  exit 1
fi

# Generate app password if not provided (for tododb application user)
if [[ -z "$MONGO_APP_PASSWORD" ]]; then
  MONGO_APP_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
fi

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
  # Disable any GCE/cloud repo that may point to dead mirrors
  for f in /etc/apt/sources.list.d/*.list; do
    [[ -f "$f" ]] && mv "$f" "$f.disabled" 2>/dev/null || true
  done
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

# --- Enable auth and create admin user (always run; admin password required at script start) ---
enable_auth() {
  echo "[*] Enabling MongoDB auth and creating admin user..."
  # Start without auth to create user (use Debian default dbPath)
  systemctl stop mongod || true
  install -o mongodb -g mongodb -d /var/lib/mongodb 2>/dev/null || true
  chown -R mongodb:mongodb /var/lib/mongodb
  mongod --bind_ip_all --noauth --dbpath /var/lib/mongodb &
  local pid=$!
  sleep 5

  mongo --quiet --eval "
    db = db.getSiblingDB('admin');
    db.createUser({
      user: '${MONGO_ADMIN_USER}',
      pwd: '${MONGO_ADMIN_PASSWORD}',
      roles: [ { role: 'root', db: 'admin' } ]
    });
  "
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  sleep 1

  # Enable auth in config
  local conf=/etc/mongod.conf
  if ! grep -q 'authorization: enabled' "$conf" 2>/dev/null; then
    sed -i '/security:/,/^[^ ]/ s/^  *#* *security:.*/security:\n  authorization: enabled/' "$conf" || true
    if ! grep -q 'authorization: enabled' "$conf"; then
      echo 'security:' >> "$conf"
      echo '  authorization: enabled' >> "$conf"
    fi
  fi

  chown -R mongodb:mongodb /var/lib/mongodb
  systemctl start mongod
  echo "[*] Auth enabled and admin user created."
}

# --- Bind MongoDB to VM internal IP (GKE-only access; firewall restricts 27017 to GKE subnet) ---
configure_bind_ip() {
  echo "[*] Binding MongoDB to VM internal IP..."
  local internal_ip
  internal_ip=$(curl -sS -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip) || internal_ip=$(hostname -I | awk '{print $1}')
  if [[ -z "$internal_ip" ]]; then
    echo "Error: Could not determine VM internal IP." >&2
    exit 1
  fi
  local conf=/etc/mongod.conf
  # Set bindIp to 127.0.0.1,<internal_ip> so local backup and GKE can connect
  if grep -q '^net:' "$conf"; then
    sed -i "/^net:/,/^[^ ]/ s/bindIp:.*/bindIp: 127.0.0.1,${internal_ip}/" "$conf"
  else
    echo "net:" >> "$conf"
    echo "  port: 27017" >> "$conf"
    echo "  bindIp: 127.0.0.1,${internal_ip}" >> "$conf"
  fi
  systemctl restart mongod
  echo "[*] MongoDB bound to 127.0.0.1,${internal_ip} (restarted)."
}

# --- Create tododb, collection, sample document, and app user with readWrite on tododb ---
create_tododb_and_app_user() {
  echo "[*] Creating tododb, sample data, and application user..."
  local mongo_auth="-u ${MONGO_ADMIN_USER} -p ${MONGO_ADMIN_PASSWORD} --authenticationDatabase admin"
  local creds_file="/etc/mongodb-app-credentials.conf"

  mongo $mongo_auth --quiet --eval "
    db = db.getSiblingDB('tododb');
    db.tasks.insertOne({ title: 'Welcome task', completed: false, createdAt: new Date() });
    if (db.tasks.countDocuments() !== 1) { throw new Error('Sample document insert failed'); }
  " || { echo "Error: Failed to create tododb or insert sample document." >&2; exit 1; }

  mongo $mongo_auth --quiet --eval "
    db = db.getSiblingDB('tododb');
    db.createUser({
      user: '${MONGO_APP_USER}',
      pwd: '${MONGO_APP_PASSWORD}',
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

  # Store credentials for cron (root only) if auth was set
  if [[ -n "$MONGO_ADMIN_PASSWORD" ]]; then
    printf 'MONGO_BACKUP_USER="%s"\nMONGO_BACKUP_PASSWORD="%s"\n' "$MONGO_ADMIN_USER" "$MONGO_ADMIN_PASSWORD" > "$creds_file"
    chmod 600 "$creds_file"
  fi

  cat > "$backup_script" << 'BACKUP_SCRIPT'
#!/usr/bin/env bash
# Daily MongoDB dump and upload to GCS. Uses VM service account (no key needed).
set -euo pipefail
BUCKET="{{GCS_BACKUP_BUCKET}}"
CREDS_FILE="/etc/mongodb-backup-credentials.conf"
DUMP_DIR="/tmp/mongodb-backup-$$"
LOG="/var/log/mongodb-backup.log"

mkdir -p "$DUMP_DIR"
trap "rm -rf '$DUMP_DIR'" EXIT

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
BACKUP_SCRIPT
  sed -i "s|{{GCS_BACKUP_BUCKET}}|$GCS_BACKUP_BUCKET|g" "$backup_script"
  chmod +x "$backup_script"

  (crontab -l 2>/dev/null | grep -v mongodb-backup-to-gcs || true; echo "0 * * * * $backup_script") | crontab -
  echo "[*] Cron set: every hour at minute 0 (0 * * * *)."
}

# --- Main ---
install_mongodb
enable_auth
configure_bind_ip
create_tododb_and_app_user
install_gsutil
setup_backup_cron
echo "[*] MongoDB setup and backup automation complete."
echo "[*] App user: $MONGO_APP_USER (password in /etc/mongodb-app-credentials.conf on this VM)."
