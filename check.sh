#!/bin/bash
# Script de vérification NekoSoft (compagnon de setup.sh).
# Projet SAE 1.03
# Vérifie que tout ce que setup.sh installe/configure est présent ET fonctionnel.
#
# Usage :
#   sudo bash check.sh                    # vérification complète
#   sudo bash check.sh mariadb web        # vérifier seulement certaines sections
#   bash check.sh --user=dev1             # vérifier pour un utilisateur dev précis
#   bash check.sh --no-color              # sortie sans couleur (logs)
#
# Sections disponibles :
#   packages, services, mariadb, web, forgejo, backup,
#   desktop, terminal, locale, abrowser, kodi
#
# Code retour : 0 = tout conforme, 1 = au moins un échec.

set -uo pipefail
# NB : volontairement SANS set -e : un check qui échoue doit être affiché,
# pas interrompre la vérification.

if [[ -t 1 ]]; then
    COLOR_OK=$'\033[0;32m'
    COLOR_KO=$'\033[0;31m'
    COLOR_WARN=$'\033[0;33m'
    COLOR_INFO=$'\033[0;36m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_OK='' COLOR_KO='' COLOR_WARN='' COLOR_INFO='' COLOR_RESET=''
fi

info() { printf '%s%s%s\n' "$COLOR_INFO" "$*" "$COLOR_RESET"; }
section() {
    printf '\n%s%s%s\n' "$COLOR_INFO" "--- $* -------------------------------------------------------------" "$COLOR_RESET"
}

# ---------------------------------------------------------------------------
# Compteurs + journal des anomalies
N_OK=0 N_KO=0 N_WARN=0 N_SKIP=0
declare -a KO_LINES=() WARN_LINES=() SKIP_LINES=()

ok() {
    N_OK=$((N_OK + 1))
    printf '  %s[OK]%s     %s\n' "$COLOR_OK" "$COLOR_RESET" "$1"
}
ko() {
    # $1 = constat, $2 = piste de correction (optionnel)
    N_KO=$((N_KO + 1))
    KO_LINES+=("${1}|${2:-}")
    printf '  %s[ECHEC]  %s%s\n' "$COLOR_KO" "$COLOR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '            -> %s\n' "$2"
}
warn() {
    N_WARN=$((N_WARN + 1))
    WARN_LINES+=("${1}|${2:-}")
    printf '  %s[ATTENTION]  %s%s\n' "$COLOR_WARN" "$COLOR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '            -> %s\n' "$2"
}
skip() {
    # $1 = constat, $2 = raison du contournement
    N_SKIP=$((N_SKIP + 1))
    SKIP_LINES+=("${1}|${2:-}")
    printf '  %s[IGNORÉ] %s%s\n' "$COLOR_WARN" "$COLOR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '            (%s)\n' "$2"
}

# Helpers --------------------------------------------------------------------
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'; }

svc_enabled() { systemctl is-enabled "$1" >/dev/null 2>&1; }
svc_active()  { systemctl is-active  "$1" >/dev/null 2>&1; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null; }

# True si l'utilisateur est membre du groupe $1
in_group() { id -nG "$1" 2>/dev/null | grep -qw "$2"; }

# ---------------------------------------------------------------------------
# Arguments
DEV_USER=""
USE_COLOR=1
SECTIONS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user=*) DEV_USER="${1#--user=}"; shift ;;
        --user)   DEV_USER="${2:-}"; shift 2 ;;
        --no-color) USE_COLOR=0; COLOR_OK='' COLOR_KO='' COLOR_WARN='' COLOR_INFO='' COLOR_RESET=''; shift ;;
        -h|--help) cat <<'EOF'
Usage : sudo bash check.sh [--user=NAME] [--no-color] [section ...]

Vérifie que tout ce que installe/configure setup.sh est présent ET fonctionnel.

Sections disponibles :
  packages, services, mariadb, web, forgejo, backup,
  webroot, desktop, terminal, locale, abrowser, kodi

Exemples :
  sudo bash check.sh                  # vérification complète
  sudo bash check.sh mariadb web      # seulement ces sections
  bash check.sh --user=dev1 packages  # autre utilisateur dev
  bash check.sh --no-color            # sortie sans couleur (logs)

Code retour : 0 = tout conforme, 1 = au moins un échec, 2 = erreur d'argument.
EOF
exit 0 ;;
        -*) echo "Option inconnue : $1 (voir : bash $0 --help)" >&2; exit 2 ;;
        *) SECTIONS+=("$1"); shift ;;
    esac
done

info "[@] NekoSoft check - $(date '+%Y-%m-%d %H:%M:%S')"

