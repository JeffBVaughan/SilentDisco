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
export DEBIAN_FRONTEND=noninteractive   # no debconf dialogs; the script sets doc_root itself
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

# Snapweb, the browser client. The upstream .deb bundles it under
# /usr/share/snapserver/snapweb; Debian's package ships only a placeholder
# page there, so fetch the real thing from the Snapweb releases.
snapweb_is_real() { [[ -f "$1/index.html" ]] && ! grep -qi "placeholder" "$1/index.html"; }
DOC_ROOT=""
if snapweb_is_real /usr/share/snapweb; then DOC_ROOT=/usr/share/snapweb
elif snapweb_is_real /usr/share/snapserver/snapweb; then DOC_ROOT=/usr/share/snapserver/snapweb
else
  echo "== snapweb (browser client)"
  apt-get install -y -qq unzip >/dev/null
  tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/badaix/snapweb/releases/latest | sed 's#.*/##')"
  ver="${tag#v}"
  tmp="$(mktemp -d)"
  if [[ -n "$ver" ]] && curl -fsSL -o "$tmp/snapweb.deb" \
      "https://github.com/badaix/snapweb/releases/download/${tag}/snapweb_${ver}-1_all.deb"; then
    apt-get install -y -qq "$tmp/snapweb.deb"
    DOC_ROOT=/usr/share/snapweb
  elif [[ -n "$ver" ]] && curl -fsSL -o "$tmp/snapweb.zip" \
      "https://github.com/badaix/snapweb/releases/download/${tag}/snapweb.zip"; then
    install -d /usr/share/snapserver/snapweb
    unzip -oq "$tmp/snapweb.zip" -d /usr/share/snapserver/snapweb
    DOC_ROOT=/usr/share/snapserver/snapweb
  else
    echo "!! could not download Snapweb (tag '${tag:-unknown}'). The browser client will"
    echo "   show a placeholder until it is installed; see server/README.md."
    DOC_ROOT=/usr/share/snapserver/snapweb
  fi
  rm -rf "$tmp"
  snapweb_is_real "$DOC_ROOT" && echo "   Snapweb ${ver} installed at $DOC_ROOT"
fi
SNAPWEB_DIR="$DOC_ROOT"

# The join page (web/party) is what the QR points at; Snapweb stays at /snapweb/
WWW=/var/lib/silentdisco/www
install -d "$WWW"
install -m 644 "$here/../../web/party/index.html" "$WWW/index.html"
install -d "$WWW/host"
install -m 644 "$here/../../web/host/index.html" "$WWW/host/index.html"
ln -sfn "$SNAPWEB_DIR" "$WWW/snapweb"
DOC_ROOT="$WWW"

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
sed -e "s#__DOC_ROOT__#$DOC_ROOT#" "$here/../config/snapserver.conf" > /etc/snapserver.conf
chmod 644 /etc/snapserver.conf
install -m 755 "$here/channel-loop.sh" /usr/local/bin/silentdisco-channel-loop
sed -e "s/__SNAP_USER__/$SNAP_USER/g" -e "s/__SNAP_GROUP__/$SNAP_GROUP/g" \
  "$here/../systemd/silentdisco-channel@.service" > /etc/systemd/system/silentdisco-channel@.service
chmod 644 /etc/systemd/system/silentdisco-channel@.service
systemctl daemon-reload
systemctl enable snapserver
systemctl restart snapserver   # restart, not just enable: the config may have changed
if [[ -f /etc/systemd/system/silentdisco-mpd@.service ]]; then
  # host/install.sh has taken over the channels with MPD; the ffmpeg loopers stay off
  for c in "${colours[@]}"; do systemctl disable --now "silentdisco-channel@$c" >/dev/null 2>&1 || true; done
  for c in "${colours[@]}"; do systemctl restart "silentdisco-mpd@$c" 2>/dev/null || true; done
else
  for c in "${colours[@]}"; do
    systemctl enable "silentdisco-channel@$c"
    systemctl restart "silentdisco-channel@$c"
  done
fi

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
echo "   Host page:   http://${ip}:1780/host/      (after host/install.sh)"
echo "   Snapweb:     http://${ip}:1780/snapweb/   (raw Snapcast panel)"
echo "   Music goes in: /var/lib/silentdisco/music/{yellow,red,green,blue}/"
echo "   Logs:        journalctl -fu snapserver"
[[ -f /etc/systemd/system/silentdisco-mpd@.service ]] && echo "   Channels:    MPD (host/install.sh)" || echo "   Channels:    ffmpeg loopers (run host/install.sh for MPD + the host page)"
echo "================================================================"
if [[ -n "${SUDO_USER:-}" ]]; then
  echo " Note: $SUDO_USER was added to the $SNAP_GROUP group. Log out and back in"
  echo "       (or run: newgrp $SNAP_GROUP) before copying music without sudo."
fi
echo
qrencode -t ANSIUTF8 "http://${ip}:1780/"
