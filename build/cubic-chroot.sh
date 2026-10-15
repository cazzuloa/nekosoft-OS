#!/bin/bash
# NekoSoft - script chroot Cubic (LAMP + Forgejo + backup + desktop + ABrowser)
set -eux

export DEBIAN_FRONTEND=noninteractive

df -h /
ls -lh /usr/share/backgrounds/ || true
cat /etc/os-release | head -3

apt update

apt install -y \
  apache2 mariadb-server \
  php libapache2-mod-php php-mysql php-cli php-mbstring php-zip php-gd php-curl \
  phpmyadmin \
  geany geany-plugins \
  abrowser abrowser-locale-fr \
  openssh-server \
  borgbackup gnupg openssl \
  lightdm-gtk-greeter-settings \
  wget curl unzip

if [ ! -e /etc/apache2/conf-enabled/phpmyadmin.conf ] && [ -e /etc/phpmyadmin/apache.conf ]; then
  ln -sf /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
  a2enconf phpmyadmin || true
fi
a2enmod php || true

# Pas de --now en chroot (pas de systemd actif) : enable uniquement
systemctl enable apache2 mariadb ssh || true

chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
chmod g+s /var/www/html
echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown www-data:www-data /var/www/html/info.php
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<title>NekoSoft 🐾 poste dev</title>
<style>body{font-family:sans-serif;background:#1E1B2E;color:#fff;text-align:center;padding:10vh 5vw}h1{font-size:3em}a{color:#FF9ED2}</style>
</head><body><h1>🐾 NekoSoft</h1><p>Apache + MariaDB + PHP OK</p>
<p><a href="/info.php">phpinfo</a> • <a href="/phpmyadmin/">phpMyAdmin</a> • <a href="http://localhost:3000">Forgejo:3000</a></p>
</body></html>
EOF
chown www-data:www-data /var/www/html/index.html

# Forgejo : binaire + service enable (demarre au boot, pas en chroot)
FORGEJO_VERSION="12.0.3"
id git 2>/dev/null || adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git
mkdir -p /var/lib/forgejo /etc/forgejo /var/log/forgejo
chown git:git /var/lib/forgejo /var/log/forgejo
chmod 750 /var/lib/forgejo
if [ ! -x /usr/local/bin/forgejo ]; then
  wget -O /usr/local/bin/forgejo "https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-amd64"
  chmod +x /usr/local/bin/forgejo
fi
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
EOF
chown git:git /etc/forgejo/app.ini; chmod 640 /etc/forgejo/app.ini
cat > /etc/systemd/system/forgejo.service <<'EOF'
[Unit]
Description=NekoSoft Forgejo
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
systemctl enable forgejo || true

# Backup chiffre : script + cron (init au premier boot)
mkdir -p /var/backups; chmod 700 /var/backups
cat > /usr/local/bin/nekosoft-backup.sh <<'EOF'
#!/bin/bash
set -eu
[ -f /root/.borg-passphrase ] || openssl rand -base64 32 > /root/.borg-passphrase; chmod 600 /root/.borg-passphrase
export BORG_PASSPHRASE="$(cat /root/.borg-passphrase)"
REPO="/var/backups/nekosoft-borg"
[ -d "$REPO" ] || borg init --encryption=repokey-blake2 "$REPO"
mysqldump --all-databases 2>/dev/null | gzip > /var/backups/all-databases.sql.gz || true
borg create --stats --compression lz4 "$REPO::{now:%Y-%m-%d_%H:%M}" /var/www/html /var/backups/all-databases.sql.gz /home /etc/forgejo /etc/apache2 --exclude '/home/*/.cache' || true
borg prune -v --list "$REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6 || true
borg compact "$REPO" || true
EOF
chmod +x /usr/local/bin/nekosoft-backup.sh
echo "0 2 * * * root /usr/local/bin/nekosoft-backup.sh >> /var/log/nekosoft-backup.log 2>&1" > /etc/cron.d/nekosoft-backup
chmod 644 /etc/cron.d/nekosoft-backup

# Wallpaper : PNG copie avant via Cubic (onglet Files)
WALL_SRC=""
for c in ./nekosoft-wallpaper-1920x1080.png /tmp/wall.png /tmp/nekosoft-wallpaper-1920x1080.png /root/nekosoft-wallpaper-1920x1080.png; do
  [ -f "$c" ] && WALL_SRC="$c" && break
done
if [ -z "$WALL_SRC" ]; then
  echo "ERREUR: wallpaper introuvable dans ./ /tmp/ /root/"
  exit 1
fi
mkdir -p /usr/share/backgrounds
cp "$WALL_SRC" /usr/share/backgrounds/nekosoft-wallpaper.png
chmod 644 /usr/share/backgrounds/nekosoft-wallpaper.png

# LXDE utilise le profil "lxde" : fournir default + lxde
mkdir -p /etc/skel/.config/pcmanfm/default /etc/skel/.config/pcmanfm/lxde
cat > /etc/skel/.config/pcmanfm/default/desktop-items-0.conf <<'EOF'
[*]
wallpaper_mode=fill
wallpaper_common=1
wallpaper=/usr/share/backgrounds/nekosoft-wallpaper.png
desktop_bg=#1E1B2E
desktop_fg=#FFFFFF
desktop_shadow=#000000
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=1
show_mounts=1
EOF
cp /etc/skel/.config/pcmanfm/default/desktop-items-0.conf /etc/skel/.config/pcmanfm/lxde/desktop-items-0.conf
cat > /etc/xdg/autostart/nekosoft-wallpaper.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=NekoSoft Wallpaper
Comment=Applique le fond d'ecran NekoSoft au demarrage de session
Exec=sh -c "sleep 2; pcmanfm --set-wallpaper /usr/share/backgrounds/nekosoft-wallpaper.png --wallpaper-mode=fill"
OnlyShowIn=LXDE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chmod 644 /etc/xdg/autostart/nekosoft-wallpaper.desktop
mkdir -p /etc/skel/.config/autostart
cp /etc/xdg/autostart/nekosoft-wallpaper.desktop /etc/skel/.config/autostart/

cat >> /etc/skel/.bashrc <<'EOF'

# --- NekoSoft ---
export PS1='\[\e[38;5;177m\]nekosoft🐾 \w \$ \[\e[0m\]'
alias ll='ls -lh --color'
alias www='cd /var/www/html'
alias logs='sudo journalctl -xeu apache2 -u mariadb -u forgejo'
EOF

mkdir -p /etc/lightdm
if ! grep -q "nekosoft-wallpaper" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
  cat >> /etc/lightdm/lightdm-gtk-greeter.conf <<EOF

[greeter]
background=/usr/share/backgrounds/nekosoft-wallpaper.png
theme-name=Adwaita-dark
icon-theme-name=elementary
font-name=Cantarell 11
EOF
fi

# ABrowser FR + uBlock force
update-locale LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr || true
locale-gen fr_FR.UTF-8 || true
UBLOCK_URL="https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
UBLOCK_ID="uBlock0@raymondhill.net"
mkdir -p /usr/lib/abrowser/distribution /etc/firefox/policies
for D in /usr/lib/abrowser/distribution /etc/firefox/policies; do
cat > "$D/policies.json" <<POLEOF
{
  "policies": {
    "RequestedLocales": ["fr"],
    "DisableTelemetry": true,
    "Extensions": { "Install": ["$UBLOCK_URL"] },
    "ExtensionSettings": { "$UBLOCK_ID": { "installation_mode": "force_installed", "install_url": "$UBLOCK_URL" } }
  }
}
POLEOF
done

apt clean
rm -rf /tmp/* /var/tmp/* /var/log/*.gz || true
du -sh /usr/share/backgrounds/nekosoft-wallpaper.png
echo "== CUBIC CHROOT OK =="
