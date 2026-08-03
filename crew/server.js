// Crewline server — a small original social-deduction game.
// One Node process serves the static client (./public) AND the WebSocket
// game protocol on the same port/host, so there's nothing else to host or
// configure — deploy this one folder and the client works out of the box.

const http = require('http');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8787;
const PUBLIC_DIR = path.join(__dirname, 'public');
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const file = path.join(PUBLIC_DIR, p);
  if (!file.startsWith(PUBLIC_DIR)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
});

const wss = new WebSocketServer({ server, path: '/ws' });

/* ---------------------- fixed map ---------------------- */
const MAP = {
  width: 860, height: 520,
  rooms: [
    { id: 'commons',    x: 340, y: 220, w: 180, h: 130 },
    { id: 'archive',    x: 60,  y: 60,  w: 220, h: 140 },
    { id: 'workshop',   x: 580, y: 60,  w: 220, h: 140 },
    { id: 'greenhouse', x: 60,  y: 340, w: 220, h: 140 },
    { id: 'reactor',    x: 580, y: 340, w: 220, h: 140 },
  ],
  corridors: [
    { x: 170, y: 200, w: 40,  h: 20 },
    { x: 670, y: 200, w: 40,  h: 20 },
    { x: 170, y: 340, w: 40,  h: 20 },
    { x: 670, y: 340, w: 40,  h: 20 },
    { x: 260, y: 270, w: 80,  h: 30 },
    { x: 520, y: 270, w: 80,  h: 30 },
  ],
  taskSpots: [
    { id: 'wiring',   name: 'Fix Wiring',    x: 150, y: 130 },
    { id: 'upload',   name: 'Upload Data',   x: 680, y: 120 },
    { id: 'water',    name: 'Water Plants',  x: 150, y: 410 },
    { id: 'coolant',  name: 'Vent Coolant',  x: 680, y: 410 },
    { id: 'align',    name: 'Align Sensor',  x: 430, y: 280 },
  ],
  spawn: { x: 430, y: 285 },
};

const KILL_RANGE = 46, TASK_RANGE = 42, KILL_COOLDOWN_MS = 22000, MEETING_MS = 26000;

const ROOMS = new Map();

function genCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  let s; do { s = Array.from({length:4}, ()=>chars[(Math.random()*chars.length)|0]).join(''); } while (ROOMS.has(s));
  return s;
}
function makeRoom(code) {
  return { code, players: new Map(), phase: 'lobby', hostId: null, meetingCooldownUntil: 0 };
}
function send(ws, msg) { if (ws.readyState === 1) ws.send(JSON.stringify(msg)); }
function broadcast(room, msg) {
  const data = JSON.stringify(msg);
  for (const p of room.players.values()) if (p.ws.readyState === 1) p.ws.send(data);
}
function lobbyList(room) {
  return [...room.players.values()].map(p => ({ id: p.id, name: p.name }));
}
function aliveList(room) {
  return [...room.players.values()].filter(p => p.alive).map(p => ({ id: p.id, name: p.name }));
}

function startGame(room) {
  const ids = [...room.players.keys()];
  const impostorCount = Math.max(1, Math.floor(ids.length / 5));
  const shuffled = ids.slice().sort(() => Math.random() - 0.5);
  const impostors = new Set(shuffled.slice(0, impostorCount));
  const taskIds = MAP.taskSpots.map(t => t.id);

  for (const id of ids) {
    const p = room.players.get(id);
    p.alive = true;
    p.role = impostors.has(id) ? 'impostor' : 'crew';
    p.tasks = p.role === 'crew' ? taskIds.slice() : [];
    p.tasksDone = [];
    p.x = MAP.spawn.x + (Math.random()*60-30);
    p.y = MAP.spawn.y + (Math.random()*60-30);
    p.killReadyAt = 0;
    send(p.ws, { t: 'role', role: p.role, tasks: p.tasks, map: MAP, you: { id: p.id, x: p.x, y: p.y } });
  }
  room.phase = 'playing';
  broadcast(room, {
    t: 'started',
    players: [...room.players.values()].map(p => ({ id: p.id, name: p.name, x: p.x, y: p.y, alive: true })),
  });
}

function checkWin(room) {
  const alive = [...room.players.values()].filter(p => p.alive);
  const impostorsAlive = alive.filter(p => p.role === 'impostor').length;
  const crewAlive = alive.length - impostorsAlive;
  const crewMembers = alive.filter(p => p.role === 'crew');
  const allTasksDone = crewMembers.length > 0 && crewMembers.every(p => p.tasksDone.length >= p.tasks.length);

  if (impostorsAlive === 0) { endGame(room, 'crew', 'Every impostor was ejected.'); return true; }
  if (impostorsAlive >= crewAlive) { endGame(room, 'impostor', 'Impostors equal or outnumber the crew.'); return true; }
  if (allTasksDone) { endGame(room, 'crew', 'All tasks were completed.'); return true; }
  return false;
}
function endGame(room, winner, reason) {
  room.phase = 'ended';
  broadcast(room, {
    t: 'ended', winner, reason,
    reveal: [...room.players.values()].map(p => ({ name: p.name, role: p.role, alive: p.alive })),
  });
}

