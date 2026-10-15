#!/bin/bash
# NekoSoft - personnalisation LXDE / LightDM / skel
# Usage: sudo bash 03-desktop.sh
# Requiert : nekosoft-wallpaper-1920x1080.png dans le meme dossier
set -eux

CDIR="$(cd "$(dirname "$0")" && pwd)"
WALL_SRC="$CDIR/nekosoft-wallpaper-1920x1080.png"
WALL_DST="/usr/share/backgrounds/nekosoft-wallpaper.png"
DEV_USER="${DEV_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"

[ -f "$WALL_SRC" ] || { echo "ERREUR: $WALL_SRC introuvable"; exit 1; }

mkdir -p /usr/share/backgrounds
cp "$WALL_SRC" "$WALL_DST"
chmod 644 "$WALL_DST"

mkdir -p "/home/$DEV_USER/.config/pcmanfm/default"
cat > "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" <<EOF
[*]
wallpaper_mode=fill
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
chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.config"

# LXDE utilise le profil "lxde" : fournir default + lxde
mkdir -p /etc/skel/.config/pcmanfm/default /etc/skel/.config/pcmanfm/lxde
cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" /etc/skel/.config/pcmanfm/default/
cp "/home/$DEV_USER/.config/pcmanfm/default/desktop-items-0.conf" /etc/skel/.config/pcmanfm/lxde/

cat > /etc/xdg/autostart/nekosoft-wallpaper.desktop <<EOF
[Desktop Entry]
Type=Application
Name=NekoSoft Wallpaper
Comment=Applique le fond d'ecran NekoSoft au demarrage de session
Exec=sh -c "sleep 2; pcmanfm --set-wallpaper $WALL_DST --wallpaper-mode=fill"
OnlyShowIn=LXDE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chmod 644 /etc/xdg/autostart/nekosoft-wallpaper.desktop
mkdir -p /etc/skel/.config/autostart
cp /etc/xdg/autostart/nekosoft-wallpaper.desktop /etc/skel/.config/autostart/

cat >> /etc/skel/.bashrc <<'EOF'

# --- NekoSoft ---
export PS1='\[\e[38;5;177m\]nekosoft🐾 \w \$ \[\e[0m\]'
alias ll='ls -lh --color'
alias www='cd /var/www/html'
alias logs='sudo journalctl -xeu apache2 -u mariadb -u forgejo'
EOF
cp /etc/skel/.bashrc "/home/$DEV_USER/.bashrc.nekosoft-add" || true
grep -q "NekoSoft" "/home/$DEV_USER/.bashrc" || cat /etc/skel/.bashrc >> "/home/$DEV_USER/.bashrc" || true

mkdir -p /etc/skel/.config/geany
mkdir -p "/home/$DEV_USER/.config/geany"

# Fichier greeter Trisquel Mini : /etc/lightdm/lightdm-gtk-greeter.conf
if ! grep -q "nekosoft-wallpaper" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
  cat >> /etc/lightdm/lightdm-gtk-greeter.conf <<EOF

[greeter]
background=$WALL_DST
theme-name=Adwaita-dark
icon-theme-name=elementary
font-name=Cantarell 11
EOF
fi

# Applique immediatement si session LXDE active
sudo -u "$DEV_USER" pcmanfm --set-wallpaper "$WALL_DST" --wallpaper-mode=fill || true

echo "== Desktop OK =="
