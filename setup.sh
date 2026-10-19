#!/bin/bash
# =============================================================================
# NekoSoft - installation d'un poste de développement Web (Trisquel 12 Mini)
# SAE 1.03 - @cazzuloa | https://github.com/cazzuloa/nekosoft-OS
#
# Options : NEKO_MODE=chroot|live   FORGEJO_VERSION=x.y.z   DEV_USER=nom
#           NEKO_PHPINFO=1 (crée /var/www/html/info.php pour la démo)
# =============================================================================

set -Eeuo pipefail
trap 'echo "[ERREUR] ligne $LINENO : $BASH_COMMAND" >&2' ERR

[[ "${DEBUG:-0}" == "1" ]] && set -x

# ----------------------------- Paramètres ------------------------------------
NEKO_MODE="${NEKO_MODE:-auto}"
FORGEJO_VERSION="${FORGEJO_VERSION:-15.0.0}"   # 15.x = LTS (support jusqu'à juillet 2027). Mets la dernière 15.0.x.
WALL_URL="https://raw.githubusercontent.com/cazzuloa/nekosoft-OS/main/wallpapers/nekosoft-wallpaper-1920x1080.png"
WALL_DST="/usr/share/backgrounds/nekosoft-wallpaper.png"
UBLOCK_ID="uBlock0@raymondhill.net"
UBLOCK_AMO="https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
UBLOCK_LOCAL="/usr/share/nekosoft/ublock-origin.xpi"
STATE_DIR="/var/lib/nekosoft"
CRED_FILE="/root/nekosoft-credentials.txt"
SELF_INSTALLED="/usr/local/sbin/nekosoft-setup"
BASHRC_BLOCK="/usr/share/nekosoft/bashrc.block"
BASHRC_MARK="# --- NekoSoft ---"
BACKUP_BASE="/var/backups/nekosoft"
BORG_REPO="$BACKUP_BASE/borg"
BORG_PASSFILE="/root/.borg-passphrase"

SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
SCRIPT_DIR="$(dirname "${SELF:-/root/x}")"
MODE=""
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -y -o Dpkg::Options::=--force-confold)

# ----------------------------- Outils ----------------------------------------
if [[ -t 1 ]]; then C_INFO=$'\033[0;36m'; C_WARN=$'\033[0;33m'; C_OFF=$'\033[0m'
else C_INFO=''; C_WARN=''; C_OFF=''; fi
info() { printf '%s[@] %s%s\n' "$C_INFO" "$*" "$C_OFF"; }
warn() { printf '%s[!] %s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { echo "[ERREUR] $*" >&2; exit 1; }

rand() { openssl rand -hex 16; }

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "Lancer en root : sudo bash $0"
}

detect_mode() {
    if [[ "$NEKO_MODE" == "auto" ]]; then
        # systemd actif (PID 1) => machine réelle ; sinon => chroot Cubic
        if [[ -d /run/systemd/system ]]; then MODE="live"; else MODE="chroot"; fi
    else
        MODE="$NEKO_MODE"
    fi
    [[ "$MODE" == "live" || "$MODE" == "chroot" ]] || die "NEKO_MODE invalide : $MODE"
}

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

# ============================================================================
# ÉTAPE 1 : INSTALLATION STATIQUE (chroot ET live)
# ============================================================================

prepare_apt() {
    if [[ "$MODE" == "chroot" ]]; then
        # Interdit le démarrage des services pendant les postinst (pas de systemd en chroot)
        printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
        chmod 755 /usr/sbin/policy-rc.d
    fi

    info "Mise à jour des paquets"
    "${APT[@]}" update
    "${APT[@]}" upgrade

    # phpMyAdmin : sélection debconf non interactive.
    # dbconfig désactivé : il exigerait un MariaDB démarré (impossible en chroot).
    # phpMyAdmin fonctionne pour la connexion ; seules les "tables liées" avancées manquent.
    echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | debconf-set-selections
    echo "phpmyadmin phpmyadmin/dbconfig-install boolean false"            | debconf-set-selections
}

install_packages() {
    info "Installation des paquets"
    "${APT[@]}" install \
        apache2 mariadb-server \
        php libapache2-mod-php php-mysql php-cli php-mbstring php-zip php-gd php-curl php-xml \
        phpmyadmin \
        geany geany-plugins \
        abrowser abrowser-locale-fr \
        git borgbackup openssl ca-certificates acl \
        locales curl wget unzip \
        lightdm-gtk-greeter-settings
}

