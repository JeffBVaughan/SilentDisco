#!/usr/bin/env python3
"""SilentDisco host API: the party controls behind web/host.

One MPD per colour feeds Snapcast. This service wraps MPD and Snapcast's
JSON-RPC in a small HTTP API the host page talks to:

  GET  /api/channels                     public: ids, display names, colours
  GET  /api/state                        everything the host page shows
  POST /api/channel/<id>/cmd             {"cmd": "play"|"pause"|"next"|"prev"|"shuffle"|
                                          "clear"|"fill"|"volume"|"random"|"remove"|"jump"|"add", ...}
  PUT  /api/channel/<id>/files?name=f    body = the file; saved, indexed, queued
  DELETE /api/channel/<id>/files?name=f
  GET  /api/channel/<id>/library
  POST /api/channel/<id>/name            {"name": "..."}
  POST /api/takeover                     {"target": "<id>", "seconds": 30}
  POST /api/release
  POST /api/mute                         {"muted": true|false}
  POST /api/pin                          {"old": "...", "new": "..."}  4 to 8 digits

Every call except /api/channels needs the PIN (header X-Pin or ?pin=).
Standard library only.
"""
import json
import os
import re
import socket
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASE      = os.environ.get("HOST_BASE", "/var/lib/silentdisco")
PORT      = int(os.environ.get("HOST_PORT", "1790"))
STATE_DIR = os.path.join(BASE, "host")        # owned by the service user; the PIN and names live here
PIN_FILE  = os.path.join(STATE_DIR, "pin")
def load_pin():
    try:
        with open(PIN_FILE) as f:
            v = f.read().strip()
            if v: return v
    except Exception: pass
    return os.environ.get("HOST_PIN", "0000")
PIN       = load_pin()
SNAP_RPC  = os.environ.get("HOST_SNAP_RPC", "http://127.0.0.1:1780/jsonrpc")
MPD_BASE_PORT = int(os.environ.get("HOST_MPD_BASE_PORT", "6600"))
CHANNELS  = [c for c in os.environ.get("HOST_CHANNELS", "Yellow,Red,Green,Blue").split(",") if c]
COLOURS   = {"yellow": "#ffc928", "red": "#ff4d5a", "green": "#36d47a", "blue": "#4a9dff"}
NAMES_FILE = os.path.join(STATE_DIR, "channels.json")
AUDIO_EXT = (".mp3", ".flac", ".m4a", ".wav", ".ogg", ".opus", ".aac", ".wma", ".aiff")

def log(*a): print(*a, file=sys.stderr, flush=True)

# ---------------------------------------------------------------- channel names
_names_lock = threading.Lock()
def load_names():
    try:
        with open(NAMES_FILE) as f: return json.load(f)
    except Exception: return {}
def save_name(cid, name):
    with _names_lock:
        d = load_names(); d[cid] = name
        tmp = NAMES_FILE + ".tmp"
        with open(tmp, "w") as f: json.dump(d, f)
        os.replace(tmp, NAMES_FILE)
def channel_list():
    names = load_names()
    return [{"id": c, "name": names.get(c, c), "colour": COLOURS.get(c.lower(), "#9ca3af"),
             "port": MPD_BASE_PORT + 1 + i} for i, c in enumerate(CHANNELS)]
def channel(cid):
    for c in channel_list():
        if c["id"].lower() == cid.lower(): return c
    return None

# ---------------------------------------------------------------- mpd client (one connection per call)
class MPDError(Exception): pass

def mpd_quote(s): return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'

def mpd(port, *commands, timeout=5):
    """Run commands in one MPD session; return a list of (key, value) pairs per command."""
    results = []
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as s:
        f = s.makefile("rwb", buffering=0)
        hello = f.readline()
        if not hello.startswith(b"OK MPD"): raise MPDError("no MPD banner")
        for cmd in commands:
            f.write((cmd + "\n").encode())
            pairs = []
            while True:
                line = f.readline()
                if not line: raise MPDError("connection closed")
                line = line.decode(errors="replace").rstrip("\n")
                if line == "OK": break
                if line.startswith("ACK"): raise MPDError(line)
                k, _, v = line.partition(": ")
                pairs.append((k, v))
            results.append(pairs)
    return results

