# Puck parts list

A puck is a wired-headphone Snapcast client: ESP32 + I2S DAC + battery, one
button to cycle colours, one LED showing the colour, in a printed shell.
Wired only; see the discovery doc for why Bluetooth out was dropped.

## Bench prototype (parts on hand, order one thing)

| Part | Have? | Notes |
|---|---|---|
| WeMos D1 mini32 (classic ESP32) | yes | The Snapcast ESP32 client port targets this chip |
| PCM5102A I2S DAC module | **order** | The purple "GY-PCM5102" board with a 3.5 mm jack on it, about $4 |
| WS2812 ring (8 LED) | yes | Channel colour; powered from 5V/BAT, data from a GPIO |
| Tactile button | yes / cheap | Channel cycle |
| Breadboard + jumper wires | yes | |
| Wired earbuds | yes | Anything with a 3.5 mm plug |

USB power for the bench. No battery needed to prove sync and the LED.

## Per-puck build (x10)

| # | Part | Qty/puck | Approx. unit | Why this one |
|---|---|---|---|---|
| 1 | Seeed XIAO ESP32-S3 | 1 | $7.50 | Tiny, USB-C, LiPo charger on board, battery pads on the back |
| 2 | PCM5102A DAC module | 1 | $4 | Line-level out drives earbuds directly. Its on-board jack is not used; the version without a jack is fine |
| 2b | Panel-mount 3.5 mm stereo jack, M6 thread | 1 | $0.60 | Mounts in the shell wall, wired to the DAC's L/R/GND pads. Cable yanks pull on the shell, not the PCB |
| 3 | 3.7 V 1000 mAh LiPo, JST-PH 2.0 lead | 1 | $5 | 6 to 8 h; the 053450 cell you have is this size |
| 4 | WS2812 16-pixel ring (44.5 mm OD) | 1 | $4 | The Halo shell is built around this ring; you have one for the first puck |
| 5 | 12 × 12 × 7.3 mm tactile switch | 1 | $0.30 | Under the printed Ø 28 cap |
| 6 | 6 mm tactile button | 1 | $0.10 | Volume (optional, hold = volume up/down cycle) |
| 7 | Slide switch SS12D00, 3-pin | 1 | $0.20 | Hard power off between the battery and the board |
| 8 | 10 kΩ resistor | 1 | | Pull-up on the button if not using the internal one |
| 9 | 300 Ω resistor | 1 | | In series with the LED data line |
| 10 | 100 µF capacitor | 1 | | Across the LED supply, standard WS2812 practice |
| 11 | M3 heat-set inserts (M3×4×5 mm) + M3 screws you already have | 4 | $0.20 | Shell lid |
| 12 | Hook-up wire 28 AWG silicone, heat shrink | | | |
| 13 | Printed shell, two parts, translucent cap | 1 | filament | Clear PETG or white PLA for the cap, anything for the body |

Roughly **$20 to $22 per puck**, about **$200 for ten** including spares.

### Fallback board

If the Snapcast ESP32 client turns out not to support the S3 well, use a
**Lolin32 Lite** (classic ESP32 with an onboard LiPo charger, about $5).
Same wiring, slightly bigger, micro-USB instead of USB-C. Decide after the
bench prototype.

## Kit-level parts (buy once)

| Part | Qty | Approx. | Notes |
|---|---|---|---|
| 6-port USB-C charger, 2 A per port | 1 to 2 | $20 | The charging rail; print a tray that lines ten pucks up |
| Short USB-C cables (15 to 20 cm) | 10 | $1 each | |
| Bulk wired earbuds, individually wrapped | 20 to 30 | $1 to $2 each | The door basket; wrapped ones feel less gross to share |
| 3.5 mm headphone splitters | a few | $2 | Two people, one puck, same song |
| Small label stickers or a printed number on the cap | 10 | | So you know which puck is which in the server status |

## DAC module jumpers

The PCM5102A module has four solder jumpers on the back. For I2S from an
ESP32 the usual setting is **1 (FLT) L, 2 (DEMP) L, 3 (XSMT) H, 4 (FMT) L**,
and the module's SCK pin tied to GND so the chip uses its internal clock.
Check against the Snapcast ESP32 client's wiring notes before soldering;
some batches ship with the bridges already made.

## Wiring (XIAO ESP32-S3, to be confirmed on the bench)

```
PCM5102A        XIAO ESP32-S3
  VIN  ───────── 3V3
  GND  ───────── GND
  SCK  ───────── GND
  BCK  ───────── D8  (I2S bit clock)
  LCK  ───────── D9  (I2S word select)
  DIN  ───────── D10 (I2S data)

WS2812B
  VDD  ───────── BAT+ (or 5V on USB)
  GND  ───────── GND
  DIN  ──300Ω─── D7

Buttons (to GND, internal pull-up)
  channel ────── D1
  volume  ────── D2

Battery
  LiPo + ── slide switch ── XIAO BAT+ pad
  LiPo − ─────────────────── XIAO BAT− pad
```

Pin numbers are placeholders until the firmware's pin config is settled;
any free GPIOs work for I2S on the S3.

## Server box extras

- 4 × M2 × 6 screws for the OLED module.
- Optional 4 × M2.5 × 6 if you prefer screws to pegs for the Pi.
- 2 × M3 heat-set inserts and 2 × M3 × 8 for the lid.
- One Ø 47 mm clear PETG window, printed.

## Not needed

- Amplifier. The DAC's line output is enough for earbuds and most
  headphones. Big studio cans will be a bit quiet; that's fine for a party.
- Level shifter for the LED. With VDD at battery voltage (3.7 to 4.2 V) a
  3.3 V data signal is reliable in practice.
- Bluetooth anything.
