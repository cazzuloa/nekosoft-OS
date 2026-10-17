#!/bin/bash
# Script d'installation pour NekoSoft basé sur Trisquel Mini 12.
# Projet SAE 1.03
# Tout droit réserver @cazzuloa | https://github.com/cazzuloa/nekosoft-OS

set -euo pipefail
# -x uniquement en debug : DEBUG=1 sudo -E bash setup.sh
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Root requis : tout le script (apt, systemctl, mysql, /etc, /home/...) l'exige.
if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERREUR] Lancer en root : sudo bash $0" >&2
    exit 1
fi

function __banner() {
    clear || true

    echo "[0;35m          [0;37m [0;35m          [0;37m [0;35m▐▓▒▒      [0;37m [0;35m          [0;37m [0;35m          [0;37m [0;35m          [0;37m [0;35m ▄▓████▄[0;37m [0;35m▐▓▓▒   [0m"
    echo "[0;35m          [0;37m [0;35m          [0;37m [0;35m▐▓▓▓  ▄[0;90;45m▀▀[0;90m▄[0;37m [0;35m          [0;37m [0;35m          [0;37m [0;35m          [0;37m [0;35m▐██▓ ▀██[0;37m [0;35m▐██▓   [0m"
    echo "[0;35m▄▄▄ ▄▄▄   [0;37m [0;35m   ▄▄▄▄▄  [0;37m [0;35m▐███ [0;90m▐[0;90;45m▄[0;35m███[0;37m [0;35m   ▄▄▄▄   [0;37m [0;35m    ▄▄▄▄▄▄[0;37m [0;35m   ▄▄▄▄   [0;37m [0;35m▐███  █▀[0;37m [0;35m▐███   [0m"
    echo "[0;35m▐[0;95;45m░░░░░░░[0;35m▄ [0;37m [0;35m ▄[0;95;45m▒▒▒▒▒▒▒[0;95m▄[0;37m [0;35m▐███  [0;90;45m▌[0;35m█[0;95;45m░[0;35m▌[0;37m [0;35m ▄[0;95;45m▒▒▒▒▒▒[0;95m▄[0;35m [0;37m [0;35m  ▄[0;95;45m▒▒▒▒▒▒[0;35m▓[0;37m [0;35m ▄[0;95;45m▒▒▒▒▒▒[0;95m▄[0;35m [0;37m [0;35m▐[0;95;45m░[0;35m██    [0;37m [0;35m▐[0;95;45m░[0;35m██▓▒░[0m"
    echo "[0;35m▐[0;95;45m▒▒▒[0;35m▀[0;95;45m░░▒▒▒[0;37m [0;35m▐[0;95;45m▒▒▒[0;35m▀▐[0;95;45m▒▒▒[0;95m▓[0;37m [0;35m▐[0;95;45m░░░[0;35m▄[0;90;45m▀[0;95;45m░░[0;35m▀ [0;37m [0;35m▐[0;95;45m▒▒▒[0;35m▀▐[0;95;45m▒▒▒[0;95m▌[0;37m [0;35m▐[0;95;45m▓▓▓▓[0;95m▀[0;35m    [0;37m [0;35m▐[0;95;45m▒▒▒[0;35m▀▐[0;95;45m▒▒▒[0;95m▌[0;37m [0;35m▐[0;95;45m░░░[0;35m▄[0;95;45m▒▓[0;35m▄[0;37m [0;35m▐[0;95;45m░░░[0;35m   [0m"
    echo "[0;95m▐[0;95;45m▓▓▒[0;35m ▐[0;95;45m▒▒▓▓[0;37m [0;95m▐[0;95;45m▓▓▓[0;35m [0;95m▐[0;95;45m▓▓▓[0;95m▓[0;37m [0;95m▐[0;95;45m▒▒▒▒▒▒▒[0;90;45m▀[0;35m [0;37m [0;95m▐[0;95;45m▓▓▓[0;35m ▐[0;95;45m▓▓▓[0;95m█[0;37m [0;35m▐[0;95m████[0;95;45m▄[0;35m    [0;37m [0;95m▐[0;95;45m▓▓▓[0;35m ▐[0;95;45m▓▓▓[0;95m█[0;37m [0;35m▐[0;95;45m▒▒▒░░▒░[0;37m [0;35m▐[0;95;45m▒▒▒[0;35m   [0m"
    echo "[0;95m▐██[0;95;45m▓[0;35m ▐[0;95;45m▓▓[0;95m██[0;37m [0;95m▐███[0;35m [0;95m▐██[0;95;45m▀[0;35m▀[0;37m [0;95m▐[0;95;45m▒▒▒[0;35m▌▀[0;95;45m▒▒▒[0;35m▌[0;37m [0;95m▐███[0;35m ▐[0;95m████[0;37m [0;35m ▀[0;95;45m▀▓▓▓▓[0;35m▄  [0;37m [0;95m▐███[0;35m ▐[0;95m████[0;37m [0;95m▐[0;95;45m▓▓▒[0;35m ▀▀ [0;37m [0;95m▐[0;95;45m▓▓▒[0;35m   [0m"
    echo "[0;95m▐███[0;35m ▐[0;95m████[0;37m [0;95m▐███▄[0;95;45m▀[0;95m▀[0;90m▀[0;35m  [0;37m [0;95m▐[0;95;45m▓▓▓[0;35m▌ [0;95;45m▓▓▓[0;35m█[0;37m [0;95m▐███[0;35m ▐[0;95m████[0;37m [0;35m    ▀[0;95;45m░▒▒▒[0;35m▄[0;37m [0;95m▐███[0;35m ▐[0;95m████[0;37m [0;95m▐██[0;95;45m▓[0;35m    [0;37m [0;95m▐██[0;95;45m▓[0;35m   [0m"
    echo "[0;95m▐[0;95;45m▓▓[0;95m█[0;35m ▐[0;95m█[0;95;45m▓▓▓[0;37m [0;95m▐[0;95;45m▓▓▓[0;35m  ▄▄▄▄[0;37m [0;95m▐███[0;35m▌ [0;95m████[0;37m [0;95m▐[0;95;45m▓▓▓[0;35m ▐[0;95;45m▓▓[0;95m██[0;37m [0;35m     ▐[0;95;45m░░░░[0;37m [0;95m▐[0;95;45m▓▓▓[0;35m ▐[0;95;45m▓▓[0;95m██[0;37m [0;95m▐███[0;35m    [0;37m [0;95m▐███[0;35m   [0m"
    echo "[0;35m▐[0;95;45m▒▓▓[0;35m ▐[0;95;45m▓▓▒▒[0;37m [0;35m▐[0;95;45m▒▒▒[0;35m  [0;95;45m▒▓▓▓[0;37m [0;95m▐███[0;35m▌ [0;95m████[0;37m [0;35m▐[0;95;45m▒▒▒[0;35m ▐[0;95;45m▒▓▓▓[0;37m [0;35m     ▄███[0;95;45m░[0;37m [0;35m▐[0;95;45m▒▒▒[0;35m ▐[0;95;45m▒▓▓▓[0;37m [0;95m▐███[0;35m    [0;37m [0;95m▐███[0;35m   [0m"
    echo "[0;35m▐[0;95;45m▒▒▒[0;35m ▐[0;95;45m▒▒▒░[0;37m [0;35m▐[0;95;45m░░░[0;35m▄[0;90;45m▀[0;95;45m▒▒▒[0;35m▌[0;37m [0;95m▐█[0;95;45m▓▓[0;35m▌ [0;95;45m▓▓▓[0;95m█[0;37m [0;35m▐[0;95;45m░░░[0;35m▄█[0;95;45m▒▒▒[0;35m▌[0;37m [0;35m ░▒▓█████▀[0;37m [0;35m▐[0;95;45m░░░[0;35m▄█[0;95;45m▒▒▒[0;35m▌[0;37m [0;95m▐[0;95;45m▓▓▓[0;35m    [0;37m [0;95m▐[0;95;45m▓▓▓[0;35m   [0m"
    echo "[0;35m▐[0;95;45m░░░[0;35m ▐[0;95;45m░░░░[0;37m [0;35m ▀[0;90;45m▄[0;35m█[0;95;45m░░░[0;90;45m▄[0;35m▀ [0;37m [0;35m▐[0;95;45m▓▓▒[0;35m▌ [0;95;45m▒▒▒[0;35m█[0;37m [0;35m ▀[0;90;45m▄[0;35m█[0;95;45m░░░[0;90;45m▄[0;35m▀ [0;37m [0;35m ░▒▓███▀  [0;37m [0;35m ▀[0;90;45m▄[0;35m█[0;95;45m░░░[0;90;45m▄[0;35m▀ [0;37m [0;95m▐[0;95;45m▒▒▒[0;35m    [0;37m [0;95m▐[0;95;45m▒▒▒[0;35m   [0m"

    printf "%s\n\n" "(c) Copyright github.com/cazzuloa"
}

