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
      if (msg.station) {
        stations.set(msg.station.id, msg.station);
        renderStations();
        if (window.electronMac) {
          window.electronMac.sendNotification('Laptop Online 💻', `${msg.station.name || msg.station.id} connected`);
        }
      }
      break;

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

    case 'screen_frame':
      handleScreenFrame(msg);
      break;

    case 'drives_listing':
      handleDrivesListing(msg);
      break;

    case 'dir_listing':
      handleDirListing(msg);
      break;

    case 'exec_result':
      alert(`[Execute Result]: ${msg.message}`);
      break;

    case 'download_progress':
      handleDownloadProgress(msg);
      break;

    case 'download_status':
      handleDownloadStatus(msg);
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

  if (window.electronMac) {
    window.electronMac.setBadge(online);
  }
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
        <button class="btn btn-direct-control" onclick="openDirectControlModal('${st.id}')">
          ⚡ Direct Control (60 FPS LAN)
        </button>
        ${isLocked ? `
          <button class="btn btn-unlock" onclick="unlockStation('${st.id}')">
            🔓 Unlock
          </button>
        ` : `
          <button class="btn btn-lock" onclick="lockStation('${st.id}')">
            🔒 Lock
          </button>
        `}
        <button class="btn btn-alert" onclick="openAlertModal('${st.id}')">
          📢 Message
        </button>
        <button class="btn btn-primary" onclick="openScreenModal('${st.id}')">
          📺 View Screen
        </button>
        <button class="btn btn-secondary" onclick="openFilesModal('${st.id}')">
          📁 Files & Games
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

// ==================== SCREEN VIEWER ====================
let screenStreamInterval = null;

function openScreenModal(stationId) {
  activeTargetStationId = stationId;
  const modal = document.getElementById('screenModal');
  const title = document.getElementById('screenModalTitle');
  const placeholder = document.getElementById('screenPlaceholder');
  const img = document.getElementById('screenImg');
  const streamBtn = document.getElementById('streamToggleBtn');

  title.textContent = `📺 Remote Screen: ${stations.get(stationId)?.name || stationId}`;
  img.style.display = 'none';
  placeholder.style.display = 'block';
  placeholder.textContent = 'Requesting screen snapshot from laptop...';
  streamBtn.textContent = '▶ Live Stream (1 FPS)';
  if (screenStreamInterval) {
    clearInterval(screenStreamInterval);
    screenStreamInterval = null;
  }

  modal.classList.add('open');
  requestScreenSnapshot();
}

function closeScreenModal() {
  const modal = document.getElementById('screenModal');
  modal.classList.remove('open');
  if (screenStreamInterval) {
    clearInterval(screenStreamInterval);
    screenStreamInterval = null;
  }
}

function requestScreenSnapshot() {
  if (!activeTargetStationId) return;
  sendAdminCommand('get_screen', activeTargetStationId);
}

function toggleScreenStream() {
  const streamBtn = document.getElementById('streamToggleBtn');
  if (screenStreamInterval) {
    clearInterval(screenStreamInterval);
    screenStreamInterval = null;
    streamBtn.textContent = '▶ Live Stream (1 FPS)';
    streamBtn.classList.remove('btn-primary');
    streamBtn.classList.add('btn-secondary');
  } else {
    requestScreenSnapshot();
    screenStreamInterval = setInterval(requestScreenSnapshot, 1000);
    streamBtn.textContent = '⏹ Stop Stream';
    streamBtn.classList.remove('btn-secondary');
    streamBtn.classList.add('btn-primary');
  }
}

function handleScreenFrame(msg) {
  if (msg.stationId !== activeTargetStationId) return;
  const placeholder = document.getElementById('screenPlaceholder');
  const img = document.getElementById('screenImg');
  const metaTime = document.getElementById('screenMetaTime');

  if (msg.image) {
    placeholder.style.display = 'none';
    img.style.display = 'block';
    img.src = `data:image/jpeg;base64,${msg.image}`;
    const date = new Date(msg.timestamp || Date.now());
    metaTime.textContent = `Snapshot Received: ${date.toLocaleTimeString()}`;
  }
}

// ==================== REMOTE FILES & GAME INSTALLER ====================
let currentBrowsedPath = '';
let parentBrowsedPath = null;

function openFilesModal(stationId) {
  activeTargetStationId = stationId;
  const modal = document.getElementById('filesModal');
  const title = document.getElementById('filesModalTitle');
  title.textContent = `📁 Remote Files & Game Installer: ${stations.get(stationId)?.name || stationId}`;

  document.getElementById('drivesButtons').innerHTML = 'Scanning drives...';
  document.getElementById('filesTableBody').innerHTML = '<tr><td colspan="4" class="text-center text-muted">Reading laptop file system...</td></tr>';
  document.getElementById('downloadProgressBox').style.display = 'none';

  modal.classList.add('open');

  // Request available drives and default directory
  sendAdminCommand('get_drives', stationId);
  sendAdminCommand('browse_dir', stationId, { path: '' });
}

