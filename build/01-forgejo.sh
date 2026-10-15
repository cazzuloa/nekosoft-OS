#!/bin/bash
# NekoSoft - Forgejo (binaire officiel + service systemd)
# Usage: sudo bash 01-forgejo.sh
set -eux

FORGEJO_VERSION="12.0.3"
BIN_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-amd64"

id git 2>/dev/null || adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git

mkdir -p /var/lib/forgejo /etc/forgejo /var/log/forgejo
chown git:git /var/lib/forgejo /var/log/forgejo
chmod 750 /var/lib/forgejo

wget -O /usr/local/bin/forgejo "$BIN_URL"
chmod +x /usr/local/bin/forgejo

# Config SQLite, port 3000
cat > /etc/forgejo/app.ini <<'EOF'
[server]
DOMAIN           = localhost
HTTP_PORT        = 3000
ROOT_URL         = http://localhost:3000/
DISABLE_SSH      = false
SSH_PORT         = 22

[database]
DB_TYPE          = sqlite3
PATH             = /var/lib/forgejo/forgejo.db

[repository]
ROOT             = /home/git/repositories

[service]
DISABLE_REGISTRATION = false

[picture]
DISABLE_GRAVATAR = false
EOF
chown git:git /etc/forgejo/app.ini
chmod 640 /etc/forgejo/app.ini

cat > /etc/systemd/system/forgejo.service <<'EOF'
[Unit]
Description=NekoSoft Forgejo (Gitea fork)
After=network.target mariadb.service

[Service]
User=git
Group=git
Type=simple
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
Environment=USER=git HOME=/home/git

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now forgejo

echo "== Forgejo OK : http://localhost:3000 =="
