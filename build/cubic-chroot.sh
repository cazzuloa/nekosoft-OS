#!/bin/bash
# NekoSoft SAE103 - CUBIC CHROOT
# À coller DANS le terminal chroot de Cubic (onglet Terminal, tu es déjà root)
# Ne lance PAS les 00-04 ici (systemd ne tourne pas en chroot).
# Ce script fait tout en mode "image" : install + enable, pas de start.
set -eux

export DEBIAN_FRONTEND=noninteractive

# --- 0. Vérifs ---
df -h /
ls -lh /usr/share/backgrounds/ || true
cat /etc/os-release | head -3

apt update

# --- 1. LAMP + outils (SANS démarrer les services) ---
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

# conf phpmyadmin -> apache (sans restart, Cubic s'en charge au boot)
if [ ! -e /etc/apache2/conf-enabled/phpmyadmin.conf ] && [ -e /etc/phpmyadmin/apache.conf ]; then
  ln -sf /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
  a2enconf phpmyadmin || true
fi
a2enmod php || true

# enable seulement (pas de --now, pas de systemd en chroot)
systemctl enable apache2 mariadb ssh || true

# /var/www/html modèle : droits + page test
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
chmod g+s /var/www/html
echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown www-data:www-data /var/www/html/info.php
# groupe www-data pour futurs devs (le user sera créé à l'install)
# + page d'accueil NekoSoft
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8">
<title>NekoSoft 🐾 poste dev</title>
<style>body{font-family:sans-serif;background:#1E1B2E;color:#fff;text-align:center;padding:10vh 5vw}h1{font-size:3em}a{color:#FF9ED2}</style>
</head><body><h1>🐾 NekoSoft</h1><p>Apache + MariaDB + PHP OK</p>
<p><a href="/info.php">phpinfo</a> • <a href="/phpmyadmin/">phpMyAdmin</a> • <a href="http://localhost:3000">Forgejo:3000</a></p>
</body></html>
EOF
chown www-data:www-data /var/www/html/index.html

# --- 2. Forgejo (binaire + service enabled, pas started) ---
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

# --- 3. Backup chiffré (script + cron, init au 1er boot) ---
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

# --- 4. Wallpaper + LXDE + LightDM + /etc/skel ---
# Le PNG doit être copié AVANT : dans Cubic, onglet Files ou :
#   wget http://10.0.2.2:8000/nekosoft-pack/nekosoft-wallpaper-1920x1080.png -O /tmp/wall.png
WALL_SRC=""
for c in ./nekosoft-wallpaper-1920x1080.png /tmp/wall.png /tmp/nekosoft-wallpaper-1920x1080.png /root/nekosoft-wallpaper-1920x1080.png; do
  [ -f "$c" ] && WALL_SRC="$c" && break
done
if [ -z "$WALL_SRC" ]; then
  echo "ERREUR: wallpaper introuvable. Fais avant :"
  echo "  wget http://10.0.2.2:8000/nekosoft-pack/nekosoft-wallpaper-1920x1080.png -O /tmp/wall.png"
  exit 1
fi
mkdir -p /usr/share/backgrounds
cp "$WALL_SRC" /usr/share/backgrounds/nekosoft-wallpaper.png
chmod 644 /usr/share/backgrounds/nekosoft-wallpaper.png

# Helper robuste commun (tous profils + CLI valide stretch)
cat > /usr/local/bin/nekosoft-wallpaper.sh <<'SCRIPTEOF'
#!/bin/bash
WALL=/usr/share/backgrounds/nekosoft-wallpaper.png
[ -f "$WALL" ] || exit 0
for p in Trisquel-mini trisquel-mini LXDE lxde default; do
  D="$HOME/.config/pcmanfm/$p"
  mkdir -p "$D"
  cat > "$D/desktop-items-0.conf" <<CONF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=$WALL
desktop_bg=#1E1B2E
desktop_fg=#FFFFFF
desktop_shadow=#000000
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=1
show_mounts=1
CONF
done
if [ -n "${DISPLAY:-}" ] && command -v pcmanfm >/dev/null 2>&1; then
  pcmanfm --set-wallpaper="$WALL" --wallpaper-mode=stretch || true
  pcmanfm --reconfigure || true
fi
exit 0
SCRIPTEOF
chmod 755 /usr/local/bin/nekosoft-wallpaper.sh

# Profils : la session Trisquel-mini lit "Trisquel-mini", LXDE lit "LXDE"/"lxde".
for p in default lxde LXDE Trisquel-mini trisquel-mini; do
  mkdir -p "/etc/skel/.config/pcmanfm/$p"
  cat > "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf" <<'EOF'
[*]
wallpaper_mode=stretch
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
done
chmod -R a+rX /etc/skel/.config/pcmanfm
# Autostart système : force le fond à chaque login LXDE
cat > /etc/xdg/autostart/nekosoft-wallpaper.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=NekoSoft Wallpaper
Comment=Applique le fond d'ecran NekoSoft au demarrage de session
Exec=/usr/local/bin/nekosoft-wallpaper.sh
OnlyShowIn=LXDE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-LXDE-Autostart-enabled=true
EOF
chmod 644 /etc/xdg/autostart/nekosoft-wallpaper.desktop
mkdir -p /etc/skel/.config/autostart
cp /etc/xdg/autostart/nekosoft-wallpaper.desktop /etc/skel/.config/autostart/
# Autostart natif lxsession (fiable, lu avant pcmanfm --desktop)
for S in LXDE Trisquel-mini; do
  F="/etc/xdg/lxsession/$S/autostart"
  [ -f "$F" ] || continue
  grep -q "nekosoft-wallpaper" "$F" || echo "@/usr/local/bin/nekosoft-wallpaper.sh" >> "$F"
done

if ! grep -q "NekoSoft" /etc/skel/.bashrc 2>/dev/null; then
cat >> /etc/skel/.bashrc <<'EOF'

# --- NekoSoft ---
export PS1='\[\e[38;5;177m\]nekosoft🐾 \w \$ \[\e[0m\]'
# Fix #4 : bleu fonce (di=01;34) illisible sur fond sombre -> dossiers en cyan clair
if [ -x /usr/bin/dircolors ]; then
  eval "$(dircolors -b)"
fi
export LS_COLORS="di=01;36:${LS_COLORS//di=01;34/di=01;36}"
alias ll='ls -lh --color'
alias www='cd /var/www/html'
alias logs='sudo journalctl -xeu apache2 -u mariadb -u forgejo'
EOF
fi

mkdir -p /etc/lightdm
python3 <<'PYEOF'
import re
p = "/etc/lightdm/lightdm-gtk-greeter.conf"
t = open(p).read()
t = re.sub(r"^\[greeter\]\nbackground=.*\n(?:theme-name=.*\n)?(?:icon-theme-name=.*\n)?(?:font-name=.*\n)?", "", t, flags=re.M)
t = re.sub(r"\n{3,}", "\n\n", t)
if "nekosoft-wallpaper" not in t:
    t = t.rstrip() + "\n\n[greeter]\nbackground=/usr/share/backgrounds/nekosoft-wallpaper.png\ntheme-name=Adwaita-dark\nicon-theme-name=elementary\nfont-name=Cantarell 11\n"
open(p, "w").write(t)
PYEOF

# --- 5. ABrowser FR + uBlock forcé ---
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

# --- 6. Nettoyage pour ISO légère ---
apt clean
rm -rf /tmp/* /var/tmp/* /var/log/*.gz || true
du -sh /usr/share/backgrounds/nekosoft-wallpaper.png
echo "== CUBIC CHROOT OK. Clique Next dans Cubic pour générer l'ISO. =="