__banner

export DEBIAN_FRONTEND=noninteractive
# Utilisateur dev réel : SUDO_USER en priorité (sudo bash setup.sh),
# sinon logname, sinon premier utilisateur avec un /home/*.
# On valide qu'il existe, sinon usermod/chown planteraient plus loin.
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
    echo "[ERREUR] Utilisateur dev introuvable (DEV_USER vide ou inexistant)." >&2
    echo "         Lance avec : sudo DEV_USER=test bash $0" >&2
    exit 1
fi
echo "[@] NekoSoft install - user dev: $DEV_USER"

echo "[@] Mise à jour de la liste des paquets"
apt update && apt upgrade -y

# phpMyAdmin en non-interactif : pré-sélection debconf pour éviter le prompt
# du choix du serveur web (apache2) et de dbconfig-common.
echo "[@] Pré-configuration phpMyAdmin (debconf non-interactif)"
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections || true
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections || true

echo "[@] Installation des paquets necessaire"
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

# phpMyAdmin : config auto apache
echo "[@] phpMyAdmin : config auto apache"
if [ ! -e /etc/apache2/conf-enabled/phpmyadmin.conf ] && [ -e /etc/phpmyadmin/apache.conf ]; then
    ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
    a2enconf phpmyadmin
fi

# Services
echo "[@] Activation des services apache2, mariadb et ssh"
if pidof systemd >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now apache2 mariadb ssh
else
    # Conteneur / live sans systemd : démarre au mieux, sans faire échouer le deploy.
    service mariadb start || service mysql start || true
    service apache2 start || true
    service ssh start || true
