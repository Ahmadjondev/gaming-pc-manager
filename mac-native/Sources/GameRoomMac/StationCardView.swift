import SwiftUI

public struct StationCardView: View {
    public let station: Station
    @ObservedObject public var service: WebSocketService

    @State private var showingDirectControl = false
    @State private var directControlTargetStation: Station? = nil
    @State private var showingAlertSheet = false
    @State private var showingScreenSheet = false
    @State private var showingFilesSheet = false
    @State private var showingPowerConfirm = false
    @State private var pendingPowerAction: String = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.cyan)
                        Text(station.displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    HStack(spacing: 6) {
                        Text(station.hostname ?? "Windows PC")
                        Text("•")
                        Text("LAN: \(station.ip ?? "Unknown")")
                            .foregroundColor(.cyan)
                        if let pub = station.publicIp, !pub.isEmpty, pub != station.ip {
                            Text("•")
                            Text("WAN: \(pub)")
                                .foregroundColor(.purple)
                        }
                        if let ts = station.tailscaleIp, !ts.isEmpty {
                            Text("•")
                            Text("TS: \(ts)")
                                .foregroundColor(.green)
                        }
                        Text(":\(station.controlPort ?? 48999)")
                            .foregroundColor(.gray)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    // Online Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(station.isOnline ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                        Text(station.isOnline ? "ONLINE" : "OFFLINE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(station.isOnline ? .green : .gray)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(station.isOnline ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                    .cornerRadius(12)

                    // Lock Badge
                    HStack(spacing: 4) {
                        Image(systemName: (station.isLocked ?? false) ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 10))
                        Text((station.isLocked ?? false) ? "LOCKED" : "UNLOCKED")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor((station.isLocked ?? false) ? .red : .cyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((station.isLocked ?? false) ? Color.red.opacity(0.15) : Color.cyan.opacity(0.15))
                    .cornerRadius(12)
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Metrics Row (CPU, RAM, Battery)
            HStack(spacing: 10) {
                MetricBox(
                    icon: "cpu",
                    title: "CPU",
                    value: "\(station.cpu ?? 0)%",
                    percent: Double(station.cpu ?? 0) / 100.0,
                    tint: cpuColor(station.cpu ?? 0)
                )

                MetricBox(
                    icon: "memorychip",
                    title: "RAM",
                    value: station.ramUsedGb != nil ? String(format: "%.1f/%.0fGB", station.ramUsedGb!, station.ramTotalGb ?? 16.0) : "\(station.ram ?? 0)%",
                    percent: Double(station.ram ?? 0) / 100.0,
                    tint: .cyan
                )

                MetricBox(
                    icon: (station.isCharging ?? true) ? "battery.100.bolt" : "battery.75",
                    title: "POWER",
                    value: "\(station.battery ?? 100)%",
                    percent: Double(station.battery ?? 100) / 100.0,
                    tint: .green
                )
            }

            // Active Game / Window
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 12))
                Text("Active:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                Text(station.activeWindow ?? "Desktop")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyan.opacity(0.08))
            .cornerRadius(6)

            // Session Countdown Panel
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SESSION REMAINING")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(station.formattedSessionTime)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                HStack(spacing: 6) {
                    ForEach([15, 30, 60, 120], id: \.self) { mins in
                        Button("+\(mins)m") {
                            service.addTime(stationId: station.id, seconds: mins * 60)
                        }
                        .buttonStyle(TimeChipButtonStyle())
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)

            // Action Toolbar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    if station.isLocked ?? false {
                        Button {
                            service.unlock(stationId: station.id)
                        } label: {
                            Label("Unlock", systemImage: "lock.open.fill")
                        }
                        .buttonStyle(ActionButtonStyle(color: .green))
                    } else {
                        Button {
                            service.lock(stationId: station.id)
                        } label: {
                            Label("Lock", systemImage: "lock.fill")
                        }
                        .buttonStyle(ActionButtonStyle(color: .red))
                    }

                    Button {
                        showingAlertSheet = true
                    } label: {
                        Label("Message", systemImage: "megaphone.fill")
                    }
                    .buttonStyle(ActionButtonStyle(color: .cyan))
                }

                // ⚡ HIGH-PERFORMANCE DIRECT CONTROL (LAN / WAN / TAILSCALE)
                HStack(spacing: 8) {
                    Button {
                        directControlTargetStation = station
                        showingDirectControl = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                            Text("⚡ Direct LAN (60 FPS)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(LinearGradient(colors: [Color.indigo, Color.purple], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(color: Color.purple.opacity(0.3), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)

                    if let pub = station.publicIp, !pub.isEmpty, pub != station.ip {
                        Button {
                            var wanStation = station
                            wanStation.ip = pub
                            directControlTargetStation = wanStation
                            showingDirectControl = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                Text("🌐 Direct WAN")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.purple.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.6), lineWidth: 1))
                            .foregroundColor(.purple)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("Connect directly over Internet using Public WAN IP (\(pub):\(station.controlPort ?? 48999))")
                    }

                    if let ts = station.tailscaleIp, !ts.isEmpty {
                        Button {
                            var tsStation = station
                            tsStation.ip = ts
                            directControlTargetStation = tsStation
                            showingDirectControl = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 11))
                                Text("🛡️ Tailscale")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.2))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.6), lineWidth: 1))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help("Connect directly over Tailscale P2P VPN (\(ts))")
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        showingScreenSheet = true
                    } label: {
                        Label("Cloud Preview", systemImage: "display")
                    }
                    .buttonStyle(ActionButtonStyle(color: .purple))

                    Button {
                        showingFilesSheet = true
                    } label: {
                        Label("Files & Games", systemImage: "folder.fill")
                    }
                    .buttonStyle(ActionButtonStyle(color: .blue))
                }

                HStack(spacing: 8) {
                    Button("Restart") {
                        pendingPowerAction = "restart"
                        showingPowerConfirm = true
                    }
                    .buttonStyle(PowerButtonStyle())

                    Button("Shutdown") {
                        pendingPowerAction = "shutdown"
                        showingPowerConfirm = true
                    }
                    .buttonStyle(PowerButtonStyle())
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: NSColor(red: 0.07, green: 0.10, blue: 0.16, alpha: 1.0)))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .sheet(isPresented: $showingDirectControl) {
            DirectRemoteControlView(station: directControlTargetStation ?? station, service: service)
        }
        .sheet(isPresented: $showingScreenSheet) {
            ScreenPreviewSheet(station: station, service: service)
        }
        .sheet(isPresented: $showingFilesSheet) {
            RemoteFileBrowserSheet(station: station, service: service)
        }
        .sheet(isPresented: $showingAlertSheet) {
            AlertSheet(station: station, service: service)
        }
        .confirmationDialog(
            "Are you sure you want to \(pendingPowerAction) \(station.displayName)?",
            isPresented: $showingPowerConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm \(pendingPowerAction.capitalized)", role: .destructive) {
                if pendingPowerAction == "restart" {
                    service.restart(stationId: station.id)
                } else {
                    service.shutdown(stationId: station.id)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var borderColor: Color {
        guard station.isOnline else { return Color.gray.opacity(0.3) }
        return (station.isLocked ?? false) ? Color.red.opacity(0.6) : Color.green.opacity(0.6)
    }

    private func cpuColor(_ val: Int) -> Color {
        if val >= 85 { return .red }
        if val >= 60 { return .orange }
        return .green
    }
}

// Subcomponents
struct MetricBox: View {
    let icon: String
    let title: String
    let value: String
    let percent: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(percent))))
                }
            }
            .frame(height: 3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }
}

struct TimeChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Color.cyan.opacity(0.4) : Color.white.opacity(0.08))
            .cornerRadius(4)
    }
}

struct ActionButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.35 : 0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.4), lineWidth: 1)
            )
            .cornerRadius(6)
    }
}

struct PowerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Color.white.opacity(configuration.isPressed ? 0.1 : 0.04))
            .cornerRadius(4)
    }
}
