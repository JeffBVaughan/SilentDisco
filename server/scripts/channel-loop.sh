#!/usr/bin/env bash
# Feed one colour channel's FIFO forever from a folder of audio files.
#
# Usage: channel-loop.sh <colour>
#   Reads  /var/lib/silentdisco/music/<colour>/   (mp3, flac, m4a, wav, ogg, opus)
#   Writes /var/lib/silentdisco/fifo/<colour>     (48 kHz 16-bit stereo PCM)
#
# Files are shuffled once per pass and the pass repeats until stopped.
# Drop new files in the folder and they are picked up on the next pass.
# A folder with no audio files plays silence so the channel still exists.

set -euo pipefail

colour="${1:?usage: channel-loop.sh <colour>}"
base="/var/lib/silentdisco"
music="$base/music/$colour"
fifo="$base/fifo/$colour"
playlist="$(mktemp -t "silentdisco-$colour.XXXXXX")"
trap 'rm -f "$playlist"' EXIT

mkdir -p "$music"

# snapserver creates the FIFO (mode=create). Wait for it rather than racing.
for _ in $(seq 1 60); do
  [[ -p "$fifo" ]] && break
  sleep 1
done
[[ -p "$fifo" ]] || { echo "FIFO $fifo never appeared; is snapserver running?" >&2; exit 1; }

while true; do
  # Build a shuffled concat playlist. Single quotes in filenames are escaped
  # the way ffmpeg's concat demuxer wants them.
  find "$music" -maxdepth 1 -type f \
    \( -iname '*.mp3' -o -iname '*.flac' -o -iname '*.m4a' -o -iname '*.wav' \
       -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.aac' \) -print0 \
    | shuf -z \
    | while IFS= read -r -d '' f; do
        printf "file '%s'\n" "${f//\'/\'\\\'\'}"
      done > "$playlist"

  if [[ ! -s "$playlist" ]]; then
    echo "No audio in $music, playing 30 s of silence" >&2
    ffmpeg -hide_banner -loglevel error -nostdin \
      -f lavfi -i anullsrc=r=48000:cl=stereo -t 30 \
      -f s16le -ar 48000 -ac 2 pipe:1 > "$fifo" || true
    continue
  fi

  # ffmpeg blocks when the FIFO is full, so snapserver sets the pace and
  # no -re flag is needed. Loudness is normalised so channels match.
  ffmpeg -hide_banner -loglevel error -nostdin \
    -f concat -safe 0 -i "$playlist" \
    -af loudnorm=I=-16:TP=-1.5:LRA=11 \
    -f s16le -ar 48000 -ac 2 pipe:1 > "$fifo" || true
done
