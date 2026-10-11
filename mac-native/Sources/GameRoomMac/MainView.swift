import SwiftUI
import Combine

public struct MainView: View {
    @StateObject private var service = WebSocketService()
    @State private var currentTime = Date()

    // Quick Direct Control Bar State
    @State private var quickIp: String = "192.168.1.105"
    @State private var quickPort: String = "48999"
    @State private var activeDirectControlStation: Station? = nil

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public var body: some View {
        VStack(spacing: 0) {
            // ==================== TOP NATIVE TOOLBAR ====================
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Color.cyan.opacity(0.3), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 38, height: 38)
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.cyan)
                            .font(.system(size: 19))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GAME ROOM HUB")
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(.white)
                        Text("Native macOS Fleet Controller")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // Server Status Indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(service.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(service.serverStatus)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(service.isConnected ? .green : .red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)

                // Digital Clock
                Text(currentTime.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)

                // Refresh Button
                Button {
                    service.connect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reconnect / Refresh Server")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Color(nsColor: NSColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0)))

            Divider()

            // ==================== SUMMARY STATS BAR ====================
            HStack(spacing: 14) {
                StatCard(title: "TOTAL STATIONS", value: "\(service.stations.count)", color: .white)
                StatCard(title: "ONLINE", value: "\(onlineCount)", color: .green)
                StatCard(title: "IN SESSION", value: "\(inSessionCount)", color: .cyan)
                StatCard(title: "LOCKED", value: "\(lockedCount)", color: .red)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)

            Divider()

            // ==================== MAIN CONTENT SCROLLVIEW ====================
            ScrollView {
                VStack(spacing: 20) {
                    // ⚡ PROMINENT DIRECT LAN 60 FPS CONTROL PANEL (ALWAYS VISIBLE)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.yellow)
                                    Text("⚡ DIRECT LAN REMOTE CONTROL (60 FPS)")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundColor(.white)
                                    Text("NO CLOUD LAG")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                                Text("Connect directly to any gaming laptop on your local Wi-Fi / Ethernet (< 3ms latency, 60 FPS, real-time mouse & keyboard)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }

                        // Inline Quick Connect Inputs
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Text("Laptop IP:")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.gray)
                                TextField("192.168.1.105", text: $quickIp)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(width: 170)
                            }

                            HStack(spacing: 8) {
                                Text("Port:")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.gray)
                                TextField("48999", text: $quickPort)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(width: 80)
                            }

                            // ⚡ LAUNCH BUTTON
                            Button {
                                launchDirectControl(ip: quickIp, port: quickPort)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                    Text("⚡ Start Direct Control (60 FPS)")
                                        .font(.system(size: 13, weight: .black))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .shadow(color: Color.purple.opacity(0.4), radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(quickIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Spacer()

                            Button {
                                addDemoStation()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle")
                                    Text("Show Demo PC")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.08))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1.0)),
                                Color(nsColor: NSColor(red: 0.08, green: 0.09, blue: 0.16, alpha: 1.0))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(LinearGradient(colors: [Color.purple.opacity(0.6), Color.indigo.opacity(0.3)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
                    )

                    // SECTION: GAMING STATIONS
                    HStack {
                        Text("CONNECTED GAMING PCS")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(service.stations.count) Available")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                    .padding(.top, 4)

                    if service.stations.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "laptopcomputer.and.arrow.down")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.6))

                            Text("No Windows Laptops Registered Yet")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)

                            Text("When you run install.bat on any gaming laptop, it connects to Render and automatically shows its LAN card here with the ⚡ Direct Control (60 FPS LAN) button.\nOr click 'Show Demo PC' above to preview the laptop card right now.")
                                .multilineTextAlignment(.center)
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                                .frame(maxWidth: 550)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .padding(20)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(10)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 520), spacing: 18)], spacing: 18) {
                            ForEach(Array(service.stations.values).sorted(by: { $0.displayName < $1.displayName })) { station in
                                StationCardView(station: station, service: service)
                            }
                        }
                    }
                }
                .padding(22)
            }
            .background(Color(nsColor: NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)))
        }
        .onReceive(timer) { input in
            currentTime = input
        }
        .sheet(item: $activeDirectControlStation) { st in
            DirectRemoteControlView(station: st)
        }
    }

    private var onlineCount: Int {
        service.stations.values.filter { $0.isOnline }.count
    }

    private var inSessionCount: Int {
        service.stations.values.filter { $0.isOnline && !($0.isLocked ?? false) && ($0.sessionSeconds ?? 0) > 0 }.count
    }

    private var lockedCount: Int {
        service.stations.values.filter { $0.isOnline && ($0.isLocked ?? false) }.count
    }

    private func launchDirectControl(ip: String, port: String) {
        let cleanIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPort = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 48999
        let manualStation = Station(
            id: "manual-\(cleanIp)",
            name: "Gaming Laptop (\(cleanIp))",
            hostname: "Gaming-Laptop",
            os: "Windows 11",
            ip: cleanIp,
            controlPort: cleanPort,
            status: "online",
            isLocked: false,
            sessionSeconds: 3600,
            sessionTotalSeconds: 3600,
            cpu: 30,
            ram: 50,
            ramTotalGb: 16.0,
            ramUsedGb: 8.0,
            battery: 100,
            isCharging: true,
            batteryStatus: "AC Power",
            activeWindow: "Desktop",
            lastSeen: Date().timeIntervalSince1970
        )
        activeDirectControlStation = manualStation
    }

    private func addDemoStation() {
        let demo = Station(
            id: "rog-demo-01",
            name: "ASUS ROG Strix (Demo)",
            hostname: "ROG-STRIX-G16",
            os: "Windows 11 Pro",
            ip: "192.168.1.105",
            controlPort: 48999,
            status: "online",
            isLocked: false,
            sessionSeconds: 2700,
            sessionTotalSeconds: 3600,
            cpu: 48,
            ram: 64,
            ramTotalGb: 32.0,
            ramUsedGb: 20.4,
            battery: 95,
            isCharging: true,
            batteryStatus: "Plugged in (Fast Charge)",
            activeWindow: "Cyberpunk 2077",
            lastSeen: Date().timeIntervalSince1970
        )
        service.stations[demo.id] = demo
        quickIp = demo.ip ?? "192.168.1.105"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: NSColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1.0)))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