fi

# MariaDB sécur mini (idempotent : relançable sans planter).
# Contexte du bug : l'ancien script faisait
#   ALTER USER 'root'@'localhost' ACCOUNT LOCK;
# Au 2e lancement, 'mysql -e ...' en root via unix_socket échouait avec
#   ERROR 4151 (HY000): Access denied, this account is locked
# et 'set -e' stoppait tout le déploiement (Forgejo, Borg, fond d'écran...).
# On ne locke PLUS root : sur Ubuntu/Trisquel root est déjà en unix_socket
# (connexion locale root-only, sans mot de passe réseau) : c'est sécurisé
# ET ça garde mysqldump + phpmyadmin + relances fonctionnels.
# Réparation d'une VM déjà cassée : niveau 3 ci-dessous. Piège documenté
# dans __mariadb_unlock_skip_grant : FLUSH PRIVILEGES AVANT l'UNLOCK rejoue
# le verrou et condamne la réparation (c'est le bug vu avec ERROR 4151).
echo "[@] MariaDB sécur mini"
echo "[@] Attente du démarrage de MariaDB"
for i in $(seq 1 30); do
    if mariadb-admin --user=root ping --silent 2>/dev/null \
        || mysqladmin --user=root ping --silent 2>/dev/null; then
        break
    fi
    if [[ "$i" -eq 30 ]]; then
        echo "[ERREUR] MariaDB ne répond pas après 30s (mariadb-admin ping)" >&2
        exit 1
    fi
    sleep 1
done

