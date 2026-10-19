#!/bin/bash
# =============================================================================
# NekoSoft - démo : page Apache personnalisée + Kodi préconfiguré
# SAE 1.03 - @cazzuloa | https://github.com/cazzuloa/nekosoft-OS
#
# Usage : sudo bash demo.sh [--no-web] [--no-kodi] [--remove]
#   --no-web    ne pas installer la page d'accueil Apache
#   --no-kodi   ne pas installer Kodi ni sa configuration
#   --remove    retire la page de démo et restaure la page Apache d'origine
#
# Peut aussi être appelé par setup.sh :  sudo NEKO_DEMO=1 bash setup.sh
# =============================================================================

set -Eeuo pipefail
trap 'echo "[ERREUR] ligne $LINENO : $BASH_COMMAND" >&2' ERR

# ----------------------------- Paramètres ------------------------------------
REPO_URL="${NEKO_REPO_URL:-https://github.com/cazzuloa/nekosoft-OS.git}"
WEBROOT="${NEKO_WEBROOT:-/var/www/html}"
SKEL_DIR="${NEKO_SKEL:-/etc/skel}"
STATE_DIR="${NEKO_STATE_DIR:-/var/lib/nekosoft}"
APACHE_DEFAULT_SAVE="$STATE_DIR/apache-default-index.html"

SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
SCRIPT_DIR="$(dirname "${SELF:-/root/x}")"
DEMO_SRC="${DEMO_SRC:-}"
CLONE_DIR=""
DO_WEB=1; DO_KODI=1; DO_REMOVE=0
export DEBIAN_FRONTEND=noninteractive

