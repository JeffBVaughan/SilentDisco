# Hotspot mode: the box is the Wi-Fi

For anywhere without a network you control: a backyard, a park, a church
hall, a cabin. The Pi stops being a Wi-Fi client and becomes an access
point named **SilentDisco**. Phones join it, get an address from it, and the
join page is at `http://10.42.0.1:1780/`. No router, no internet needed.

## Install

```bash
cd ~/SilentDisco/ap && sudo ./install.sh
```

Creates the hotspot profile in NetworkManager, prints the generated
password, installs the `silentdisco-ap` command and the portal service.
It does **not** switch modes.

## Switching

From the host page: the Wi-Fi bar under the "Everyone to" row shows the
current mode and has a switch button, plus a "hotspot at boot" checkbox.

From the Pi:

```bash
sudo silentdisco-ap on        # become the hotspot
sudo silentdisco-ap off       # back to the saved home Wi-Fi
sudo silentdisco-ap status
sudo silentdisco-ap boot on   # come up as a hotspot after a reboot
sudo silentdisco-ap set pass partytime   # also: ssid, band (bg|a), channel
```

Switching to hotspot drops the house Wi-Fi on `wlan0`. To reach the box
again, join the SilentDisco network and open `http://10.42.0.1:1780/host/`.
Ethernet is untouched: with a cable in, the box stays on the LAN in both
modes, which is the comfortable way to run it at home.

## What guests see

- The OLED alternates every six seconds between a Wi-Fi QR (scan it and
  the phone offers to join the network, no typing) and the join-page QR.
- The hotspot's DNS answers every name with the box's address, and a small
  server on port 80 answers the "is there internet?" probes phones make so
  they stay on the Wi-Fi rather than quietly switching to mobile data.
  Anything else typed into a browser lands on the join page.
- Phones may still show "no internet" on the network; that's expected.

## Capacity

| Box | Hotspot radio | Comfortable listeners on Opus |
|---|---|---|
| Pi 3B | 2.4 GHz only | 10 to 15 |
| Pi 4 / 5 | 2.4 or 5 GHz (`set band a`) | 25 to 30 |
| Any Pi + a real access point on Ethernet | | the access point's limit, 50+ |

The server itself is nowhere near its limit at these numbers; the radio is.

## Files

| File | Purpose |
|---|---|
| `silentdisco-ap` | the command; installed to `/usr/local/sbin` |
| `/etc/silentdisco/ap.conf` | ssid, password, band, channel, address, boot setting |
| `portal.py` + `silentdisco-portal.service` | port 80 probe answers and redirect |
| `/etc/NetworkManager/dnsmasq-shared.d/silentdisco.conf` | hotspot DNS catch-all |
| `/etc/sudoers.d/silentdisco-ap` | lets the host service run the command |