# Root : plusieurs checks (root MariaDB via unix_socket, /root/.borg-passphrase,
# apache2ctl configtest) l'exigent. Sans root on continue en mode dégradé.
ROOT_OK=1
if [[ "$(id -u)" -ne 0 ]]; then
    ROOT_OK=0
    warn "Script lancé sans root : les checks privilégiés seront ignorés" \
         "relance avec : sudo bash $0"
fi

# Utilisateur dev : même logique que setup.sh
if [[ -z "$DEV_USER" ]]; then
    DEV_USER="${SUDO_USER:-}"
fi
if [[ -z "$DEV_USER" ]]; then
    DEV_USER="$(logname 2>/dev/null || true)"
fi
if [[ -z "$DEV_USER" ]]; then
    DEV_USER="$(ls -1 /home 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$DEV_USER" ]] || ! id "$DEV_USER" >/dev/null 2>&1; then
    DEV_USER=""
    warn "Utilisateur dev introuvable : checks utilisateur ignorés" \
         "lance avec : sudo bash $0 --user=<login>"
else
    info "[@] Utilisateur dev vérifié : $DEV_USER"
fi

RUN_SECTION() { return 0; }  # placeholder (évite un bug de tableau vide sous set -u)

WANT() {
    # True si aucune section n'a été passée en argument, ou si $1 en fait partie.
    if [[ "${#SECTIONS[@]}" -eq 0 ]]; then return 0; fi
    local s
    for s in "${SECTIONS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
    return 1
}

# ---------------------------------------------------------------------------
# 1. Paquets
check_packages() {
    section "Paquets installés (apt)"
    local pkgs=(
        apache2 mariadb-server
        php libapache2-mod-php php-mysql php-cli php-mbstring php-zip php-gd php-curl
        phpmyadmin
        geany geany-plugins
        abrowser abrowser-locale-fr
        openssh-server
        borgbackup gnupg
        lightdm-gtk-greeter-settings
        wget curl unzip
        kodi
    )
    local p missing=()
    for p in "${pkgs[@]}"; do
        if pkg_installed "$p"; then
            ok "$p : installé"
        else
            ko "$p : paquet ABSENT" "sudo apt install -y $p  (ou relance setup.sh)"
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        info "[@] Paquets manquants (${#missing[@]}) : ${missing[*]}"
    fi
}