def pairs_to_dict(pairs): return {k: v for k, v in pairs}
def pairs_to_songs(pairs):
    songs, cur = [], None
    for k, v in pairs:
        if k == "file":
            cur = {"file": v}; songs.append(cur)
        elif cur is not None: cur[k] = v
    return songs
def song_view(s):
    if not s: return None
    title = s.get("Title") or os.path.splitext(os.path.basename(s.get("file", "")))[0]
    return {"id": int(s["Id"]) if "Id" in s else None, "pos": int(s["Pos"]) if "Pos" in s else None,
            "title": title, "artist": s.get("Artist", ""), "file": s.get("file", ""),
            "duration": float(s.get("duration", 0) or 0)}

def channel_state(c):
    try:
        status, cur, queue = mpd(c["port"], "status", "currentsong", "playlistinfo")
        st = pairs_to_dict(status)
        return {"status": {"state": st.get("state", "stop"), "elapsed": float(st.get("elapsed", 0) or 0),
                           "volume": int(st.get("volume", -1)), "random": st.get("random") == "1",
                           "repeat": st.get("repeat") == "1", "queue_len": int(st.get("playlistlength", 0)),
                           "updating": "updating_db" in st},
                "now": song_view(pairs_to_dict(cur)) if cur else None,
                "queue": [song_view(s) for s in pairs_to_songs(queue)], "error": st.get("error")}
    except Exception as e:
        return {"status": {"state": "down"}, "now": None, "queue": [], "error": str(e)}

def library(c):
    try:
        (pairs,) = mpd(c["port"], "listall")
        return [v for k, v in pairs if k == "file"]
    except Exception: return []

def fill_and_play(c):
    """Queue everything (shuffled, repeating) and play. Used on empty queues and by 'fill'."""
    mpd(c["port"], "update")
    for _ in range(40):                                   # wait for the index
        if "updating_db" not in pairs_to_dict(mpd(c["port"], "status")[0]): break
        time.sleep(0.25)
    if not library(c): return False
    mpd(c["port"], "clear", 'add ""', "shuffle", "random 1", "repeat 1", "single 0", "consume 0", "play")
    return True

def ensure_playing():
    """At start and every minute: any channel with files but an empty or stopped queue gets filled."""
    for c in channel_list():
        try:
            st = pairs_to_dict(mpd(c["port"], "status")[0])
            if int(st.get("playlistlength", 0)) == 0:
                if fill_and_play(c): log(f"{c['id']}: queue filled")
            elif st.get("state") == "stop":
                mpd(c["port"], "repeat 1", "play")
        except Exception as e:
            log(f"{c['id']}: mpd not reachable ({e})")

# ---------------------------------------------------------------- snapcast
_rpc_id = 0
def snap(method, params=None):
    global _rpc_id; _rpc_id += 1
    body = json.dumps({"id": _rpc_id, "jsonrpc": "2.0", "method": method, "params": params or {}}).encode()
    req = urllib.request.Request(SNAP_RPC, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=3) as r:
        j = json.load(r)
    if "error" in j: raise RuntimeError(j["error"].get("message", "rpc error"))
    return j["result"]

def listeners():
    """{stream_id: [client views]} plus groups for takeover."""
    server = snap("Server.GetStatus")["server"]
    per = {}
    groups = []
    for g in server["groups"]:
        groups.append({"id": g["id"], "stream_id": g["stream_id"], "muted": g.get("muted", False),
                       "clients": [c["id"] for c in g["clients"] if c.get("connected")]})
        for c in g["clients"]:
            if not c.get("connected"): continue
            h = c.get("host", {}); cfg = c.get("config", {})
            per.setdefault(g["stream_id"], []).append({
                "id": c["id"], "name": cfg.get("name") or h.get("name") or c["id"],
                "kind": "puck" if (h.get("arch") or "").startswith("xtensa") or c["id"].startswith("puck") else "phone",
                "volume": cfg.get("volume", {}).get("percent"), "muted": cfg.get("volume", {}).get("muted")})
    return per, groups

# ---------------------------------------------------------------- takeover ("everyone to Red")
_take_lock = threading.Lock()
_takeover = {"active": False, "target": None, "until": 0, "saved": {}}

