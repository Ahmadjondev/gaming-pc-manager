const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 3000;
const AUTH_TOKEN = process.env.AUTH_TOKEN || 'gameroom_secret_key_2026';
const PUBLIC_DIR = path.join(__dirname, 'public');

// In-memory state of gaming stations
// Map<stationId, StationState>
const stations = new Map();
// Map<stationId, WebSocket>
const clientSockets = new Map();
// Set<WebSocket> for connected admin dashboards
const adminSockets = new Set();

// Utility to get local LAN IP address
function getLocalIp() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const net of interfaces[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address;
      }
    }
  }
  return 'localhost';
}

// Simple static HTTP file server
const server = http.createServer((req, res) => {
  let reqPath = req.url.split('?')[0];
  if (reqPath === '/' || reqPath === '') reqPath = '/index.html';

  const filePath = path.join(PUBLIC_DIR, reqPath);
  const ext = path.extname(filePath).toLowerCase();

  const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json',
    '.png': 'image/png',
    '.svg': 'image/svg+xml'
  };

  fs.readFile(filePath, (err, content) => {
    if (err) {
      if (err.code === 'ENOENT') {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('404 Not Found');
      } else {
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('500 Internal Server Error');
      }
      return;
    }

    res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
    res.end(content);
  });
});

// Setup WebSockets
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  const { pathname } = new URL(request.url, `http://${request.headers.host}`);

  if (pathname === '/ws/client' || pathname === '/ws/admin') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request, pathname);
    });
  } else {
    socket.destroy();
  }
});

wss.on('connection', (ws, req, pathname) => {
  if (pathname === '/ws/admin') {
    handleAdminConnection(ws);
  } else if (pathname === '/ws/client') {
    handleClientConnection(ws, req);
  }
});

// Broadcast snapshot to all connected admin dashboards
function broadcastToAdmins(message) {
  const json = JSON.stringify(message);
  for (const admin of adminSockets) {
    if (admin.readyState === WebSocket.OPEN) {
      admin.send(json);
    }
  }
}

function getStationsSnapshot() {
  return Array.from(stations.values());
}

// ----------------- ADMIN DASHBOARD HANDLER -----------------
function handleAdminConnection(ws) {
  adminSockets.add(ws);
  console.log(`[Admin] Dashboard connected (Total dashboards: ${adminSockets.size})`);

  // Send initial state snapshot
  ws.send(JSON.stringify({
    type: 'init',
    stations: getStationsSnapshot(),
    serverTime: Date.now()
  }));

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      handleAdminCommand(msg);
    } catch (err) {
      console.error('[Admin] Invalid JSON message:', err.message);
    }
  });

  ws.on('close', () => {
    adminSockets.delete(ws);
    console.log(`[Admin] Dashboard disconnected (Remaining: ${adminSockets.size})`);
  });
}

function handleAdminCommand(cmd) {
  const { targetId, action } = cmd;
  console.log(`[Admin Command] Action: ${action} -> Target: ${targetId || 'ALL'}`);

  const targetStation = stations.get(targetId);
  const clientWs = clientSockets.get(targetId);

  switch (action) {
    case 'lock':
      if (targetStation) {
        targetStation.isLocked = true;
        targetStation.sessionSeconds = 0;
        broadcastToAdmins({ type: 'station_update', station: targetStation });
      }
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({ action: 'lock', message: cmd.message || 'Locked by Administrator' }));
      }
      break;

    case 'unlock':
      if (targetStation) {
        targetStation.isLocked = false;
        broadcastToAdmins({ type: 'station_update', station: targetStation });
      }
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({ action: 'unlock' }));
      }
      break;

    case 'start_session': {
      const durationSeconds = Number(cmd.durationSeconds) || 3600;
      if (targetStation) {
        targetStation.isLocked = false;
        targetStation.sessionSeconds = durationSeconds;
        targetStation.sessionTotalSeconds = durationSeconds;
        broadcastToAdmins({ type: 'station_update', station: targetStation });
      }
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({ action: 'unlock' }));
      }
      break;
    }

    case 'add_time': {
      const addSeconds = Number(cmd.seconds) || 1800;
      if (targetStation) {
        targetStation.sessionSeconds = (targetStation.sessionSeconds || 0) + addSeconds;
        targetStation.sessionTotalSeconds = (targetStation.sessionTotalSeconds || 0) + addSeconds;
        if (targetStation.isLocked) {
          targetStation.isLocked = false;
          if (clientWs && clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(JSON.stringify({ action: 'unlock' }));
          }
        }
        broadcastToAdmins({ type: 'station_update', station: targetStation });
      }
      break;
    }

    case 'stop_session':
      if (targetStation) {
        targetStation.isLocked = true;
        targetStation.sessionSeconds = 0;
        broadcastToAdmins({ type: 'station_update', station: targetStation });
      }
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({ action: 'lock', message: 'Session stopped by Administrator' }));
      }
      break;

    case 'alert':
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({
          action: 'alert',
          title: cmd.title || 'Admin Announcement',
          message: cmd.message || 'Notification from Game Room Admin'
        }));
      }
      break;

    case 'restart':
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({ action: 'restart' }));
      }
      break;

    case 'shutdown':
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify({ action: 'shutdown' }));
      }
      break;

    case 'get_screen':
    case 'get_drives':
    case 'browse_dir':
    case 'exec_file':
    case 'download_file':
      if (clientWs && clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(JSON.stringify(cmd));
      }
      break;
  }
}