configure_apache() {
    info "Configuration d'Apache et de phpMyAdmin"
    a2enmod rewrite >/dev/null

    if [[ -e /etc/phpmyadmin/apache.conf ]]; then
        ln -sf /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
        a2enconf phpmyadmin >/dev/null
    fi

    # phpMyAdmin accessible uniquement depuis la machine elle-même
    cat > /etc/apache2/conf-available/zz-nekosoft-phpmyadmin-local.conf <<'EOF'
<Directory /usr/share/phpmyadmin>
    Require local
</Directory>
EOF
    a2enconf zz-nekosoft-phpmyadmin-local >/dev/null

    systemctl enable apache2 mariadb >/dev/null 2>&1 || true
}

configure_webroot() {
    info "Droits sur /var/www/html (groupe www-data + ACL par défaut)"
    chown -R www-data:www-data /var/www/html
    find /var/www/html -type d -exec chmod 2775 {} +
    find /var/www/html -type f -exec chmod 664 {} +
    # ACL : tout nouveau fichier créé par un membre de www-data reste lisible/écrivable par le groupe
    setfacl -R    -m g:www-data:rwX /var/www/html
    setfacl -R -d -m g:www-data:rwX /var/www/html

    if [[ "${NEKO_PHPINFO:-0}" == "1" ]]; then
        echo "<?php phpinfo(); ?>" > /var/www/html/info.php
        chown www-data:www-data /var/www/html/info.php
        warn "info.php créé : à supprimer après la démo"
    fi
}

install_forgejo() {
    info "Installation de Forgejo ${FORGEJO_VERSION}"
    [[ "$(uname -m)" == "x86_64" ]] || die "Binaire Forgejo prévu pour x86_64 uniquement"

    id git >/dev/null 2>&1 || adduser --system --shell /bin/bash --gecos 'Git Version Control' \
        --group --disabled-password --home /home/git git

    mkdir -p /var/lib/forgejo /var/log/forgejo /etc/forgejo
    chown git:git /var/lib/forgejo /var/log/forgejo
    chmod 750 /var/lib/forgejo
    chown root:git /etc/forgejo
    # 770 uniquement le temps de générer app.ini (fb_forgejo le repasse en 750).
    # Si app.ini existe déjà (setup.sh relancé), on ne rouvre pas le dossier.
    if [[ -f /etc/forgejo/app.ini ]]; then chmod 750 /etc/forgejo; else chmod 770 /etc/forgejo; fi

    local v="$FORGEJO_VERSION"
    local url="https://codeberg.org/forgejo/forgejo/releases/download/v${v}/forgejo-${v}-linux-amd64"
    local tmp; tmp="$(mktemp -d)"

    if [[ -x /usr/local/bin/forgejo ]] && /usr/local/bin/forgejo --version 2>/dev/null | grep -q "version ${v}"; then
        info "Forgejo ${v} déjà présent"
    else
        curl -fL --retry 3 -o "$tmp/forgejo"        "$url"
        curl -fL --retry 3 -o "$tmp/forgejo.sha256" "$url.sha256"
        local expected; expected="$(awk '{print $1}' "$tmp/forgejo.sha256")"
        echo "$expected  $tmp/forgejo" | sha256sum -c -   # abandonne si le hash ne correspond pas
        systemctl stop forgejo 2>/dev/null || true
        install -m 755 "$tmp/forgejo" /usr/local/bin/forgejo
    fi
    rm -rf "$tmp"

    # Le service n'est lancé que si /etc/forgejo/app.ini existe (créé au 1er démarrage)
    cat > /etc/systemd/system/forgejo.service <<'EOF'
[Unit]
Description=NekoSoft Forgejo (forge logicielle)
After=network.target
ConditionPathExists=/etc/forgejo/app.ini

[Service]
User=git
Group=git
Type=simple
WorkingDirectory=/var/lib/forgejo
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
RestartSec=2s
Environment=USER=git HOME=/home/git FORGEJO_WORK_DIR=/var/lib/forgejo

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable forgejo >/dev/null 2>&1 || true
}

