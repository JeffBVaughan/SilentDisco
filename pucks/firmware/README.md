# Puck firmware

A Snapcast client for the Seeed XIAO ESP32-S3 with a PCM5102A DAC: joins
the Wi-Fi, finds the box by mDNS, plays the chosen colour through wired
headphones in sync with every phone, and switches colour with one button.
The host page sees it as `puck-01`, `puck-02`, …

Built on Phil Schatzmann's [arduino-snapclient](https://github.com/pschatzmann/arduino-snapclient)
and [arduino-audio-tools](https://github.com/pschatzmann/arduino-audio-tools),
with [arduino-libopus](https://github.com/pschatzmann/arduino-libopus) for
the Opus stream the box sends.

## Build and flash (once per PC)

1. Install [VS Code](https://code.visualstudio.com/) and the **PlatformIO IDE**
   extension. First build downloads the ESP32 toolchain, a few hundred MB.
2. Open the folder `pucks/firmware` in VS Code ("Open Folder").
3. Copy `include/config.h.example` to `include/config.h`. Put your Wi-Fi
   networks in it, the hotspot first if you use it, and set `PUCK_NUMBER`.
4. Plug the XIAO in over USB-C. Click the PlatformIO **Upload** arrow in the
   status bar (or `pio run -t upload` in the PlatformIO terminal).
   If the upload can't find the board, hold the XIAO's **B** button while
   pressing **R**, release, then upload again.
5. Click **Monitor** (`pio device monitor`) to watch it join and find the box.

Each further puck: change `PUCK_NUMBER`, upload.

## Bench wiring

XIAO ESP32-S3 pins are GPIO numbers; the silkscreen labels are in brackets.

| PCM5102A | XIAO |
|---|---|
| VIN | 5V (bench, on USB) or BAT+ (in the puck) |
| GND | GND |
| SCK | GND |
| BCK | GPIO 7 (D8) |
| LCK | GPIO 8 (D9) |
| DIN | GPIO 9 (D10) |

| Other | XIAO |
|---|---|
| Channel button | GPIO 2 (D1) to GND |
| Volume button (optional) | GPIO 3 (D2) to GND |
| WS2812 data, via 300 Ω | GPIO 4 (D3) |
| WS2812 power | 5V and GND |

PCM5102A solder bridges on the back: **1 L, 2 L, 3 H, 4 L**. Plug wired
earbuds into the module's own jack for the bench.

## What it does

- Tries the Wi-Fi networks in `config.h` in order, LED blinks blue meanwhile.
- Finds the Snapcast server by mDNS, falls back to `SERVER_FALLBACK_IP`.
  Red blink means no server.
- Plays. LED shows the channel colour, dim. Short press the button: next
  colour, LED flashes bright. Hold 1.5 s: volume steps 100 → 65 → 40 %.
- Remembers its last colour and volume across power cycles.
- Follows the host page: "Everyone to Red" moves pucks too, and the LED
  updates within three seconds.
- The box's per-client volume and mute (Snapweb, host page) apply as well.

## Layout of the code

- `platformio.ini`: board, partitions, libraries, build flags.
- `src/main.cpp`: the Arduino loop runs only the Snapcast client on core 1;
  a control task on core 0 does Wi-Fi watching, the button, the LED and
  the JSON-RPC calls that switch channels. The two never block each other.
- `include/config.h`: your networks, puck number and pins (git-ignored).

## Tuning if the audio is wrong

- Stutter: raise `cfg.buffer_count` in `main.cpp` (8 → 16), or lower the
  LED count while testing.
- Early or late versus phones: the library's `CONFIG_PROCESSING_TIME_MS`
  (default -172) is the DAC-path latency estimate; add
  `-DCONFIG_PROCESSING_TIME_MS=-150` to `build_flags` and bisect by ear
  against a phone on wired earbuds.
- No sound at all: check the solder bridges, and that SCK is tied to GND.
- Build errors inside the audio library about I2S drivers: PlatformIO's
  stock ESP32 platform is on the older Arduino core. Swap the `platform`
  line in `platformio.ini` for the community one that tracks the current
  core:
  `platform = https://github.com/pioarduino/platform-espressif32/releases/download/stable/platform-espressif32.zip`

## Not yet

- Battery level reporting (the XIAO has no divider on BAT; a 2-resistor
  divider into GPIO 1 is the plan).
- Over-the-air updates. Flash over USB for now.