# ---------------------------------------------------------------------------
# 2. Services : activés + démarrés + réellement fonctionnels
check_services() {
    section "Services (systemd) : apache2, mariadb, ssh, forgejo"
    local s
    for s in apache2 mariadb ssh forgejo; do
        if ! command -v systemctl >/dev/null 2>&1; then
            skip "$s : systemctl absent (conteneur/live ?)" "vérifier avec : service $s status"
            continue
        fi
        if systemctl list-unit-files "$s.service" --no-legend 2>/dev/null | grep -q .; then
            if svc_enabled "$s"; then
                ok "$s : activé au boot (enabled)"
            else
                ko "$s : NON activé au boot" "sudo systemctl enable $s"
            fi
            if svc_active "$s"; then
                ok "$s : démarré (active)"
            else
                ko "$s : ARRÊTÉ (inactive)" "sudo systemctl start $s && sudo journalctl -xeu $s"
            fi
        else
            ko "$s : unité systemd absente" "relance setup.sh (il crée les services)"
        fi
    done

    # SSH : port 22 réellement en écoute (preuve de fonctionnement)
    if command -v ss >/dev/null 2>&1; then
        if ss -tln 2>/dev/null | grep -qE '(:|\])22[[:space:]]'; then
            ok "ssh : port 22 en écoute"
        else
            ko "ssh : port 22 PAS en écoute" "sudo systemctl start ssh && sudo ss -tln | grep :22"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 3. MariaDB : conformité de la sécurisation faite par setup.sh
check_mariadb() {
    section "MariaDB : root (unix_socket) + admin + durcissement"
    if ! command -v mysql >/dev/null 2>&1; then
        ko "mysql : binaire absent" "sudo apt install -y mariadb-server"
        return
    fi
    if ! (mariadb-admin ping --silent >/dev/null 2>&1 || mysqladmin ping --silent >/dev/null 2>&1); then
        ko "MariaDB : ne répond pas au ping" "sudo systemctl start mariadb"
        return
    fi
    ok "MariaDB : répond au ping"

    if [[ "$ROOT_OK" -ne 1 ]]; then
        skip "MariaDB : checks root/admin ignorés (root requis)" "relance : sudo bash $0"
        return
    fi

    # root via unix_socket (canal utilisé par setup.sh + backup)
    if mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
        ok "root : connexion unix_socket OK"
    else
        ko "root : connexion unix_socket EN ÉCHEC" "relance setup.sh (réparation skip-grant-tables auto)"
        return
    fi

    # root ne doit PAS être verrouillé (piège ERROR 4151 de l'ancien script).
    # mysql.user expose la colonne account_locked : table réelle (MariaDB < 10.4)
    # ou vue sur global_priv (>= 10.4) -> une seule requête suffit.
    local locked
    locked="$(mysql --user=root -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host='localhost' AND account_locked='Y';" 2>/dev/null || echo 1)"
    if [[ "$locked" == "0" ]]; then
        ok "root : compte non verrouillé (ACCOUNT UNLOCK)"
    else
        ko "root : compte verrouillé (ERROR 4151 au 2e run)" "relance setup.sh : déverrouillage automatique"
    fi

    # plugin unix_socket attendu (sans mot de passe réseau)
    local plugin
    plugin="$(mysql --user=root -N -B -e "SELECT plugin FROM mysql.user WHERE User='root' AND Host='localhost';" 2>/dev/null || echo '?')"
    if [[ "$plugin" == *"unix_socket"* || "$plugin" == "?" ]]; then
        ok "root : authentification unix_socket ($plugin)"
    else
        warn "root : plugin d'auth = '$plugin' (unix_socket attendu)" \
             "sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;\""
    fi

    # admin applicatif (identifiants connus de la doc NekoSoft)
    if MYSQL_PWD='nekosoft-root' mysql --user=admin -e "SELECT 1;" >/dev/null 2>&1; then
        ok "admin : login/mot de passe OK (nekosoft-root)"
    else
        ko "admin : login/mot de passe EN ÉCHEC" \
           "sudo mysql -e \"CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root'; ALTER USER 'admin'@'localhost' IDENTIFIED BY 'nekosoft-root'; GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;\""
    fi
    if mysql --user=root -N -B -e "SHOW GRANTS FOR 'admin'@'localhost';" 2>/dev/null | grep -q "ALL PRIVILEGES"; then
        ok "admin : ALL PRIVILEGES ON *.* WITH GRANT OPTION"
    else
        ko "admin : privilèges insuffisants" "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
    fi

    # durcissement : pas d'utilisateur anonyme, pas de base 'test'
    local anon
    anon="$(mysql --user=root -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE User='';" 2>/dev/null || echo -1)"
    if [[ "$anon" == "0" ]]; then
        ok "durcissement : aucun utilisateur anonyme"
    else
        ko "durcissement : $anon utilisateur(s) anonyme(s) présents" \
           "sudo mysql -e \"DELETE FROM mysql.user WHERE User=''; FLUSH PRIVILEGES;\""
    fi
    if [[ -z "$(mysql --user=root -N -B -e "SHOW DATABASES LIKE 'test';" 2>/dev/null)" ]]; then
        ok "durcissement : base 'test' absente"
    else
        ko "durcissement : base 'test' présente" \
           "sudo mysql -e \"DROP DATABASE test; DELETE FROM mysql.db WHERE Db='test';\""
    fi
}

# ---------------------------------------------------------------------------
# 4. Web : Apache + PHP + phpMyAdmin réellement fonctionnels
check_web() {
    section "Web : Apache + PHP + phpMyAdmin"
    if ! command -v curl >/dev/null 2>&1; then
        ko "curl absent : tests HTTP impossibles" "sudo apt install -y curl"
        return
    fi

    if [[ "$ROOT_OK" -eq 1 ]] && command -v apache2ctl >/dev/null 2>&1; then
        if apache2ctl configtest 2>/dev/null | grep -q "Syntax OK"; then
            ok "Apache : syntaxe de configuration OK"
        else
            ko "Apache : ERREUR de configuration" "sudo apache2ctl configtest && sudo journalctl -xeu apache2"
        fi
    fi

    local code
    code="$(http_code "http://localhost/")"
    if [[ "$code" == "200" ]]; then
        ok "Apache : http://localhost/ répond (HTTP $code)"
    else
        ko "Apache : http://localhost/ répond HTTP $code (200 attendu)" \
           "sudo systemctl start apache2 && curl -v http://localhost/"
    fi

    # Page de test PHP posée par setup.sh
    if [[ -f /var/www/html/info.php ]]; then
        ok "/var/www/html/info.php : présent"
    else
        ko "/var/www/html/info.php : ABSENT" 'echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/info.php'
    fi
    if curl -fsS --max-time 10 http://localhost/info.php 2>/dev/null | grep -qi "PHP Version"; then
        ok "PHP : page info.php exécutée (mod-php fonctionne)"
    else
        ko "PHP : info.php ne s'exécute pas via Apache" \
           "sudo a2enmod php && sudo systemctl restart apache2 (vérifier libapache2-mod-php)"
    fi

    # phpMyAdmin accessible via l'auto-config apache de setup.sh
    if [[ -e /etc/apache2/conf-enabled/phpmyadmin.conf ]]; then
        ok "phpMyAdmin : conf-enabled/phpmyadmin.conf présent"
    else
        ko "phpMyAdmin : apache conf ABSENT" \
           "sudo ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf && sudo a2enconf phpmyadmin && sudo systemctl reload apache2"
    fi
    code="$(http_code "http://localhost/phpmyadmin/")"
    case "$code" in
        200)          ok "phpMyAdmin : http://localhost/phpmyadmin/ répond (HTTP $code)" ;;
        301|302|303|307) warn "phpMyAdmin : HTTP $code (redirection) sur /phpmyadmin/" \
                         "curl -L http://localhost/phpmyadmin/ pour suivre la redirection" ;;
        *)            ko "phpMyAdmin : HTTP $code sur /phpmyadmin/" \
                      "vérifier a2enconf phpmyadmin et le service apache2" ;;
    esac

    # Modules PHP demandés par setup.sh
    local m mods=("mbstring" "zip" "gd" "curl" "mysqli")
    if command -v php >/dev/null 2>&1; then
        for m in "${mods[@]}"; do
            if php -m 2>/dev/null | grep -qi "^$m$"; then
                ok "PHP : module $m chargé"
            else
                ko "PHP : module $m ABSENT" "sudo apt install -y php-$m && sudo systemctl restart apache2"
            fi
        done
        ok "PHP : version $(php -r 'echo PHP_VERSION;' 2>/dev/null)"
    else
        ko "PHP : binaire php absent" "sudo apt install -y php-cli"
    fi
}

