const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const { AndroidRemote, RemoteKeyCode, RemoteDirection } = require('androidtv-remote');

const PORT = process.env.PORT || 8791;
const PUBLIC_DIR = path.join(__dirname, 'public');
const CONFIG_PATH = path.join(__dirname, 'config.json');

/* ---------------- persisted config (TV pairing + access code) ---------------- */
function loadConfig(){
  try { return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); }
  catch(e){ return {}; }
}
function saveConfig(cfg){
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}
let config = loadConfig();
if (!config.accessCode){
  config.accessCode = crypto.randomBytes(4).toString('hex').toUpperCase();
  saveConfig(config);
}
console.log('');
console.log('======================================================');
console.log(' Remote access code:', config.accessCode);
console.log(' Enter this once in the web client to unlock control.');
console.log('======================================================');
console.log('');

// only these key names are ever accepted from a client — never pass client
// input straight into the RemoteKeyCode lookup unchecked.
const ALLOWED_KEYS = [
  'KEYCODE_DPAD_UP','KEYCODE_DPAD_DOWN','KEYCODE_DPAD_LEFT','KEYCODE_DPAD_RIGHT','KEYCODE_DPAD_CENTER',
  'KEYCODE_HOME','KEYCODE_BACK','KEYCODE_VOLUME_UP','KEYCODE_VOLUME_DOWN','KEYCODE_MUTE',
  'KEYCODE_MEDIA_PLAY_PAUSE','KEYCODE_MEDIA_NEXT','KEYCODE_MEDIA_PREVIOUS','KEYCODE_SETTINGS','KEYCODE_ENTER',
];
const QUICK_LINKS = {
  youtube: 'https://www.youtube.com',
  netflix: 'https://www.netflix.com/title',
};

/* ---------------- TV connection (single shared instance) ---------------- */
let remote = null;
let tvState = { connected:false, host: config.host||null, powered:null, volume:null, currentApp:null, pairing:false };
const clients = new Set();

function broadcast(msg){
  const data = JSON.stringify(msg);
  for (const ws of clients) if (ws.readyState===1 && ws.authed) ws.send(data);
}
function broadcastStatus(){
  broadcast({ t:'status', ...tvState });
}

function connectTV(host){
  if (remote) { try{ remote.stop(); }catch(e){} remote = null; }
  tvState.host = host; tvState.connected = false; tvState.pairing = true;
  config.host = host; saveConfig(config);

  const options = { pairing_port:6467, remote_port:6466, name:'arcade-remote' };
  if (config.cert && config.certHost === host) options.cert = config.cert;

  remote = new AndroidRemote(host, options);

  remote.on('secret', () => {
    tvState.pairing = true;
    broadcast({ t:'needCode' });
  });
  remote.on('ready', () => {
    tvState.connected = true; tvState.pairing = false;
    try { config.cert = remote.getCertificate(); config.certHost = host; saveConfig(config); } catch(e){}
    broadcastStatus();
    broadcast({ t:'ready' });
  });
  remote.on('powered', p => { tvState.powered = p; broadcastStatus(); });
  remote.on('volume', v => { tvState.volume = v; broadcastStatus(); });
  remote.on('current_app', a => { tvState.currentApp = a; broadcastStatus(); });
  remote.on('unpaired', () => {
    tvState.connected = false;
    config.cert = null; saveConfig(config);
    broadcast({ t:'unpaired' });
  });
  remote.on('error', err => {
    broadcast({ t:'error', message: String(err && err.message || err) });
  });

  remote.start().catch(err => {
    broadcast({ t:'error', message: 'Could not reach that TV: ' + (err && err.message || err) });
  });
}

// auto-reconnect on boot if we already have a paired TV
if (config.host && config.cert) connectTV(config.host);

/* ---------------- static file server + WebSocket ---------------- */
const MIME = { '.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.json':'application/json' };
const server = http.createServer((req,res)=>{
  let p = req.url.split('?')[0];
  if (p === '/') p = '/index.html';
  const file = path.join(PUBLIC_DIR, p);
  if (!file.startsWith(PUBLIC_DIR)) { res.writeHead(403); res.end(); return; }
  fs.readFile(file, (err,data)=>{
    if (err){ res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, {'Content-Type': MIME[path.extname(file)] || 'application/octet-stream'});
    res.end(data);
  });
});

const wss = new WebSocketServer({ server, path:'/ws' });
wss.on('connection', ws=>{
  ws.authed = false;
  clients.add(ws);
  ws.send(JSON.stringify({ t:'hello', hasTV: !!tvState.host }));

  ws.on('message', raw=>{
    let msg; try { msg = JSON.parse(raw); } catch(e){ return; }

    if (msg.t === 'auth'){
      ws.authed = (msg.code || '').toUpperCase() === config.accessCode;
      ws.send(JSON.stringify({ t:'auth', ok: ws.authed }));
      if (ws.authed) ws.send(JSON.stringify({ t:'status', ...tvState }));
      return;
    }
    if (!ws.authed) { ws.send(JSON.stringify({ t:'error', message:'Not authorized' })); return; }

    if (msg.t === 'connectTV'){
      if (typeof msg.host === 'string' && /^[0-9.]{7,15}$/.test(msg.host)) connectTV(msg.host);
      return;
    }
    if (msg.t === 'code'){
      if (remote && typeof msg.code === 'string') remote.sendCode(msg.code);
      return;
    }
    if (msg.t === 'key'){
      if (!remote || !tvState.connected) return;
      if (!ALLOWED_KEYS.includes(msg.code)) return;
      const dir = msg.hold ? RemoteDirection.START_LONG : RemoteDirection.SHORT;
      remote.sendKey(RemoteKeyCode[msg.code], dir);
      return;
    }
    if (msg.t === 'power'){
      if (remote && tvState.connected) remote.sendPower();
      return;
    }
    if (msg.t === 'openApp'){
      if (remote && tvState.connected && QUICK_LINKS[msg.app]) remote.sendAppLink(QUICK_LINKS[msg.app]);
      return;
    }
  });

  ws.on('close', ()=> clients.delete(ws));
});

server.listen(PORT, ()=> console.log('Remote relay listening on port', PORT));
