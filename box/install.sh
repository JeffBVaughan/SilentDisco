#!/usr/bin/env bash
# Install the SilentDisco face service on the Pi. Safe to re-run.
#   sudo ./install.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
venv=/opt/silentdisco-face

echo "== packages"
apt-get install -y -qq python3-venv python3-dev python3-pil libfreetype6-dev libjpeg-dev libopenjp2-7 i2c-tools gcc fonts-dejavu-core >/dev/null

echo "== python venv at $venv"
[[ -d $venv ]] || python3 -m venv --system-site-packages "$venv"
"$venv/bin/pip" install -q --upgrade pip
"$venv/bin/pip" install -q rpi_ws281x "luma.oled" qrcode
install -m 755 "$here/face.py" "$venv/face.py"

echo "== I2C on, onboard analog audio off (it shares the PWM the ring uses)"
cfg=/boot/firmware/config.txt
[[ -f $cfg ]] || cfg=/boot/config.txt
grep -q '^dtparam=i2c_arm=on' "$cfg" || echo 'dtparam=i2c_arm=on' >> "$cfg"
sed -i 's/^dtparam=audio=on/dtparam=audio=off/' "$cfg"
grep -q '^dtparam=audio=off' "$cfg" || echo 'dtparam=audio=off' >> "$cfg"
modprobe i2c-dev 2>/dev/null || true

echo "== service"
install -m 644 "$here/silentdisco-face.service" /etc/systemd/system/
[[ -f /etc/default/silentdisco-face ]] || cat > /etc/default/silentdisco-face <<'ENV'
# Settings for face.py. Uncomment to override.
#FACE_LED_PIN=18
#FACE_LED_COUNT=16
#FACE_LED_BRIGHT=96
#FACE_LED_OFFSET=0
#FACE_OLED_ADDR=0x3C
ENV
systemctl daemon-reload
systemctl enable silentdisco-face
systemctl restart silentdisco-face

echo
echo "Face service running. Watch it:   journalctl -fu silentdisco-face"
echo "I2C devices (OLED should be 3c):  i2cdetect -y 1"
if grep -q '^dtparam=audio=off' "$cfg" && lsmod | grep -q snd_bcm2835; then
  echo "Reboot once so the onboard audio driver lets go of the PWM: sudo reboot"
fi
