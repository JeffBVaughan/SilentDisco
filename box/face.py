#!/usr/bin/env python3
"""SilentDisco face: the LED ring and OLED on the front of the server box.

Polls Snapcast's JSON-RPC every second, counts connected listeners per colour
channel, lights one quadrant of a 16-pixel WS2812 ring per channel (one bright
pixel per listener, the rest a dim glow in the channel colour), and shows the
join QR code plus listener counts on a 128x64 SSD1306 OLED.

Hardware is optional: if the ring or OLED library is missing or the device is
absent, that part is skipped and the rest keeps running. --dry-run prints the
state to the terminal instead of touching any hardware.
"""
import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request

# ---------------------------------------------------------------- settings
SNAP_RPC   = os.environ.get("FACE_SNAP_RPC", "http://127.0.0.1:1780/jsonrpc")
JOIN_PORT  = int(os.environ.get("FACE_JOIN_PORT", "1780"))
POLL_S     = float(os.environ.get("FACE_POLL_S", "1.0"))
LED_PIN    = int(os.environ.get("FACE_LED_PIN", "18"))     # PWM0, header pin 12
LED_COUNT  = int(os.environ.get("FACE_LED_COUNT", "16"))
LED_BRIGHT = int(os.environ.get("FACE_LED_BRIGHT", "96"))  # 0..255, keeps the 5 V rail happy
LED_OFFSET = int(os.environ.get("FACE_LED_OFFSET", "0"))   # rotate so Yellow sits top-right
OLED_ADDR  = int(os.environ.get("FACE_OLED_ADDR", "0x3C"), 16)

# channel name (as in snapserver.conf) -> colour, in the order they go round the ring
CHANNELS = [
    ("Yellow", (255, 190, 0)),
    ("Red",    (255, 30, 40)),
    ("Green",  (30, 220, 90)),
    ("Blue",   (40, 130, 255)),
]
DIM = 0.08          # idle glow as a fraction of full colour
PIXELS_PER_CH = LED_COUNT // len(CHANNELS)


# ---------------------------------------------------------------- snapcast
def snap_status():
    """Return {channel_name: listener_count} from Server.GetStatus."""
    req = json.dumps({"id": 1, "jsonrpc": "2.0", "method": "Server.GetStatus"}).encode()
    with urllib.request.urlopen(urllib.request.Request(
            SNAP_RPC, data=req, headers={"Content-Type": "application/json"}), timeout=2) as r:
        server = json.load(r)["result"]["server"]
    # the ?name= from snapserver.conf lives in uri.query.name; the id matches it for pipes
    stream_name = {s["id"]: s.get("uri", {}).get("query", {}).get("name") or s["id"]
                   for s in server["streams"]}
    counts = {name: 0 for name, _ in CHANNELS}
    for g in server["groups"]:
        name = stream_name.get(g["stream_id"], g["stream_id"])
        n = sum(1 for c in g["clients"] if c.get("connected"))
        if name in counts:
            counts[name] += n
    return counts


def join_url():
    try:
        ip = subprocess.check_output(["hostname", "-I"], text=True).split()[0]
    except Exception:
        ip = socket.gethostbyname(socket.gethostname())
    return f"http://{ip}:{JOIN_PORT}/"


# ---------------------------------------------------------------- ring
class Ring:
    def __init__(self):
        from rpi_ws281x import PixelStrip, Color
        self.Color = Color
        self.strip = PixelStrip(LED_COUNT, LED_PIN, brightness=LED_BRIGHT)
        self.strip.begin()

    def show(self, counts, t):
        for ci, (name, rgb) in enumerate(CHANNELS):
            n = counts.get(name, 0)
            for p in range(PIXELS_PER_CH):
                idx = (ci * PIXELS_PER_CH + p + LED_OFFSET) % LED_COUNT
                if p < min(n, PIXELS_PER_CH):
                    k = 1.0
                    if n > PIXELS_PER_CH:          # full quadrant: slow pulse means "and more"
                        k = 0.6 + 0.4 * (0.5 + 0.5 * __import__("math").sin(t * 2.0))
                else:
                    k = DIM
                self.strip.setPixelColor(idx, self.Color(int(rgb[0]*k), int(rgb[1]*k), int(rgb[2]*k)))
        self.strip.show()

    def off(self):
        for i in range(LED_COUNT):
            self.strip.setPixelColor(i, self.Color(0, 0, 0))
        self.strip.show()