// ----------------- WINDOWS CLIENT HANDLER -----------------
function handleClientConnection(ws, req) {
  let stationId = null;
  const remoteIp = req.socket.remoteAddress;

  console.log(`[Client] Connection received from ${remoteIp}`);

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());

      if (msg.type === 'register') {
        if (AUTH_TOKEN && msg.authToken !== AUTH_TOKEN) {
          console.warn(`[Security] Rejected unauthorized registration from ${remoteIp} (Invalid token)`);
          ws.send(JSON.stringify({ error: 'Unauthorized: Invalid auth token' }));
          ws.close(4001, 'Unauthorized');
          return;
        }

        stationId = msg.stationId || 'laptop-unknown';
        clientSockets.set(stationId, ws);

        const existing = stations.get(stationId) || {};
        const stationState = {
          ...existing,
          id: stationId,
          name: msg.stationName || stationId,
          hostname: msg.hostname || 'Unknown-PC',
          os: msg.os || 'Windows',
          ip: msg.ip || remoteIp,
          status: 'online',
          isLocked: existing.isLocked !== undefined ? existing.isLocked : false,
          sessionSeconds: existing.sessionSeconds || 0,
          sessionTotalSeconds: existing.sessionTotalSeconds || 0,
          lastSeen: Date.now()
        };

        stations.set(stationId, stationState);
        console.log(`[Client Registered] ${stationState.name} (${stationId}) - ${stationState.ip}`);

        // Broadcast to admins
        broadcastToAdmins({ type: 'station_connected', station: stationState });

        // Enforce lock state if station was previously locked
        if (stationState.isLocked) {
          ws.send(JSON.stringify({ action: 'lock', message: 'Station is currently locked' }));
        }
      } else if (msg.type === 'telemetry') {
        stationId = msg.stationId || stationId;
        if (!stationId) return;

        const station = stations.get(stationId);
        if (station) {
          station.status = 'online';
          station.cpu = msg.cpu ?? station.cpu;
          station.ram = msg.ram ?? station.ram;
          station.ramTotalGb = msg.ramTotalGb ?? station.ramTotalGb;
          station.ramUsedGb = msg.ramUsedGb ?? station.ramUsedGb;
          station.battery = msg.battery ?? station.battery;
          station.isCharging = msg.isCharging ?? station.isCharging;
          station.batteryStatus = msg.batteryStatus ?? station.batteryStatus;
          station.activeWindow = msg.activeWindow || 'Desktop';
          station.isLocked = msg.isLocked !== undefined ? msg.isLocked : station.isLocked;
          station.lastSeen = Date.now();

          broadcastToAdmins({ type: 'station_update', station });
        }
      } else if (['screen_frame', 'drives_listing', 'dir_listing', 'exec_result', 'download_progress', 'download_status'].includes(msg.type)) {
        broadcastToAdmins(msg);
      }
    } catch (err) {
      console.error('[Client] Message error:', err.message);
    }
  });

  ws.on('close', () => {
    if (stationId) {
      console.log(`[Client Disconnected] ${stationId}`);
      clientSockets.delete(stationId);

      const station = stations.get(stationId);
      if (station) {
        station.status = 'offline';
        broadcastToAdmins({ type: 'station_update', station });
      }
    }
  });

  ws.on('error', (err) => {
    console.error(`[Client Socket Error] ${stationId}:`, err.message);
  });
}

// ----------------- SESSION COUNTDOWN TIMER -----------------
// Runs every 1 second to update active sessions
setInterval(() => {
  let anyUpdated = false;

  for (const station of stations.values()) {
    if (station.sessionSeconds > 0 && !station.isLocked) {
      station.sessionSeconds -= 1;
      anyUpdated = true;

      // When session time expires: Auto-lock!
      if (station.sessionSeconds <= 0) {
        station.sessionSeconds = 0;
        station.isLocked = true;

        console.log(`[Session Expired] Locking station: ${station.name} (${station.id})`);
        const clientWs = clientSockets.get(station.id);
        if (clientWs && clientWs.readyState === WebSocket.OPEN) {
          clientWs.send(JSON.stringify({
            action: 'lock',
            message: 'Your gaming time has ended! Please contact administrator.'
          }));
        }
      }
    }
  }

  if (anyUpdated) {
    broadcastToAdmins({ type: 'session_tick', stations: getStationsSnapshot() });
  }
}, 1000);

// Start server
server.listen(PORT, '0.0.0.0', () => {
  const lanIp = getLocalIp();
  console.log('========================================================');
  console.log('🎮  GAME ROOM PC MANAGEMENT SERVER IS RUNNING!');
  console.log('========================================================');
  console.log(`🖥️   Mac Local Dashboard:  http://localhost:${PORT}`);
  console.log(`📱  LAN Access (Phone/Mac): http://${lanIp}:${PORT}`);
  console.log(`🔌  Windows Agent URL:      ws://${lanIp}:${PORT}/ws/client`);
  console.log('========================================================');
  console.log('Ready to connect gaming laptop client.');
});