install_backup_tools() {
    info "Installation du script et du timer de sauvegarde Borg"

    cat > /usr/local/bin/nekosoft-backup.sh <<'EOF'
#!/bin/bash
# Sauvegarde chiffrée (Borg repokey-blake2) : web, bases SQL, Forgejo, /home, config
set -euo pipefail
export BORG_PASSPHRASE="$(cat /root/.borg-passphrase)"
BASE=/var/backups/nekosoft
REPO="$BASE/borg"
STAGE="$BASE/staging"
mkdir -p "$STAGE"; chmod 700 "$BASE" "$STAGE"

# 1) Dump SQL (root via unix_socket). pipefail => une erreur de dump fait échouer la sauvegarde
if command -v mariadb-dump >/dev/null; then DUMP=mariadb-dump; else DUMP=mysqldump; fi
"$DUMP" --user=root --all-databases --single-transaction | gzip > "$STAGE/all-databases.sql.gz"

# 2) Base SQLite de Forgejo : copie cohérente (arrêt de quelques secondes)
if [[ -f /var/lib/forgejo/forgejo.db ]]; then
    was_active=0
    systemctl is-active --quiet forgejo && was_active=1
    [[ $was_active -eq 1 ]] && systemctl stop forgejo
    cp -a /var/lib/forgejo/forgejo.db "$STAGE/" || echo "[!] copie forgejo.db échouée" >&2
    [[ $was_active -eq 1 ]] && systemctl start forgejo
fi

# 3) Archive chiffrée
borg create --stats --compression lz4 \
    --exclude '/home/*/.cache' \
    --exclude '/var/lib/forgejo/forgejo.db*' \
    "$REPO::{hostname}-{now:%Y-%m-%d_%H:%M}" \
    /var/www/html "$STAGE" /home /etc/forgejo /etc/apache2 /var/lib/forgejo

# 4) Rétention : 7 jours, 4 semaines, 6 mois
borg prune --list "$REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6
borg compact "$REPO"
EOF
    chmod 755 /usr/local/bin/nekosoft-backup.sh

    cat > /etc/systemd/system/nekosoft-backup.service <<'EOF'
[Unit]
Description=NekoSoft - sauvegarde Borg chiffrée
ConditionPathExists=/var/backups/nekosoft/borg

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nekosoft-backup.sh
EOF

    # Timer (et pas cron à 2h) : les portables sont éteints la nuit => Persistent rattrape au prochain démarrage
    cat > /etc/systemd/system/nekosoft-backup.timer <<'EOF'
[Unit]
Description=NekoSoft - sauvegarde quotidienne

[Timer]
OnCalendar=*-*-* 12:30:00
Persistent=true
RandomizedDelaySec=20min

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable nekosoft-backup.timer >/dev/null 2>&1 || true
}

# ----------------------------- Personnalisation visuelle ---------------------

write_pcmanfm_conf() {   # $1 = fichier de destination
    mkdir -p "$(dirname "$1")"
    cat > "$1" <<EOF
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
}

install_wallpaper() {
    info "Fond d'écran NekoSoft"
    mkdir -p /usr/share/backgrounds
    local local_file="$SCRIPT_DIR/nekosoft-wallpaper.png"
    # En chroot Cubic : dépose nekosoft-wallpaper.png à côté du script => pas besoin d'Internet
    if [[ -f "$local_file" ]]; then
        install -m 644 "$local_file" "$WALL_DST"
    elif wget -q -O "$WALL_DST" "$WALL_URL"; then
        chmod 644 "$WALL_DST"
    else
        warn "Fond d'écran introuvable (ni fichier local, ni téléchargement) : étape ignorée"
        rm -f "$WALL_DST"
        return 0
    fi

    # Le profil lu dépend de la session : on les fournit tous (modèle /etc/skel)
    local p
    for p in default lxde LXDE Trisquel-mini trisquel-mini; do
        write_pcmanfm_conf "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf"
    done
    find /etc/skel/.config/pcmanfm -type d -exec chmod 755 {} +
    find /etc/skel/.config/pcmanfm -type f -exec chmod 644 {} +

    # Écran de connexion LightDM
    local greeter=/etc/lightdm/lightdm-gtk-greeter.conf
    if [[ -f "$greeter" ]]; then
        grep -q '^\[greeter\]' "$greeter" || printf '\n[greeter]\n' >> "$greeter"
        sed -i '/^background=/d' "$greeter"
        sed -i "/^\[greeter\]/a background=$WALL_DST" "$greeter"
    else
        warn "$greeter absent : écran de connexion non modifié"
    fi
}

