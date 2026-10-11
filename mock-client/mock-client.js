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
      authToken: process.env.AUTH_TOKEN || 'gameroom_secret_key_2026',
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
      } else if (msg.action === 'get_screen') {
        console.log('📺 >>> SCREEN CAPTURE REQUESTED: Sending mock frame <<<');
        // 1x1 transparent/cyan JPEG placeholder base64
        const mockFrame = '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';
        ws.send(JSON.stringify({
          type: 'screen_frame',
          stationId: STATION_ID,
          image: mockFrame,
          timestamp: Date.now()
        }));
      } else if (msg.action === 'get_drives') {
        console.log('💽 >>> DRIVES REQUESTED: Sending mock drives <<<');
        ws.send(JSON.stringify({
          type: 'drives_listing',
          stationId: STATION_ID,
          drives: [
            { Name: 'C:\\', Label: 'Windows NVMe', TotalGb: 512.0, FreeGb: 148.5, DriveType: 'Fixed' },
            { Name: 'D:\\', Label: 'Games SSD', TotalGb: 2048.0, FreeGb: 1120.2, DriveType: 'Fixed' }
          ]
        }));
      } else if (msg.action === 'browse_dir') {
        const path = msg.path || 'D:\\Games';
        console.log(`📁 >>> BROWSE DIR REQUESTED: ${path} <<<`);
        ws.send(JSON.stringify({
          type: 'dir_listing',
          stationId: STATION_ID,
          result: {
            CurrentPath: path,
            ParentPath: path.length > 3 ? 'D:\\' : null,
            Items: [
              { Name: 'Counter-Strike 2', FullPath: `${path}\\Counter-Strike 2`, IsDirectory: true, LastModified: '2026-10-10 14:20' },
              { Name: 'Valorant', FullPath: `${path}\\Valorant`, IsDirectory: true, LastModified: '2026-10-09 18:30' },
              { Name: 'Cyberpunk 2077', FullPath: `${path}\\Cyberpunk 2077`, IsDirectory: true, LastModified: '2026-10-05 21:00' },
              { Name: 'SteamSetup.exe', FullPath: `${path}\\SteamSetup.exe`, IsDirectory: false, SizeFormatted: '2.1 MB', IsExecutable: true, LastModified: '2026-10-11 10:15' },
              { Name: 'EpicInstaller.msi', FullPath: `${path}\\EpicInstaller.msi`, IsDirectory: false, SizeFormatted: '45.3 MB', IsExecutable: true, LastModified: '2026-10-08 11:00' }
            ]
          }
        }));
      } else if (msg.action === 'exec_file') {
        console.log(`▶ >>> LAUNCHING FILE REMOTELY: ${msg.filePath} <<<`);
        ws.send(JSON.stringify({
          type: 'exec_result',
          stationId: STATION_ID,
          success: true,
          message: `Process launched successfully: ${msg.filePath} (PID: 8420)`
        }));
      } else if (msg.action === 'download_file') {
        console.log(`⬇ >>> DOWNLOADING FILE: ${msg.url} to ${msg.destinationFolder} <<<`);
        let p = 0;
        const dlInt = setInterval(() => {
          p += 25;
          ws.send(JSON.stringify({ type: 'download_progress', stationId: STATION_ID, percent: Math.min(100, p) }));
          if (p >= 100) {
            clearInterval(dlInt);
            ws.send(JSON.stringify({
              type: 'download_status',
              stationId: STATION_ID,
              status: 'completed',
              message: `Successfully downloaded installer to ${msg.destinationFolder}`
            }));
          }
        }, 500);
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