# Helper : exécute SQL en root via unix_socket, avec réparation auto si locké.
# Niveau 1 : root unix_socket direct (cas nominal).
# Niveau 2 : debian-sys-maint (si présent, répare un LOCK posé par l'ancien script).
# Niveau 3 : redémarrage temporaire en skip-grant-tables (récupération root
#             sans aucun mot de passe : fonctionne même si
#             /etc/mysql/debian.cnf n'existe pas, comme sur Trisquel Mini).
#             Le déverrouillage se fait DIRECTEMENT dans les tables système
#             (account_locked), jamais via FLUSH PRIVILEGES + ALTER USER.
__mariadb_service() {
    # $1 = start|stop|restart
    if pidof systemd >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
        systemctl "$1" mariadb 2>/dev/null || systemctl "$1" mysql 2>/dev/null || true
    else
        service mariadb "$1" 2>/dev/null || service mysql "$1" 2>/dev/null || true
    fi
}
__mariadb_wait_alive() {
    # $1 = tentatives max (défaut 30)
    local n="${1:-30}"
    for i in $(seq 1 "$n"); do
        if mariadb-admin ping --silent 2>/dev/null \
            || mysqladmin ping --silent 2>/dev/null; then
            return 0
        fi
        if [[ "$i" -eq "$n" ]]; then
            return 1
        fi
        sleep 1
    done
}
__mariadb_wait_down() {
    # $1 = tentatives max (défaut 30) ; vrai dès que le serveur ne répond plus.
    local n="${1:-30}"
    for i in $(seq 1 "$n"); do
        if ! (mariadb-admin ping --silent 2>/dev/null \
            || mysqladmin ping --silent 2>/dev/null); then
            return 0
        fi
        sleep 1
    done
    return 1
}
__mariadb_force_stop() {
    # Arrête tout mariadbd/mysqld résiduel même s'il n'est pas géré par
    # systemd (orphelin d'un run précédent interrompu : seul le wrapper
    # mysqld_safe avait été tué). Il tient encore le socket/pid/datadir et
    # mysqld_safe refuse alors de démarrer ("A mysqld process already exists").
    # Nettoie aussi socket/pid éventuellement périmés.
    if ! pidof mariadbd >/dev/null 2>&1 && ! pidof mysqld >/dev/null 2>&1; then
        return 0
    fi
    echo "[@] Processus MariaDB résiduel détecté : arrêt forcé"
    for p in $(pidof mariadbd 2>/dev/null; pidof mysqld 2>/dev/null); do
        kill "$p" 2>/dev/null || true
    done
    for i in $(seq 1 30); do
        if ! pidof mariadbd >/dev/null 2>&1 && ! pidof mysqld >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    if pidof mariadbd >/dev/null 2>&1 || pidof mysqld >/dev/null 2>&1; then
        for p in $(pidof mariadbd 2>/dev/null; pidof mysqld 2>/dev/null); do
            kill -9 "$p" 2>/dev/null || true
        done
        sleep 2
    fi
    rm -f /run/mysqld/mysqld.pid /run/mysqld/mysqld.sock /run/mysqld/mysqld.sock.lock 2>/dev/null || true
    return 0
}
__mariadb_unlock_skip_grant() {
    echo "[@] Réparation root MariaDB via skip-grant-tables (aucun mot de passe requis)"
    __mariadb_service stop
    # Arrêt d'un éventuel serveur résiduel hors systemd (orphelin d'un run
    # précédent) : sinon il tient le socket et mysqld_safe refuse de démarrer
    # ("A mysqld process already exists").
    __mariadb_force_stop
    # Attendre l'arrêt effectif : sinon le socket reste occupé et le
    # serveur de réparation ne peut pas démarrer derrière.
    __mariadb_wait_down 30 || true
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
    if [[ "$ok" -ne 1 ]]; then
        echo "[ERREUR] Serveur de réparation MariaDB injoignable : arrêt du service échoué ou démarrage KO (voir $REPAIR_LOG)" >&2
        kill "$repair_pid" 2>/dev/null || true
        return 1
    fi
    # PIÈGE (cause du bug observé) : ne JAMAIS faire FLUSH PRIVILEGES ici.
    # Le FLUSH réactive les contrôles d'accès AVANT que root soit déverrouillé ;
    # le verrou posé par l'ancien script (ACCOUNT LOCK) rejette alors la session
    # de réparation elle-même (ERROR 4151 "this account is locked") et le
    # déverrouillage ne s'exécute JAMAIS. Sous skip-grant-tables, on lève donc
    # le verrou DIRECTEMENT dans les tables système, sans réactiver les ACL :
    # le serveur de réparation les ignore, et le redémarrage normal relira les
    # tables corrigées.
    local unlock_sql
    if [[ -n "$(mysql --user=root -N -B -e "SELECT 1 FROM information_schema.tables WHERE table_schema='mysql' AND table_name='global_priv' LIMIT 1;" 2>/dev/null)" ]]; then
        # MariaDB >= 10.4 : le verrou est la clé account_locked du JSON
        # mysql.global_priv (mysql.user n'est plus qu'une vue en lecture).
        unlock_sql="UPDATE mysql.global_priv SET Priv = JSON_REMOVE(Priv, '\$.account_locked') WHERE User='root' AND Host='localhost';"
    else
        # Ancienne MariaDB (mysql.user = vraie table) : colonne account_locked.
        unlock_sql="UPDATE mysql.user SET account_locked='N' WHERE User='root' AND Host='localhost';"
    fi
    if ! mysql --user=root -e "$unlock_sql"; then
        echo "[ERREUR] Déverrouillage de root MariaDB impossible (voir $REPAIR_LOG)" >&2
        kill "$repair_pid" 2>/dev/null || true
        return 1
    fi
    # Arrêt du serveur de réparation : les ACL sont restées désactivées,
    # donc mysqladmin shutdown passe. Repli : tuer le serveur de réparation
    # (et lui seul), puis attendre qu'il lâche le socket.
    mariadb-admin --user=root shutdown 2>/dev/null || mysqladmin --user=root shutdown 2>/dev/null || true
    if ! __mariadb_wait_down 30; then
        __mariadb_force_stop
        __mariadb_wait_down 30 || true
    fi
    kill "$repair_pid" 2>/dev/null || true
    wait "$repair_pid" 2>/dev/null || true
    # Un arrêt forcé peut laisser socket/pid périmés : le service ne
    # redémarrerait pas. Plus aucun serveur ne tourne à ce stade.
    rm -f /run/mysqld/mysqld.sock /run/mysqld/mysqld.sock.lock /run/mysqld/mysqld.pid 2>/dev/null || true
    __mariadb_service start
    if ! __mariadb_wait_alive 30; then
        echo "[ERREUR] MariaDB ne redémarre pas après réparation" >&2
        return 1
    fi
    # Vérifie que root (unix_socket) répond vraiment, sinon la suite du
    # script échouerait avec un message moins clair.
    if ! mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
        echo "[ERREUR] root MariaDB toujours verrouillé après réparation (voir $REPAIR_LOG)" >&2
        return 1
    fi
    return 0
}
# Canal SQL privilégié : tableau MYSQL_ADMIN.
MYSQL_ADMIN=()
if mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
    MYSQL_ADMIN=(mysql --user=root)