function closeFilesModal() {
  document.getElementById('filesModal').classList.remove('open');
}

function handleDrivesListing(msg) {
  if (msg.stationId !== activeTargetStationId) return;
  const container = document.getElementById('drivesButtons');
  container.innerHTML = '';

  if (!msg.drives || msg.drives.length === 0) {
    container.textContent = 'No drives found.';
    return;
  }

  for (const d of msg.drives) {
    const btn = document.createElement('button');
    btn.className = 'drive-chip';
    btn.textContent = `💽 ${d.Name} (${d.FreeGb} GB free / ${d.TotalGb} GB)`;
    btn.onclick = () => {
      document.querySelectorAll('.drive-chip').forEach(c => c.classList.remove('active'));
      btn.classList.add('active');
      browsePath(d.Name);
    };
    container.appendChild(btn);
  }
}

function handleDirListing(msg) {
  if (msg.stationId !== activeTargetStationId) return;
  const res = msg.result;
  const tableBody = document.getElementById('filesTableBody');
  const pathDisplay = document.getElementById('currentPathDisplay');
  const upBtn = document.getElementById('btnParentDir');

  if (res.error) {
    tableBody.innerHTML = `<tr><td colspan="4" style="color: var(--color-ruby); padding: 12px;">Error: ${res.error}</td></tr>`;
    return;
  }

  currentBrowsedPath = res.CurrentPath;
  parentBrowsedPath = res.ParentPath;
  pathDisplay.value = currentBrowsedPath;
  upBtn.disabled = !parentBrowsedPath;

  tableBody.innerHTML = '';

  if (!res.Items || res.Items.length === 0) {
    tableBody.innerHTML = '<tr><td colspan="4" class="text-center text-muted" style="padding: 16px;">This folder is empty.</td></tr>';
    return;
  }

  for (const item of res.Items) {
    const tr = document.createElement('tr');
    tr.className = 'file-row';

    if (item.IsDirectory) {
      tr.innerHTML = `
        <td><a class="folder-link" onclick="browsePath('${escapePath(item.FullPath)}')">📁 ${item.Name}</a></td>
        <td class="text-muted">&lt;DIR&gt;</td>
        <td class="text-muted">${item.LastModified}</td>
        <td>-</td>
      `;
    } else {
      let actionHtml = '-';
      if (item.IsExecutable) {
        actionHtml = `<button class="btn-install" onclick="runRemoteFile('${escapePath(item.FullPath)}')">▶ Run / Install</button>`;
      }

      tr.innerHTML = `
        <td><span>📄 ${item.Name}</span></td>
        <td>${item.SizeFormatted}</td>
        <td class="text-muted">${item.LastModified}</td>
        <td>${actionHtml}</td>
      `;
    }

    tableBody.appendChild(tr);
  }
}

function escapePath(path) {
  return (path || '').replace(/\\/g, '\\\\');
}

function browsePath(path) {
  if (!activeTargetStationId) return;
  document.getElementById('filesTableBody').innerHTML = '<tr><td colspan="4" class="text-center text-muted" style="padding: 16px;">Loading directory...</td></tr>';
  sendAdminCommand('browse_dir', activeTargetStationId, { path });
}

function navigateParentDir() {
  if (parentBrowsedPath) {
    browsePath(parentBrowsedPath);
  }
}

function refreshCurrentDir() {
  if (currentBrowsedPath) {
    browsePath(currentBrowsedPath);
  }
}

function runRemoteFile(filePath) {
  if (!confirm(`Are you sure you want to run this installer/program on the laptop?\n\nFile: ${filePath}`)) {
    return;
  }

  sendAdminCommand('exec_file', activeTargetStationId, { filePath });
}

function startRemoteDownload() {
  const urlInput = document.getElementById('downloadUrlInput');
  const nameInput = document.getElementById('downloadFileNameInput');
  const url = urlInput.value.trim();
  const fileName = nameInput.value.trim() || null;

  if (!url) {
    alert('Please enter a valid direct download URL.');
    return;
  }

  const destinationFolder = currentBrowsedPath || 'C:\\Games';
  const progressBox = document.getElementById('downloadProgressBox');
  const progressBar = document.getElementById('downloadProgressBar');
  const statusLabel = document.getElementById('downloadStatusLabel');

  progressBox.style.display = 'block';
  progressBar.style.width = '0%';
  statusLabel.textContent = `Sending download request for ${url}...`;

  sendAdminCommand('download_file', activeTargetStationId, {
    url,
    destinationFolder,
    fileName
  });

  urlInput.value = '';
  nameInput.value = '';
}

