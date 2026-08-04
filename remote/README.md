# TV Remote — control a Google TV from an old iPad

A small relay server that lets an old iPad (too old to install the real
Google TV app) control a TV running Google TV, from Safari over your home
Wi-Fi.

## Why this needs a server at all

Google TV's real remote-control protocol isn't public — there's no
"send a URL to the TV" API a web page can call directly. The actual protocol
(reverse-engineered, used by the official Android TV Remote app) requires a
raw TLS socket + protobuf messages + a one-time PIN pairing handshake, which
a browser can't do. So this folder runs a small Node.js relay on your
Windows PC: your iPad's Safari talks plain WebSocket to the relay, and the
relay does the real TV protocol on your PC's behalf, using the
[`androidtv-remote`](https://www.npmjs.com/package/androidtv-remote)
open-source library (MIT-family licensed, community-maintained — this
project doesn't reimplement Google's unofficial protocol itself, it reuses
an existing well-tested client for it).

## Known limitation, please read

`androidtv-remote`'s own dependencies (`node-forge`, `protobufjs`) had
known security vulnerabilities in their pinned versions; this project
forces newer, patched versions via `package.json`'s `overrides` field and
was smoke-tested afterward to confirm the library still loads and exposes
the same API. I could not test the actual TV pairing handshake end-to-end
myself (no physical Google TV here) — that part needs your real device.
If pairing fails in a way that looks like a real bug (not just a wrong IP),
send me the relay's console output and I'll help debug it.

This relay is only meant to run on your trusted home network — it isn't
hardened for exposure to the open internet. Don't port-forward it.

## One-time setup

```
cd remote
npm install
```

## Running it

```
npm start
```

The console prints an **access code** on startup, e.g.:

```
======================================================
 Remote access code: D2A86AFC
 Enter this once in the web client to unlock control.
======================================================
```

Keep this window open while you want to use the remote.

## Connecting from the iPad

1. Make sure the iPad and your Windows PC are on the same Wi-Fi network.
2. On the iPad's Safari, go to `http://<your-pc's-local-ip>:8791/`
   (find your PC's IP via `ipconfig` in a terminal — look for "IPv4 Address").
3. Enter the access code shown in the server console.
4. First time only: enter your TV's local IP (Settings → Network & Internet
   on the TV itself shows this), tap **Pair / Connect**. The TV will show a
   pairing code on screen — type it into the iPad and submit.
5. After that, the pairing is remembered (saved in `remote/config.json`) —
   future runs reconnect automatically, no re-pairing needed unless the TV
   forgets it (factory reset, network change, etc.).

## What the remote can do

D-pad + OK, Home, Back, Power, Volume up/down/mute, Play/Pause/Next/Previous,
Settings, and a quick "Open YouTube" button. More app quick-links can be
added to the `QUICK_LINKS` object in `server.js`.

## Adding a second TV or re-pairing

Tap "Pair a different TV" in the web UI, enter the new IP, and go through
the pairing-code step again.