function resolveMeeting(room) {
  if (room.phase !== 'meeting') return;
  clearTimeout(room.meetingTimer);
  const tally = new Map();
  for (const v of room.votes.values()) {
    if (v === 'skip') continue;
    tally.set(v, (tally.get(v) || 0) + 1);
  }
  let ejectedId = null, max = 0, tie = false;
  for (const [id, count] of tally) {
    if (count > max) { max = count; ejectedId = id; tie = false; }
    else if (count === max) tie = true;
  }
  if (tie || max === 0) ejectedId = null;

  let ejectedInfo = null;
  if (ejectedId) {
    const p = room.players.get(ejectedId);
    if (p) { p.alive = false; ejectedInfo = { id: p.id, name: p.name, role: p.role }; }
  }
  room.phase = 'playing';
  room.meetingCooldownUntil = Date.now() + 8000;
  broadcast(room, { t: 'meetingResult', ejected: ejectedInfo });
  checkWin(room);
}

wss.on('connection', (ws) => {
  let me = null, myRoom = null;

  function joinRoom(room, name) {
    const id = Math.random().toString(36).slice(2, 9);
    const p = { id, name: (name || 'Player').slice(0, 16), ws, alive: true,
      x: MAP.spawn.x, y: MAP.spawn.y, role: null, tasks: [], tasksDone: [], killReadyAt: 0 };
    room.players.set(id, p);
    if (!room.hostId) room.hostId = id;
    me = p; myRoom = room;
    send(ws, { t: 'joined', id, code: room.code, hostId: room.hostId });
    broadcast(room, { t: 'lobby', players: lobbyList(room), hostId: room.hostId });
  }

  ws.on('message', (raw) => {
    let msg; try { msg = JSON.parse(raw); } catch { return; }

    switch (msg.t) {
      case 'create': {
        const room = makeRoom(genCode());
        ROOMS.set(room.code, room);
        joinRoom(room, msg.name);
        break;
      }
      case 'join': {
        const room = ROOMS.get((msg.code || '').toUpperCase());
        if (!room) { send(ws, { t: 'error', message: 'Room not found.' }); return; }
        if (room.phase !== 'lobby') { send(ws, { t: 'error', message: 'That game already started.' }); return; }
        joinRoom(room, msg.name);
        break;
      }
      case 'start': {
        if (!myRoom || myRoom.hostId !== me.id || myRoom.phase !== 'lobby') return;
        if (myRoom.players.size < 3) { send(ws, { t: 'error', message: 'Need at least 3 players.' }); return; }
        startGame(myRoom);
        break;
      }
      case 'move': {
        if (!myRoom || myRoom.phase !== 'playing' || !me.alive) return;
        me.x = msg.x; me.y = msg.y;
        broadcast(myRoom, { t: 'pos', id: me.id, x: me.x, y: me.y });
        break;
      }
      case 'task': {
        if (!myRoom || myRoom.phase !== 'playing' || !me.alive || me.role !== 'crew') return;
        const spot = MAP.taskSpots.find(t => t.id === msg.id);
        if (!spot || !me.tasks.includes(msg.id) || me.tasksDone.includes(msg.id)) return;
        if (Math.hypot(me.x - spot.x, me.y - spot.y) > TASK_RANGE) return;
        me.tasksDone.push(msg.id);
        send(ws, { t: 'taskDone', id: msg.id, done: me.tasksDone.length, total: me.tasks.length });
        checkWin(myRoom);
        break;
      }
      case 'kill': {
        if (!myRoom || myRoom.phase !== 'playing' || !me.alive || me.role !== 'impostor') return;
        if (Date.now() < me.killReadyAt) return;
        const target = myRoom.players.get(msg.targetId);
        if (!target || !target.alive || target.id === me.id) return;
        if (Math.hypot(target.x - me.x, target.y - me.y) > KILL_RANGE) return;
        target.alive = false;
        me.killReadyAt = Date.now() + KILL_COOLDOWN_MS;
        broadcast(myRoom, { t: 'killed', id: target.id });
        checkWin(myRoom);
        break;
      }
      case 'meeting': {
        if (!myRoom || myRoom.phase !== 'playing' || !me.alive) return;
        if (Date.now() < myRoom.meetingCooldownUntil) return;
        myRoom.phase = 'meeting';
        myRoom.votes = new Map();
        const endsAt = Date.now() + MEETING_MS;
        broadcast(myRoom, { t: 'meeting', callerName: me.name, players: aliveList(myRoom), endsAt });
        myRoom.meetingTimer = setTimeout(() => resolveMeeting(myRoom), MEETING_MS);
        break;
      }
      case 'vote': {
        if (!myRoom || myRoom.phase !== 'meeting' || !me.alive) return;
        myRoom.votes.set(me.id, msg.targetId || 'skip');
        broadcast(myRoom, { t: 'voteCast', voterId: me.id });
        if (myRoom.votes.size >= aliveList(myRoom).length) resolveMeeting(myRoom);
        break;
      }
    }
  });

  ws.on('close', () => {
    if (!myRoom) return;
    myRoom.players.delete(me.id);
    if (myRoom.players.size === 0) { ROOMS.delete(myRoom.code); return; }
    if (myRoom.hostId === me.id) myRoom.hostId = [...myRoom.players.keys()][0];
    if (myRoom.phase === 'lobby') broadcast(myRoom, { t: 'lobby', players: lobbyList(myRoom), hostId: myRoom.hostId });
    else { broadcast(myRoom, { t: 'left', id: me.id }); if (myRoom.phase === 'playing') checkWin(myRoom); }
  });
});

server.listen(PORT, () => console.log('Crewline server listening on :' + PORT));
