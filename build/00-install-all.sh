#!/bin/bash
# NekoSoft - installation base (LAMP + outils)
# Usage: sudo bash 00-install-all.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERREUR: lancer en root : sudo bash $0" >&2
    exit 1
fi

if [[ -z "${DEV_USER:-}" ]]; then
    DEV_USER="${SUDO_USER:-}"
fi
if [[ -z "${DEV_USER:-}" ]]; then
    DEV_USER="$(logname 2>/dev/null || true)"
fi
if [[ -z "${DEV_USER:-}" ]]; then
    DEV_USER="$(ls -1 /home 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${DEV_USER:-}" ]] || ! id "$DEV_USER" >/dev/null 2>&1; then
    echo "[ERREUR] Utilisateur dev introuvable. Lance avec : sudo DEV_USER=test bash $0" >&2
    exit 1
fi
echo "== NekoSoft install - user dev: $DEV_USER =="

apt update

apt install -y \
  apache2 mariadb-server \
  php libapache2-mod-php php-mysql php-cli php-mbstring php-zip php-gd php-curl \
  phpmyadmin \
  geany geany-plugins \
  abrowser abrowser-locale-fr \
  openssh-server \
  borgbackup gnupg \
  lightdm-gtk-greeter-settings \
  wget curl unzip

# Expose phpMyAdmin via Apache
if [ ! -e /etc/apache2/conf-enabled/phpmyadmin.conf ] && [ -e /etc/phpmyadmin/apache.conf ]; then
  ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
  a2enconf phpmyadmin
fi

if pidof systemd >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  systemctl enable --now apache2 mariadb ssh
else
  service mariadb start || service mysql start || true
  service apache2 start || true
  service ssh start || true
fi

# Securisation MariaDB (idempotent : relançable).
# Ne JAMAIS locker root : root en unix_socket est déjà sécurisé, et
# ACCOUNT LOCK casse le 2e run avec ERROR 4151 (this account is locked)
# + mysqldump + phpmyadmin. On répare aussi un éventuel LOCK précédent.
for i in $(seq 1 30); do
  if mariadb-admin --user=root ping --silent 2>/dev/null \
      || mysqladmin --user=root ping --silent 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[ERREUR] MariaDB ne répond pas après 30s" >&2
    exit 1
  fi
  sleep 1
done
mysql_root() {
  if mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
    mysql --user=root "$@"
  elif [ -f /etc/mysql/debian.cnf ] && mysql --defaults-file=/etc/mysql/debian.cnf -e "SELECT 1;" >/dev/null 2>&1; then
    echo "root MariaDB verrouillé par un ancien run : réparation via debian-sys-maint"
    mysql --defaults-file=/etc/mysql/debian.cnf "$@"
  else
    mysql --user=root "$@"
  fi
}
mysql_root -e "ALTER USER 'root'@'localhost' ACCOUNT UNLOCK;"
mysql_root -e "DELETE FROM mysql.user WHERE User='';"
mysql_root -e "DROP DATABASE IF EXISTS test;"
mysql_root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
mysql_root -e "CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
mysql_root -e "ALTER USER 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
mysql_root -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
mysql_root -e "FLUSH PRIVILEGES;"

usermod -aG www-data "$DEV_USER"
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
chmod g+s /var/www/html

echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown www-data:www-data /var/www/html/info.php

echo "== Install OK =="
