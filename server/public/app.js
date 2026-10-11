let ws = null;
const stations = new Map();
let activeTargetStationId = null;
let pendingPowerAction = null;

// DOM Elements
const serverStatusDot = document.getElementById('serverStatusDot');
const serverStatusText = document.getElementById('serverStatusText');
const liveClock = document.getElementById('liveClock');
const stationsGrid = document.getElementById('stationsGrid');
const emptyState = document.getElementById('emptyState');
const wsHintUrl = document.getElementById('wsHintUrl');

// Stats Elements
const statTotal = document.getElementById('statTotal');
const statOnline = document.getElementById('statOnline');
const statInSession = document.getElementById('statInSession');
const statLocked = document.getElementById('statLocked');
const stationCountTag = document.getElementById('stationCountTag');

// Clock Ticker
setInterval(() => {
  const now = new Date();
  liveClock.textContent = now.toTimeString().split(' ')[0];
}, 1000);

// Initialize hint URL with current location host
if (wsHintUrl) {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  wsHintUrl.textContent = `${protocol}//${window.location.host}/ws/client`;
}

// Connect to Admin WebSocket
function connectWebSocket() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const url = `${protocol}//${window.location.host}/ws/admin`;

  serverStatusText.textContent = 'Connecting...';
  serverStatusDot.className = 'status-dot';

  ws = new WebSocket(url);

  ws.onopen = () => {
    serverStatusText.textContent = 'Server Online';
    serverStatusDot.className = 'status-dot pulse-green';
  };

  ws.onmessage = (event) => {
    try {
      const data = JSON.parse(event.data);
      handleServerMessage(data);
    } catch (err) {
      console.error('Failed to parse server message:', err);
    }
  };

  ws.onclose = () => {
    serverStatusText.textContent = 'Disconnected (Retrying)';
    serverStatusDot.className = 'status-dot pulse-red';
    setTimeout(connectWebSocket, 3000);
  };

  ws.onerror = () => {
    ws.close();
  };
}

function sendAdminCommand(action, targetId, extra = {}) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({
      action,
      targetId,
      ...extra
    }));
  } else {
    alert('Server is currently disconnected. Cannot send command.');
  }
}

function handleServerMessage(msg) {
  switch (msg.type) {
    case 'init':
      stations.clear();
      if (Array.isArray(msg.stations)) {
        for (const st of msg.stations) {
          stations.set(st.id, st);
        }
      }
      renderStations();
      break;

    case 'station_connected':
    case 'station_update':
      if (msg.station) {
        stations.set(msg.station.id, msg.station);
        renderStations();
      }
      break;

    case 'session_tick':
      if (Array.isArray(msg.stations)) {
        for (const st of msg.stations) {
          stations.set(st.id, st);
        }
        renderStations();
      }
      break;
  }
}

function updateSummaryStats() {
  const list = Array.from(stations.values());
  const total = list.length;
  const online = list.filter(s => s.status === 'online').length;
  const inSession = list.filter(s => s.status === 'online' && !s.isLocked && (s.sessionSeconds || 0) > 0).length;
  const locked = list.filter(s => s.status === 'online' && s.isLocked).length;

  statTotal.textContent = total;
  statOnline.textContent = online;
  statInSession.textContent = inSession;
  statLocked.textContent = locked;
  stationCountTag.textContent = `${total} ${total === 1 ? 'Device' : 'Devices'}`;
}