elif [[ -f /etc/mysql/debian.cnf ]] && mysql --defaults-file=/etc/mysql/debian.cnf -e "SELECT 1;" >/dev/null 2>&1; then
    echo "[@] root MariaDB verrouillé par un ancien run : réparation via debian-sys-maint"
    MYSQL_ADMIN=(mysql --defaults-file=/etc/mysql/debian.cnf)
else
    if ! __mariadb_unlock_skip_grant; then
        exit 1
    fi
    MYSQL_ADMIN=(mysql --user=root)
fi
# Répare un éventuel LOCK posé par l'ancien script, puis sécurise sans locker.
"${MYSQL_ADMIN[@]}" -e "ALTER USER 'root'@'localhost' ACCOUNT UNLOCK;"
"${MYSQL_ADMIN[@]}" -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;"
"${MYSQL_ADMIN[@]}" -e "DELETE FROM mysql.user WHERE User='';"
"${MYSQL_ADMIN[@]}" -e "DROP DATABASE IF EXISTS test;"
"${MYSQL_ADMIN[@]}" -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
# Admin applicatif : IF NOT EXISTS + ALTER => mot de passe à jour à chaque run.
"${MYSQL_ADMIN[@]}" -e "CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
"${MYSQL_ADMIN[@]}" -e "ALTER USER 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root';"
"${MYSQL_ADMIN[@]}" -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
"${MYSQL_ADMIN[@]}" -e "FLUSH PRIVILEGES;"
# Preuve que root + admin fonctionnent (échoue avec set -e si cassé).
mysql --user=root -e "SELECT VERSION();" >/dev/null
MYSQL_PWD='nekosoft-root' mysql --user=admin -e "SELECT 1;" >/dev/null
echo "[@] MariaDB OK : root (unix_socket) + admin fonctionnels"


# /var/www/html accessible au dev
echo "[@] Configuration des droits d'accès de $DEV_USER à /var/www/html via le groupe www-data"
usermod -aG www-data "$DEV_USER"
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/www/html
# sticky dev : nouveaux fichiers héritent du groupe
chmod g+s /var/www/html

# Test PHP
echo "[@] Création de la page de test PHP dans /var/www/html"
echo "<?php phpinfo(); ?>" > /var/www/html/info.php
chown www-data:www-data /var/www/html/info.php

# Version PHP
echo "[@] Version de PHP :"
php -r 'echo PHP_VERSION, PHP_EOL;'

echo "[@] -----------------------------------------"
echo "[@] Installation de Forgejo"
FORGEJO_VERSION="12.0.3"
BIN_URL="https://codeberg.org/forgejo/forgejo/releases/download/v${FORGEJO_VERSION}/forgejo-${FORGEJO_VERSION}-linux-amd64"

echo "[@] Création de l'utilisateur système git"
id git 2>/dev/null || adduser --system --shell /bin/bash --gecos 'Git Version Control' --group --disabled-password --home /home/git git

echo "[@] Préparation des répertoires et des permissions de Forgejo"
mkdir -p /var/lib/forgejo /etc/forgejo /var/log/forgejo
chown git:git /var/lib/forgejo /var/log/forgejo
chmod 750 /var/lib/forgejo

echo "[@] Téléchargement de Forgejo ${FORGEJO_VERSION}"
wget -O /usr/local/bin/forgejo "$BIN_URL"
chmod +x /usr/local/bin/forgejo

# config minimale : sqlite (zéro dépendance, parfait pour poste dev), port 3000
echo "[@] Création de la configuration Forgejo (SQLite, port 3000)"
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

echo "[@] Création du service systemd Forgejo"
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

echo "[@] Activation et démarrage du service Forgejo"
systemctl daemon-reload
systemctl enable --now forgejo

echo "[@] Forgejo installé : http://localhost:3000 (1er compte = admin)"
systemctl status forgejo --no-pager | head -15


echo "[@] Préparation des sauvegardes Borg"
# DEV_USER déjà validé en tête de script : ne pas le réécraser (logname échoue en root).
REPO="/var/backups/nekosoft-borg"
PASSPHRASE_FILE="/root/.borg-passphrase"

echo "[@] Création du répertoire de sauvegarde"
mkdir -p /var/backups
chmod 700 /var/backups

# mot de passe généré une fois, conservé root-only (à justifier : clef hors poste en prod)
if [ ! -f "$PASSPHRASE_FILE" ]; then
    echo "[@] Génération de la passphrase Borg"
    openssl rand -base64 32 > "$PASSPHRASE_FILE"
    chmod 600 "$PASSPHRASE_FILE"
    echo "Passphrase générée dans $PASSPHRASE_FILE"
fi
export BORG_PASSPHRASE="$(cat "$PASSPHRASE_FILE")"

# init repo chiffré repokey-blake2 si nouveau
if [ ! -d "$REPO" ]; then
    echo "[@] Initialisation du dépôt Borg chiffré"
    borg init --encryption=repokey-blake2 "$REPO"