# ---------------------------------------------------------------------------
# 5. Forgejo : binaire, config, service, port 3000
check_forgejo() {
    section "Forgejo (Git auto-hébergé, port 3000)"
    if [[ -x /usr/local/bin/forgejo ]]; then
        ok "/usr/local/bin/forgejo : binaire exécutable"
        local ver
        ver="$(/usr/local/bin/forgejo --version 2>/dev/null | head -n1)"
        [[ -n "$ver" ]] && info "[@] Forgejo : $ver"
    else
        ko "/usr/local/bin/forgejo : binaire ABSENT ou non exécutable" "relance setup.sh (téléchargement Forgejo)"
    fi

    if id git >/dev/null 2>&1; then
        ok "utilisateur système 'git' : présent"
    else
        ko "utilisateur système 'git' : ABSENT" \
           "sudo adduser --system --shell /bin/bash --group --disabled-password --home /home/git git"
    fi

    local d
    for d in /var/lib/forgejo /etc/forgejo /var/log/forgejo; do
        if [[ -d "$d" ]]; then
            ok "$d : répertoire présent"
        else
            ko "$d : répertoire ABSENT" "relance setup.sh (création des répertoires Forgejo)"
        fi
    done

    if [[ -f /etc/forgejo/app.ini ]]; then
        ok "/etc/forgejo/app.ini : présent"
        if [[ "$(stat -c %a /etc/forgejo/app.ini 2>/dev/null)" == "640" \
            && "$(stat -c %U:%G /etc/forgejo/app.ini 2>/dev/null)" == "git:git" ]]; then
            ok "/etc/forgejo/app.ini : droits 640 git:git"
        else
            ko "/etc/forgejo/app.ini : droits incorrects ($(stat -c %a:%U:%G /etc/forgejo/app.ini 2>/dev/null))" \
               "sudo chown git:git /etc/forgejo/app.ini && sudo chmod 640 /etc/forgejo/app.ini"
        fi
        if grep -q "HTTP_PORT.*=.*3000" /etc/forgejo/app.ini 2>/dev/null \
            && grep -q "DB_TYPE.*=.*sqlite3" /etc/forgejo/app.ini 2>/dev/null; then
            ok "/etc/forgejo/app.ini : port 3000 + sqlite3 configurés"
        else
            ko "/etc/forgejo/app.ini : port 3000 ou sqlite3 mal configuré" "relance setup.sh (réécrit app.ini)"
        fi
    else
        ko "/etc/forgejo/app.ini : ABSENT" "relance setup.sh"
    fi

    if [[ -f /etc/systemd/system/forgejo.service ]]; then
        ok "/etc/systemd/system/forgejo.service : présent"
    else
        ko "/etc/systemd/system/forgejo.service : ABSENT" "relance setup.sh"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        if svc_enabled forgejo && svc_active forgejo; then
            ok "forgejo : service enabled + active"
        else
            ko "forgejo : service KO (enabled/active)" \
               "sudo systemctl daemon-reload && sudo systemctl enable --now forgejo"
        fi
    fi

    local code
    code="$(http_code "http://localhost:3000/")"
    case "$code" in
        200)             ok "Forgejo : http://localhost:3000/ répond (HTTP $code)" ;;
        301|302|303|307) ok "Forgejo : http://localhost:3000/ répond (redirection HTTP $code)" ;;
        *)               ko "Forgejo : http://localhost:3000/ répond HTTP $code" \
                         "sudo systemctl start forgejo && sudo journalctl -xeu forgejo" ;;
    esac
}

