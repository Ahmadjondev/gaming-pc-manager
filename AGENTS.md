# Gaming Room PC Management System

This project is a real-time gaming PC/laptop management and screen-locking platform designed for gaming lounges, cybercafés, and LAN centers.

## Architecture

1. **Server (`server/`)**:
   - Node.js WebSocket + HTTP server on port 3000.
   - Serves dark-mode Web Dashboard (`server/public/`).
   - Manages active stations, sessions, countdown timers, and broadcasts state to all connected admin dashboards.
   - Start with: `cd server && npm start`.

2. **Windows Client Agent (`client-windows/`)**:
   - C# (.NET 8) WinForms application.
   - Connects to Mac server via WebSocket (`ws://<MAC-IP>:3000/ws/client`).
   - Streams live hardware telemetry (CPU %, RAM %, Battery %, Active Game/Window title).
   - Enforces full-screen kiosk lock overlay (`LockForm.cs`) with low-level keyboard hook intercepting Windows key, Alt+Tab, Alt+F4.
   - Listens for remote commands: `lock`, `unlock`, `alert`, `restart`, `shutdown`.
   - Single-file self-contained `.exe` build via GitHub Actions workflow (`.github/workflows/build-windows-client.yml`).

3. **Mock Client (`mock-client/`)**:
   - Node.js script to simulate a Windows gaming laptop on Mac for rapid testing without a physical Windows machine.
   - Run with: `cd mock-client && node mock-client.js`.

## Recent Milestones
- Project created and moved to `~/Documents/gaming-pc-manager`.
- Initial git repository initialized and committed.
- End-to-end WebSocket communication verified (lock, unlock, alert commands tested).
