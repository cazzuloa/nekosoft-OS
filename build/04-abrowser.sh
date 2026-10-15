#!/bin/bash
# NekoSoft - ABrowser FR + uBlock Origin force via policies.json
# Usage: sudo bash 04-abrowser.sh
set -eux

update-locale LANG=fr_FR.UTF-8 LANGUAGE=fr_FR:fr LC_ALL=fr_FR.UTF-8 || true
locale-gen fr_FR.UTF-8 || true

UBLOCK_URL="https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
UBLOCK_ID="uBlock0@raymondhill.net"

mkdir -p /usr/lib/abrowser/distribution /etc/firefox/policies
for D in /usr/lib/abrowser/distribution /etc/firefox/policies; do
cat > "$D/policies.json" <<EOF
{
  "policies": {
    "LanguagePacks": ["fr"],
    "RequestedLocales": ["fr"],
    "DisableTelemetry": true,
    "Extensions": {
      "Install": ["$UBLOCK_URL"]
    },
    "ExtensionSettings": {
      "$UBLOCK_ID": {
        "installation_mode": "force_installed",
        "install_url": "$UBLOCK_URL"
      }
    }
  }
}
EOF
done

mkdir -p /etc/skel/.mozilla
DEV_USER="${DEV_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"
if [ -d "/home/$DEV_USER/.mozilla" ]; then
  cp -a "/home/$DEV_USER/.mozilla/." /etc/skel/.mozilla/ || true
fi

echo "== ABrowser OK =="
