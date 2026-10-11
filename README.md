# 🎮 Game Room PC Management System

A lightweight, real-time gaming PC/laptop management and screen-locking system designed for gaming lounges, cybercafés, and LAN centers.

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────┐
│                  YOUR MAC                    │
│  - Node.js WebSocket + Web Server (Port 3000)│
│  - Real-time Cyberpunk Web Dashboard         │
│  - Accessible via Safari, Chrome, or Phone   │
└──────────────────────┬───────────────────────┘
                       │ WebSocket (LAN / Wi-Fi)
┌──────────────────────┴───────────────────────┐
│           WINDOWS GAMING LAPTOP              │
│  - C# (.NET 8) Native Agent                  │
│  - Real-time Hardware Telemetry (CPU/RAM/Bat)│
│  - Win32 Full-Screen Kiosk Lock Overlay      │
│  - Low-level Keyboard Hooks (WinKey/Alt+Tab) │
└──────────────────────────────────────────────┘
```

---

## 🚀 Quick Start Guide

### Step 1: Start the Server on your Mac

1. Open your terminal and navigate to the server folder:
   ```bash
   cd gaming-pc-manager/server
   npm start
   ```
2. The terminal will display your Mac's local network addresses:
   * **Dashboard URL (Mac):** `http://localhost:3000`
   * **Dashboard URL (Phone / iPad):** `http://<your-mac-ip>:3000`
   * **Windows Agent WebSocket URL:** `ws://<your-mac-ip>:3000/ws/client`
3. Open `http://localhost:3000` in Safari or Chrome.

---

### Step 2: Compile the Windows Agent via GitHub Actions

You don't need any Windows machine or .NET SDK on your Mac to compile the C# client:

1. Commit and push this project to your GitHub repository:
   ```bash
   git add .
   git commit -m "Add game room management system and Windows agent"
   git push origin main
   ```
2. Open your repository on **GitHub.com** and go to the **Actions** tab.
3. You will see the **Build Windows Gaming Agent** workflow running.
4. Once completed (approx. 1-2 minutes), click on the run and download the **`GameRoomAgent-Windows-x64`** artifact.
5. Extract the `.zip` on your Windows laptop. It contains:
   * `GameRoomAgent.exe` (Single-file self-contained executable, no runtimes required)
   * `config.json`

---

### Step 3: Run on the Windows Laptop

1. On the Windows laptop, open `config.json` in Notepad:
   ```json
   {
     "serverUrl": "ws://<YOUR-MAC-IP>:3000/ws/client",
     "stationId": "laptop-01",
     "stationName": "Gaming Laptop 01",
     "telemetryIntervalSeconds": 3,
     "autoLockOnDisconnect": false
   }
   ```
   *(Replace `<YOUR-MAC-IP>` with the IP printed by the server on your Mac, e.g. `192.168.31.177`)*.

2. Double-click **`GameRoomAgent.exe`**:
   * It starts silently in the system tray with a shield icon.
   * Immediately connects to your Mac server over Wi-Fi/LAN.
   * Telemetry (CPU %, RAM %, Battery %, Active Game) will appear live on your Mac dashboard!

---

### Step 4: Control from Your Mac Dashboard

From the web dashboard at `http://localhost:3000`:
* **🔒 Lock Now:** Displays an inescapable full-screen dark lock overlay on the laptop and intercepts Windows keys / Alt+Tab.
* **🔓 Unlock Now:** Dismisses the lock screen and lets the user play.
* **⏳ Session Timers:** Click `+15m`, `+30m`, `+1h`, or `+2h`. When the timer expires, the laptop will automatically lock itself!
* **📢 Message:** Send instant announcement popups to the laptop screen.
* **🔄 Restart / ⏻ Shutdown:** Remote power control with confirmation dialogs.

---

## 🧪 Testing on Mac (Without the Laptop)

You can test the entire Mac dashboard right now before deploying to Windows:

1. In one terminal, start the server:
   ```bash
   cd gaming-pc-manager/server
   npm start
   ```
2. In a second terminal, run the mock client:
   ```bash
   cd gaming-pc-manager/mock-client
   node mock-client.js
   ```
3. Open `http://localhost:3000` to see the simulated gaming laptop reporting live game status, CPU, RAM, battery, and reacting to your Lock/Unlock commands in real time!
