#!/bin/bash
# =============================================================================
# NekoSoft - empaquette les médias de démo Kodi
#
# GitHub refuse les fichiers de plus de 100 Mo : l'archive est découpée en
# parts de 90 Mo (demo/kodi/media.tar.gz.00, .01, ...) qui, elles, peuvent
# être versionnées. demo.sh reconstitue l'archive (cat des parts), vérifie
# son empreinte sha256 puis l'extrait dans /srv/nekosoft/media.
#
# Usage : bash scripts/pack-demo-media.sh [--drop-source]
#   --drop-source  supprime demo/kodi/media après un empaquetage réussi
#
# NEKO_MEDIA_PART_SIZE permet de changer la taille des parts (défaut : 90m).
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MEDIA_SRC="$REPO_DIR/demo/kodi/media"
OUT_DIR="$REPO_DIR/demo/kodi"
ARCHIVE="$OUT_DIR/media.tar.gz"
MANIFEST="$OUT_DIR/media.sha256"
PART_SIZE="${NEKO_MEDIA_PART_SIZE:-90m}"
MAX_PART_BYTES=$((100 * 1024 * 1024))
DROP_SOURCE=0

info() { printf '[@] %s\n' "$*"; }
die()  { echo "[ERREUR] $*" >&2; exit 1; }

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); if ($0 !~ /^=+$/) print; next } { exit }' "$0"
}

for arg in "$@"; do
    case "$arg" in
        --drop-source) DROP_SOURCE=1 ;;
        -h|--help)     usage; exit 0 ;;
        *)             die "option inconnue : $arg (voir --help)" ;;
    esac
done

[[ -d "$MEDIA_SRC" ]] || die "dossier média introuvable : $MEDIA_SRC (décompresse l'archive ou re-télécharge les fichiers)"
[[ -n "$(find "$MEDIA_SRC" -type f -print -quit)" ]] || die "dossier média vide : $MEDIA_SRC"

info "Empaquetage de $MEDIA_SRC"
# Options tar : archive reproductible (même empreinte à chaque passage)
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 \
    -czf "$ARCHIVE" -C "$MEDIA_SRC" .

# Contrôle de contenu : même nombre de fichiers dans la source et l'archive
src_count="$(find "$MEDIA_SRC" -type f | wc -l)"
tar_count="$(tar -tzf "$ARCHIVE" | grep -vc '/$' || true)"
[[ "$src_count" -eq "$tar_count" ]] \
    || { rm -f "$ARCHIVE"; die "archive incomplète : $tar_count fichier(s) au lieu de $src_count"; }

hash="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
printf '%s  media.tar.gz\n' "$hash" > "$MANIFEST"
info "Empreinte sha256 : $hash"

info "Découpage en parts de $PART_SIZE (limite GitHub : 100 Mo/fichier)"
rm -f "$OUT_DIR"/media.tar.gz.[0-9][0-9]
split -b "$PART_SIZE" -d -a 2 "$ARCHIVE" "$OUT_DIR/media.tar.gz."
rm -f "$ARCHIVE"

# Contrôle : les parts réassemblées doivent redonner l'empreinte d'origine
have="$(cat "$OUT_DIR"/media.tar.gz.[0-9][0-9] | sha256sum | awk '{print $1}')"
[[ "$have" == "$hash" ]] || die "réassemblage incorrect ($have ≠ $hash)"

for p in "$OUT_DIR"/media.tar.gz.[0-9][0-9]; do
    size="$(stat -c %s "$p")"
    (( size < MAX_PART_BYTES )) || die "$(basename "$p") dépasse 100 Mo : réduire NEKO_MEDIA_PART_SIZE"
    info "  $(basename "$p") : $(( size / 1024 / 1024 )) Mo"
done

if [[ "$DROP_SOURCE" -eq 1 ]]; then
    rm -rf "$MEDIA_SRC"
    info "Dossier source supprimé : $MEDIA_SRC"
fi

info "Terminé. Penser à versionner demo/kodi/media.tar.gz.* et demo/kodi/media.sha256"