# ---------------------------------------------------------------------------
# 6. Sauvegardes Borg + cron
check_backup() {
    section "Sauvegardes Borg : dépôt, passphrase, script, cron"
    local REPO="/var/backups/nekosoft-borg"
    local PASSPHRASE_FILE="/root/.borg-passphrase"

    if [[ "$ROOT_OK" -ne 1 ]]; then
        # /root et /var/backups sont en 700 root : sans root on ne peut rien
        # lire -> sinon faux "ABSENT" sur une install pourtant conforme.
        skip "Borg : passphrase + dépôt non vérifiables sans root" "relance : sudo bash $0"
    else
        if [[ -f "$PASSPHRASE_FILE" ]]; then
            ok "$PASSPHRASE_FILE : présent"
            if [[ "$(stat -c %a "$PASSPHRASE_FILE" 2>/dev/null)" == "600" ]]; then
                ok "$PASSPHRASE_FILE : droits 600 (root-only)"
            else
                ko "$PASSPHRASE_FILE : droits $(stat -c %a "$PASSPHRASE_FILE" 2>/dev/null) (600 attendu)" \
                   "sudo chmod 600 $PASSPHRASE_FILE"
            fi
        else
            ko "$PASSPHRASE_FILE : ABSENT" "relance setup.sh (génération de la passphrase)"
        fi

        if [[ ! -d "$REPO" ]]; then
            ko "$REPO : dépôt ABSENT" "relance setup.sh (borg init --encryption=repokey-blake2)"
        else
            ok "$REPO : dépôt présent"
            export BORG_PASSPHRASE="$(cat "$PASSPHRASE_FILE" 2>/dev/null)"
            if command -v borg >/dev/null 2>&1; then
                if borg config "$REPO" encryption 2>/dev/null | grep -q "repokey"; then
                    ok "Borg : dépôt chiffré ($(borg config "$REPO" encryption 2>/dev/null))"
                else
                    ko "Borg : chiffrement du dépôt non reconnu (repokey attendu)" \
                       "recréer le dépôt : rm -rf $REPO puis relance setup.sh"
                fi
                if borg list --short "$REPO" 2>/dev/null | grep -q .; then
                    local n
                    n="$(borg list --short "$REPO" 2>/dev/null | wc -l)"
                    ok "Borg : $n archive(s) dans le dépôt"
                else
                    warn "Borg : dépôt vide (aucune archive)" \
                         "lance : sudo /usr/local/bin/nekosoft-backup.sh"
                fi
            else
                ko "borg : binaire absent" "sudo apt install -y borgbackup"
            fi
            unset BORG_PASSPHRASE
        fi
    fi

    if [[ -x /usr/local/bin/nekosoft-backup.sh ]]; then
        ok "/usr/local/bin/nekosoft-backup.sh : exécutable"
    else
        ko "/usr/local/bin/nekosoft-backup.sh : ABSENT ou non exécutable" "relance setup.sh"
    fi

    if [[ -f /etc/cron.d/nekosoft-backup ]]; then
        ok "/etc/cron.d/nekosoft-backup : présent"
        if [[ "$(stat -c %a /etc/cron.d/nekosoft-backup 2>/dev/null)" == "644" ]] \
            && grep -q "0 2 \* \* \* root" /etc/cron.d/nekosoft-backup 2>/dev/null; then
            ok "cron : sauvegarde quotidienne planifiée à 2 h (droits 644)"
        else
            ko "cron : planification 2h ou droits incorrects" "relance setup.sh (réécrit /etc/cron.d/nekosoft-backup)"
        fi
    else
        ko "/etc/cron.d/nekosoft-backup : ABSENT" "relance setup.sh"
    fi

    # dump SQL utilisé par le script de backup (re-généré à chaque run : warning seulement)
    if [[ -s /var/backups/all-databases.sql.gz ]]; then
        ok "/var/backups/all-databases.sql.gz : dump SQL présent"
    else
        warn "/var/backups/all-databases.sql.gz : absent/vide" \
             "lance : sudo /usr/local/bin/nekosoft-backup.sh"
    fi
}