# ----------------------------- Outils ----------------------------------------
if [[ -t 1 ]]; then C_INFO=$'\033[0;36m'; C_WARN=$'\033[0;33m'; C_OFF=$'\033[0m'
else C_INFO=''; C_WARN=''; C_OFF=''; fi
info() { printf '%s[@] %s%s\n' "$C_INFO" "$*" "$C_OFF"; }
warn() { printf '%s[!] %s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { echo "[ERREUR] $*" >&2; exit 1; }

cleanup() { [[ -n "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"; return 0; }
trap cleanup EXIT

# Utilisateurs humains (même critère que setup.sh) : "login:home"
list_users() {
    local u uid home
    while IFS=: read -r u _ uid _ _ home _; do
        if (( uid >= 1000 && uid < 60000 )) && [[ -d "$home" ]]; then
            echo "$u:$home"
        fi
    done < /etc/passwd
}

# Applique les droits web (www-data, setgid sur les dossiers) aux fichiers copiés
fix_web_perms() {
    local rel t
    local wu=""; id www-data >/dev/null 2>&1 && wu="www-data"
    while IFS= read -r -d '' rel; do
        t="$WEBROOT/${rel#./}"
        if [[ -d "$t" ]]; then chmod 2775 "$t"; else chmod 664 "$t"; fi
        if [[ -n "$wu" ]]; then chown "$wu:$wu" "$t"; fi
    done < <(cd "$DEMO_SRC/www" && find . -mindepth 1 -print0)
}

# ----------------------------- Sources ---------------------------------------
resolve_source() {
    if [[ -n "$DEMO_SRC" ]]; then
        :
    elif [[ -d "$SCRIPT_DIR/demo" ]]; then
        DEMO_SRC="$SCRIPT_DIR/demo"
    else
        command -v git >/dev/null 2>&1 || die "git absent : sudo apt install git (ou dépose le dossier demo/ à côté du script)"
        CLONE_DIR="$(mktemp -d)"
        info "Téléchargement du dépôt NekoSoft"
        git clone --depth 1 --quiet "$REPO_URL" "$CLONE_DIR/repo" || die "clone impossible : $REPO_URL"
        DEMO_SRC="$CLONE_DIR/repo/demo"
    fi
    [[ -d "$DEMO_SRC" ]] || die "dossier demo introuvable : $DEMO_SRC"
}

# ----------------------------- Page Apache -----------------------------------
install_web() {
    [[ -d "$DEMO_SRC/www" ]] || die "$DEMO_SRC/www introuvable"
    [[ -d "$WEBROOT" ]]      || die "$WEBROOT absent : lance d'abord setup.sh"
    info "Page d'accueil Apache NekoSoft"
    mkdir -p "$STATE_DIR"

    # DirectoryIndex d'Apache : index.html passe AVANT index.php. On met la page par défaut de côté.
    if [[ -f "$WEBROOT/index.html" ]]; then
        if grep -qi 'default page' "$WEBROOT/index.html"; then
            [[ -e "$APACHE_DEFAULT_SAVE" ]] || cp -a "$WEBROOT/index.html" "$APACHE_DEFAULT_SAVE"
            rm -f "$WEBROOT/index.html"
            info "Page par défaut d'Apache sauvegardée dans $APACHE_DEFAULT_SAVE"
        else
            warn "$WEBROOT/index.html (personnalisé) masque index.php : renomme-le pour voir la page de démo"
        fi
    fi

    cp -a "$DEMO_SRC/www/." "$WEBROOT/"
    fix_web_perms
    command -v php >/dev/null 2>&1 || warn "php absent : la page index.php ne s'exécutera pas (lance setup.sh)"
    touch "$STATE_DIR/demo-web.done"
}

remove_web() {
    [[ -d "$DEMO_SRC/www" ]] || die "$DEMO_SRC/www introuvable (nécessaire pour savoir quoi retirer)"
    info "Retrait de la page de démo"
    local rel
    while IFS= read -r -d '' rel; do
        rm -f "$WEBROOT/${rel#./}"
    done < <(cd "$DEMO_SRC/www" && find . -type f -print0)
    if [[ -f "$APACHE_DEFAULT_SAVE" && ! -e "$WEBROOT/index.html" ]]; then
        cp -a "$APACHE_DEFAULT_SAVE" "$WEBROOT/index.html"
        info "Page par défaut d'Apache restaurée"
    fi
    rm -f "$STATE_DIR/demo-web.done"
}

# ----------------------------- Kodi ------------------------------------------
# $1 = dossier home ; $2 = propriétaire (vide pour /etc/skel)
deploy_kodi_to() {
    local home="$1" owner="${2:-}" dst="$1/.kodi" rel t

    # Kodi réécrit guisettings.xml à sa fermeture : inutile de copier pendant qu'il tourne
    if [[ -n "$owner" ]] && pgrep -u "$owner" -x 'kodi(\.bin|-x11)?' >/dev/null 2>&1; then
        warn "Kodi tourne pour $owner : ferme-le puis relance demo.sh"
        return 0
    fi

    mkdir -p "$dst/userdata"
    # Sauvegarde de la config d'origine, une seule fois, et seulement si elle diffère de la nôtre
    if [[ -f "$dst/userdata/guisettings.xml" && ! -e "$dst/userdata/guisettings.xml.bak-nekosoft" ]] \
       && ! cmp -s "$dst/userdata/guisettings.xml" "$DEMO_SRC/kodi/userdata/guisettings.xml"; then
        cp -a "$dst/userdata/guisettings.xml" "$dst/userdata/guisettings.xml.bak-nekosoft"
    fi
    cp -a "$DEMO_SRC/kodi/." "$dst/"

    # Droits : uniquement sur ce qu'on a copié
    while IFS= read -r -d '' rel; do
        t="$dst/${rel#./}"
        if [[ -d "$t" ]]; then chmod 755 "$t"; else chmod 644 "$t"; fi
    done < <(cd "$DEMO_SRC/kodi" && find . -mindepth 1 -print0)

    if [[ -n "$owner" ]]; then chown -R "$owner:" "$dst"; fi
    return 0
}

install_kodi() {
    [[ -d "$DEMO_SRC/kodi" ]] || die "$DEMO_SRC/kodi introuvable"
    info "Kodi : installation et configuration en français"

    if ! dpkg-query -W -f='${Status}' kodi 2>/dev/null | grep -q '^install ok installed$'; then
        apt-cache show kodi >/dev/null 2>&1 || die "paquet 'kodi' introuvable dans les dépôts (apt-get update ?)"
        info "Installation du paquet kodi (volumineux : prévoir quelques minutes)"
        apt-get -y -o Dpkg::Options::=--force-confold install kodi
    fi

    mkdir -p "$STATE_DIR"
    deploy_kodi_to "$SKEL_DIR" ""            # nouveaux utilisateurs

    local entry u home d
    while IFS= read -r entry; do             # utilisateurs existants
        u="${entry%%:*}"; home="${entry#*:}"
        info "Configuration Kodi pour $u"
        deploy_kodi_to "$home" "$u"
        # Raccourci sur le bureau (Bureau en français, Desktop sinon)
        for d in "$home/Bureau" "$home/Desktop"; do
            if [[ -d "$d" && -f /usr/share/applications/kodi.desktop ]]; then
                install -m 755 -o "$u" -g "$(id -gn "$u")" /usr/share/applications/kodi.desktop "$d/kodi.desktop"
            fi
        done
    done < <(list_users)

    touch "$STATE_DIR/demo-kodi.done"
}

# ----------------------------- Main ------------------------------------------
main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            --no-web)  DO_WEB=0 ;;
            --no-kodi) DO_KODI=0 ;;
            --remove)  DO_REMOVE=1 ;;
            -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
            *) die "option inconnue : $arg (voir --help)" ;;
        esac
    done

    [[ "$(id -u)" -eq 0 ]] || die "Lancer en root : sudo bash $0"
    resolve_source

    if [[ "$DO_REMOVE" -eq 1 ]]; then
        remove_web
        info "Démo retirée (la config Kodi des utilisateurs est conservée)."
        return 0
    fi

    [[ "$DO_WEB"  -eq 1 ]] && install_web
    [[ "$DO_KODI" -eq 1 ]] && install_kodi

    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/demo.done"
    info "Démo prête."
    [[ "$DO_WEB"  -eq 1 ]] && info "  Page d'accueil : http://localhost/"
    [[ "$DO_KODI" -eq 1 ]] && info "  Kodi           : menu Applications (ou raccourci du bureau), reconnexion conseillée"
    return 0
}

main "$@"