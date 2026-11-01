# SilentDisco

A bring-your-own-headphones silent disco for house parties. One Raspberry Pi
serves four colour channels (four different songs at once); guests join from
their phone's browser, or with a small printed ESP32 "puck" with a colour LED
and a channel button for anyone with wired headphones.

- [server/](server/README.md): Raspberry Pi + Snapcast setup. **Start here.**
- [web/](web/README.md): the join page guests see.
- [host/](host/README.md): MPD per channel and the host's controls page.
- [box/](box/README.md): LED ring + OLED face for the server box, wiring and service.
- [hardware/](hardware/README.md): OpenSCAD models for the Halo puck and Dial box.
- [pucks/PARTS.md](pucks/PARTS.md): parts list.
- [docs/DISCOVERY.md](docs/DISCOVERY.md): the wider product and hardware
  discovery, including the bigger-event and Auracast options.

Planned: `pucks/firmware/` (ESP32 Snapcast client for the XIAO).