# ---------------------------------------------------------------------------
# 7. Webroot /var/www/html : droits dev
check_webroot() {
    section "Webroot /var/www/html (droits développeur)"
    if [[ ! -d /var/www/html ]]; then
        ko "/var/www/html : répertoire ABSENT" "sudo apt install -y apache2"
        return
    fi
    local owner
    owner="$(stat -c %U:%G /var/www/html 2>/dev/null)"
    if [[ "$owner" == "www-data:www-data" ]]; then
        ok "/var/www/html : propriétaire $owner"
    else
        ko "/var/www/html : propriétaire $owner (www-data:www-data attendu)" \
           "sudo chown -R www-data:www-data /var/www/html"
    fi
    local mode
    mode="$(stat -c %a /var/www/html 2>/dev/null)"
    case "$mode" in
        2775|775) ok "/var/www/html : mode $mode (775 + setgid)" ;;
        *)        ko "/var/www/html : mode $mode (2775 attendu)" \
                  "sudo chmod -R 775 /var/www/html && sudo chmod g+s /var/www/html" ;;
    esac

    if [[ -n "$DEV_USER" ]]; then
        if in_group "$DEV_USER" www-data; then
            ok "$DEV_USER : membre du groupe www-data"
        else
            ko "$DEV_USER : PAS membre du groupe www-data" \
               "sudo usermod -aG www-data $DEV_USER (puis re-login)"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 8. Bureau NekoSoft : wallpaper, PCManFM, LightDM, Geany
check_desktop() {
    section "Bureau NekoSoft : fond d'écran, PCManFM, LightDM, Geany"

    if [[ -s /usr/share/backgrounds/nekosoft-wallpaper.png ]]; then
        ok "/usr/share/backgrounds/nekosoft-wallpaper.png : présent"
        if head -c8 /usr/share/backgrounds/nekosoft-wallpaper.png 2>/dev/null | od -An -tx1 2>/dev/null | grep -qi "89 50 4e 47"; then
            ok "wallpaper : signature PNG valide"
        else
            ko "wallpaper : fichier corrompu (pas un PNG valide)" "relance setup.sh (re-téléchargement)"
        fi
    else
        ko "/usr/share/backgrounds/nekosoft-wallpaper.png : ABSENT" "relance setup.sh"
    fi

    if [[ -x /usr/local/bin/nekosoft-wallpaper.sh ]]; then
        ok "/usr/local/bin/nekosoft-wallpaper.sh : exécutable"
    else
        ko "/usr/local/bin/nekosoft-wallpaper.sh : ABSENT ou non exécutable" "relance setup.sh"
    fi

    if [[ -f /etc/xdg/autostart/nekosoft-wallpaper.desktop ]]; then
        ok "/etc/xdg/autostart/nekosoft-wallpaper.desktop : présent"
    else
        ko "/etc/xdg/autostart/nekosoft-wallpaper.desktop : ABSENT" "relance setup.sh"
    fi

    # Profils PCManFM (le profil réellement lu dépend de la session LXDE)
    local profiles=(default lxde LXDE Trisquel-mini trisquel-mini)
    local base p
    for base in "/home/$DEV_USER/.config/pcmanfm" "/etc/skel/.config/pcmanfm"; do
        [[ -z "$DEV_USER" && "$base" == "/home/"* ]] && continue
        for p in "${profiles[@]}"; do
            local f="$base/$p/desktop-items-0.conf"
            if [[ -f "$f" ]] && grep -q "^wallpaper=/usr/share/backgrounds/nekosoft-wallpaper.png$" "$f" 2>/dev/null; then
                ok "$f : wallpaper configuré"
            elif [[ -f "$f" ]]; then
                ko "$f : wallpaper mal configuré" "relance setup.sh (réécrit les profils PCManFM)"
            else
                ko "$f : ABSENT" "relance setup.sh (profils PCManFM + skel)"
            fi
        done
    done

    # Autostart natif lxsession (backup du .desktop)
    local s f_found=0
    for s in LXDE Trisquel-mini; do
        local f="/etc/xdg/lxsession/$s/autostart"
        [[ -f "$f" ]] || continue
        f_found=1
        if grep -q "nekosoft-wallpaper" "$f" 2>/dev/null; then
            ok "$f : entrée nekosoft-wallpaper présente"
        else
            ko "$f : entrée @nekosoft-wallpaper ABSENTE" 'echo "@/usr/local/bin/nekosoft-wallpaper.sh" | sudo tee -a "'"$f"'"'
        fi
    done
    [[ "$f_found" -eq 0 ]] && skip "lxsession : aucun /etc/xdg/lxsession/*/autostart (LXDE non installé)" ""

    # LightDM : greeter aux couleurs NekoSoft
    if [[ -f /etc/lightdm/lightdm-gtk-greeter.conf ]]; then
        if grep -q "background=/usr/share/backgrounds/nekosoft-wallpaper.png" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
            ok "LightDM : fond d'écran NekoSoft sur l'écran de connexion"
        else
            ko "LightDM : fond d'écran NekoSoft NON configuré" "relance setup.sh (bloc [greeter])"
        fi
    elif pkg_installed lightdm-gtk-greeter-settings; then
        ko "/etc/lightdm/lightdm-gtk-greeter.conf : ABSENT (LightDM installé)" "relance setup.sh"
    else
        skip "LightDM : non installé (bureau de la VM cible uniquement)" ""
    fi

    # Geany
    if [[ -d /etc/skel/.config/geany ]]; then
        ok "/etc/skel/.config/geany : présent"
    else
        ko "/etc/skel/.config/geany : ABSENT" "sudo mkdir -p /etc/skel/.config/geany"
    fi
    if [[ -n "$DEV_USER" ]]; then
        if [[ -d "/home/$DEV_USER/.config/geany" ]]; then
            ok "/home/$DEV_USER/.config/geany : présent"
        else
            ko "/home/$DEV_USER/.config/geany : ABSENT" "sudo mkdir -p /home/$DEV_USER/.config/geany"
        fi
    fi
}

