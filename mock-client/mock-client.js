const { WebSocket } = require('../server/node_modules/ws');

const SERVER_URL = process.env.SERVER_URL || 'ws://localhost:3000/ws/client';
const STATION_ID = 'laptop-01';
const STATION_NAME = 'ROG Strix G16 (Demo)';

console.log('====================================================');
console.log('🤖 MOCK WINDOWS GAMING LAPTOP CLIENT');
console.log('====================================================');
console.log(`Connecting to: ${SERVER_URL}`);

let isLocked = false;
let battery = 92;
const games = [
  'Counter-Strike 2 (Matchmaking)',
  'Cyberpunk 2077: Phantom Liberty',
  'Valorant (Competitive)',
  'Dota 2',
  'Grand Theft Auto V',
  'Steam Client'
];
let currentGameIdx = 0;

function connect() {
  const ws = new WebSocket(SERVER_URL);

  ws.on('open', () => {
    console.log(' Connected to Mac Server as Windows Gaming Laptop!');

    // Send registration
    ws.send(JSON.stringify({
      type: 'register',
      stationId: STATION_ID,
      stationName: STATION_NAME,
      hostname: 'ROG-STRIX-WIN11',
      os: 'Microsoft Windows 11 Pro 64-bit (10.0.22631)',
      ip: '192.168.1.125'
    }));

    // Start telemetry loop every 3 seconds
    const interval = setInterval(() => {
      if (ws.readyState !== WebSocket.OPEN) {
        clearInterval(interval);
        return;
      }

      // Slightly fluctuate metrics
      const cpu = Math.floor(25 + Math.random() * 45); // 25% - 70%
      const ram = Math.floor(55 + Math.random() * 20); // 55% - 75%
      battery = Math.max(20, battery - (Math.random() > 0.8 ? 1 : 0));
      if (Math.random() > 0.85) {
        currentGameIdx = (currentGameIdx + 1) % games.length;
      }

      ws.send(JSON.stringify({
        type: 'telemetry',
        stationId: STATION_ID,
        cpu,
        ram,
        ramTotalGb: 32.0,
        ramUsedGb: parseFloat(((32.0 * ram) / 100).toFixed(1)),
        battery,
        isCharging: true,
        batteryStatus: 'Plugged in (High Performance)',
        activeWindow: isLocked ? 'STATION LOCKED OVERLAY' : games[currentGameIdx],
        isLocked
      }));
    }, 3000);
  });

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      console.log('\n[COMMAND RECEIVED FROM MAC DASHBOARD]');
      console.log(JSON.stringify(msg, null, 2));

      if (msg.action === 'lock') {
        isLocked = true;
        console.log('🔒 >>> LAPTOP LOCK SCREEN ENGAGED <<< 🔒');
        console.log(`Lock message: ${msg.message || 'Standard Lock'}`);
      } else if (msg.action === 'unlock') {
        isLocked = false;
        console.log('🟢 >>> LAPTOP UNLOCKED! GAME SESSION ACTIVE <<< 🟢');
      } else if (msg.action === 'alert') {
        console.log(`📢 >>> DIALOG POPUP: [${msg.title}] ${msg.message} <<<`);
      } else if (msg.action === 'restart') {
        console.log('🔄 >>> SYSTEM RESTART SCHEDULED IN 5s <<<');
      } else if (msg.action === 'shutdown') {
        console.log('⏻ >>> SYSTEM SHUTDOWN SCHEDULED IN 5s <<<');
      }
    } catch (err) {
      console.error('Failed to parse command:', err);
    }
  });

  ws.on('close', () => {
    console.log('🔌 Disconnected from server. Reconnecting in 3 seconds...');
    setTimeout(connect, 3000);
  });

  ws.on('error', (err) => {
    console.error('Socket error:', err.message);
  });
}

connect();
