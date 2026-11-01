# SilentDisco server (Raspberry Pi 3B + Snapcast)

One Pi, four colour channels, everyone's phone joins through a web page.
This is step one of the build. Pucks and the LED box come later and plug
into the same server.

```
  music/yellow/ ─┐                           ┌─ phone (browser)  ─ earbuds
  music/red/    ─┤  looper   ┌───────────┐   ├─ phone (browser)  ─ earbuds
  music/green/  ─┼─ ffmpeg ─▶│ snapserver│──▶├─ Android Snapcast app
  music/blue/   ─┘   FIFOs   └───────────┘   └─ ESP32 puck (later) ─ wired
                      Raspberry Pi 3B, on Ethernet
```

Snapcast keeps every client within a few milliseconds of each other. Each
client picks one of the four streams; switching is instant.

## What you need

- Raspberry Pi 3B, a microSD card (8 GB+), its power supply.
- An Ethernet cable to your router. The 3B's Wi-Fi is 2.4 GHz only and
  shares an antenna with Bluetooth. On Wi-Fi it could not sustain raw PCM to
  even two listeners in testing (choppy audio, hundreds of retried packets),
  which is why the stream is Opus. Wired is boring and reliable, and it is the
  server: its link is shared by every listener.
- Some music files, sorted into four folders.

## 1. Flash the card

Raspberry Pi Imager, choose **Raspberry Pi OS Lite (64-bit)**. In the
settings gear before writing:

- hostname: `silentdisco`
- enable SSH, set a username and password
- Wi-Fi: optional, Ethernet is preferred

Boot it, then from your laptop:

```bash
ssh <user>@silentdisco.local
```

## 2. Install

```bash
sudo apt-get install -y git
git clone https://github.com/JeffBVaughan/SilentDisco.git
cd SilentDisco/server/scripts
sudo ./install.sh
```

The script installs ffmpeg and the Snapcast server package, fetches Snapweb
(the browser client) from its own release page if the server package only
shipped a placeholder, writes `/etc/snapserver.conf` with the four channels,
creates the music folders, starts the four looper services, and prints the
join URL plus a QR code.

Raspberry Pi OS Trixie already ships snapcast 0.31 in apt, so the pinned
release download failing is normal there. Debian's package does not include
Snapweb, which is why the script downloads it separately.

The script adds your login user to the snapserver group so you can drop music
in without sudo. That takes effect on your next login: log out and back in,
or run `newgrp _snapserver`, before copying files.

## 3. Add music

Each colour is a folder. Anything ffmpeg can read is fine (mp3, flac, m4a,
wav, ogg, opus). Loudness is normalised so switching channels doesn't blast
anyone.

```bash
scp ~/Music/party/*.mp3 <user>@silentdisco.local:/var/lib/silentdisco/music/yellow/
```

Or on the Pi itself, copy into:

```
/var/lib/silentdisco/music/yellow/
/var/lib/silentdisco/music/red/
/var/lib/silentdisco/music/green/
/var/lib/silentdisco/music/blue/
```

Each looper shuffles its folder and plays it on repeat. New files are picked
up on the next pass; to force it:

```bash
sudo systemctl restart silentdisco-channel@yellow
```

An empty folder plays silence so the channel still shows up.

## 4. Join from a phone

Open the URL the installer printed, `http://<pi-ip>:1780/`, or scan the QR.
`http://silentdisco.local:1780/` works on iPhones and Macs; Android is hit
and miss with `.local` names, so put the IP on the QR.

The page is the join page from `web/party/`: four colour tiles with a live
listener count on each. Tap a colour and it plays. Tap another to switch.
The volume slider is local to the phone. Screen off is fine on Android; on
iOS keep the tab open (the lock-screen player controls work).

Snapweb, the full control panel, is still there at
`http://<pi-ip>:1780/snapweb/` for the host: mute or move any listener,
set volumes, see everything connected.

Android users can also install the **Snapcast** app from the Play Store and
point it at the Pi; it is the most robust client for long sessions.

Reprint the QR any time:

```bash
~/SilentDisco/server/scripts/qr.sh            # terminal
~/SilentDisco/server/scripts/qr.sh join.png   # for printing
```

## 5. Test the sync

1. Put one short file with a sharp click or a metronome in the yellow
   folder (a 120 bpm click track from any drum app is ideal).
2. Join from two phones with wired earbuds, hold one earbud from each up to
   your ears. Clicks should land as one. Wired-to-wired should be within a
   few ms.
3. Swap one phone to Bluetooth earbuds. You will now hear a double click;
   that gap is the Bluetooth latency, usually 100 to 250 ms. This is
   expected and is why the pucks and the door basket use wired headphones.
4. Leave both playing for an hour. They should not drift.

## Operating it

```bash
# status
systemctl status snapserver 'silentdisco-channel@*'

# live logs
journalctl -fu snapserver -u 'silentdisco-channel@*'

# who is connected and on which stream (JSON-RPC)
curl -s http://localhost:1780/jsonrpc -d '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' | python3 -m json.tool
```

Changing the config: edit `/etc/snapserver.conf` (or the copy in this repo
and re-run `install.sh`), then `sudo systemctl restart snapserver`. The
loopers restart with it.

That JSON-RPC endpoint is what the puck's button and the LED box will use
later: `Client.SetStream`-style calls to hop a client between colours, and
`Server.GetStatus` to count listeners per colour.

## Your inventory and where it fits

From the photo:

- **Raspberry Pi 3B**: the server. Done.
- **Pi Zero W (v1)**: too slow to serve, but a perfectly good first
  *client*. With a $4 PCM5102A I2S DAC it becomes a Linux "puck" running
  `snapclient`, which is the quickest way to test wired sync before any
  ESP32 firmware exists. It has no headphone jack of its own.
- **Le Potato in the black case**: a spare server if the Pi is busy, or a
  second box for a second room. Ethernet only, no onboard Wi-Fi.
- **WeMos D1 mini32**: a real ESP32 (classic WROOM-32). This is the first
  puck prototype board; the Snapcast ESP32 client port targets exactly this
  chip. Add the PCM5102A, a button, and one ring and you have a puck on the
  bench.
- **WeMos D1 mini (ESP8266)** + **0.96" OLED** + **WS2812 rings**: the
  server box's face. Rings show the four colours with brightness or
  segment count tied to listener count from `Server.GetStatus`; the OLED
  shows the join URL and now-playing. Not for audio.
- **1000 mAh LiPo (053450)**: right size for a puck, roughly 6 to 8 hours.
  The D1 mini32 has no charger, so for a battery puck pair it with a TP4056
  module or move to a board with charging built in (XIAO ESP32-S3).
- **nRF8001 BLE breakout**: 2013-era Bluetooth LE, no audio capability.
  Leave it in the drawer.

Parts to order for the next step: a couple of PCM5102A DAC modules, a few
TP4056 USB-C charger modules, 3.5 mm jack breakouts, and tactile buttons.
All of it is a few dollars.

## Next steps after this works

1. `pucks/`: ESP32 firmware (Snapcast ESP32 client first, custom later),
   wiring, printed shell.
2. A host page: per-channel now playing, skip, queue, uploads, and an
   "everyone to one colour" button, with MPD under each channel.
3. Access-point mode so the box carries its own Wi-Fi to parks and cabins.
