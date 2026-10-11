import SwiftUI
import Combine

public struct MainView: View {
    @StateObject private var service = WebSocketService()
    @State private var currentTime = Date()

    // Direct Connect by IP State
    @State private var showingDirectConnectSheet = false
    @State private var directConnectIp: String = "192.168.1."
    @State private var directConnectPort: String = "48999"
    @State private var directConnectStation: Station? = nil

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public var body: some View {
        VStack(spacing: 0) {
            // ==================== TOP NATIVE TOOLBAR ====================
            HStack(spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Color.cyan.opacity(0.3), Color.purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.cyan)
                            .font(.system(size: 18))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("GAME ROOM HUB")
                            .font(.system(size: 15, weight: .black))
                            .foregroundColor(.white)
                        Text("Native macOS Fleet Controller")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                // Direct Connect by IP Button
                Button {
                    showingDirectConnectSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("⚡ Direct Connect (IP)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .shadow(color: Color.purple.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .help("Connect directly to any gaming laptop IP on your LAN")

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
            .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // ==================== MAIN CONTENT (GRID OF STATIONS) ====================
            ScrollView {
                if service.stations.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: "laptopcomputer.trianglebadge.exclamationmark")
                            .font(.system(size: 52))
                            .foregroundColor(.indigo)

                        Text("Waiting for Gaming Laptops to Connect...")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)

                        Text("Run install.bat on any Windows gaming laptop.\nIt will auto-register here with its local LAN IP address!")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)

                        HStack(spacing: 12) {
                            Button {
                                showingDirectConnectSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.fill")
                                    Text("⚡ Connect Directly by IP")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Button {
                                addDemoStation()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Demo PC Card")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 350)
                    .padding(40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 380, maximum: 500), spacing: 18)], spacing: 18) {
                        ForEach(Array(service.stations.values).sorted(by: { $0.displayName < $1.displayName })) { station in
                            StationCardView(station: station, service: service)
                        }
                    }
                    .padding(20)
                }
            }
            .background(Color(nsColor: NSColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1.0)))
        }
        .onReceive(timer) { input in
            currentTime = input
        }
        .sheet(isPresented: $showingDirectConnectSheet) {
            DirectConnectSheet(
                ip: $directConnectIp,
                port: $directConnectPort,
                onConnect: { enteredIp, enteredPort in
                    showingDirectConnectSheet = false
                    let customStation = Station(
                        id: "manual-\(enteredIp)",
                        name: "Gaming PC (\(enteredIp))",
                        hostname: "Gaming-Laptop",
                        os: "Windows 11",
                        ip: enteredIp,
                        controlPort: Int(enteredPort) ?? 48999,
                        status: "online",
                        isLocked: false,
                        sessionSeconds: 3600,
                        sessionTotalSeconds: 3600,
                        cpu: 25,
                        ram: 45,
                        ramTotalGb: 16.0,
                        ramUsedGb: 7.2,
                        battery: 100,
                        isCharging: true,
                        batteryStatus: "AC Power",
                        activeWindow: "Desktop",
                        lastSeen: Date().timeIntervalSince1970
                    )
                    directConnectStation = customStation
                }
            )
        }
        .sheet(item: $directConnectStation) { st in
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
    }
}

// ==================== DIRECT CONNECT SHEET ====================

struct DirectConnectSheet: View {
    @Binding var ip: String
    @Binding var port: String
    let onConnect: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⚡ Direct LAN Remote Control")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Connect directly to any gaming laptop's IP address on your Wi-Fi/LAN")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAPTOP LOCAL IP ADDRESS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    TextField("e.g. 192.168.1.105", text: $ip)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTROL PORT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    TextField("48999", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14, design: .monospaced))
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    onConnect(ip.trimmingCharacters(in: .whitespacesAndNewlines), port.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("Connect 60 FPS")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Color(nsColor: .windowBackgroundColor))
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