# ---------------------------------------------------------------- oled
def load_fonts():
    """Small TrueType fonts if DejaVu is around, else Pillow's bitmap default."""
    from PIL import ImageFont
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, 9), ImageFont.truetype(path, 9)
    f = ImageFont.load_default()
    return f, f


def make_qr(url):
    import qrcode
    for box in (2, 1):
        q = qrcode.QRCode(border=1, box_size=box, error_correction=qrcode.constants.ERROR_CORRECT_L)
        q.add_data(url)
        q.make(fit=True)
        img = q.make_image(fill_color="white", back_color="black").convert("1")
        if img.height <= 64:
            return img
    return img


def draw_frame(d, counts, url, qr, fonts):
    """Draw one 128x64 frame onto an ImageDraw. Shared by the device and the dry run."""
    big, small = fonts
    d.bitmap((0, (64 - qr.height) // 2), qr, fill="white")
    x = qr.width + 2
    d.text((x, 0), "SILENT DISCO", font=big, fill="white")
    host = url.replace("http://", "").rstrip("/")
    ip, _, port = host.partition(":")
    d.text((x, 12), ip, font=small, fill="white")
    d.text((x, 22), f"port {port}", font=small, fill="white")
    c = lambda n: counts.get(n, 0)
    d.text((x, 34), f"Y{c('Yellow'):>2}  R{c('Red'):>2}", font=small, fill="white")
    d.text((x, 44), f"G{c('Green'):>2}  B{c('Blue'):>2}", font=small, fill="white")
    d.text((x, 54), f"{sum(counts.values())} listening", font=small, fill="white")


class Oled:
    def __init__(self):
        from luma.core.interface.serial import i2c
        from luma.oled.device import ssd1306
        self.dev = ssd1306(i2c(port=1, address=OLED_ADDR), width=128, height=64)
        self.fonts = load_fonts()
        self.qr = None
        self.qr_url = None

    def show(self, counts, url):
        from luma.core.render import canvas
        if url != self.qr_url:
            self.qr, self.qr_url = make_qr(url), url
        with canvas(self.dev) as d:
            draw_frame(d, counts, url, self.qr, self.fonts)

    def off(self):
        self.dev.clear()


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print state, touch no hardware")
    ap.add_argument("--frame", metavar="PNG", help="with --dry-run: also write the OLED frame to this PNG")
    args = ap.parse_args()

    ring = oled = None
    if not args.dry_run:
        try:
            ring = Ring()
        except Exception as e:
            print(f"ring disabled: {e}", file=sys.stderr)
        try:
            oled = Oled()
        except Exception as e:
            print(f"oled disabled: {e}", file=sys.stderr)

    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    url = join_url()
    last_url_check = time.monotonic()
    counts = {name: 0 for name, _ in CHANNELS}
    while running:
        t = time.monotonic()
        try:
            counts = snap_status()
        except Exception as e:
            print(f"snapserver unreachable: {e}", file=sys.stderr)
        if t - last_url_check > 30:              # DHCP can move us
            url, last_url_check = join_url(), t
        if args.dry_run and args.frame:
            try:
                from PIL import Image, ImageDraw
                img = Image.new("1", (128, 64))
                draw_frame(ImageDraw.Draw(img), counts, url, make_qr(url), load_fonts())
                img.resize((512, 256)).save(args.frame)
            except Exception as e:
                print(f"frame: {e}", file=sys.stderr)
        if args.dry_run:
            bar = "  ".join(f"{n[0]}:{'#' * min(counts[n], PIXELS_PER_CH)}{'.' * (PIXELS_PER_CH - min(counts[n], PIXELS_PER_CH))}"
                            for n, _ in CHANNELS)
            print(f"\r{url}  {bar}  ", end="", flush=True)
        if ring:
            try: ring.show(counts, t)
            except Exception as e: print(f"ring: {e}", file=sys.stderr)
        if oled:
            try: oled.show(counts, url)
            except Exception as e: print(f"oled: {e}", file=sys.stderr)
        time.sleep(POLL_S if not (ring and any(v > PIXELS_PER_CH for v in counts.values())) else 0.1)

    if ring: ring.off()
    if oled: oled.off()


if __name__ == "__main__":
    main()
