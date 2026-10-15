#!/bin/bash
# NekoSoft - fix fond d'ecran LIVE + installe (a lancer dans chroot Cubic)
set -eux

WALL=/usr/share/backgrounds/nekosoft-wallpaper.png
[ -f "$WALL" ] || { echo "ERREUR: $WALL absent du chroot"; exit 1; }

read -r -d '' CONF <<'EOF' || true
[*]
wallpaper_mode=fill
wallpaper_common=1
wallpaper=/usr/share/backgrounds/nekosoft-wallpaper.png
desktop_bg=#1E1B2E
desktop_fg=#FFFFFF
desktop_shadow=#000000
show_wm_menu=0
sort=mtime;ascending;
show_documents=0
show_trash=1
show_mounts=1
EOF

# LXDE utilise le profil "lxde" : fournir default + lxde
for p in default lxde; do
  mkdir -p "/etc/skel/.config/pcmanfm/$p"
  printf '%s\n' "$CONF" > "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf"
done

mkdir -p /root/.config/pcmanfm/lxde /root/.config/pcmanfm/default
printf '%s\n' "$CONF" > /root/.config/pcmanfm/lxde/desktop-items-0.conf
printf '%s\n' "$CONF" > /root/.config/pcmanfm/default/desktop-items-0.conf

cat > /etc/xdg/autostart/nekosoft-wallpaper.desktop <<EOF
[Desktop Entry]
Type=Application
Name=NekoSoft Wallpaper
Comment=Applique le fond d'ecran NekoSoft au demarrage de session
Exec=sh -c "sleep 2; pcmanfm --set-wallpaper $WALL --wallpaper-mode=fill"
OnlyShowIn=LXDE;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chmod 644 /etc/xdg/autostart/nekosoft-wallpaper.desktop

mkdir -p /etc/skel/.config/autostart
cp /etc/xdg/autostart/nekosoft-wallpaper.desktop /etc/skel/.config/autostart/

echo "== FIX WALLPAPER OK =="
ls -l /etc/skel/.config/pcmanfm/*/desktop-items-0.conf /etc/xdg/autostart/nekosoft-wallpaper.desktop
