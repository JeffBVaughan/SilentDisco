#!/usr/bin/env bash
# Print the join QR code in the terminal, or save it as PNG for printing:
#   ./qr.sh            -> terminal
#   ./qr.sh join.png   -> PNG file
ip="$(hostname -I | awk '{print $1}')"
url="http://${ip}:1780/"
if [[ -n "${1:-}" ]]; then
  qrencode -s 12 -m 2 -o "$1" "$url" && echo "wrote $1 for $url"
else
  echo "$url"; qrencode -t ANSIUTF8 "$url"
fi
