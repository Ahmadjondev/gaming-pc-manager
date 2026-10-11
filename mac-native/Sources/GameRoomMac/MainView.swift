import SwiftUI
import Combine

public struct MainView: View {
    @StateObject private var service = WebSocketService()
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public var body: some View {
        VStack(spacing: 0) {
            // TOP NATIVE TOOLBAR
            HStack(spacing: 16) {
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

            // SUMMARY STATS BAR
            HStack(spacing: 14) {
                StatCard(title: "TOTAL STATIONS", value: "\(service.stations.count)", color: .white)
                StatCard(title: "ONLINE", value: "\(onlineCount)", color: .green)
                StatCard(title: "IN SESSION", value: "\(inSessionCount)", color: .cyan)
                StatCard(title: "LOCKED", value: "\(lockedCount)", color: .red)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // MAIN CONTENT (GRID OF STATIONS)
            ScrollView {
                if service.stations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "laptopcomputer.trianglebadge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Waiting for Gaming Laptops to Connect...")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("Run install.bat on any Windows gaming laptop.\nIt will connect automatically to this Mac app via the cloud!")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
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
