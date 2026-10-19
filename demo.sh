#!/bin/bash
# =============================================================================
# NekoSoft - démo : page Apache personnalisée + Kodi préconfiguré
# SAE 1.03 - @cazzuloa | https://github.com/cazzuloa/nekosoft-OS
#
# Usage : sudo bash demo.sh [--no-web] [--no-kodi] [--no-media] [--remove]
#   --no-web    ne pas installer la page d'accueil Apache
#   --no-kodi   ne pas installer Kodi ni sa configuration
#   --no-media  ne pas déployer les médias de démonstration
#   --remove    retire la page de démo et restaure la page Apache d'origine
#               (la config Kodi et les médias partagés sont conservés)
#
# Médias : l'archive du dépôt (demo/kodi/media.tar.gz.00, .01, ...) est
# décompressée dans $NEKO_MEDIA_DIR (défaut /srv/nekosoft/media), partagée
# par tous les utilisateurs et référencée dans les sources de Kodi.
# La regénérer avec : bash scripts/pack-demo-media.sh
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
MEDIA_DIR="${NEKO_MEDIA_DIR:-/srv/nekosoft/media}"
APACHE_DEFAULT_SAVE="$STATE_DIR/apache-default-index.html"

SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
SCRIPT_DIR="$(dirname "${SELF:-/root/x}")"
DEMO_SRC="${DEMO_SRC:-}"
CLONE_DIR=""
DO_WEB=1; DO_KODI=1; DO_MEDIA=1; DO_REMOVE=0
export DEBIAN_FRONTEND=noninteractive

# ----------------------------- Outils ----------------------------------------
if [[ -t 1 ]]; then C_INFO=$'\033[0;36m'; C_WARN=$'\033[0;33m'; C_OFF=$'\033[0m'
else C_INFO=''; C_WARN=''; C_OFF=''; fi
info() { printf '%s[@] %s%s\n' "$C_INFO" "$*" "$C_OFF"; }
warn() { printf '%s[!] %s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { echo "[ERREUR] $*" >&2; exit 1; }

cleanup() { [[ -n "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"; return 0; }
trap cleanup EXIT

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); if ($0 !~ /^=+$/) print; next } { exit }' "$0"
}

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

# ----------------------------- Médias partagés -------------------------------
# Archive entière (media.tar.gz) ou parts numérotées (media.tar.gz.00, .01, ...)
list_media_parts() {
    local d="$DEMO_SRC/kodi" p n=0
    if [[ -f "$d/media.tar.gz" ]]; then
        printf '%s\n' "$d/media.tar.gz"
        return 0
    fi
    for p in "$d"/media.tar.gz.[0-9][0-9]; do
        [[ -f "$p" ]] || continue
        printf '%s\n' "$p"
        n=$((n + 1))
    done
    (( n > 0 ))
}

