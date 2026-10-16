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
# + mysqldump + phpmyadmin. On répare aussi un éventuel LOCK précédent,
# y compris sans debian-sys-maint (absent sur Trisquel Mini) via un
# redémarrage temporaire en skip-grant-tables.
for i in $(seq 1 30); do
  if mariadb-admin ping --silent 2>/dev/null \
      || mysqladmin ping --silent 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "[ERREUR] MariaDB ne répond pas après 30s" >&2
    exit 1
  fi
  sleep 1
done
__mariadb_service() {
  if pidof systemd >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    systemctl "$1" mariadb 2>/dev/null || systemctl "$1" mysql 2>/dev/null || true
  else
    service mariadb "$1" 2>/dev/null || service mysql "$1" 2>/dev/null || true
  fi
}
__mariadb_wait_alive() {
  local n="${1:-30}"
  for i in $(seq 1 "$n"); do
    if mariadb-admin ping --silent 2>/dev/null \
        || mysqladmin ping --silent 2>/dev/null; then
      return 0
    fi
    if [ "$i" -eq "$n" ]; then
      return 1
    fi
    sleep 1
  done
}
__mariadb_unlock_skip_grant() {
  echo "Réparation root MariaDB via skip-grant-tables (aucun mot de passe requis)"
  __mariadb_service stop
  sleep 3
  mkdir -p /run/mysqld || true
  chown mysql:mysql /run/mysqld 2>/dev/null || chown mysql /run/mysqld 2>/dev/null || true
  REPAIR_LOG="/var/log/mariadb-repair.log"
  touch "$REPAIR_LOG" 2>/dev/null || REPAIR_LOG="/tmp/mariadb-repair.log"
  if command -v mysqld_safe >/dev/null 2>&1; then
    mysqld_safe --skip-grant-tables --skip-networking >>"$REPAIR_LOG" 2>&1 &
  else
    mariadbd-safe --skip-grant-tables --skip-networking >>"$REPAIR_LOG" 2>&1 &
  fi
  local repair_pid=$!
  local ok=0
  for i in $(seq 1 30); do
    if mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 1
  done
  if [ "$ok" -ne 1 ]; then
    echo "[ERREUR] Serveur de réparation MariaDB injoignable (voir $REPAIR_LOG)" >&2
    kill "$repair_pid" 2>/dev/null || true
    return 1
  fi
  mysql --user=root -e "FLUSH PRIVILEGES;"
  mysql --user=root -e "ALTER USER 'root'@'localhost' ACCOUNT UNLOCK;"
  mysql --user=root -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;"
  mysql --user=root -e "FLUSH PRIVILEGES;"
  mysqladmin --user=root shutdown || kill "$repair_pid" 2>/dev/null || true
  wait "$repair_pid" 2>/dev/null || true
  sleep 3
  __mariadb_service start
  if ! __mariadb_wait_alive 30; then
    echo "[ERREUR] MariaDB ne redémarre pas après réparation" >&2
    return 1
  fi
  return 0
}
MYSQL_ADMIN=()
if mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
  MYSQL_ADMIN=(mysql --user=root)
elif [ -f /etc/mysql/debian.cnf ] && mysql --defaults-file=/etc/mysql/debian.cnf -e "SELECT 1;" >/dev/null 2>&1; then
  echo "root MariaDB verrouillé par un ancien run : réparation via debian-sys-maint"
  MYSQL_ADMIN=(mysql --defaults-file=/etc/mysql/debian.cnf)
else
  if ! __mariadb_unlock_skip_grant; then
    exit 1
  fi
  MYSQL_ADMIN=(mysql --user=root)
fi
"${MYSQL_ADMIN[@]}" -e "ALTER USER 'root'@'localhost' ACCOUNT UNLOCK;"
"${MYSQL_ADMIN[@]}" -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;"
"${MYSQL_ADMIN[@]}" -e "DELETE FROM mysql.user WHERE User='';"
"${MYSQL_ADMIN[@]}" -e "DROP DATABASE IF EXISTS test;"
"${MYSQL_ADMIN[@]}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
"${MYSQL_ADMIN[@]}" -e "CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
"${MYSQL_ADMIN[@]}" -e "ALTER USER 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
"${MYSQL_ADMIN[@]}" -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
"${MYSQL_ADMIN[@]}" -e "FLUSH PRIVILEGES;"
mysql --user=root -e "SELECT VERSION();" >/dev/null
MYSQL_PWD='nekosoft-root' mysql --user=admin -e "SELECT 1;" >/dev/null
echo "MariaDB OK : root (unix_socket) + admin fonctionnels"

usermod -aG www-data "$DEV_USER"
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
chmod g+s /var/www/html

echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown www-data:www-data /var/www/html/info.php

echo "== Install OK =="