install_bashrc_block() {
    info "Terminal NekoSoft (PS1, couleurs, alias)"
    mkdir -p /usr/share/nekosoft
    cat > "$BASHRC_BLOCK" <<'EOF'
# --- NekoSoft ---
export PS1='\[\e[38;5;177m\]nekosoft🐾 \w \$ \[\e[0m\]'
# dossiers en cyan clair (le bleu foncé est illisible sur fond sombre)
if [ -x /usr/bin/dircolors ]; then
    eval "$(dircolors -b)"
fi
export LS_COLORS="di=01;36:${LS_COLORS//di=01;34/di=01;36}"
alias ll='ls -lh --color'
alias www='cd /var/www/html'
alias logs='sudo journalctl -xe -u apache2 -u mariadb -u forgejo'
EOF
    grep -qF "$BASHRC_MARK" /etc/skel/.bashrc 2>/dev/null || { echo >> /etc/skel/.bashrc; cat "$BASHRC_BLOCK" >> /etc/skel/.bashrc; }
}

install_locale() {
    info "Langue système : français"
    locale-gen fr_FR.UTF-8
    update-locale LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr
}

install_abrowser() {
    info "ABrowser : français, uBlock Origin, navigateur par défaut"

    # uBlock Origin embarqué dans l'image : fonctionne même hors-ligne au 1er lancement
    local src="$UBLOCK_AMO"
    mkdir -p /usr/share/nekosoft
    if curl -fL --retry 3 -o "$UBLOCK_LOCAL" "$UBLOCK_AMO"; then
        chmod 644 "$UBLOCK_LOCAL"
        src="file://$UBLOCK_LOCAL"
    else
        warn "xpi uBlock non téléchargé : repli sur l'installation depuis addons.mozilla.org (Internet requis au 1er lancement)"
    fi

    local d
    for d in /usr/lib/abrowser/distribution /etc/firefox/policies; do
        mkdir -p "$d"
        cat > "$d/policies.json" <<EOF
{
  "policies": {
    "RequestedLocales": ["fr"],
    "DisableTelemetry": true,
    "DontCheckDefaultBrowser": true,
    "ExtensionSettings": {
      "$UBLOCK_ID": {
        "installation_mode": "force_installed",
        "install_url": "$src"
      }
    }
  }
}
EOF
    done

    # Navigateur par défaut : système + modèle utilisateur
    if [[ -x /usr/bin/abrowser ]]; then
        update-alternatives --set x-www-browser    /usr/bin/abrowser 2>/dev/null || true
        update-alternatives --set gnome-www-browser /usr/bin/abrowser 2>/dev/null || true
    fi
    mkdir -p /etc/skel/.config
    cat > /etc/skel/.config/mimeapps.list <<'EOF'
[Default Applications]
text/html=abrowser.desktop
x-scheme-handler/http=abrowser.desktop
x-scheme-handler/https=abrowser.desktop
EOF
    info "Vérification après installation : abrowser -> about:policies"
}

# Crée ou complète un mimeapps.list pour que abrowser soit le navigateur par défaut.
# Un fichier existant (créé par la session) est mis à jour, pas ignoré.
set_default_browser() {   # $1 = chemin du mimeapps.list
    local f="$1" k
    mkdir -p "$(dirname "$f")"
    [[ -e "$f" ]] || printf '[Default Applications]\n' > "$f"
    grep -q '^\[Default Applications\]' "$f" || printf '\n[Default Applications]\n' >> "$f"
    for k in text/html x-scheme-handler/http x-scheme-handler/https; do
        # supprime l'ancienne valeur dans la section [Default Applications] uniquement, puis réinsère
        sed -i "/^\[Default Applications\]/,/^\[/{/^${k//\//\\/}=/d}" "$f"
        sed -i "/^\[Default Applications\]/a ${k}=abrowser.desktop" "$f"
    done
}

# Live uniquement : applique le modèle /etc/skel aux utilisateurs déjà existants.
# (En ISO, les utilisateurs créés par l'installeur héritent déjà de /etc/skel.)
apply_to_existing_users() {
    local u uid home
    while IFS=: read -r u _ uid _ _ home _; do
        if (( uid >= 1000 && uid < 60000 )) && [[ -d "$home" ]]; then
            info "Application du modèle NekoSoft à $u"
            if [[ -d /etc/skel/.config/pcmanfm ]]; then
                mkdir -p "$home/.config/pcmanfm"
                cp -a /etc/skel/.config/pcmanfm/. "$home/.config/pcmanfm/"
                chown -R "$u:" "$home/.config/pcmanfm"
            fi
            set_default_browser "$home/.config/mimeapps.list"
            chown "$u:" "$home/.config/mimeapps.list"
            if ! grep -qF "$BASHRC_MARK" "$home/.bashrc" 2>/dev/null; then
                { echo; cat "$BASHRC_BLOCK"; } >> "$home/.bashrc"
                chown "$u:" "$home/.bashrc"
            fi
        fi
    done < /etc/passwd
}