# ---------------------------------------------------------------------------
# 9. Terminal : .bashrc NekoSoft + alias dev
check_terminal() {
    section "Terminal : .bashrc NekoSoft + alias développeur"
    local f
    for f in /etc/skel/.bashrc "/home/$DEV_USER/.bashrc"; do
        [[ -z "$DEV_USER" && "$f" == "/home/"* ]] && continue
        if [[ ! -f "$f" ]]; then
            ko "$f : ABSENT" "relance setup.sh (bloc NekoSoft + skel)"
            continue
        fi
        if grep -q "NekoSoft" "$f" 2>/dev/null; then
            ok "$f : bloc NekoSoft présent"
        else
            ko "$f : bloc NekoSoft ABSENT" "relance setup.sh (ajoute le bloc en fin de .bashrc)"
        fi
        if grep -q "nekosoft🐾" "$f" 2>/dev/null; then
            ok "$f : prompt PS1 nekosoft configuré"
        else
            warn "$f : PS1 nekosoft introuvable" "relance setup.sh"
        fi
        local miss=()
        grep -q "alias www=" "$f" 2>/dev/null || miss+=("www")
        grep -q "alias logs=" "$f" 2>/dev/null || miss+=("logs")
        grep -q "alias ll=" "$f" 2>/dev/null || miss+=("ll")
        if [[ ${#miss[@]} -eq 0 ]]; then
            ok "$f : alias ll / www / logs présents"
        else
            ko "$f : alias manquant(s) : ${miss[*]}" "relance setup.sh"
        fi
    done
}

# ---------------------------------------------------------------------------
# 10. Locale française
check_locale() {
    section "Locale système : français"
    if locale -a 2>/dev/null | grep -qi "fr_FR.utf8\|fr_FR.utf-8"; then
        ok "fr_FR.UTF-8 : locale générée"
    else
        warn "fr_FR.UTF-8 : locale non générée" "sudo locale-gen fr_FR.UTF-8 && sudo update-locale LANG=fr_FR.UTF-8"
    fi
    if [[ -f /etc/default/locale ]] && grep -q "LANG=fr_FR.UTF-8" /etc/default/locale; then
        ok "/etc/default/locale : LANG=fr_FR.UTF-8"
    else
        warn "/etc/default/locale : LANG fr_FR.UTF-8 absent" \
             "sudo update-locale LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr LC_ALL=fr_FR.UTF-8"
    fi
}

# ---------------------------------------------------------------------------
# 11. ABrowser + uBlock Origin forcé (politiques entreprise)
check_abrowser() {
    section "ABrowser : politiques uBlock Origin + français"
    local UB_ID="uBlock0@raymondhill.net"
    local d f
    for d in /usr/lib/abrowser/distribution /etc/firefox/policies; do
        f="$d/policies.json"
        if [[ ! -f "$f" ]]; then
            ko "$f : ABSENT" "relance setup.sh (écrit policies.json)"
            continue
        fi
        ok "$f : présent"
        if command -v python3 >/dev/null 2>&1; then
            if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; then
                ok "$f : JSON valide"
            else
                ko "$f : JSON INVALIDE" "relance setup.sh (réécrit policies.json)"
                continue
            fi
            if python3 -c "
import json,sys
p=json.load(open(sys.argv[1]))['policies']
es=p.get('ExtensionSettings',{}).get(sys.argv[2],{})
assert es.get('installation_mode')=='force_installed', 'uBlock non forcé'
assert p.get('LanguagePacks')==['fr'] or 'fr' in (p.get('LanguagePacks') or []), 'locale fr absente'
" "$f" "$UB_ID" >/dev/null 2>&1; then
                ok "$f : uBlock force_installed + locale fr"
            else
                ko "$f : uBlock non forcé ou locale fr absente" "relance setup.sh (réécrit policies.json)"
            fi
        else
            skip "$f : python3 absent, JSON non validé" ""
        fi
    done
    if command -v abrowser >/dev/null 2>&1; then
        ok "abrowser : binaire présent"
    else
        ko "abrowser : binaire absent" "sudo apt install -y abrowser abrowser-locale-fr"
    fi
}

# ---------------------------------------------------------------------------
# 12. Kodi en français
check_kodi() {
    section "Kodi : install + français + raccourcis"
    if command -v kodi >/dev/null 2>&1; then
        ok "kodi : binaire présent ($(command -v kodi))"
        kodi --version >/dev/null 2>&1 && info "[@] Kodi : $(kodi --version 2>/dev/null | head -n1)"
    else
        ko "kodi : binaire ABSENT" "sudo apt install -y kodi"
    fi
    local target f
    for target in "/home/$DEV_USER" "/etc/skel"; do
        [[ -z "$DEV_USER" && "$target" == "/home/"* ]] && continue
        f="$target/.kodi/userdata/guisettings.xml"
        if [[ -f "$f" ]] && grep -q "resource.language.fr_fr" "$f" 2>/dev/null; then
            ok "$f : Kodi préconfiguré en français"
        else
            ko "$f : Kodi français non préconfiguré" "relance setup.sh (seed_kodi_fr)"
        fi
    done
    if [[ -n "$DEV_USER" ]] && pkg_installed kodi && [[ -f /usr/share/applications/kodi.desktop ]]; then
        local found=0 d
        for d in "/home/$DEV_USER/Bureau" "/home/$DEV_USER/Desktop"; do
            [[ -f "$d/kodi.desktop" ]] && found=1
        done
        if [[ "$found" -eq 1 ]]; then
            ok "raccourci Kodi : présent sur le bureau de $DEV_USER"
        else
            warn "raccourci Kodi : absent du bureau de $DEV_USER" "relance setup.sh"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Exécution
declare -A SECTION_FUNCS=(
    [packages]=check_packages
    [services]=check_services
    [mariadb]=check_mariadb
    [web]=check_web
    [forgejo]=check_forgejo
    [backup]=check_backup
    [webroot]=check_webroot
    [desktop]=check_desktop
    [terminal]=check_terminal
    [locale]=check_locale
    [abrowser]=check_abrowser
    [kodi]=check_kodi
)

# Validation des noms de sections demandés
if [[ ${#SECTIONS[@]} -gt 0 ]]; then
    for s in "${SECTIONS[@]}"; do
        if [[ -z "${SECTION_FUNCS[$s]:-}" ]]; then
            echo "[ERREUR] Section inconnue : $s" >&2
            echo "Sections : ${!SECTION_FUNCS[*]}" >&2
            exit 2
        fi
    done
fi

for s in packages services mariadb web forgejo backup webroot desktop terminal locale abrowser kodi; do
    if WANT "$s"; then
        "${SECTION_FUNCS[$s]}"
    fi
done

# ---------------------------------------------------------------------------
# Récapitulatif
TOTAL=$((N_OK + N_KO))
printf '\n%s%s============================================================%s\n' "$COLOR_INFO" "" "$COLOR_RESET"
info "Résultat NekoSoft : $N_OK OK / $N_KO ÉCHEC(S) / $N_WARN ATTENTION(S) / $N_SKIP IGNORÉ(S)"

if [[ ${#KO_LINES[@]} -gt 0 ]]; then
    info "Échecs à corriger :"
    for line in "${KO_LINES[@]}"; do
        printf '  %s• %s%s\n' "$COLOR_KO" "${line%%|*}" "$COLOR_RESET"
        h="${line#*|}"
        if [[ -n "$h" && "$h" != "${line%%|*}" ]]; then
            printf '    -> %s\n' "$h"
        fi
    done
    info "Le setup.sh est idempotent : sudo bash setup.sh corrige tout d'un coup."
fi

if [[ $N_KO -gt 0 ]]; then
    printf '%s[ECHEC] Poste NON CONFORME (%d/%d checks en échec)%s\n' "$COLOR_KO" "$N_KO" "$TOTAL" "$COLOR_RESET"
    exit 1
else
    if [[ $N_WARN -gt 0 || $N_SKIP -gt 0 ]]; then
        printf '%s[OK] Poste CONFORME (avec %d attention(s) et %d check(s) ignoré(s))%s\n' \
            "$COLOR_OK" "$N_WARN" "$N_SKIP" "$COLOR_RESET"
    else
        printf '%s[OK] Poste 100%% CONFORME (%d/%d checks OK)%s\n' "$COLOR_OK" "$TOTAL" "$TOTAL" "$COLOR_RESET"
    fi
    exit 0
fi