fi

# script de sauvegarde quotidien
echo "[@] Création du script de sauvegarde quotidien"
cat > /usr/local/bin/nekosoft-backup.sh <<'EOF'
#!/bin/bash
set -eu
export BORG_PASSPHRASE="$(cat /root/.borg-passphrase)"
REPO="/var/backups/nekosoft-borg"
# dump SQL avant borg (root via unix_socket : fonctionne car on ne locke plus root)
mariadb-dump --user=root --all-databases 2>/dev/null | gzip > /var/backups/all-databases.sql.gz || mysqldump --user=root --all-databases 2>/dev/null | gzip > /var/backups/all-databases.sql.gz || true
borg create --stats --compression lz4 \
    "$REPO::{now:%Y-%m-%d_%H:%M}" \
    /var/www/html \
    /var/backups/all-databases.sql.gz \
    /home \
    /etc/forgejo /etc/apache2 \
    --exclude '/home/*/.cache'
# rétention : 7 jours, 4 semaines, 6 mois
borg prune -v --list "$REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6
borg compact "$REPO"
EOF
chmod +x /usr/local/bin/nekosoft-backup.sh

# 1ère sauvegarde immédiate (preuve démo)
echo "[@] Exécution de la première sauvegarde Borg"
BORG_PASSPHRASE="$(cat "$PASSPHRASE_FILE")" /usr/local/bin/nekosoft-backup.sh || true
borg list "$REPO" || true

# cron quotidien 2h
echo "[@] Planification de la sauvegarde quotidienne à 2 h"
echo "0 2 * * * root /usr/local/bin/nekosoft-backup.sh >> /var/log/nekosoft-backup.log 2>&1" > /etc/cron.d/nekosoft-backup
chmod 644 /etc/cron.d/nekosoft-backup

echo "[@] Sauvegardes Borg configurées. Vérification : borg list $REPO"
echo "[@] Pour la soutenance : borg info $REPO montre le chiffrement repokey"

echo "[@] Configuration du fond d'écran NekoSoft"
WALL_URL="https://raw.githubusercontent.com/cazzuloa/nekosoft-OS/main/wallpapers/nekosoft-wallpaper-1920x1080.png"
WALL_DST="/usr/share/backgrounds/nekosoft-wallpaper.png"
# DEV_USER déjà validé en tête de script.

# 1. Installer le fond système
echo "[@] Téléchargement et installation du fond d'écran système"
mkdir -p /usr/share/backgrounds
if ! wget -O "$WALL_DST" "$WALL_URL"; then
    echo "[ATTENTION] Fond d'écran non téléchargé (hors-ligne ?) : suite sans wallpaper" >&2
    WALL_DST=""
fi
if [[ -n "$WALL_DST" ]]; then
chmod 644 "$WALL_DST"
fi

# 2. Config PCManFM (gestionnaire bureau LXDE) pour l'utilisateur actuel
# La session Trisquel-mini lit le profil "Trisquel-mini", pas "default".
# On fournit donc TOUS les profils : le bon est toujours trouvé.
echo "[@] Configuration du fond d'écran dans les profils PCManFM de $DEV_USER"
mkdir -p "/home/$DEV_USER/.config/pcmanfm/default"
cat > "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" <<EOF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=$WALL_DST
desktop_bg=#1E1B2E
desktop_fg=#FFFFFF
desktop_shadow=#000000
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=1
show_mounts=1
EOF
for p in lxde LXDE Trisquel-mini trisquel-mini; do
    mkdir -p "/home/$DEV_USER/.config/pcmanfm/$p"
    cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" "/home/$DEV_USER/.config/pcmanfm/$p/desktop-items-0.conf"
done
chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.config"

# Helper robuste : réécrit tous les profils + applique en live.
# (Évite le "sh -c ..." fragile dans le .desktop et le --wallpaper-mode=fill invalide :
#  pcmanfm CLI n'accepte que color|stretch|fit|center|tile.)
echo "[@] Installation du script d'application du fond d'écran"
cat > /usr/local/bin/nekosoft-wallpaper.sh <<SCRIPTEOF
#!/bin/bash
WALL=$WALL_DST
[ -f "\$WALL" ] || exit 0
for p in Trisquel-mini trisquel-mini LXDE lxde default; do
    D="\$HOME/.config/pcmanfm/\$p"
    mkdir -p "\$D"
    cat > "\$D/desktop-items-0.conf" <<CONF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=\$WALL
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
if [ -n "\${DISPLAY:-}" ] && command -v pcmanfm >/dev/null 2>&1; then
    pcmanfm --set-wallpaper="\$WALL" --wallpaper-mode=stretch || true
    pcmanfm --reconfigure || true
fi
exit 0
SCRIPTEOF
chmod 755 /usr/local/bin/nekosoft-wallpaper.sh