install_media() {
    local manifest="$DEMO_SRC/kodi/media.sha256"
    local want="" have="" staging parent p
    local -a parts=()

    [[ -n "$MEDIA_DIR" && "$MEDIA_DIR" != "/" ]] || die "NEKO_MEDIA_DIR invalide : '$MEDIA_DIR'"

    mapfile -t parts < <(list_media_parts || true)
    if (( ${#parts[@]} == 0 )); then
        die "aucune archive média dans $DEMO_SRC/kodi (générer avec : bash scripts/pack-demo-media.sh)"
    fi

    if [[ -f "$manifest" ]]; then
        want="$(awk 'NR == 1 { print $1 }' "$manifest")"
        info "Médias : vérification de l'archive (${#parts[@]} part(s))"
        have="$(cat "${parts[@]}" | sha256sum | awk '{print $1}')"
        [[ "$want" == "$have" ]] \
            || die "archive média corrompue ($have ≠ $want) : re-cloner le dépôt ou relancer scripts/pack-demo-media.sh"
    else
        warn "manifeste absent ($manifest) : extraction sans vérification d'intégrité"
        want="$(cat "${parts[@]}" | sha256sum | awk '{print $1}')"
    fi

    # Déjà décompressé et à jour ? (empreinte gravée après extraction)
    if [[ -n "$want" && -d "$MEDIA_DIR" && -f "$MEDIA_DIR/.nekosoft-media" ]] \
       && [[ "$want" == "$(cat "$MEDIA_DIR/.nekosoft-media")" ]]; then
        info "Médias : $MEDIA_DIR déjà à jour"
        mkdir -p "$STATE_DIR"
        printf '%s\n' "$MEDIA_DIR" > "$STATE_DIR/media-dir"
        touch "$STATE_DIR/demo-media.done"
        return 0
    fi

    info "Médias : extraction vers $MEDIA_DIR"
    parent="$(dirname "$MEDIA_DIR")"
    mkdir -p "$parent"
    staging="$(mktemp -d "$parent/.nekosoft-media.XXXXXX")"
    if ! cat "${parts[@]}" | tar -xzf - -C "$staging"; then
        rm -rf "$staging"
        die "extraction de l'archive média impossible"
    fi
    if [[ -z "$(find "$staging" -type f -print -quit)" ]]; then
        rm -rf "$staging"
        die "archive média vide"
    fi

    for p in film serie music; do
        [[ -d "$staging/$p" ]] || warn "dossier média inattendu : $p absent de l'archive"
    done

    # Remplacement atomique : on ne supprime l'ancien contenu qu'une fois le nouveau prêt
    rm -rf "$MEDIA_DIR"
    mv "$staging" "$MEDIA_DIR"
    chmod -R u=rwX,go=rX "$MEDIA_DIR"
    [[ -n "$want" ]] && printf '%s\n' "$want" > "$MEDIA_DIR/.nekosoft-media"

    mkdir -p "$STATE_DIR"
    printf '%s\n' "$MEDIA_DIR" > "$STATE_DIR/media-dir"
    touch "$STATE_DIR/demo-media.done"
    info "Médias : $(du -sh "$MEDIA_DIR" | cut -f1) disponibles pour tous les utilisateurs"
}

# ----------------------------- Kodi ------------------------------------------
# $1 = dossier home ; $2 = propriétaire (vide pour /etc/skel)
deploy_kodi_to() {
    local home="$1" owner="${2:-}" dst="$1/.kodi" rel t f

    # Kodi réécrit guisettings.xml à sa fermeture : inutile de copier pendant qu'il tourne
    if [[ -n "$owner" ]] && pgrep -u "$owner" -x 'kodi(\.bin|-x11)?' >/dev/null 2>&1; then
        warn "Kodi tourne pour $owner : ferme-le puis relance demo.sh"
        return 0
    fi

    mkdir -p "$dst/userdata"
    # Ancienne version de la démo : les médias étaient copiés dans ~/.kodi/media
    if [[ -d "$dst/media" ]]; then
        warn "$dst/media : ancienne copie locale des médias (désormais partagés dans $MEDIA_DIR)"
        warn "  à supprimer pour libérer l'espace : sudo rm -rf '$dst/media'"
    fi
    # Sauvegarde de la config d'origine, une seule fois, et seulement si elle diffère de la nôtre
    for f in guisettings.xml sources.xml; do
        [[ -f "$dst/userdata/$f" ]] || continue
        [[ -e "$dst/userdata/$f.bak-nekosoft" ]] && continue
        cmp -s "$dst/userdata/$f" "$DEMO_SRC/kodi/userdata/$f" && continue
        cp -a "$dst/userdata/$f" "$dst/userdata/$f.bak-nekosoft"
    done

    # Seule la configuration est copiée : les médias restent dans $MEDIA_DIR (partagés)
    cp -a "$DEMO_SRC/kodi/userdata/." "$dst/userdata/"

    # NEKO_MEDIA_DIR personnalisé : on réécrit les chemins des sources Kodi
    if [[ "$MEDIA_DIR" != "/srv/nekosoft/media" && -f "$dst/userdata/sources.xml" ]]; then
        local esc="${MEDIA_DIR//\\/\\\\}"; esc="${esc//&/\\&}"; esc="${esc//|/\\|}"
        sed -i "s|/srv/nekosoft/media|$esc|g" "$dst/userdata/sources.xml"
    fi

    # Droits : uniquement sur ce qu'on a copié
    while IFS= read -r -d '' rel; do
        t="$dst/userdata/${rel#./}"
        if [[ -d "$t" ]]; then chmod 755 "$t"; else chmod 644 "$t"; fi
    done < <(cd "$DEMO_SRC/kodi/userdata" && find . -mindepth 1 -print0)

    if [[ -n "$owner" ]]; then chown -R "$owner:" "$dst"; fi
    return 0
}

install_kodi() {
    [[ -d "$DEMO_SRC/kodi/userdata" ]] || die "$DEMO_SRC/kodi/userdata introuvable"
    info "Kodi : installation et configuration en français"

    if ! dpkg-query -W -f='${Status}' kodi 2>/dev/null | grep -q '^install ok installed$'; then
        if ! apt-cache show kodi >/dev/null 2>&1; then
            info "Mise à jour de la liste des paquets"
            apt-get update || die "apt-get update impossible (réseau ?)"
        fi
        apt-cache show kodi >/dev/null 2>&1 || die "paquet 'kodi' introuvable dans les dépôts"
        info "Installation du paquet kodi (volumineux : prévoir quelques minutes)"
        apt-get -y -o Dpkg::Options::=--force-confold install kodi
    fi

    [[ -d "$MEDIA_DIR" ]] || warn "$MEDIA_DIR absent : les sources Kodi pointeront dans le vide (relance sans --no-media)"

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
            --no-web)   DO_WEB=0 ;;
            --no-kodi)  DO_KODI=0 ;;
            --no-media) DO_MEDIA=0 ;;
            --remove)   DO_REMOVE=1 ;;
            -h|--help)  usage; exit 0 ;;
            *) die "option inconnue : $arg (voir --help)" ;;
        esac
    done

    [[ "$(id -u)" -eq 0 ]] || die "Lancer en root : sudo bash $0"
    resolve_source

    if [[ "$DO_REMOVE" -eq 1 ]]; then
        remove_web
        info "Démo retirée (config Kodi et médias partagés conservés)."
        return 0
    fi

    [[ "$DO_MEDIA" -eq 1 ]] && install_media
    [[ "$DO_WEB"   -eq 1 ]] && install_web
    [[ "$DO_KODI"  -eq 1 ]] && install_kodi

    mkdir -p "$STATE_DIR"
    touch "$STATE_DIR/demo.done"
    info "Démo prête."
    [[ "$DO_WEB"   -eq 1 ]] && info "  Page d'accueil : http://localhost/"
    [[ "$DO_MEDIA" -eq 1 ]] && info "  Médias         : $MEDIA_DIR"
    [[ "$DO_KODI"  -eq 1 ]] && info "  Kodi           : menu Applications (ou raccourci du bureau), reconnexion conseillée"
    return 0
}

main "$@"
