import SwiftUI

public struct ScreenPreviewSheet: View {
    public let station: Station
    @ObservedObject public var service: WebSocketService
    @Environment(\.dismiss) private var dismiss

    @State private var isStreaming: Bool = false
    @State private var streamTimer: Timer? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "display")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.purple)
                    Text("Remote Screen: \(station.displayName)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        service.requestScreen(stationId: station.id)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    if isStreaming {
                        Button {
                            toggleStream()
                        } label: {
                            Label("Stop Stream", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    } else {
                        Button {
                            toggleStream()
                        } label: {
                            Label("Live (1 FPS)", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }

                    Button("Close") {
                        stopStream()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(16)
            .background(Color(nsColor: NSColor.windowBackgroundColor))

            Divider()

            // Viewport
            ZStack {
                Color.black

                if let img = service.latestScreenImage, service.latestScreenStationId == station.id {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Requesting live screen capture from \(station.displayName)...")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(minWidth: 800, minHeight: 480)

            Divider()

            // Footer
            HStack {
                if let date = service.latestScreenTimestamp {
                    Text("Last frame: \(date.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                } else {
                    Text("Waiting for image...")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Text("Native macOS Metal / Quartz Renderer")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor.windowBackgroundColor))
        }
        .frame(width: 960, height: 600)
        .onAppear {
            service.requestScreen(stationId: station.id)
        }
        .onDisappear {
            stopStream()
        }
    }

    private func toggleStream() {
        if isStreaming {
            stopStream()
        } else {
            isStreaming = true
            service.requestScreen(stationId: station.id)
            streamTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                service.requestScreen(stationId: station.id)
            }
        }
    }

    private func stopStream() {
        isStreaming = false
        streamTimer?.invalidate()
        streamTimer = nil
    }
}
