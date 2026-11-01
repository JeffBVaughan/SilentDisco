#!/usr/bin/env bash
# Install MPD per channel and the host API. Safe to re-run.
#   sudo ./install.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
base=/var/lib/silentdisco
colours=(yellow red green blue)
names=(Yellow Red Green Blue)

SNAP_USER="$(systemctl show snapserver -p User --value 2>/dev/null || true)"
[[ -n "$SNAP_USER" ]] || { id _snapserver >/dev/null 2>&1 && SNAP_USER=_snapserver || SNAP_USER=snapserver; }
SNAP_GROUP="$(id -gn "$SNAP_USER")"

echo "== packages"
apt-get install -y -qq mpd >/dev/null
# the stock single MPD must not run; we run one per channel
systemctl disable --now mpd.service mpd.socket >/dev/null 2>&1 || true

echo "== the old ffmpeg loopers hand over to MPD"
for c in "${colours[@]}"; do systemctl disable --now "silentdisco-channel@$c" >/dev/null 2>&1 || true; done

echo "== mpd instances"
install -d /etc/silentdisco
for i in "${!colours[@]}"; do
  c="${colours[$i]}"; port=$((6601 + i))
  install -d -o "$SNAP_USER" -g "$SNAP_GROUP" "$base/mpd/$c/playlists" "$base/music/$c"
  sed -e "s#__BASE__#$base#g" -e "s#__COLOUR__#$c#g" -e "s#__PORT__#$port#g" \
    "$here/mpd.conf.template" > "/etc/silentdisco/mpd-$c.conf"
done
chmod -R g+w "$base/music"
# the FIFO must be owned by the mpd user; recreate ours if it exists with the wrong owner
install -d -o "$SNAP_USER" -g "$SNAP_GROUP" "$base/fifo"
for c in "${colours[@]}"; do
  f="$base/fifo/$c"
  [[ -p "$f" ]] || { rm -f "$f"; mkfifo -m 644 "$f"; }
  chown "$SNAP_USER:$SNAP_GROUP" "$f"
done
sed -e "s/__SNAP_USER__/$SNAP_USER/g" -e "s/__SNAP_GROUP__/$SNAP_GROUP/g" \
  "$here/silentdisco-mpd@.service" > /etc/systemd/system/silentdisco-mpd@.service

echo "== host api"
install -d /usr/local/lib/silentdisco
install -m 755 "$here/host.py" /usr/local/lib/silentdisco/host.py
sed -e "s/__SNAP_USER__/$SNAP_USER/g" -e "s/__SNAP_GROUP__/$SNAP_GROUP/g" \
  "$here/silentdisco-host.service" > /etc/systemd/system/silentdisco-host.service
if [[ ! -f /etc/default/silentdisco-host ]]; then
  pin="$(shuf -i 1000-9999 -n 1)"
  cat > /etc/default/silentdisco-host <<ENV
# Host page PIN. Change it any time, then: sudo systemctl restart silentdisco-host
HOST_PIN=$pin
#HOST_PORT=1790
#HOST_CHANNELS=Yellow,Red,Green,Blue
ENV
  chmod 640 /etc/default/silentdisco-host; chgrp "$SNAP_GROUP" /etc/default/silentdisco-host
fi
# the host page itself is served by snapserver next to the join page
www=$base/www
if [[ -d $www ]]; then
  install -d "$www/host"
  install -m 644 "$here/../web/host/index.html" "$www/host/index.html"
fi

systemctl daemon-reload
for c in "${colours[@]}"; do systemctl enable "silentdisco-mpd@$c" >/dev/null; systemctl restart "silentdisco-mpd@$c"; done
systemctl enable silentdisco-host >/dev/null
systemctl restart silentdisco-host
sleep 1
systemctl restart snapserver

pin="$(grep -E '^HOST_PIN=' /etc/default/silentdisco-host | cut -d= -f2)"
ip="$(hostname -I | awk '{print $1}')"
echo
echo "================================================================"
echo " Host controls:  http://${ip}:1780/host/     PIN: ${pin}"
echo " Each colour now runs on MPD. Existing music folders were picked up."
echo " Logs: journalctl -fu silentdisco-host -u 'silentdisco-mpd@*'"
echo "================================================================"