function formatSeconds(totalSec) {
  if (!totalSec || totalSec <= 0) return '00:00:00';
  const hrs = Math.floor(totalSec / 3600);
  const mins = Math.floor((totalSec % 3600) / 60);
  const secs = totalSec % 60;
  return `${String(hrs).padStart(2, '0')}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

function getProgressColorClass(percent) {
  if (percent >= 85) return 'fill-ruby';
  if (percent >= 60) return 'fill-amber';
  return 'fill-emerald';
}

function renderStations() {
  updateSummaryStats();

  const list = Array.from(stations.values());

  if (list.length === 0) {
    emptyState.style.display = 'block';
    return;
  }

  emptyState.style.display = 'none';

  for (const st of list) {
    let card = document.getElementById(`station-${st.id}`);
    const isOnline = st.status === 'online';
    const isLocked = st.isLocked;
    const sessionSec = st.sessionSeconds || 0;
    const cpu = st.cpu ?? 0;
    const ram = st.ram ?? 0;
    const ramText = st.ramUsedGb ? `${st.ramUsedGb} / ${st.ramTotalGb} GB` : `${ram}%`;
    const battery = st.battery ?? 100;
    const isCharging = st.isCharging ?? true;
    const activeApp = st.activeWindow || 'Desktop';

    const cardClass = !isOnline 
      ? 'station-card offline-card' 
      : isLocked 
        ? 'station-card locked-card' 
        : 'station-card active-card';

    if (!card) {
      card = document.createElement('div');
      card.id = `station-${st.id}`;
      stationsGrid.appendChild(card);
    }

    card.className = cardClass;
    card.innerHTML = `
      <div class="card-header">
        <div class="station-meta">
          <h3>
            <span>💻</span> ${st.name || st.id}
          </h3>
          <div class="station-sub">${st.hostname || 'Windows PC'} &bull; ${st.ip || 'LAN'}</div>
        </div>
        <div class="badges-group">
          <span class="badge ${isOnline ? 'badge-online' : 'badge-offline'}">
            ${isOnline ? '● ONLINE' : '○ OFFLINE'}
          </span>
          <span class="badge ${isLocked ? 'badge-locked' : 'badge-unlocked'}">
            ${isLocked ? '🔒 LOCKED' : '🟢 UNLOCKED'}
          </span>
        </div>
      </div>

      <!-- METRICS -->
      <div class="metrics-row">
        <div class="metric-box">
          <span class="metric-title">CPU USAGE</span>
          <span class="metric-number">${cpu}%</span>
          <div class="progress-track">
            <div class="progress-fill ${getProgressColorClass(cpu)}" style="width: ${cpu}%"></div>
          </div>
        </div>

        <div class="metric-box">
          <span class="metric-title">RAM USAGE</span>
          <span class="metric-number">${ram}%</span>
          <div class="progress-track">
            <div class="progress-fill ${getProgressColorClass(ram)}" style="width: ${ram}%"></div>
          </div>
        </div>

        <div class="metric-box">
          <span class="metric-title">BATTERY / POWER</span>
          <span class="metric-number">${battery}% ${isCharging ? '⚡' : '🔋'}</span>
          <div class="progress-track">
            <div class="progress-fill fill-emerald" style="width: ${battery}%"></div>
          </div>
        </div>
      </div>

      <!-- ACTIVE GAME / WINDOW -->
      <div class="active-app-box">
        <span class="active-app-icon">🎯</span>
        <div class="active-app-text" title="${activeApp}">
          <span class="active-app-label">Active:</span> ${activeApp}
        </div>
      </div>

      <!-- SESSION TIMER -->
      <div class="session-panel">
        <div class="session-header">
          <span class="session-label">SESSION TIME REMAINING</span>
          <span class="session-countdown">${formatSeconds(sessionSec)}</span>
        </div>
        <div class="time-btn-group">
          <button class="time-chip" onclick="addStationTime('${st.id}', 900)">+15m</button>
          <button class="time-chip" onclick="addStationTime('${st.id}', 1800)">+30m</button>
          <button class="time-chip" onclick="addStationTime('${st.id}', 3600)">+1h</button>
          <button class="time-chip" onclick="addStationTime('${st.id}', 7200)">+2h</button>
        </div>
      </div>

      <!-- ACTION CONTROLS -->
      <div class="action-toolbar">
        ${isLocked ? `
          <button class="btn btn-unlock" onclick="unlockStation('${st.id}')">
            🔓 Unlock Now
          </button>
        ` : `
          <button class="btn btn-lock" onclick="lockStation('${st.id}')">
            🔒 Lock Now
          </button>
        `}
        <button class="btn btn-alert" onclick="openAlertModal('${st.id}')">
          📢 Message
        </button>
        <button class="btn btn-power" onclick="confirmPowerAction('${st.id}', 'restart')">
          🔄 Restart
        </button>
        <button class="btn btn-power" onclick="confirmPowerAction('${st.id}', 'shutdown')">
          ⏻ Shutdown
        </button>
      </div>
    `;
  }
}

// Actions
function lockStation(id) {
  sendAdminCommand('lock', id, { message: 'Station locked by Administrator' });
}

function unlockStation(id) {
  sendAdminCommand('unlock', id);
}

function addStationTime(id, seconds) {
  sendAdminCommand('add_time', id, { seconds });
}

// Alert Modal
function openAlertModal(id) {
  activeTargetStationId = id;
  document.getElementById('alertModal').classList.add('open');
  document.getElementById('alertMessageInput').focus();
}

function closeAlertModal() {
  document.getElementById('alertModal').classList.remove('open');
  activeTargetStationId = null;
}

function submitAlert() {
  if (!activeTargetStationId) return;
  const title = document.getElementById('alertTitleInput').value.trim() || 'Admin Notice';
  const message = document.getElementById('alertMessageInput').value.trim();

  if (!message) {
    alert('Please enter a message.');
    return;
  }

  sendAdminCommand('alert', activeTargetStationId, { title, message });
  document.getElementById('alertMessageInput').value = '';
  closeAlertModal();
}

// Power Modal
function confirmPowerAction(id, action) {
  activeTargetStationId = id;
  pendingPowerAction = action;
  
  const titleElem = document.getElementById('powerModalTitle');
  const promptElem = document.getElementById('powerModalPrompt');
  const confirmBtn = document.getElementById('confirmPowerBtn');

  if (action === 'restart') {
    titleElem.textContent = '🔄 Confirm Laptop Restart';
    promptElem.textContent = `Are you sure you want to RESTART station [${id}]? The laptop will reboot in 5 seconds.`;
  } else {
    titleElem.textContent = '⏻ Confirm Laptop Shutdown';
    promptElem.textContent = `Are you sure you want to SHUT DOWN station [${id}]? The laptop will power off in 5 seconds.`;
  }

  confirmBtn.onclick = () => {
    sendAdminCommand(pendingPowerAction, activeTargetStationId);
    closePowerModal();
  };

  document.getElementById('powerModal').classList.add('open');
}

function closePowerModal() {
  document.getElementById('powerModal').classList.remove('open');
  activeTargetStationId = null;
  pendingPowerAction = null;
}

// Initialize on page load
connectWebSocket();
