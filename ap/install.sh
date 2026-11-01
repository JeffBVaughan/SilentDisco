#!/usr/bin/env bash
# Install hotspot (access point) mode. Safe to re-run. Does NOT switch modes.
#   sudo ./install.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP_USER="$(systemctl show snapserver -p User --value 2>/dev/null || true)"
[[ -n "$SNAP_USER" ]] || { id _snapserver >/dev/null 2>&1 && SNAP_USER=_snapserver || SNAP_USER=snapserver; }
SNAP_GROUP="$(id -gn "$SNAP_USER")"

command -v nmcli >/dev/null || { echo "NetworkManager (nmcli) not found; this needs Raspberry Pi OS Bookworm or newer" >&2; exit 1; }

echo "== config"
install -d /etc/silentdisco
if [[ ! -f /etc/silentdisco/ap.conf ]]; then
  pass="$(tr -dc 'a-km-z2-9' </dev/urandom | head -c 8)"     # no l/1/0/o lookalikes
  cat > /etc/silentdisco/ap.conf <<CONF
# Hotspot settings. Change with: sudo silentdisco-ap set ssid|pass|band|channel VALUE
AP_SSID="SilentDisco"
AP_PASS="$pass"
AP_BAND=bg          # bg = 2.4 GHz (every Pi), a = 5 GHz (Pi 4/5)
AP_CHANNEL=6
AP_IP=10.42.0.1
AP_CAPTIVE=1        # hotspot DNS sends every name to the box
AP_AT_BOOT=off
CONF
  chmod 640 /etc/silentdisco/ap.conf; chgrp "$SNAP_GROUP" /etc/silentdisco/ap.conf
fi
. /etc/silentdisco/ap.conf
echo "PORTAL_JOIN=http://${AP_IP}:1780/" > /etc/silentdisco/portal.env

echo "== command"
install -m 755 "$here/silentdisco-ap" /usr/local/sbin/silentdisco-ap
# let the host service switch modes from the host page
cat > /etc/sudoers.d/silentdisco-ap <<SUDO
$SNAP_USER ALL=(root) NOPASSWD: /usr/local/sbin/silentdisco-ap
SUDO
chmod 440 /etc/sudoers.d/silentdisco-ap

echo "== portal"
install -d /usr/local/lib/silentdisco
install -m 755 "$here/portal.py" /usr/local/lib/silentdisco/portal.py
sed -e "s/__SNAP_USER__/$SNAP_USER/g" -e "s/__SNAP_GROUP__/$SNAP_GROUP/g" "$here/silentdisco-portal.service" > /etc/systemd/system/silentdisco-portal.service
systemctl daemon-reload
systemctl enable silentdisco-portal >/dev/null
systemctl restart silentdisco-portal

echo "== NetworkManager profile"
/usr/local/sbin/silentdisco-ap apply

echo
echo "================================================================"
echo " Hotspot ready (not switched on)."
echo "   Network:  $AP_SSID     password: $AP_PASS"
echo "   Box address in hotspot mode: http://${AP_IP}:1780/"
echo "   Switch:   sudo silentdisco-ap on | off | status"
echo "             or from the host page."
echo " Switching on drops the house Wi-Fi: reach the box via the hotspot or Ethernet."
echo "================================================================"
