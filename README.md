# The Arcade

An original, self-built collection of small games — no third-party art, code,
or branding from any commercial game is used anywhere here. Names and
mechanics are deliberately different from anything they're loosely inspired
by, on purpose.

```
index.html            THE ARCADE — the hub / launcher, links to everything below
blockfall.html         BLOCKFALL — 25-player voxel battle royale (offline, vs bots)
runner.html            OVERDRIVE DASH — endless 3-lane runner (offline, solo)
roblox-hub/            BUILD WORLD — a mini-hub of its own
  index.html            its own menu screen
  obby.html             SKYRISE OBBY — 3D jump/climb obstacle course
  maze.html             COIN MAZE — procedural top-down maze
crew/                  CREWLINE — online social-deduction game (needs a real server, see below)
  server.js             Node + WebSocket game server
  public/index.html      the game client, served by server.js
remote/                TV REMOTE — utility, not a game (needs a real server too, see below)
  server.js             Node relay speaking the real (unofficial) Google TV protocol
  public/index.html      the remote-control client, served by server.js
```

## Running the static games (everything except Crewline)

Everything except `crew/` is plain HTML/JS/CSS — no build step, no server
required beyond something that serves static files (browsers block ES
module imports over `file://`, so don't just double-click `index.html`).

Locally, from this folder:
```
python -m http.server 8080
```
then open `http://localhost:8080/`.

To put it online permanently: push this folder to a GitHub repo and enable
**GitHub Pages** (repo Settings → Pages → deploy from a branch). Any device
with a browser — including an iPad's Safari — can then open the Pages URL
directly. No signing, no App Store, no Codemagic needed for any of this;
that whole pipeline (see `iOS-Game/README.md`) is only for the separate
native SpriteKit app, not this web arcade.

## Running Crewline (the online multiplayer game)

Crewline needs an actual always-on Node.js process — it's not static files,
since players' positions, roles, and votes have to be synchronized live
between everyone in a room. That means it can't live on GitHub Pages; it
needs a real (if small) server host.

### Run it locally first
```
cd crew
npm install
npm start
```
Open `http://localhost:8787/` in a couple of browser tabs/devices on the
same network to test a full game before deploying anywhere.

### Deploy it for real (free tier works fine for friends playing together)

Any Node host that supports WebSockets works. Render.com's free tier is a
straightforward option:

1. Push the `crew/` folder to its own GitHub repo (or a subfolder of this
   one — either works, just point Render at the right path).
2. On render.com: **New → Web Service** → connect the repo.
3. Build command: `npm install`. Start command: `npm start`.
4. Render assigns a URL like `https://crewline-yourname.onrender.com` —
   that's the whole app, client and server both served from that one URL.
5. Free tier sleeps after inactivity and takes a few seconds to wake up on
   the next visit — expected, not a bug, and fine for casual play with
   friends.

Once deployed, update the **CREWLINE** card's link in the root `index.html`
hub from the local `crew/` path to that live URL, so the arcade hub points
at the real deployment instead of a local-only path.

### Playing it
- One person clicks **Create Room**, gets a 4-letter code, shares it.
- Everyone else enters that code and **Join**.
- Need at least 3 players for the host's **Start Game** button to work.
- One player is secretly the impostor; crewmates complete tasks (walk to a
  glowing task spot, press **E** near it) while the impostor eliminates
  crewmates (**E** near them, cooldown between kills) without getting caught.
- Anyone can **Call Meeting** to force a discussion + vote; most votes gets
  ejected (ties/skip majority eject no one).
- Crew wins by finishing all tasks or ejecting every impostor; the impostor
  wins by reducing the crew to equal or fewer numbers.

## Running TV Remote (controls a Google TV, not a game)

Also a real Node process, same reason as Crewline — but this one is
**deliberately not meant to be deployed publicly**. It controls a physical
TV in your house over the local network using an unofficial, reverse-
engineered protocol (via the community `androidtv-remote` package); it has
no business being reachable from the internet.

```
cd remote
npm install
npm start
```

The console prints an access code on startup — enter that once in the web
client (`http://<your-pc's-local-ip>:8791/` from the iPad, same Wi-Fi).
Full pairing walkthrough is in `remote/README.md`. Keep this running only
on a trusted home machine; don't port-forward it or put it behind a public
host the way Crewline can be.

## Notes

- The Roblox-style sub-hub (`roblox-hub/`) is meant to grow over time —
  more small original rooms/games can be added as separate `.html` files
  and linked from `roblox-hub/index.html`.
- Nothing in this repo talks to the separate native iOS project in
  `iOS-Game/` — that's a fully independent SpriteKit app with its own build
  pipeline, documented in its own README.
