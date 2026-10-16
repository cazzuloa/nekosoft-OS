#!/bin/bash
# NekoSoft SAE103 - 03-desktop.sh
# Fond d'écran + personnalisations LXDE + LightDM + /etc/skel
# Usage: sudo bash 03-desktop.sh
# Pré-requis : nekosoft-wallpaper-1920x1080.png à côté du script ou dans ../wallpapers/
set -eux

CDIR="$(cd "$(dirname "$0")" && pwd)"
WALL_SRC=""
for c in "$CDIR/nekosoft-wallpaper-1920x1080.png" "$CDIR/../wallpapers/nekosoft-wallpaper-1920x1080.png"; do
  [ -f "$c" ] && WALL_SRC="$c" && break
done
WALL_DST="/usr/share/backgrounds/nekosoft-wallpaper.png"
DEV_USER="${DEV_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"

[ -n "$WALL_SRC" ] || { echo "ERREUR: nekosoft-wallpaper-1920x1080.png introuvable (cherché dans $CDIR et $CDIR/../wallpapers)"; exit 1; }

# 1. Installer le fond système
mkdir -p /usr/share/backgrounds
cp "$WALL_SRC" "$WALL_DST"
chmod 644 "$WALL_DST"

# 2. Config PCManFM (gestionnaire bureau LXDE) pour l'utilisateur actuel
# La session Trisquel-mini lit le profil "Trisquel-mini", pas "default".
# On fournit donc TOUS les profils : le bon est toujours trouvé.
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

# 3. Modèle /etc/skel pour tout futur utilisateur (exigence sujet \$HOME via /etc/skel)
for p in default lxde LXDE Trisquel-mini trisquel-mini; do
  mkdir -p "/etc/skel/.config/pcmanfm/$p"
  cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf"
done
find /etc/skel/.config/pcmanfm -type d -exec chmod 755 {} \;
find /etc/skel/.config/pcmanfm -type f -exec chmod 644 {} \;
# Autostart XDG (backup) : Exec direct, pas de sh -c
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
mkdir -p /etc/skel/.config/geany
mkdir -p "/home/$DEV_USER/.config/geany"

# 4. Écran de login LightDM aux couleurs NekoSoft
# Trisquel Mini : vrai fichier = /etc/lightdm/lightdm-gtk-greeter.conf (pas de .d/)
# Idempotent : nettoie les anciens blocs ajoutés avant de réécrire (évite doublons [greeter])
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

# 5. Appliquer immédiatement si session LXDE active (ne casse rien sinon)
sudo -u "$DEV_USER" /usr/local/bin/nekosoft-wallpaper.sh || true
# Répare aussi les profils existants de l'utilisateur actuel (cas Trisquel-mini)
for p in lxde LXDE Trisquel-mini trisquel-mini; do
  mkdir -p "/home/$DEV_USER/.config/pcmanfm/$p"
  cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" "/home/$DEV_USER/.config/pcmanfm/$p/desktop-items-0.conf"
done
chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.config"

echo "== Desktop OK. Vérif : nouveau user test =="
echo "sudo adduser testnek && sudo -u testnek cat ~/.config/pcmanfm/default/desktop-items-0.conf"
