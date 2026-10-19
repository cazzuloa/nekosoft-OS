#!/bin/bash
# =============================================================================
# NekoSoft - vérification du poste (compagnon de setup.sh)
# SAE 1.03 - @cazzuloa
#
# À lancer sur la VM / machine INSTALLÉE (pas dans le chroot Cubic) :
# la plupart des checks exigent systemd et les services démarrés.
#
# Usage :
#   sudo bash check.sh                     # vérification complète
#   sudo bash check.sh mariadb web         # seulement certaines sections
#   sudo bash check.sh --user=dev1         # un utilisateur dev précis
#   bash check.sh --no-color               # sortie sans couleur (logs)
#
# Sections : packages, services, firstboot, mariadb, web, forgejo, backup,
#            webroot, desktop, terminal, locale, abrowser
#
# Code retour : 0 = conforme, 1 = au moins un échec, 2 = erreur d'argument.
# =============================================================================

set -uo pipefail
# NB : volontairement SANS set -e : un check qui échoue doit être affiché,
# pas interrompre la vérification.

# ----------------------------- Constantes (miroir de setup.sh) ---------------
STATE_DIR="/var/lib/nekosoft"
CRED_FILE="/root/nekosoft-credentials.txt"
SELF_INSTALLED="/usr/local/sbin/nekosoft-setup"
BASHRC_MARK="# --- NekoSoft ---"
BACKUP_BASE="/var/backups/nekosoft"
BORG_REPO="$BACKUP_BASE/borg"
BORG_PASSFILE="/root/.borg-passphrase"
BORG_KEYFILE="/root/borg-key-backup.txt"
WALL_DST="/usr/share/backgrounds/nekosoft-wallpaper.png"
UBLOCK_ID="uBlock0@raymondhill.net"
UBLOCK_LOCAL="/usr/share/nekosoft/ublock-origin.xpi"
PCMANFM_PROFILES=(default lxde LXDE Trisquel-mini trisquel-mini)
FORGEJO_ADMIN="nekoadmin"
SECTION_ORDER=(packages services firstboot mariadb web forgejo backup webroot desktop terminal locale abrowser)

# ----------------------------- Affichage -------------------------------------
if [[ -t 1 ]]; then
    COLOR_OK=$'\033[0;32m' COLOR_KO=$'\033[0;31m' COLOR_WARN=$'\033[0;33m'
    COLOR_INFO=$'\033[0;36m' COLOR_RESET=$'\033[0m'
else
    COLOR_OK='' COLOR_KO='' COLOR_WARN='' COLOR_INFO='' COLOR_RESET=''
fi

info()    { printf '%s%s%s\n' "$COLOR_INFO" "$*" "$COLOR_RESET"; }
section() { printf '\n%s--- %s ---%s\n' "$COLOR_INFO" "$*" "$COLOR_RESET"; }

N_OK=0 N_KO=0 N_WARN=0 N_SKIP=0
declare -a KO_LINES=()

ok()   { N_OK=$((N_OK + 1)); printf '  %s[OK]%s       %s\n' "$COLOR_OK" "$COLOR_RESET" "$1"; }
ko()   {   # $1 = constat, $2 = piste de correction
    N_KO=$((N_KO + 1)); KO_LINES+=("${1}|${2:-}")
    printf '  %s[ECHEC]%s    %s\n' "$COLOR_KO" "$COLOR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '              -> %s\n' "$2"
}
warn() {
    N_WARN=$((N_WARN + 1))
    printf '  %s[ATTENTION]%s %s\n' "$COLOR_WARN" "$COLOR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '              -> %s\n' "$2"
}
skip() {
    N_SKIP=$((N_SKIP + 1))
    printf '  %s[IGNORÉ]%s   %s\n' "$COLOR_WARN" "$COLOR_RESET" "$1"
    [[ -n "${2:-}" ]] && printf '              (%s)\n' "$2"
}