# 3. Modèle /etc/skel pour tout futur utilisateur (\$HOME via /etc/skel)
echo "[@] Configuration du fond d'écran pour les futurs utilisateurs"
for p in default lxde LXDE Trisquel-mini trisquel-mini; do
    mkdir -p "/etc/skel/.config/pcmanfm/$p"
    cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf"
done
find /etc/skel/.config/pcmanfm -type d -exec chmod 755 {} \;
find /etc/skel/.config/pcmanfm -type f -exec chmod 644 {} \;
# Autostart XDG (backup) : Exec direct, pas de sh -c
echo "[@] Configuration du démarrage automatique du fond d'écran"
cat > /etc/xdg/autostart/nekosoft-wallpaper.desktop <<EOF
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
# Autostart natif lxsession (méthode fiable, lue avant pcmanfm --desktop)
for S in LXDE Trisquel-mini; do
    F="/etc/xdg/lxsession/$S/autostart"
    [ -f "$F" ] || continue
    grep -q "nekosoft-wallpaper" "$F" || echo "@/usr/local/bin/nekosoft-wallpaper.sh" >> "$F"
done

# .bashrc NekoSoft + alias utiles dev (idempotent : pas de doublon si relancé)
echo "[@] Configuration du terminal NekoSoft et des alias développeur"
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
cp /etc/skel/.bashrc "/home/$DEV_USER/.bashrc.nekosoft-add" || true
# ajoute aussi à l'utilisateur actuel sans écraser
grep -q "NekoSoft" "/home/$DEV_USER/.bashrc" || cat /etc/skel/.bashrc >> "/home/$DEV_USER/.bashrc" || true
# Note: méthode propre = le bloc ci-dessus est déjà dans /etc/skel pour futurs users

# Marque-page Geany + page d'accueil ABrowser via skel
echo "[@] Préparation de la configuration Geany"
mkdir -p /etc/skel/.config/geany
mkdir -p "/home/$DEV_USER/.config/geany"

# 4. Écran de login LightDM aux couleurs NekoSoft
# Trisquel Mini : vrai fichier = /etc/lightdm/lightdm-gtk-greeter.conf (pas de .d/)
# Idempotent : nettoie les anciens blocs ajoutés avant de réécrire (évite doublons [greeter])
echo "[@] Configuration de l'écran de connexion LightDM avec le fond NekoSoft"
if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]]; then
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
else
    echo "[ATTENTION] /etc/lightdm/lightdm-gtk-greeter.conf absent (pas de LightDM ?) : étape ignorée" >&2
fi

# 5. Appliquer immédiatement si session LXDE active (ne casse rien sinon)
echo "[@] Application immédiate du fond d'écran et réparation des profils PCManFM"
sudo -u "$DEV_USER" /usr/local/bin/nekosoft-wallpaper.sh || true
# Répare aussi les profils existants de l'utilisateur actuel (cas Trisquel-mini)
for p in lxde LXDE Trisquel-mini trisquel-mini; do
    mkdir -p "/home/$DEV_USER/.config/pcmanfm/$p"
    cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" "/home/$DEV_USER/.config/pcmanfm/$p/desktop-items-0.conf"
done
chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.config"

echo "[@] Bureau NekoSoft configuré. Vérification possible avec un nouvel utilisateur :"
echo "sudo adduser testnek && sudo -u testnek cat ~/.config/pcmanfm/default/desktop-items-0.conf"

# 1. Forcer le français : ABrowser utilise les locales système + paquet abrowser-locale-fr
# On impose fr dans /etc/default/locale (pris en compte au login)
echo "[@] Configuration du français comme langue système"
update-locale LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr LC_ALL=fr_FR.UTF-8 || true
locale-gen fr_FR.UTF-8 || true

# 2. uBlock Origin : installation forcée entreprise (ne peut pas être désactivée)
# Doc Firefox Enterprise policies : ExtensionSettings + Extensions Install
# ABrowser lit /usr/lib/abrowser/distribution/policies.json (comme Firefox)
# On met aussi /etc/firefox/policies au cas où (ABrowser est un rebrand Firefox)
echo "[@] Configuration d'ABrowser et installation forcée de uBlock Origin"
UBLOCK_URL="https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
# ID officiel uBlock Origin :
UBLOCK_ID="uBlock0@raymondhill.net"

mkdir -p /usr/lib/abrowser/distribution /etc/firefox/policies
for D in /usr/lib/abrowser/distribution /etc/firefox/policies; do
cat > "$D/policies.json" <<EOF
{
  "policies": {
    "LanguagePacks": ["fr"],
    "RequestedLocales": ["fr"],
    "DisableTelemetry": true,
    "Extensions": {
      "Install": ["$UBLOCK_URL"]
    },
    "ExtensionSettings": {
      "$UBLOCK_ID": {
        "installation_mode": "force_installed",
        "install_url": "$UBLOCK_URL"
      }
    }
  }
}
EOF
done