function handleDownloadProgress(msg) {
  if (msg.stationId !== activeTargetStationId) return;
  const progressBar = document.getElementById('downloadProgressBar');
  const statusLabel = document.getElementById('downloadStatusLabel');
  progressBar.style.width = `${msg.percent}%`;
  statusLabel.textContent = `Downloading installer: ${msg.percent}%`;
}

function handleDownloadStatus(msg) {
  if (msg.stationId !== activeTargetStationId) return;
  const statusLabel = document.getElementById('downloadStatusLabel');
  statusLabel.textContent = msg.message;
  if (msg.status === 'completed') {
    setTimeout(() => {
      refreshCurrentDir();
    }, 1500);
  }
}

// ==================== DIRECT LAN 60 FPS REMOTE CONTROL ====================
let directControlWs = null;
let directStation = null;
let directInputEnabled = true;
let directFpsCount = 0;
let directFpsTimer = null;
let directLastFpsTime = Date.now();
let directPingTimer = null;

function openDirectControlModal(stationId) {
  const st = stations.get(stationId);
  if (!st) return;
  startDirectSession(st);
}

function startDirectSession(st) {
  directStation = st;
  const ip = st.ip || '127.0.0.1';
  const port = st.controlPort || 48999;

  document.getElementById('directControlModalTitle').textContent = `⚡ Direct LAN Control — ${st.name || st.id}`;
  document.getElementById('directIpBadge').textContent = `${ip}:${port}`;
  document.getElementById('directFpsBadge').textContent = '0 FPS';
  document.getElementById('directPingBadge').textContent = '... ms';
  document.getElementById('directConnectingOverlay').style.display = 'block';
  document.getElementById('directConnectingText').textContent = `Connecting directly to ${ip}:${port} over local network...`;

  document.getElementById('directControlModal').classList.add('open');

  const canvas = document.getElementById('directCanvas');
  const ctx = canvas.getContext('2d');
  canvas.focus();

  if (directControlWs) {
    directControlWs.close();
  }

  const wsUrl = `ws://${ip}:${port}/control`;
  console.log('[Direct LAN] Connecting to', wsUrl);

  try {
    directControlWs = new WebSocket(wsUrl);
    directControlWs.binaryType = 'blob';

    let lastPingSend = Date.now();

    directControlWs.onopen = () => {
      console.log('[Direct LAN] Connected to gaming laptop directly!');
      document.getElementById('directConnectingOverlay').style.display = 'none';

      // Send initial settings
      directControlWs.send(JSON.stringify({ type: 'set_fps', fps: 60 }));
      directControlWs.send(JSON.stringify({ type: 'set_quality', quality: 65 }));

      // Ping measurement
      clearInterval(directPingTimer);
      directPingTimer = setInterval(() => {
        if (directControlWs && directControlWs.readyState === WebSocket.OPEN) {
          lastPingSend = Date.now();
          directControlWs.send(JSON.stringify({ type: 'ping' }));
        }
      }, 2000);
    };

    directControlWs.onmessage = (event) => {
      if (typeof event.data === 'string') {
        const pingMs = Math.max(1, Date.now() - lastPingSend);
        document.getElementById('directPingBadge').textContent = `${pingMs} ms`;
        return;
      }

      // Binary JPEG frame
      const blob = event.data;
      const img = new Image();
      const url = URL.createObjectURL(blob);
      img.onload = () => {
        if (canvas.width !== img.width || canvas.height !== img.height) {
          canvas.width = img.width;
          canvas.height = img.height;
        }
        ctx.drawImage(img, 0, 0);
        URL.revokeObjectURL(url);

        // FPS measurement
        directFpsCount++;
        const now = Date.now();
        if (now - directLastFpsTime >= 1000) {
          const fps = Math.round((directFpsCount * 1000) / (now - directLastFpsTime));
          document.getElementById('directFpsBadge').textContent = `${fps} FPS`;
          directFpsCount = 0;
          directLastFpsTime = now;
        }
      };
      img.src = url;
    };

    directControlWs.onerror = () => {
      document.getElementById('directConnectingText').textContent = `Could not connect to ${ip}:${port}. Ensure laptop is running agent and on same Wi-Fi.`;
    };

    directControlWs.onclose = () => {
      clearInterval(directPingTimer);
      console.log('[Direct LAN] Disconnected');
    };
  } catch (err) {
    document.getElementById('directConnectingText').textContent = `Connection error: ${err.message}`;
  }

  setupDirectInputListeners(canvas);
}

