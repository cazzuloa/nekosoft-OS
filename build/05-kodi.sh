#!/bin/bash
# NekoSoft SAE103 - 05-kodi.sh
# Kodi Media Center (https://kodi.tv) - mediacenter 100% libre (GPLv2)
# Usage: sudo bash 05-kodi.sh
# Testé pour : Trisquel 12 Mini (LXDE, base Ubuntu) + Debian/Ubuntu
set -eux

export DEBIAN_FRONTEND=noninteractive
DEV_USER="${DEV_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"

# 0. Root requis
if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR: lancer en root : sudo bash $0"
  exit 1
fi

# 1. Dépôt universe (Trisquel/Ubuntu) : Kodi y est, 100% libre, pas de PPA/snap/flatpak
# Justification soutenance : on reste sur dépôt officiel libre, sans binaire proprio.
if command -v lsb_release >/dev/null 2>&1 && lsb_release -is 2>/dev/null | grep -qiE "trisquel|ubuntu"; then
  apt update
  apt install -y software-properties-common || true
  add-apt-repository -y universe || true
fi

# 2. Install Kodi
apt update
apt install -y kodi

# 3. Vérif binaire + version (preuve démo/soutenance)
command -v kodi
kodi --version || true
dpkg -l kodi | tail -5

# 4. Français par défaut pour user actuel + futurs users via /etc/skel
# Kodi lit ~/.kodi/userdata/guisettings.xml ; on pré-seede locale.language fr_fr.
# Si Kodi écrase au 1er lancement, le réglage manuel reste : Interface > Regional > Language = French.
seed_kodi_fr() {
  BASE="$1/.kodi/userdata"
  mkdir -p "$BASE"
  if [ ! -f "$BASE/guisettings.xml" ]; then
    cat > "$BASE/guisettings.xml" <<'EOF'
<settings version="2">
  <section id="system">
    <category id="locale">
      <group id="1">
        <setting id="locale.language">resource.language.fr_fr</setting>
        <setting id="locale.country">France</setting>
        <setting id="locale.charset">DEFAULT</setting>
      </group>
    </category>
  </section>
</settings>
EOF
  fi
}

if [ -n "${DEV_USER:-}" ] && [ -d "/home/$DEV_USER" ]; then
  seed_kodi_fr "/home/$DEV_USER"
  chown -R "$DEV_USER:$DEV_USER" "/home/$DEV_USER/.kodi"
fi
mkdir -p /etc/skel/.kodi/userdata
if [ ! -f /etc/skel/.kodi/userdata/guisettings.xml ]; then
  BASE="/etc/skel/.kodi/userdata"
  cat > "$BASE/guisettings.xml" <<'EOF'
<settings version="2">
  <section id="system">
    <category id="locale">
      <group id="1">
        <setting id="locale.language">resource.language.fr_fr</setting>
        <setting id="locale.country">France</setting>
        <setting id="locale.charset">DEFAULT</setting>
      </group>
    </category>
  </section>
</settings>
EOF
fi

# 5. Raccourci Bureau LXDE (le .desktop système existe déjà via le paquet)
# On le copie vers le Bureau de l'utilisateur + skel pour futurs users.
if [ -f /usr/share/applications/kodi.desktop ]; then
  if [ -n "${DEV_USER:-}" ] && [ -d "/home/$DEV_USER" ]; then
    mkdir -p "/home/$DEV_USER/Bureau" "/home/$DEV_USER/Desktop"
    cp -f /usr/share/applications/kodi.desktop "/home/$DEV_USER/Bureau/kodi.desktop" || true
    cp -f /usr/share/applications/kodi.desktop "/home/$DEV_USER/Desktop/kodi.desktop" || true
    chmod +x "/home/$DEV_USER/Bureau/kodi.desktop" "/home/$DEV_USER/Desktop/kodi.desktop" || true
    chown "$DEV_USER:$DEV_USER" "/home/$DEV_USER/Bureau/kodi.desktop" "/home/$DEV_USER/Desktop/kodi.desktop" || true
  fi
  mkdir -p /etc/skel/Bureau /etc/skel/Desktop
  cp -f /usr/share/applications/kodi.desktop /etc/skel/Bureau/ || true
  cp -f /usr/share/applications/kodi.desktop /etc/skel/Desktop/ || true
  chmod +x /etc/skel/Bureau/kodi.desktop /etc/skel/Desktop/kodi.desktop || true
fi

echo "== Kodi OK : lance 'kodi' ou clique l'icône Bureau =="
echo "== Vérif : kodi --version + Interface > Regional > Language = French =="
echo "== Site officiel : https://kodi.tv/download =="