install_firstboot_service() {
    info "Installation du service de premier démarrage"
    mkdir -p "$STATE_DIR"
    if [[ -n "$SELF" && -f "$SELF" ]]; then
        [[ "$SELF" == "$SELF_INSTALLED" ]] || install -m 755 "$SELF" "$SELF_INSTALLED"
    else
        die "Le script doit être un fichier (pas 'curl | bash') pour pouvoir se réinstaller."
    fi
    # Le fond d'écran local (Cubic) n'est plus nécessaire après installation : déjà dans /usr/share/backgrounds

    cat > /etc/systemd/system/nekosoft-firstboot.service <<'EOF'
[Unit]
Description=NekoSoft - configuration au premier démarrage
After=network-online.target mariadb.service
Wants=network-online.target
ConditionPathExists=!/var/lib/nekosoft/firstboot.done
# Ne pas s'exécuter dans la session live du CD/USB, seulement sur le système installé
ConditionKernelCommandLine=!boot=casper

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nekosoft-setup --firstboot
RemainAfterExit=yes
TimeoutStartSec=15min

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable nekosoft-firstboot.service >/dev/null 2>&1 || true
}

cleanup_chroot() {
    rm -f /usr/sbin/policy-rc.d
    apt-get clean
}

# ============================================================================
# ÉTAPE 2 : PREMIER DÉMARRAGE (machine réelle, systemd actif)
# Chaque sous-étape pose un fichier .done => relançable sans doublon.
# ============================================================================

step_done() { [[ -e "$STATE_DIR/$1.done" ]]; }
mark_done() { touch "$STATE_DIR/$1.done"; }

fb_mariadb() {
    step_done mariadb && return 0
    info "MariaDB : sécurisation et compte admin"

    if [[ ! -d /var/lib/mysql/mysql ]]; then
        mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null
    fi
    systemctl enable --now mariadb

    local i
    for i in $(seq 1 30); do
        mariadb-admin ping --silent 2>/dev/null && break
        [[ "$i" -eq 30 ]] && die "MariaDB ne répond pas"
        sleep 1
    done

    local pw; pw="$(rand)"
    mysql --user=root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;
DROP USER IF EXISTS ''@'localhost';
DROP USER IF EXISTS ''@'$(hostname)';
DROP DATABASE IF EXISTS test;
CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY '$pw';
ALTER USER 'admin'@'localhost' IDENTIFIED BY '$pw';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    {
        echo "== MariaDB / phpMyAdmin (http://localhost/phpmyadmin) =="
        echo "utilisateur : admin"
        echo "mot de passe : $pw"
        echo "(root : connexion locale via 'sudo mysql', sans mot de passe)"
        echo
    } >> "$CRED_FILE"
    mark_done mariadb
}

fb_users() {
    step_done users && return 0
    info "Ajout des utilisateurs au groupe www-data"
    local u uid home
    if [[ -n "${DEV_USER:-}" ]]; then
        id "$DEV_USER" >/dev/null 2>&1 || die "DEV_USER introuvable : $DEV_USER"
        usermod -aG www-data "$DEV_USER"
    else
        while IFS=: read -r u _ uid _ _ home _; do
            if (( uid >= 1000 && uid < 60000 )) && [[ -d "$home" ]]; then
                usermod -aG www-data "$u"
                info "  $u -> www-data (reconnexion nécessaire)"
            fi
        done < /etc/passwd
    fi
    mark_done users
}

fb_borg() {
    step_done borg && return 0
    info "Borg : passphrase, dépôt chiffré, sauvegarde de test"

    if [[ ! -f "$BORG_PASSFILE" ]]; then
        ( umask 077; openssl rand -base64 32 > "$BORG_PASSFILE" )
    fi
    mkdir -p "$BACKUP_BASE"
    chmod 700 "$BACKUP_BASE"
    export BORG_PASSPHRASE; BORG_PASSPHRASE="$(cat "$BORG_PASSFILE")"

    if [[ ! -d "$BORG_REPO" ]]; then
        borg init --encryption=repokey-blake2 "$BORG_REPO"
        ( umask 077; borg key export "$BORG_REPO" /root/borg-key-backup.txt )
    fi
    {
        echo "== Borg (sauvegardes chiffrées) =="
        echo "dépôt        : $BORG_REPO"
        echo "passphrase   : $BORG_PASSFILE"
        echo "export clé   : /root/borg-key-backup.txt"
        echo "=> COPIER passphrase + clé HORS de ce poste (clé USB) : sinon pas de restauration si le disque meurt."
        echo
    } >> "$CRED_FILE"

    systemctl enable --now nekosoft-backup.timer
    /usr/local/bin/nekosoft-backup.sh || warn "Première sauvegarde échouée (voir le message ci-dessus)"
    mark_done borg
}