# ----------------------------- Helpers ---------------------------------------
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed$'; }
have_systemd()  { [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; }
svc_enabled()   { systemctl is-enabled "$1" >/dev/null 2>&1; }
svc_active()    { systemctl is-active  "$1" >/dev/null 2>&1; }
unit_exists()   {   # list-unit-files exige le nom complet : on ajoute .service si besoin
    local u="$1"; [[ "$u" == *.* ]] || u="$u.service"
    systemctl list-unit-files "$u" --no-legend 2>/dev/null | grep -q .
}
http_code()     { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null; }
http_code_L()   { curl -sL -o /dev/null -w '%{http_code}' --max-time 10 "$1" 2>/dev/null; }
in_group()      { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -qx "$2"; }
home_of()       { getent passwd "$1" | cut -d: -f6; }

# Extrait le mot de passe d'une section de /root/nekosoft-credentials.txt
# $1 = début de l'en-tête (ex. "== MariaDB")
cred_password() {
    [[ -r "$CRED_FILE" ]] || return 1
    awk -v h="$1" 'index($0, h) == 1 {f=1; next}
                   f && /^mot de passe : / {sub(/^mot de passe : /, ""); print; exit}
                   f && /^$/ {exit}' "$CRED_FILE"
}

# Vérifie plusieurs fichiers d'un coup ; une seule ligne OK si tout est bon.
# $1 = libellé ; $2 = motif grep (fixe) ou "" (existence seule) ; $3... = fichiers
check_files_contain() {
    local label="$1" pat="$2"; shift 2
    local f bad=()
    for f in "$@"; do
        if [[ ! -f "$f" ]]; then bad+=("$f (absent)")
        elif [[ -n "$pat" ]] && ! grep -qF -- "$pat" "$f" 2>/dev/null; then bad+=("$f (contenu incorrect)")
        fi
    done
    if [[ ${#bad[@]} -eq 0 ]]; then
        ok "$label : $# fichier(s) conforme(s)"
    else
        for f in "${bad[@]}"; do ko "$label : $f" "relance : sudo $SELF_INSTALLED  (ou sudo bash setup.sh)"; done
    fi
}

# ----------------------------- Arguments -------------------------------------
ORIG_ARGS=("$@")
DEV_USERS=()
FORCED_USER=""
SECTIONS=()

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user=*)   FORCED_USER="${1#--user=}"; shift ;;
        --user)     [[ $# -ge 2 && -n "${2:-}" ]] || { echo "--user attend un nom d'utilisateur" >&2; exit 2; }
                    FORCED_USER="$2"; shift 2 ;;
        --no-color) COLOR_OK='' COLOR_KO='' COLOR_WARN='' COLOR_INFO='' COLOR_RESET=''; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*)         echo "Option inconnue : $1 (voir : bash $0 --help)" >&2; exit 2 ;;
        *)          SECTIONS+=("$1"); shift ;;
    esac
done

# Validation des sections
for s in "${SECTIONS[@]}"; do
    found=0
    for t in "${SECTION_ORDER[@]}"; do [[ "$s" == "$t" ]] && found=1; done
    if [[ $found -eq 0 ]]; then
        echo "[ERREUR] Section inconnue : $s" >&2
        echo "Sections : ${SECTION_ORDER[*]}" >&2
        exit 2
    fi
done

WANT() {
    [[ ${#SECTIONS[@]} -eq 0 ]] && return 0
    local s; for s in "${SECTIONS[@]}"; do [[ "$s" == "$1" ]] && return 0; done
    return 1
}

# Relance automatique avec sudo : sans root, une partie des checks est ignorée ou fausse
# (ex. /etc/forgejo et /root illisibles). NEKO_NO_SUDO=1 pour désactiver.
if [[ "$(id -u)" -ne 0 && -z "${NEKO_NO_SUDO:-}" ]] && command -v sudo >/dev/null 2>&1; then
    info "[@] Relance avec sudo (nécessaire pour tout vérifier)"
    exec sudo bash "$0" "${ORIG_ARGS[@]}"
fi

info "[@] NekoSoft check - $(date '+%Y-%m-%d %H:%M:%S')"

ROOT_OK=1
if [[ "$(id -u)" -ne 0 ]]; then
    ROOT_OK=0
    warn "Lancé sans root : les checks privilégiés seront ignorés" "relance : sudo bash $0"
fi

# Utilisateurs à vérifier : même logique que setup.sh (uid 1000-59999 avec un home)
if [[ -n "$FORCED_USER" ]]; then
    if id "$FORCED_USER" >/dev/null 2>&1; then DEV_USERS=("$FORCED_USER")
    else echo "[ERREUR] Utilisateur introuvable : $FORCED_USER" >&2; exit 2; fi
else
    while IFS=: read -r u _ uid _ _ home _; do
        if (( uid >= 1000 && uid < 60000 )) && [[ -d "$home" ]]; then DEV_USERS+=("$u"); fi
    done < /etc/passwd
fi
if [[ ${#DEV_USERS[@]} -eq 0 ]]; then
    warn "Aucun utilisateur humain trouvé : checks par utilisateur ignorés" "relance avec --user=<login>"
else
    info "[@] Utilisateur(s) vérifié(s) : ${DEV_USERS[*]}"
fi

# =============================================================================
# 1. Paquets (liste = install_packages de setup.sh)
# =============================================================================
check_packages() {
    section "Paquets installés (apt)"
    local pkgs=(
        apache2 mariadb-server
        php libapache2-mod-php php-mysql php-cli php-mbstring php-zip php-gd php-curl php-xml
        phpmyadmin geany geany-plugins abrowser abrowser-locale-fr
        git borgbackup openssl ca-certificates acl locales curl wget unzip
        lightdm-gtk-greeter-settings
    )
    local p missing=()
    for p in "${pkgs[@]}"; do pkg_installed "$p" || missing+=("$p"); done
    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "${#pkgs[@]} paquets installés"
    else
        for p in "${missing[@]}"; do ko "$p : paquet ABSENT" "sudo apt install -y $p"; done
        ok "$(( ${#pkgs[@]} - ${#missing[@]} ))/${#pkgs[@]} paquets installés"
    fi
}

# =============================================================================
# 2. Services systemd
# =============================================================================
check_services() {
    section "Services systemd"
    if ! have_systemd; then
        skip "systemd non actif (chroot / live ?)" "lancer check.sh sur la machine installée"
        return
    fi

    local s
    for s in apache2 mariadb forgejo nekosoft-backup.timer; do
        if ! unit_exists "$s"; then
            ko "$s : unité absente" "relance setup.sh"
            continue
        fi
        if svc_enabled "$s"; then ok "$s : activé au démarrage"
        else ko "$s : NON activé" "sudo systemctl enable $s"; fi
        if svc_active "$s"; then ok "$s : actif"
        else ko "$s : INACTIF" "sudo systemctl start $s ; sudo journalctl -xeu $s"; fi
    done

    # Service de premier démarrage : doit être activé (il se désactive de lui-même via ConditionPathExists)
    if unit_exists nekosoft-firstboot.service; then
        if svc_enabled nekosoft-firstboot.service; then ok "nekosoft-firstboot : activé"
        else ko "nekosoft-firstboot : NON activé" "sudo systemctl enable nekosoft-firstboot"; fi
    elif [[ -e "$STATE_DIR/firstboot.done" ]]; then
        # setup.sh lancé directement sur la machine (mode live) : pas de service, config faite en direct
        ok "nekosoft-firstboot : non installé, configuration faite en direct (setup.sh mode live)"
    else
        ko "nekosoft-firstboot.service : unité absente" \
           "image Cubic : relance setup.sh dans le chroot ; machine directe : sudo bash setup.sh"
    fi
}

# =============================================================================
# 3. Configuration au premier démarrage
# =============================================================================
check_firstboot() {
    section "Premier démarrage (nekosoft-firstboot)"
    if [[ "$ROOT_OK" -ne 1 ]]; then
        skip "firstboot : /var/lib/nekosoft et /root illisibles" "relance : sudo bash $0"
        return
    fi

    local step missing=()
    for step in mariadb users borg forgejo; do
        [[ -e "$STATE_DIR/$step.done" ]] || missing+=("$step")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then ok "étapes terminées : mariadb, users, borg, forgejo"
    else ko "étapes firstboot non terminées : ${missing[*]}" \
            "sudo $SELF_INSTALLED --firstboot ; journalctl -u nekosoft-firstboot"; fi

    if [[ -e "$STATE_DIR/firstboot.done" ]]; then ok "firstboot.done présent"
    else ko "firstboot.done ABSENT" "sudo $SELF_INSTALLED --firstboot"; fi

    # Le script réinstallé n'existe qu'avec le service firstboot (image Cubic / mode chroot)
    if [[ -f /etc/systemd/system/nekosoft-firstboot.service ]]; then
        if [[ -x "$SELF_INSTALLED" ]]; then ok "$SELF_INSTALLED : présent (utilisé par nekosoft-firstboot)"
        else ko "$SELF_INSTALLED : ABSENT alors que nekosoft-firstboot.service existe" "relance setup.sh dans le chroot Cubic"; fi
    else
        ok "installation directe (mode live) : pas de service firstboot, $SELF_INSTALLED non requis"
    fi

    if [[ -f "$CRED_FILE" ]]; then
        if [[ "$(stat -c %a "$CRED_FILE")" == "600" ]]; then ok "$CRED_FILE : présent, droits 600"
        else ko "$CRED_FILE : droits $(stat -c %a "$CRED_FILE") (600 attendu)" "sudo chmod 600 $CRED_FILE"; fi
    else
        warn "$CRED_FILE : absent" "supprimé volontairement après copie ? sinon relancer le firstboot"
    fi
}

# =============================================================================
# 4. MariaDB
# =============================================================================
check_mariadb() {
    section "MariaDB : root (unix_socket) + admin + durcissement"
    if ! command -v mysql >/dev/null 2>&1; then
        ko "mysql : binaire absent" "sudo apt install -y mariadb-server"; return
    fi
    if ! (mariadb-admin ping --silent >/dev/null 2>&1 || mysqladmin ping --silent >/dev/null 2>&1); then
        ko "MariaDB : ne répond pas au ping" "sudo systemctl start mariadb"; return
    fi
    ok "MariaDB : répond au ping"

    if [[ "$ROOT_OK" -ne 1 ]]; then
        skip "MariaDB : checks root/admin ignorés" "relance : sudo bash $0"; return
    fi

    if mysql --user=root -e "SELECT 1;" >/dev/null 2>&1; then
        ok "root : connexion unix_socket OK"
    else
        ko "root : connexion unix_socket EN ÉCHEC" "sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;\""
        return
    fi

    local plugin
    plugin="$(mysql --user=root -N -B -e "SELECT plugin FROM mysql.user WHERE User='root' AND Host='localhost';" 2>/dev/null)"
    if [[ "$plugin" == *unix_socket* ]]; then ok "root : authentification unix_socket"
    else warn "root : plugin d'auth = '${plugin:-inconnu}' (unix_socket attendu)" \
              "sudo mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket;\""; fi

    # Compte admin : existence + privilèges (ko), connexion avec le mot de passe généré (warn si changé)
    local n
    n="$(mysql --user=root -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE User='admin' AND Host='localhost';" 2>/dev/null || echo 0)"
    if [[ "$n" == "1" ]]; then
        ok "admin@localhost : compte présent"
        if mysql --user=root -N -B -e "SHOW GRANTS FOR 'admin'@'localhost';" 2>/dev/null | grep -q "ALL PRIVILEGES"; then
            ok "admin : ALL PRIVILEGES"
        else
            ko "admin : privilèges insuffisants" "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;"
        fi
        local pw; pw="$(cred_password '== MariaDB' || true)"
        if [[ -z "$pw" ]]; then
            skip "admin : test de connexion (mot de passe introuvable dans $CRED_FILE)" ""
        elif MYSQL_PWD="$pw" mysql --user=admin -e "SELECT 1;" >/dev/null 2>&1; then
            ok "admin : connexion avec le mot de passe de $CRED_FILE"
        else
            warn "admin : mot de passe de $CRED_FILE refusé" "mot de passe modifié depuis ? sinon le réinitialiser"
        fi
    else
        ko "admin@localhost : compte ABSENT" "sudo $SELF_INSTALLED --firstboot (supprimer $STATE_DIR/mariadb.done avant)"
    fi

    local anon
    anon="$(mysql --user=root -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE User='';" 2>/dev/null || echo -1)"
    if [[ "$anon" == "0" ]]; then ok "durcissement : aucun utilisateur anonyme"
    else ko "durcissement : $anon utilisateur(s) anonyme(s)" "sudo mysql -e \"DROP USER IF EXISTS ''@'localhost';\""; fi

    if [[ -z "$(mysql --user=root -N -B -e "SHOW DATABASES LIKE 'test';" 2>/dev/null)" ]]; then
        ok "durcissement : base 'test' absente"
    else
        ko "durcissement : base 'test' présente" "sudo mysql -e \"DROP DATABASE test;\""
    fi
}

# =============================================================================
# 5. Web : Apache + PHP + phpMyAdmin
# =============================================================================
check_web() {
    section "Web : Apache + PHP + phpMyAdmin"
    if ! command -v curl >/dev/null 2>&1; then
        ko "curl absent : tests HTTP impossibles" "sudo apt install -y curl"; return
    fi

    if [[ "$ROOT_OK" -eq 1 ]] && command -v apache2ctl >/dev/null 2>&1; then
        if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then ok "Apache : syntaxe de configuration OK"
        else ko "Apache : ERREUR de configuration" "sudo apache2ctl configtest"; fi
    fi

    local code
    code="$(http_code http://localhost/)"
    if [[ "$code" == "200" ]]; then ok "Apache : http://localhost/ répond (HTTP $code)"
    else ko "Apache : http://localhost/ répond HTTP $code (200 attendu)" "sudo systemctl start apache2"; fi

    # Test PHP fonctionnel : fichier temporaire dont la sortie n'apparaît que si PHP est exécuté
    if [[ "$ROOT_OK" -eq 1 && -d /var/www/html ]]; then
        local t="/var/www/html/.neko-check-$$.php" out
        printf '<?php echo "NEKO_PHP_" . "OK_" . (6 * 7);' > "$t"
        chmod 644 "$t"
        out="$(curl -fsS --max-time 10 "http://localhost/${t##*/}" 2>/dev/null)"
        rm -f "$t"
        if [[ "$out" == "NEKO_PHP_OK_42" ]]; then ok "PHP : exécuté par Apache (libapache2-mod-php)"
        else ko "PHP : le code PHP n'est pas exécuté par Apache" "sudo a2enmod php* ; sudo systemctl restart apache2"; fi
    else
        skip "PHP : test d'exécution (root requis)" "relance : sudo bash $0"
    fi

    # info.php : optionnel (NEKO_PHPINFO=1), à supprimer après la démo
    if [[ -f /var/www/html/info.php ]]; then
        warn "/var/www/html/info.php présent" "à supprimer après la démo : sudo rm /var/www/html/info.php"
    fi

    # phpMyAdmin
    if [[ -e /etc/apache2/conf-enabled/phpmyadmin.conf ]]; then ok "phpMyAdmin : conf Apache activée"
    else ko "phpMyAdmin : conf Apache non activée" "sudo a2enconf phpmyadmin && sudo systemctl reload apache2"; fi

    if [[ -e /etc/apache2/conf-enabled/zz-nekosoft-phpmyadmin-local.conf ]]; then
        ok "phpMyAdmin : restreint à l'accès local (Require local)"
    else
        ko "phpMyAdmin : restriction locale NON activée" "relance setup.sh (configure_apache)"
    fi

    code="$(http_code_L http://localhost/phpmyadmin/)"
    if [[ "$code" == "200" ]]; then ok "phpMyAdmin : http://localhost/phpmyadmin/ répond (HTTP $code)"
    else ko "phpMyAdmin : HTTP $code sur /phpmyadmin/" "sudo a2enconf phpmyadmin ; sudo systemctl reload apache2"; fi

    # Modules PHP (php -m : le module xml s'appelle "xml", mysql -> "mysqli")
    if command -v php >/dev/null 2>&1; then
        local m mods=(mbstring zip gd curl mysqli xml) loaded miss=()
        loaded="$(php -m 2>/dev/null)"
        for m in "${mods[@]}"; do grep -qix "$m" <<<"$loaded" || miss+=("$m"); done
        if [[ ${#miss[@]} -eq 0 ]]; then ok "PHP $(php -r 'echo PHP_VERSION;') : modules ${mods[*]} chargés"
        else ko "PHP : modules absents : ${miss[*]}" "sudo apt install -y php-xml php-mysql php-mbstring php-zip php-gd php-curl"; fi
    else
        ko "PHP : binaire php absent" "sudo apt install -y php-cli"
    fi
}

# =============================================================================
# 6. Forgejo
# =============================================================================
check_forgejo() {
    section "Forgejo (forge logicielle, 127.0.0.1:3000)"
    if [[ -x /usr/local/bin/forgejo ]]; then
        ok "/usr/local/bin/forgejo : exécutable ($(/usr/local/bin/forgejo --version 2>/dev/null | head -n1))"
    else
        ko "/usr/local/bin/forgejo : ABSENT" "relance setup.sh (téléchargement + sha256)"
    fi

    if id git >/dev/null 2>&1; then ok "utilisateur système 'git' : présent"
    else ko "utilisateur 'git' : ABSENT" "relance setup.sh"; fi

    local d own
    for d in /var/lib/forgejo /var/log/forgejo; do
        own="$(stat -c %U:%G "$d" 2>/dev/null)"
        if [[ "$own" == "git:git" ]]; then ok "$d : propriétaire git:git"
        else ko "$d : propriétaire '${own:-absent}' (git:git attendu)" "sudo chown git:git $d"; fi
    done

    # /etc/forgejo est verrouillé en 750 root:git après la génération d'app.ini
    if [[ -d /etc/forgejo ]]; then
        local m; m="$(stat -c %a /etc/forgejo)"
        if [[ "$m" == "750" ]]; then ok "/etc/forgejo : droits 750"
        else ko "/etc/forgejo : droits $m (750 attendu)" "sudo chmod 750 /etc/forgejo"; fi
    else
        ko "/etc/forgejo : ABSENT" "relance setup.sh"
    fi

    local ini=/etc/forgejo/app.ini
    if [[ -f $ini ]]; then
        if [[ "$(stat -c %a:%U:%G $ini)" == "640:git:git" ]]; then ok "$ini : droits 640 git:git"
        else ko "$ini : droits $(stat -c %a:%U:%G $ini) (640:git:git attendu)" "sudo chown git:git $ini ; sudo chmod 640 $ini"; fi

        local k bad=()
        for k in "HTTP_ADDR = 127.0.0.1" "HTTP_PORT = 3000" "DB_TYPE = sqlite3" \
                 "INSTALL_LOCK = true" "DISABLE_REGISTRATION = true" "DISABLE_SSH = true"; do
            grep -qF "$k" $ini 2>/dev/null || bad+=("$k")
        done
        if [[ ${#bad[@]} -eq 0 ]]; then ok "$ini : écoute locale, sqlite3, install verrouillée, inscriptions fermées"
        else ko "$ini : paramètres manquants : ${bad[*]}" "relance le firstboot (supprimer $STATE_DIR/forgejo.done)"; fi
    elif [[ "$ROOT_OK" -ne 1 && ! -x /etc/forgejo ]]; then
        skip "$ini : illisible sans root (dossier root:git)" "relance : sudo bash $0"
    else
        ko "$ini : ABSENT" "sudo $SELF_INSTALLED --firstboot"
    fi

    if [[ -f /etc/systemd/system/forgejo.service ]]; then ok "forgejo.service : unité installée"
    else ko "forgejo.service : ABSENT" "relance setup.sh"; fi

    # Fonctionnel
    local code
    code="$(http_code http://localhost:3000/)"
    case "$code" in
        200|303) ok "Forgejo : http://localhost:3000/ répond (HTTP $code)" ;;
        *)       ko "Forgejo : http://localhost:3000/ répond HTTP $code" "sudo systemctl start forgejo ; sudo journalctl -xeu forgejo" ;;
    esac

    if command -v ss >/dev/null 2>&1; then
        if ss -tln 2>/dev/null | grep -q '127.0.0.1:3000'; then ok "Forgejo : port 3000 en écoute sur 127.0.0.1 uniquement"
        elif ss -tln 2>/dev/null | grep -qE '(0.0.0.0|\*|\[::\]):3000'; then ko "Forgejo : port 3000 exposé sur toutes les interfaces" "HTTP_ADDR = 127.0.0.1 dans $ini"
        fi
    fi

    # Compte administrateur
    if [[ "$ROOT_OK" -eq 1 && -x /usr/local/bin/forgejo && -f $ini ]]; then
        if runuser -u git -- env HOME=/home/git FORGEJO_WORK_DIR=/var/lib/forgejo \
             /usr/local/bin/forgejo --config $ini --work-path /var/lib/forgejo admin user list 2>/dev/null \
             | grep -qw "$FORGEJO_ADMIN"; then
            ok "compte admin '$FORGEJO_ADMIN' : présent"
            local pw; pw="$(cred_password '== Forgejo' || true)"
            if [[ -n "$pw" ]]; then
                code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
                        --config <(printf 'user = "%s:%s"\n' "$FORGEJO_ADMIN" "$pw") \
                        http://localhost:3000/api/v1/user 2>/dev/null)"
                if [[ "$code" == "200" ]]; then ok "compte admin : authentification API OK (mot de passe de $CRED_FILE)"
                else warn "compte admin : authentification refusée (HTTP $code)" "mot de passe modifié depuis ?"; fi
            fi
        else
            ko "compte admin '$FORGEJO_ADMIN' : ABSENT" "sudo $SELF_INSTALLED --firstboot (supprimer $STATE_DIR/forgejo.done avant)"
        fi
    else
        skip "compte admin Forgejo : non vérifié (root requis)" "relance : sudo bash $0"
    fi
}

# =============================================================================
# 7. Sauvegardes Borg (dépôt chiffré + timer systemd)
# =============================================================================
check_backup() {
    section "Sauvegardes Borg : dépôt chiffré, timer, restauration"

    if [[ -x /usr/local/bin/nekosoft-backup.sh ]]; then ok "nekosoft-backup.sh : exécutable"
    else ko "nekosoft-backup.sh : ABSENT" "relance setup.sh"; fi

    local u
    for u in nekosoft-backup.service nekosoft-backup.timer; do
        if [[ -f /etc/systemd/system/$u ]]; then ok "$u : installé"
        else ko "$u : ABSENT" "relance setup.sh"; fi
    done

    if have_systemd && unit_exists nekosoft-backup.timer; then
        local next
        next="$(systemctl list-timers nekosoft-backup.timer --no-legend 2>/dev/null | awk '{print $1, $2, $3}')"
        [[ -n "$next" ]] && info "      prochaine exécution : $next"
    fi

    if [[ "$ROOT_OK" -ne 1 ]]; then
        skip "Borg : passphrase/dépôt/restauration non vérifiables sans root" "relance : sudo bash $0"
        return
    fi

    # Passphrase + clé exportée
    if [[ -f "$BORG_PASSFILE" ]]; then
        if [[ "$(stat -c %a "$BORG_PASSFILE")" == "600" ]]; then ok "$BORG_PASSFILE : présent, droits 600"
        else ko "$BORG_PASSFILE : droits $(stat -c %a "$BORG_PASSFILE") (600 attendu)" "sudo chmod 600 $BORG_PASSFILE"; fi
    else
        ko "$BORG_PASSFILE : ABSENT" "sudo $SELF_INSTALLED --firstboot"
    fi
    if [[ -f "$BORG_KEYFILE" ]]; then ok "$BORG_KEYFILE : clé exportée"
    else warn "$BORG_KEYFILE : absent" "borg key export $BORG_REPO $BORG_KEYFILE"; fi

    if [[ -d "$BACKUP_BASE" ]]; then
        if [[ "$(stat -c %a "$BACKUP_BASE")" == "700" ]]; then ok "$BACKUP_BASE : droits 700"
        else ko "$BACKUP_BASE : droits $(stat -c %a "$BACKUP_BASE") (700 attendu)" "sudo chmod 700 $BACKUP_BASE"; fi
    fi

    if [[ ! -d "$BORG_REPO" ]]; then
        ko "$BORG_REPO : dépôt ABSENT" "sudo $SELF_INSTALLED --firstboot"
        return
    fi
    ok "$BORG_REPO : dépôt présent"

    if ! command -v borg >/dev/null 2>&1; then ko "borg : binaire absent" "sudo apt install -y borgbackup"; return; fi
    [[ -r "$BORG_PASSFILE" ]] || return

    export BORG_PASSPHRASE; BORG_PASSPHRASE="$(cat "$BORG_PASSFILE")"

    # Chiffrement
    local enc
    enc="$(borg info "$BORG_REPO" 2>/dev/null | grep -i '^Encrypted:' || true)"
    if grep -qi 'yes' <<<"$enc" && grep -qi 'repokey' <<<"$enc"; then ok "dépôt chiffré : ${enc#Encrypted: }"
    else ko "dépôt non chiffré ou illisible (${enc:-aucune info})" "recréer : borg init --encryption=repokey-blake2 $BORG_REPO"; fi

    # Archives
    local last count
    last="$(borg list --short --last 1 "$BORG_REPO" 2>/dev/null)"
    count="$(borg list --short "$BORG_REPO" 2>/dev/null | wc -l)"
    if [[ -z "$last" ]]; then
        warn "dépôt vide (aucune archive)" "sudo /usr/local/bin/nekosoft-backup.sh"
        unset BORG_PASSPHRASE; return
    fi
    ok "$count archive(s) ; dernière : $last"

    # Cohérence du dépôt
    if borg check "$BORG_REPO" >/dev/null 2>&1; then ok "borg check : dépôt et archives cohérents"
    else ko "borg check : ÉCHEC" "borg check --verbose $BORG_REPO"; fi

    # Contenu attendu dans la dernière archive
    local listing; listing="$(borg list --short "$BORG_REPO::$last" 2>/dev/null)"
    local p miss=()
    for p in var/www/html var/backups/nekosoft/staging/all-databases.sql.gz etc/forgejo etc/apache2 home; do
        grep -qx "$p\(/.*\)\?" <<<"$listing" || miss+=("$p")
    done
    if [[ ${#miss[@]} -eq 0 ]]; then ok "archive : contient web, dump SQL, Forgejo, Apache, /home"
    else ko "archive : éléments absents : ${miss[*]}" "sudo /usr/local/bin/nekosoft-backup.sh puis revérifier"; fi

    # Test de restauration réel : un petit fichier extrait puis comparé
    local tmp; tmp="$(mktemp -d)"
    if ( cd "$tmp" && borg extract "$BORG_REPO::$last" etc/apache2/apache2.conf >/dev/null 2>&1 ); then
        if cmp -s "$tmp/etc/apache2/apache2.conf" /etc/apache2/apache2.conf; then
            ok "restauration : etc/apache2/apache2.conf extrait et identique à l'original"
        else
            warn "restauration : fichier extrait différent de l'original" "modifié depuis la dernière sauvegarde ?"
        fi
    else
        ko "restauration : extraction impossible depuis $last" "borg extract $BORG_REPO::$last etc/apache2/apache2.conf"
    fi
    rm -rf "$tmp"
    unset BORG_PASSPHRASE
}

# =============================================================================
# 8. Webroot : droits développeur
# =============================================================================
check_webroot() {
    section "Webroot /var/www/html (droits développeur)"
    if [[ ! -d /var/www/html ]]; then
        ko "/var/www/html : ABSENT" "sudo apt install -y apache2"; return
    fi

    local owner mode
    owner="$(stat -c %U:%G /var/www/html)"; mode="$(stat -c %a /var/www/html)"
    if [[ "$owner" == "www-data:www-data" ]]; then ok "propriétaire $owner"
    else ko "propriétaire $owner (www-data:www-data attendu)" "sudo chown -R www-data:www-data /var/www/html"; fi

    if [[ "$mode" == "2775" ]]; then ok "mode 2775 (rwxrwsr-x : setgid)"
    else ko "mode $mode (2775 attendu)" "sudo chmod 2775 /var/www/html"; fi

    if command -v getfacl >/dev/null 2>&1; then
        if getfacl -p /var/www/html 2>/dev/null | grep -q '^default:group:www-data:rwx'; then
            ok "ACL par défaut : g:www-data:rwx"
        else
            ko "ACL par défaut www-data absente" "sudo setfacl -R -d -m g:www-data:rwX /var/www/html"
        fi
    else
        ko "getfacl absent (paquet acl)" "sudo apt install -y acl"
    fi

    local u
    for u in "${DEV_USERS[@]}"; do
        if in_group "$u" www-data; then ok "$u : membre du groupe www-data"
        else ko "$u : PAS dans le groupe www-data" "sudo usermod -aG www-data $u (puis reconnexion)"; continue; fi

        # Test d'écriture réel avec les groupes de l'utilisateur
        if [[ "$ROOT_OK" -eq 1 ]]; then
            if runuser -u "$u" -- bash -c 'f="$(mktemp -p /var/www/html .neko-w.XXXXXX)" && rm -f "$f"' 2>/dev/null; then
                ok "$u : peut créer des fichiers dans /var/www/html"
            else
                ko "$u : ne peut PAS écrire dans /var/www/html" "vérifier groupe www-data, mode 2775 et ACL"
            fi
        fi
    done
}

# =============================================================================
# 9. Bureau : fond d'écran, PCManFM, LightDM, navigateur par défaut
# =============================================================================
check_desktop() {
    section "Bureau NekoSoft : fond d'écran, PCManFM, LightDM"

    if [[ -s "$WALL_DST" ]]; then
        if [[ "$(head -c4 "$WALL_DST" | od -An -tx1 | tr -d ' \n')" == "89504e47" ]]; then
            ok "$WALL_DST : présent, PNG valide"
        else
            ko "$WALL_DST : fichier corrompu (pas un PNG)" "relance setup.sh (retélécharger / copier le fichier)"
        fi
    else
        ko "$WALL_DST : ABSENT" "copier nekosoft-wallpaper.png à côté de setup.sh puis relancer"
    fi

    # Profils PCManFM : skel (modèle) + chaque utilisateur
    local files=() p u h
    for p in "${PCMANFM_PROFILES[@]}"; do files+=("/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf"); done
    check_files_contain "skel PCManFM (${#PCMANFM_PROFILES[@]} profils)" "wallpaper=$WALL_DST" "${files[@]}"

    for u in "${DEV_USERS[@]}"; do
        h="$(home_of "$u")"; files=()
        for p in "${PCMANFM_PROFILES[@]}"; do files+=("$h/.config/pcmanfm/$p/desktop-items-0.conf"); done
        check_files_contain "$u : PCManFM" "wallpaper=$WALL_DST" "${files[@]}"
    done

    # LightDM
    local g=/etc/lightdm/lightdm-gtk-greeter.conf
    if [[ -f $g ]]; then
        if grep -qF "background=$WALL_DST" $g; then ok "LightDM : fond d'écran NekoSoft sur l'écran de connexion"
        else ko "LightDM : fond d'écran NON configuré" "relance setup.sh (install_wallpaper)"; fi
    else
        ko "$g : ABSENT" "sudo apt install -y lightdm-gtk-greeter-settings ; relance setup.sh"
    fi

    # Navigateur par défaut
    check_files_contain "skel : mimeapps.list (abrowser par défaut)" "x-scheme-handler/https=abrowser.desktop" /etc/skel/.config/mimeapps.list
    for u in "${DEV_USERS[@]}"; do
        h="$(home_of "$u")"
        check_files_contain "$u : mimeapps.list" "x-scheme-handler/https=abrowser.desktop" "$h/.config/mimeapps.list"
    done
}

# =============================================================================
# 10. Terminal : bloc .bashrc NekoSoft
# =============================================================================
check_terminal() {
    section "Terminal : .bashrc NekoSoft (PS1, couleurs, alias)"
    local f label miss
    local targets=("/etc/skel/.bashrc")
    local u; for u in "${DEV_USERS[@]}"; do targets+=("$(home_of "$u")/.bashrc"); done

    for f in "${targets[@]}"; do
        if [[ ! -f "$f" ]]; then ko "$f : ABSENT" "relance setup.sh"; continue; fi
        if ! grep -qF "$BASHRC_MARK" "$f"; then ko "$f : bloc NekoSoft ABSENT" "relance setup.sh"; continue; fi
        miss=()
        grep -qF 'nekosoft🐾'   "$f" || miss+=("PS1")
        grep -q  "alias ll="   "$f" || miss+=("alias ll")
        grep -q  "alias www="  "$f" || miss+=("alias www")
        grep -q  "alias logs=" "$f" || miss+=("alias logs")
        if [[ ${#miss[@]} -eq 0 ]]; then ok "$f : bloc NekoSoft complet (PS1, ll, www, logs)"
        else ko "$f : éléments manquants : ${miss[*]}" "relance setup.sh"; fi
    done
}

# =============================================================================
# 11. Locale française
# =============================================================================
check_locale() {
    section "Locale système : français"
    if locale -a 2>/dev/null | grep -qiE '^fr_FR\.utf-?8$'; then ok "fr_FR.UTF-8 : locale générée"
    else ko "fr_FR.UTF-8 : locale non générée" "sudo locale-gen fr_FR.UTF-8"; fi

    if grep -qx 'LANG=fr_FR.UTF-8' /etc/default/locale 2>/dev/null; then ok "/etc/default/locale : LANG=fr_FR.UTF-8"
    else ko "/etc/default/locale : LANG=fr_FR.UTF-8 absent" "sudo update-locale LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr"; fi
}

# =============================================================================
# 12. ABrowser : français + uBlock Origin forcé
# =============================================================================
check_abrowser() {
    section "ABrowser : français + uBlock Origin"
    if command -v abrowser >/dev/null 2>&1; then ok "abrowser : installé"
    else ko "abrowser : binaire absent" "sudo apt install -y abrowser abrowser-locale-fr"; fi

    if ! command -v python3 >/dev/null 2>&1; then
        skip "policies.json : python3 absent, JSON non validé" ""; return
    fi

    local f
    for f in /usr/lib/abrowser/distribution/policies.json /etc/firefox/policies/policies.json; do
        if [[ ! -f "$f" ]]; then ko "$f : ABSENT" "relance setup.sh (install_abrowser)"; continue; fi
        if python3 - "$f" "$UBLOCK_ID" <<'PY' 2>/dev/null
import json, sys
p = json.load(open(sys.argv[1]))["policies"]
assert "fr" in p.get("RequestedLocales", []), "locale fr absente"
e = p["ExtensionSettings"][sys.argv[2]]
assert e["installation_mode"] == "force_installed", "uBlock non forcé"
assert e["install_url"], "install_url vide"
PY
        then ok "$f : JSON valide, locale fr, uBlock Origin force_installed"
        else ko "$f : JSON invalide, locale fr ou uBlock absents" "relance setup.sh (install_abrowser)"; fi
    done

    # xpi embarqué (installation hors-ligne)
    if [[ -s "$UBLOCK_LOCAL" ]]; then
        if [[ "$(head -c2 "$UBLOCK_LOCAL")" == "PK" ]]; then ok "$UBLOCK_LOCAL : xpi embarqué (archive valide)"
        else ko "$UBLOCK_LOCAL : pas une archive xpi valide" "relance setup.sh (install_abrowser)"; fi
    elif grep -q 'file://' /usr/lib/abrowser/distribution/policies.json 2>/dev/null; then
        ko "$UBLOCK_LOCAL : ABSENT alors que policies.json le référence" "relance setup.sh"
    else
        warn "xpi uBlock non embarqué : Internet requis au 1er lancement d'abrowser" "relance setup.sh avec accès Internet"
    fi

    # Navigateur par défaut (alternatives)
    local alt
    alt="$(readlink -f /etc/alternatives/x-www-browser 2>/dev/null)"
    if [[ "$alt" == *abrowser* ]]; then ok "x-www-browser : $alt"
    else warn "x-www-browser pointe vers '${alt:-rien}'" "sudo update-alternatives --set x-www-browser /usr/bin/abrowser"; fi
}

# =============================================================================
# Exécution
# =============================================================================
for s in "${SECTION_ORDER[@]}"; do
    WANT "$s" && "check_$s"
done

# ----------------------------- Récapitulatif ---------------------------------
TOTAL=$((N_OK + N_KO))
printf '\n%s============================================================%s\n' "$COLOR_INFO" "$COLOR_RESET"
info "Résultat NekoSoft : $N_OK OK / $N_KO ÉCHEC(S) / $N_WARN ATTENTION(S) / $N_SKIP IGNORÉ(S)"

if [[ ${#KO_LINES[@]} -gt 0 ]]; then
    info "Échecs à corriger :"
    for line in "${KO_LINES[@]}"; do
        printf '  %s• %s%s\n' "$COLOR_KO" "${line%%|*}" "$COLOR_RESET"
        h="${line#*|}"
        [[ -n "$h" && "$h" != "$line" ]] && printf '      -> %s\n' "$h"
    done
fi

if [[ $N_KO -gt 0 ]]; then
    printf '%s[ECHEC] Poste NON CONFORME (%d/%d checks en échec)%s\n' "$COLOR_KO" "$N_KO" "$TOTAL" "$COLOR_RESET"
    exit 1
fi
if [[ $N_WARN -gt 0 || $N_SKIP -gt 0 ]]; then
    printf '%s[OK] Poste CONFORME (%d attention(s), %d check(s) ignoré(s))%s\n' "$COLOR_OK" "$N_WARN" "$N_SKIP" "$COLOR_RESET"
else
    printf '%s[OK] Poste 100%% CONFORME (%d/%d checks OK)%s\n' "$COLOR_OK" "$TOTAL" "$TOTAL" "$COLOR_RESET"
fi
exit 0