# Web pages

## party/ — the join page

What guests see when they scan the QR. One screen, one tile per channel,
tap to listen. No install, works in Safari and Chrome on phones.

It is a self-contained Snapcast client in about 300 lines: it speaks
Snapcast's binary stream protocol over a WebSocket, syncs its clock with the
server the same way the native clients do, and schedules each 20 ms PCM
chunk on the Web Audio clock. That is why phones stay within a few
milliseconds of each other and of the pucks.

- Requires `codec = pcm` on the server (set in `server/config/snapserver.conf`).
- Served by snapserver itself from `/var/lib/silentdisco/www/`; the
  installer copies it there. Snapweb lives beside it at `/snapweb/`.
- Listener counts and now-playing come from `Server.GetStatus` every 2 s.
- Switching colour is a `Group.SetStream` call for the phone's own group.
- Audio is routed through a hidden `<audio>` element so the phone treats it
  as media playback: lock-screen controls, keeps going with the screen off
  where the OS allows it.
- `?host=pi:1780` lets you open the file from anywhere and point it at a Pi.

Tested headless against a local snapserver with two PCM streams: 50 chunks
a second, none dropped, scheduling error under 10 ms, switching works.

Testing locally without a Pi:

```bash
snapserver -c /path/to/test.conf   # two pipe streams, codec = pcm, doc_root = web/party
```

## host/ — the host's controls

Served at `/host/`, PIN protected, talks to the host API on port 1790. See
[host/README.md](../host/README.md).
