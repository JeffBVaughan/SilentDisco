#!/usr/bin/env bash
# One-shot installer for the SilentDisco server on Raspberry Pi OS (Bookworm
# or newer, 64-bit Lite recommended). Safe to re-run.
#
#   sudo ./install.sh
#
# What it does:
#   1. Installs ffmpeg, qrencode and the official snapserver .deb (with Snapweb).
#   2. Installs /etc/snapserver.conf with the four colour channels.
#   3. Creates /var/lib/silentdisco/{music,fifo}/<colour>.
#   4. Installs and enables the looper services.
#   5. Prints the join URL and a QR code for it.

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
colours=(yellow red green blue)

# Pin a known-good Snapcast release. Newer releases are at
# https://github.com/badaix/snapcast/releases ; bump this when you upgrade.
SNAPCAST_VERSION="${SNAPCAST_VERSION:-0.31.0}"

echo "== packages"
apt-get update -qq
apt-get install -y -qq ffmpeg qrencode curl avahi-daemon

arch="$(dpkg --print-architecture)"        # arm64 on 64-bit Pi OS, armhf on 32-bit
codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
deb="snapserver_${SNAPCAST_VERSION}-1_${arch}_${codename}.deb"
if ! dpkg -s snapserver 2>/dev/null | grep -q "Version: ${SNAPCAST_VERSION}"; then
  echo "== snapserver ${SNAPCAST_VERSION} (${deb})"
  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/$deb" \
      "https://github.com/badaix/snapcast/releases/download/v${SNAPCAST_VERSION}/${deb}"; then
    apt-get install -y -qq "$tmp/$deb"
  else
    echo "   release .deb not found for ${arch}/${codename}; falling back to apt's snapserver"
    apt-get install -y -qq snapserver
  fi
  rm -rf "$tmp"
fi

if [[ ! -d /usr/share/snapserver/snapweb ]]; then
  echo "!! Snapweb not found at /usr/share/snapserver/snapweb."
  echo "   The browser client will not work until it is installed; see server/README.md."
fi

# The service user differs by package: upstream .deb uses "snapserver",
# Debian/Raspberry Pi OS use "_snapserver". Ask systemd, then fall back.
SNAP_USER="$(systemctl show snapserver -p User --value 2>/dev/null || true)"
if [[ -z "$SNAP_USER" ]]; then
  if id _snapserver >/dev/null 2>&1; then SNAP_USER=_snapserver; else SNAP_USER=snapserver; fi
fi
if ! id "$SNAP_USER" >/dev/null 2>&1; then
  echo "!! cannot find the snapserver service user (tried '$SNAP_USER')" >&2; exit 1
fi
SNAP_GROUP="$(id -gn "$SNAP_USER")"
echo "== snapserver runs as $SNAP_USER:$SNAP_GROUP"

echo "== directories"
for c in "${colours[@]}"; do
  install -d -o "$SNAP_USER" -g "$SNAP_GROUP" /var/lib/silentdisco/music/"$c"
done
install -d -o "$SNAP_USER" -g "$SNAP_GROUP" /var/lib/silentdisco/fifo
# Let the login user drop music in without sudo.
if [[ -n "${SUDO_USER:-}" ]] && id -u "$SUDO_USER" >/dev/null 2>&1; then
  usermod -aG "$SNAP_GROUP" "$SUDO_USER"
  chmod -R g+w /var/lib/silentdisco/music
fi

echo "== config and services"
install -m 644 "$here/../config/snapserver.conf" /etc/snapserver.conf
install -m 755 "$here/channel-loop.sh" /usr/local/bin/silentdisco-channel-loop
sed -e "s/__SNAP_USER__/$SNAP_USER/g" -e "s/__SNAP_GROUP__/$SNAP_GROUP/g" \
  "$here/../systemd/silentdisco-channel@.service" > /etc/systemd/system/silentdisco-channel@.service
chmod 644 /etc/systemd/system/silentdisco-channel@.service
systemctl daemon-reload
systemctl enable --now snapserver
for c in "${colours[@]}"; do
  systemctl enable --now "silentdisco-channel@$c"
done

echo "== hostname"
if [[ "$(hostname)" != "silentdisco" ]]; then
  hostnamectl set-hostname silentdisco
  sed -i 's/127\.0\.1\.1.*/127.0.1.1\tsilentdisco/' /etc/hosts
fi

ip="$(hostname -I | awk '{print $1}')"
echo
echo "================================================================"
echo " SilentDisco server is up."
echo "   Join page:   http://${ip}:1780/   (or http://silentdisco.local:1780/)"
echo "   Music goes in: /var/lib/silentdisco/music/{yellow,red,green,blue}/"
echo "   Logs:        journalctl -fu snapserver -u 'silentdisco-channel@*'"
echo "================================================================"
echo
qrencode -t ANSIUTF8 "http://${ip}:1780/"
