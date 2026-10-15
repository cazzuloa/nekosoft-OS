#!/bin/bash
# NekoSoft SAE103 - fix fond d'écran LIVE + installé + futurs users
# À coller dans le terminal chroot de Cubic (root), puis Next -> Generate.
# Cause trouvée : la session Trisquel-mini lit le profil pcmanfm "Trisquel-mini",
# pas "default" ni "lxde". + autostart XDG manquant + --wallpaper-mode=fill invalide
# (pcmanfm CLI n'accepte que color|stretch|fit|center|tile).
# Fix : tous les profils + helper + autostart lxsession natif + XDG.
set -eux

WALL=/usr/share/backgrounds/nekosoft-wallpaper.png
[ -f "$WALL" ] || { echo "ERREUR: $WALL absent du chroot"; exit 1; }

cat > /usr/local/bin/nekosoft-wallpaper.sh <<'SCRIPTEOF'
#!/bin/bash
WALL=/usr/share/backgrounds/nekosoft-wallpaper.png
[ -f "$WALL" ] || exit 0
for p in Trisquel-mini trisquel-mini LXDE lxde default; do
  D="$HOME/.config/pcmanfm/$p"
  mkdir -p "$D"
  cat > "$D/desktop-items-0.conf" <<CONF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=$WALL
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
if [ -n "${DISPLAY:-}" ] && command -v pcmanfm >/dev/null 2>&1; then
  pcmanfm --set-wallpaper="$WALL" --wallpaper-mode=stretch || true
  pcmanfm --reconfigure || true
fi
exit 0
SCRIPTEOF
chmod 755 /usr/local/bin/nekosoft-wallpaper.sh

for p in default lxde LXDE Trisquel-mini trisquel-mini; do
  mkdir -p "/etc/skel/.config/pcmanfm/$p"
  cat > "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf" <<CONF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=$WALL
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
chmod -R a+rX /etc/skel/.config/pcmanfm

# Applique aussi au root du chroot (inoffensif, preuve de config)
for p in default lxde LXDE Trisquel-mini trisquel-mini; do
  mkdir -p "/root/.config/pcmanfm/$p"
  cp "/etc/skel/.config/pcmanfm/$p/desktop-items-0.conf" "/root/.config/pcmanfm/$p/desktop-items-0.conf"
done

# Autostart XDG (backup)
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

# Autostart natif lxsession (fiable : lu avant pcmanfm --desktop)
for S in LXDE Trisquel-mini; do
  F="/etc/xdg/lxsession/$S/autostart"
  [ -f "$F" ] || continue
  grep -q "nekosoft-wallpaper" "$F" || echo "@/usr/local/bin/nekosoft-wallpaper.sh" >> "$F"
done

echo "== FIX WALLPAPER OK =="
ls -l /etc/skel/.config/pcmanfm/*/desktop-items-0.conf /etc/xdg/autostart/nekosoft-wallpaper.desktop
cat /etc/xdg/lxsession/Trisquel-mini/autostart || true