def takeover(target, seconds):
    with _take_lock:
        _, groups = listeners()
        if not _takeover["active"]:
            _takeover["saved"] = {g["id"]: g["stream_id"] for g in groups}
        for g in groups:
            if g["stream_id"] != target:
                try: snap("Group.SetStream", {"id": g["id"], "stream_id": target})
                except Exception as e: log("takeover:", e)
        _takeover.update(active=True, target=target, until=time.time() + seconds)
    threading.Timer(seconds, lambda: release(expected_until=_takeover["until"])).start()

def release(expected_until=None):
    with _take_lock:
        if not _takeover["active"]: return
        if expected_until is not None and abs(expected_until - _takeover["until"]) > 0.5: return  # superseded
        for gid, sid in _takeover["saved"].items():
            try: snap("Group.SetStream", {"id": gid, "stream_id": sid})
            except Exception: pass
        _takeover.update(active=False, target=None, until=0, saved={})

def mute_all(muted):
    _, groups = listeners()
    for g in groups:
        try: snap("Group.SetMute", {"id": g["id"], "mute": bool(muted)})
        except Exception as e: log("mute:", e)

# ---------------------------------------------------------------- http
class Handler(BaseHTTPRequestHandler):
    server_version = "silentdisco-host/0.1"
    def log_message(self, fmt, *a): pass

    def _send(self, code, obj=None, raw=None, ctype="application/json"):
        body = raw if raw is not None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Pin")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
        self.send_header("Cache-Control", "no-store")
        self.end_headers(); self.wfile.write(body)
    def _json(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}
    def _authed(self, q):
        return (self.headers.get("X-Pin") or q.get("pin", [""])[0]) == PIN

    def do_OPTIONS(self): self._send(204, raw=b"")

    def route(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        parts = [p for p in u.path.split("/") if p]
        return u, q, parts

    def do_GET(self):
        u, q, parts = self.route()
        if parts == ["api", "channels"]:
            return self._send(200, [{k: c[k] for k in ("id", "name", "colour")} for c in channel_list()])
        if not self._authed(q): return self._send(401, {"error": "pin"})
        if parts == ["api", "state"]:
            try: per, _ = listeners()
            except Exception as e: per = {}; log("snap:", e)
            chans = []
            for c in channel_list():
                d = channel_state(c)
                d.update(id=c["id"], name=c["name"], colour=c["colour"],
                         listeners=per.get(c["id"], []), library_count=len(library(c)))
                chans.append(d)
            return self._send(200, {"channels": chans, "total": sum(len(v) for v in per.values()),
                                    "takeover": {k: _takeover[k] for k in ("active", "target", "until")}, "now": time.time()})
        if len(parts) == 4 and parts[:2] == ["api", "channel"] and parts[3] == "library":
            c = channel(parts[2])
            return self._send(200, library(c)) if c else self._send(404, {"error": "no such channel"})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        u, q, parts = self.route()
        if not self._authed(q): return self._send(401, {"error": "pin"})
        body = self._json()
        try:
            if parts == ["api", "takeover"]:
                target = channel(body.get("target", ""))
                if not target: return self._send(400, {"error": "bad target"})
                takeover(target["id"], max(1, min(600, int(body.get("seconds", 30)))))
                return self._send(200, {"ok": True})
            if parts == ["api", "release"]:
                release(); return self._send(200, {"ok": True})
            if parts == ["api", "mute"]:
                mute_all(bool(body.get("muted"))); return self._send(200, {"ok": True})
            if parts == ["api", "pin"]:
                global PIN
                old, new = str(body.get("old", "")), str(body.get("new", ""))
                if old != PIN: return self._send(403, {"error": "current PIN is wrong"})
                if not re.fullmatch(r"\d{4,8}", new): return self._send(400, {"error": "new PIN must be 4 to 8 digits"})
                try:
                    tmp = PIN_FILE + ".tmp"
                    with open(tmp, "w") as f: f.write(new + "\n")
                    os.chmod(tmp, 0o600); os.replace(tmp, PIN_FILE)
                except Exception as e:
                    return self._send(500, {"error": f"could not save the PIN: {e}"})
                PIN = new; log("PIN changed")
                return self._send(200, {"ok": True})
            if len(parts) == 4 and parts[:2] == ["api", "channel"]:
                c = channel(parts[2])
                if not c: return self._send(404, {"error": "no such channel"})
                if parts[3] == "name":
                    name = re.sub(r"<[^>]*>", "", str(body.get("name", "")))
                    name = re.sub(r"[^\w .&'!?-]", "", name)[:24].strip() or c["id"]
                    save_name(c["id"], name); return self._send(200, {"ok": True, "name": name})
                if parts[3] == "cmd":
                    cmd = body.get("cmd"); p = c["port"]
                    if cmd == "play": mpd(p, "repeat 1", "play")
                    elif cmd == "pause": mpd(p, "pause 1")
                    elif cmd == "next": mpd(p, "next")
                    elif cmd == "prev": mpd(p, "previous")
                    elif cmd == "shuffle": mpd(p, "shuffle")
                    elif cmd == "clear": mpd(p, "clear")
                    elif cmd == "fill": fill_and_play(c)
                    elif cmd == "volume": mpd(p, f"setvol {max(0, min(100, int(body.get('value', 100))))}")
                    elif cmd == "random": mpd(p, f"random {1 if body.get('value') else 0}")
                    elif cmd == "remove": mpd(p, f"deleteid {int(body['id'])}")
                    elif cmd == "jump": mpd(p, f"playid {int(body['id'])}")
                    elif cmd == "add": mpd(p, f"add {mpd_quote(body['file'])}", "repeat 1", "play")
                    else: return self._send(400, {"error": "unknown cmd"})
                    return self._send(200, {"ok": True})
        except MPDError as e:
            return self._send(502, {"error": str(e)})
        except Exception as e:
            return self._send(500, {"error": str(e)})
        self._send(404, {"error": "not found"})

    def do_PUT(self):
        u, q, parts = self.route()
        if not self._authed(q): return self._send(401, {"error": "pin"})
        if len(parts) == 4 and parts[:2] == ["api", "channel"] and parts[3] == "files":
            c = channel(parts[2])
            if not c: return self._send(404, {"error": "no such channel"})
            name = os.path.basename(q.get("name", [""])[0]).strip()
            if not name or not name.lower().endswith(AUDIO_EXT):
                return self._send(400, {"error": "need ?name=file with an audio extension"})
            n = int(self.headers.get("Content-Length") or 0)
            if n <= 0 or n > 200 * 1024 * 1024: return self._send(413, {"error": "bad size"})
            dest = os.path.join(BASE, "music", c["id"].lower(), name)
            tmp = dest + ".part"
            with open(tmp, "wb") as f:
                left = n
                while left:
                    chunk = self.rfile.read(min(1 << 20, left))
                    if not chunk: break
                    f.write(chunk); left -= len(chunk)
            os.replace(tmp, dest)
            try:
                mpd(c["port"], "update")
                for _ in range(40):
                    if "updating_db" not in pairs_to_dict(mpd(c["port"], "status")[0]): break
                    time.sleep(0.25)
                st = pairs_to_dict(mpd(c["port"], "status")[0])
                if int(st.get("playlistlength", 0)) == 0: fill_and_play(c)
                else: mpd(c["port"], f"add {mpd_quote(name)}", "repeat 1", "play")
            except Exception as e:
                return self._send(200, {"ok": True, "warning": f"saved, but MPD said: {e}"})
            return self._send(200, {"ok": True, "file": name})
        self._send(404, {"error": "not found"})

    def do_DELETE(self):
        u, q, parts = self.route()
        if not self._authed(q): return self._send(401, {"error": "pin"})
        if len(parts) == 4 and parts[:2] == ["api", "channel"] and parts[3] == "files":
            c = channel(parts[2])
            name = os.path.basename(q.get("name", [""])[0])
            path = os.path.join(BASE, "music", c["id"].lower(), name) if c else ""
            if not c or not name or not os.path.isfile(path): return self._send(404, {"error": "no such file"})
            os.remove(path)
            try:
                (found,) = mpd(c["port"], f"playlistfind file {mpd_quote(name)}")
                ids = [v for k, v in found if k == "Id"]
                mpd(c["port"], *[f"deleteid {i}" for i in ids], "update")
            except Exception: pass
            return self._send(200, {"ok": True})
        self._send(404, {"error": "not found"})

def keeper():
    while True:
        try: ensure_playing()
        except Exception as e: log("keeper:", e)
        time.sleep(60)

def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    threading.Thread(target=keeper, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    log(f"host api on :{PORT}, channels {CHANNELS}, pin {'set' if PIN != '0000' else 'DEFAULT 0000'}")
    srv.serve_forever()

if __name__ == "__main__":
    main()