forgejo_cmd() {
    runuser -u git -- env HOME=/home/git FORGEJO_WORK_DIR=/var/lib/forgejo \
        /usr/local/bin/forgejo --config /etc/forgejo/app.ini --work-path /var/lib/forgejo "$@"
}

fb_forgejo() {
    step_done forgejo && return 0
    info "Forgejo : configuration, secrets, compte administrateur"

    local gen=(runuser -u git -- env HOME=/home/git /usr/local/bin/forgejo generate secret)
    local secret_key internal_token jwt lfs_jwt
    secret_key="$("${gen[@]}" SECRET_KEY)"
    internal_token="$("${gen[@]}" INTERNAL_TOKEN)"
    jwt="$("${gen[@]}" JWT_SECRET)"
    lfs_jwt="$("${gen[@]}" LFS_JWT_SECRET)"

    umask 077
    cat > /etc/forgejo/app.ini <<EOF
APP_NAME = NekoSoft Forge
RUN_USER = git
RUN_MODE = prod
WORK_PATH = /var/lib/forgejo

[server]
DOMAIN = localhost
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3000
ROOT_URL = http://localhost:3000/
; Accès HTTP uniquement (pas de SSH exposé sur le poste)
DISABLE_SSH = true
LFS_JWT_SECRET = $lfs_jwt

[database]
DB_TYPE = sqlite3
PATH = /var/lib/forgejo/forgejo.db

[repository]
ROOT = /home/git/repositories

[security]
INSTALL_LOCK = true
SECRET_KEY = $secret_key
INTERNAL_TOKEN = $internal_token

[oauth2]
JWT_SECRET = $jwt

[service]
DISABLE_REGISTRATION = true

[picture]
DISABLE_GRAVATAR = true
EOF
    umask 022
    chown git:git /etc/forgejo/app.ini
    chmod 640 /etc/forgejo/app.ini
    chmod 750 /etc/forgejo   # verrouille le dossier après génération

    forgejo_cmd migrate
    local pw; pw="$(rand)"
    forgejo_cmd admin user create --admin --username nekoadmin --email nekoadmin@nekosoft.local \
        --password "$pw" --must-change-password=false
    {
        echo "== Forgejo (http://localhost:3000) =="
        echo "utilisateur : nekoadmin"
        echo "mot de passe : $pw"
        echo "(inscriptions publiques désactivées : nouveaux comptes créés par l'admin)"
        echo
    } >> "$CRED_FILE"

    systemctl enable --now forgejo
    mark_done forgejo
}

firstboot() {
    mkdir -p "$STATE_DIR"
    touch "$CRED_FILE"; chmod 600 "$CRED_FILE"
    fb_mariadb
    fb_users
    fb_borg
    fb_forgejo
    touch "$STATE_DIR/firstboot.done"
    info "Configuration terminée. Identifiants générés : sudo cat $CRED_FILE"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    case "${1:-}" in
        --firstboot) require_root; firstboot; exit 0 ;;
        -h|--help)   sed -n '2,25p' "$0"; exit 0 ;;
    esac

    require_root
    detect_mode
    __banner
    info "Mode détecté : $MODE  (forçable : NEKO_MODE=chroot|live)"

    prepare_apt
    install_packages
    configure_apache
    configure_webroot
    install_forgejo
    install_backup_tools
    install_wallpaper
    install_bashrc_block
    install_locale
    install_abrowser
    apply_to_existing_users

    if [[ "$MODE" == "chroot" ]]; then
        install_firstboot_service
        cleanup_chroot
        info "Image prête. Au 1er démarrage de chaque machine, le service nekosoft-firstboot terminera la configuration."
    else
        firstboot
        info "Déconnecte/reconnecte ta session pour : groupe www-data, fond d'écran, alias."
    fi
}

main "$@"