function setupDirectInputListeners(canvas) {
  // Remove existing listeners to avoid duplicates
  canvas.onmousemove = (e) => {
    if (!directInputEnabled || !directControlWs || directControlWs.readyState !== WebSocket.OPEN) return;
    const rect = canvas.getBoundingClientRect();
    const x = Math.min(Math.max(0, (e.clientX - rect.left) / rect.width), 1);
    const y = Math.min(Math.max(0, (e.clientY - rect.top) / rect.height), 1);
    directControlWs.send(JSON.stringify({ type: 'mouse_move', x, y }));
  };

  canvas.onmousedown = (e) => {
    if (!directInputEnabled || !directControlWs || directControlWs.readyState !== WebSocket.OPEN) return;
    canvas.focus();
    const btn = e.button === 2 ? 'right' : e.button === 1 ? 'middle' : 'left';
    directControlWs.send(JSON.stringify({ type: 'mouse_down', button: btn }));
  };

  canvas.onmouseup = (e) => {
    if (!directInputEnabled || !directControlWs || directControlWs.readyState !== WebSocket.OPEN) return;
    const btn = e.button === 2 ? 'right' : e.button === 1 ? 'middle' : 'left';
    directControlWs.send(JSON.stringify({ type: 'mouse_up', button: btn }));
  };

  canvas.oncontextmenu = (e) => {
    e.preventDefault();
  };

  canvas.onwheel = (e) => {
    if (!directInputEnabled || !directControlWs || directControlWs.readyState !== WebSocket.OPEN) return;
    e.preventDefault();
    const delta = e.deltaY < 0 ? 120 : -120;
    directControlWs.send(JSON.stringify({ type: 'mouse_wheel', delta }));
  };

  canvas.onkeydown = (e) => {
    if (!directInputEnabled || !directControlWs || directControlWs.readyState !== WebSocket.OPEN) return;
    e.preventDefault();
    directControlWs.send(JSON.stringify({ type: 'key_down', vk: e.keyCode }));
  };

  canvas.onkeyup = (e) => {
    if (!directInputEnabled || !directControlWs || directControlWs.readyState !== WebSocket.OPEN) return;
    e.preventDefault();
    directControlWs.send(JSON.stringify({ type: 'key_up', vk: e.keyCode }));
  };
}

function toggleDirectInput() {
  directInputEnabled = !directInputEnabled;
  const btn = document.getElementById('btnDirectToggleInput');
  btn.textContent = directInputEnabled ? '🎮 Control: ON' : '👁️ View Only';
  btn.style.background = directInputEnabled ? '#6366f1' : 'rgba(255,255,255,0.1)';
}

function sendDirectSpecialKey(key) {
  if (directControlWs && directControlWs.readyState === WebSocket.OPEN) {
    directControlWs.send(JSON.stringify({ type: 'special_key', key }));
  }
}

function openDirectMoonlight() {
  if (directStation && directStation.ip) {
    window.location.href = `moonlight://${directStation.ip}`;
  }
}

function openDirectRDP() {
  if (directStation && directStation.ip) {
    window.location.href = `rdp://${directStation.ip}`;
  }
}

function closeDirectControlModal() {
  document.getElementById('directControlModal').classList.remove('open');
  if (directControlWs) {
    directControlWs.close();
    directControlWs = null;
  }
  clearInterval(directPingTimer);
}

// ==================== MANUAL DIRECT CONNECT MODAL ====================
function openDirectConnectModal() {
  document.getElementById('directConnectModal').classList.add('open');
  document.getElementById('manualIpInput').focus();
}

function closeDirectConnectModal() {
  document.getElementById('directConnectModal').classList.remove('open');
}

function submitManualDirectConnect() {
  const ip = document.getElementById('manualIpInput').value.trim();
  const port = parseInt(document.getElementById('manualPortInput').value.trim()) || 48999;
  if (!ip) return;

  closeDirectConnectModal();
  startDirectSession({
    id: `manual-${ip}`,
    name: `Gaming Laptop (${ip})`,
    ip,
    controlPort: port
  });
}

// ==================== DEMO PC CARD ====================
function addDemoStation() {
  const demo = {
    id: 'rog-demo-01',
    name: 'ASUS ROG Strix (Demo)',
    hostname: 'ROG-STRIX-G16',
    os: 'Windows 11 Pro',
    ip: '192.168.1.105',
    controlPort: 48999,
    status: 'online',
    isLocked: false,
    sessionSeconds: 2700,
    sessionTotalSeconds: 3600,
    cpu: 48,
    ram: 64,
    ramTotalGb: 32.0,
    ramUsedGb: 20.4,
    battery: 95,
    isCharging: true,
    batteryStatus: 'Plugged in (Fast Charge)',
    activeWindow: 'Cyberpunk 2077',
    lastSeen: Date.now()
  };
  stations.set(demo.id, demo);
  renderStations();
}

// Initialize on page load
connectWebSocket();

