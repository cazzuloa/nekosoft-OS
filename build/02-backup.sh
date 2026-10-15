#!/bin/bash
# NekoSoft - sauvegarde chiffree BorgBackup (quotidienne)
# Usage: sudo bash 02-backup.sh
set -eux

DEV_USER="${DEV_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"
REPO="/var/backups/nekosoft-borg"
PASSPHRASE_FILE="/root/.borg-passphrase"

mkdir -p /var/backups
chmod 700 /var/backups

if [ ! -f "$PASSPHRASE_FILE" ]; then
  openssl rand -base64 32 > "$PASSPHRASE_FILE"
  chmod 600 "$PASSPHRASE_FILE"
fi
export BORG_PASSPHRASE="$(cat $PASSPHRASE_FILE)"

if [ ! -d "$REPO" ]; then
  borg init --encryption=repokey-blake2 "$REPO"
fi

cat > /usr/local/bin/nekosoft-backup.sh <<'EOF'
#!/bin/bash
set -eu
export BORG_PASSPHRASE="$(cat /root/.borg-passphrase)"
REPO="/var/backups/nekosoft-borg"
mysqldump --all-databases | gzip > /var/backups/all-databases.sql.gz || true
borg create --stats --compression lz4 \
  "$REPO::{now:%Y-%m-%d_%H:%M}" \
  /var/www/html \
  /var/backups/all-databases.sql.gz \
  /home \
  /etc/forgejo /etc/apache2 \
  --exclude '/home/*/.cache'
# Retention : 7 jours, 4 semaines, 6 mois
borg prune -v --list "$REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6
borg compact "$REPO"
EOF
chmod +x /usr/local/bin/nekosoft-backup.sh

BORG_PASSPHRASE="$(cat $PASSPHRASE_FILE)" /usr/local/bin/nekosoft-backup.sh || true
borg list "$REPO" || true

echo "0 2 * * * root /usr/local/bin/nekosoft-backup.sh >> /var/log/nekosoft-backup.log 2>&1" > /etc/cron.d/nekosoft-backup
chmod 644 /etc/cron.d/nekosoft-backup

echo "== Backup OK =="