# 3. Page d'accueil NekoSoft + moteur fr pour tout nouvel user via /etc/skel
mkdir -p /etc/skel/.mozilla
# On copie le profil actuel si uBlock déjà installé manuellement (bonus, pas obligatoire)
if [ -d "/home/$DEV_USER/.mozilla" ]; then
    cp -a "/home/$DEV_USER/.mozilla/." /etc/skel/.mozilla/ || true
fi

echo "[@] ABrowser configuré. Vérification : abrowser about:policies doit montrer uBlock force_installed"
echo "[@] Si besoin, installation manuelle de démonstration : https://addons.mozilla.org/fr/firefox/addon/ublock-origin/"

# --- Kodi : root déjà vérifié en tête de script, rien à re-vérifier ici ---

# 1. Dépôt universe (Trisquel/Ubuntu) : Kodi y est, 100% libre, pas de PPA/snap/flatpak
# Justification soutenance : on reste sur dépôt officiel libre, sans binaire proprio.
if command -v lsb_release >/dev/null 2>&1 && lsb_release -is 2>/dev/null | grep -qiE "trisquel|ubuntu"; then
  echo "[@] Activation du dépôt universe pour installer Kodi"
  apt update
  apt install -y software-properties-common || true
  add-apt-repository -y universe || true
fi

# 2. Install Kodi
echo "[@] Installation de Kodi"
apt update
apt install -y kodi

# 3. Vérif binaire + version (preuve démo/soutenance)
echo "[@] Vérification de l'installation de Kodi"
command -v kodi
kodi --version || true
dpkg -l kodi | tail -5

# 4. Français par défaut pour user actuel + futurs users via /etc/skel
# Kodi lit ~/.kodi/userdata/guisettings.xml ; on pré-seede locale.language fr_fr.
# Si Kodi écrase au 1er lancement, le réglage manuel reste : Interface > Regional > Language = French.
echo "[@] Configuration de Kodi en français pour l'utilisateur actuel et les futurs utilisateurs"
seed_kodi_fr() {
  BASE="$1/.kodi/userdata"
  mkdir -p "$BASE"
  if [ ! -f "$BASE/guisettings.xml" ]; then
    cat > "$BASE/guisettings.xml" <<'EOF'
<settings version="2">
  <section id="system">
    <category id="locale">
      <group id="1">
        <setting id="locale.language">resource.language.fr_fr</setting>
        <setting id="locale.country">France</setting>
        <setting id="locale.charset">DEFAULT</setting>
      </group>
    </category>
  </section>
</settings>
EOF
  fi
}

if [ -n "${DEV_USER:-}" ] && [ -d "/home/$DEV_USER" ]; then
  seed_kodi_fr "/home/$DEV_USER"
  chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.kodi"
fi
mkdir -p /etc/skel/.kodi/userdata
if [ ! -f /etc/skel/.kodi/userdata/guisettings.xml ]; then
  BASE="/etc/skel/.kodi/userdata"
  cat > "$BASE/guisettings.xml" <<'EOF'
<settings version="2">
  <section id="system">
    <category id="locale">
      <group id="1">
        <setting id="locale.language">resource.language.fr_fr</setting>
        <setting id="locale.country">France</setting>
        <setting id="locale.charset">DEFAULT</setting>
      </group>
    </category>
  </section>
</settings>
EOF
fi

# 5. Raccourci Bureau LXDE (le .desktop système existe déjà via le paquet)
# On le copie vers le Bureau de l'utilisateur + skel pour futurs users.
echo "[@] Création des raccourcis Kodi sur les bureaux"
if [ -f /usr/share/applications/kodi.desktop ]; then
    if [ -n "${DEV_USER:-}" ] && [ -d "/home/$DEV_USER" ]; then
        mkdir -p "/home/$DEV_USER/Bureau" "/home/$DEV_USER/Desktop"
        cp -f /usr/share/applications/kodi.desktop "/home/$DEV_USER/Bureau/kodi.desktop" || true
        cp -f /usr/share/applications/kodi.desktop "/home/$DEV_USER/Desktop/kodi.desktop" || true
        chmod +x "/home/$DEV_USER/Bureau/kodi.desktop" "/home/$DEV_USER/Desktop/kodi.desktop" || true
        chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/Bureau/kodi.desktop" "/home/$DEV_USER/Desktop/kodi.desktop" || true
    fi
    mkdir -p /etc/skel/Bureau /etc/skel/Desktop
    cp -f /usr/share/applications/kodi.desktop /etc/skel/Bureau/ || true
    cp -f /usr/share/applications/kodi.desktop /etc/skel/Desktop/ || true
    chmod +x /etc/skel/Bureau/kodi.desktop /etc/skel/Desktop/kodi.desktop || true
fi

echo "[@] Kodi installé : lancez 'kodi' ou cliquez sur l'icône du bureau"
echo "[@] Vérification : kodi --version puis Interface > Regional > Language = French"
