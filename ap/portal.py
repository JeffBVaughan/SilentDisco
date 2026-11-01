#!/usr/bin/env python3
"""Tiny port-80 server for hotspot mode.

Phones probe for internet when they join a network. We answer those probes as
the real sites would, so phones stay on the box's Wi-Fi instead of falling
back to mobile data, and we redirect everything else to the join page. With
hotspot DNS pointing every name at the box, typing any http address into a
browser lands on the join page.
"""
import os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

JOIN = os.environ.get("PORTAL_JOIN", "http://10.42.0.1:1780/")
PROBES = {
    "/generate_204": (204, b"", "text/plain"),
    "/gen_204": (204, b"", "text/plain"),
    "/hotspot-detect.html": (200, b"<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>", "text/html"),
    "/library/test/success.html": (200, b"<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>", "text/html"),
    "/connecttest.txt": (200, b"Microsoft Connect Test", "text/plain"),
    "/ncsi.txt": (200, b"Microsoft NCSI", "text/plain"),
    "/success.txt": (200, b"success\n", "text/plain"),       # Firefox
    "/canonical.html": (200, b"<meta http-equiv=\"refresh\" content=\"0;url=https://support.mozilla.org/kb/captive-portal\"/>", "text/html"),
    "/check_network_status.txt": (200, b"NetworkManager is online\n", "text/plain"),
    "/nm": (200, b"NetworkManager is online\n", "text/plain"),
}

class H(BaseHTTPRequestHandler):
    server_version = "silentdisco-portal/0.1"
    def log_message(self, *a): pass
    def _reply(self, code, body, ctype):
        self.send_response(code)
        if body: self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store"); self.end_headers()
        if body and self.command != "HEAD": self.wfile.write(body)
    def do_GET(self):
        path = self.path.split("?")[0]
        host = (self.headers.get("Host") or "").lower()
        if path in PROBES or host.startswith(("captive.apple.com", "connectivitycheck.", "www.msftconnecttest.com", "detectportal.")):
            code, body, ctype = PROBES.get(path, (200, b"Success", "text/plain"))
            return self._reply(code, body, ctype)
        self.send_response(302); self.send_header("Location", JOIN); self.send_header("Cache-Control", "no-store"); self.end_headers()
    do_HEAD = do_GET

if __name__ == "__main__":
    port = int(os.environ.get("PORTAL_PORT", "80"))
    print(f"portal on :{port}, join page {JOIN}", file=sys.stderr, flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), H).serve_forever()
