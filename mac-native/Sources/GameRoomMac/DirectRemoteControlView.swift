import SwiftUI
import AppKit

public struct DirectRemoteControlView: View {
    public let station: Station
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: DirectControlSession

    public init(station: Station) {
        self.station = station
        let ip = station.ip ?? "127.0.0.1"
        let port = station.controlPort ?? 48999
        _session = StateObject(wrappedValue: DirectControlSession(ip: ip, port: port))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ==================== TOP HUD TOOLBAR ====================
            HStack(spacing: 12) {
                // Station Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.isConnected ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(station.displayName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 6) {
                        Text(station.ip ?? "LAN IP Unknown")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)

                        Text("• Port \(station.controlPort ?? 48999)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)

                        Text("⚡ Direct P2P")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }

                Spacer()

                // Live Performance HUD
                HStack(spacing: 10) {
                    // FPS Counter
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 11))
                        Text("\(session.currentFps) FPS")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(session.currentFps >= 30 ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                    .foregroundColor(session.currentFps >= 30 ? .green : .yellow)
                    .cornerRadius(6)

                    // Ping Latency
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                        Text("\(session.pingMs) ms")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(6)

                    // FPS Target Picker
                    Picker("", selection: $session.targetFps) {
                        Text("30 FPS").tag(30)
                        Text("60 FPS").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .onChange(of: session.targetFps) { newFps in
                        session.setFps(newFps)
                    }

                    // Input Toggle
                    Button(action: {
                        session.isInputEnabled.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: session.isInputEnabled ? "gamecontroller.fill" : "eye.fill")
                            Text(session.isInputEnabled ? "Control ON" : "View Only")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(session.isInputEnabled ? Color.indigo : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Windows Keys shortcuts
                    Menu {
                        Button("⊞ Windows Key") { session.sendSpecialKey("win") }
                        Button("🖥️ Show Desktop (Win+D)") { session.sendSpecialKey("desktop") }
                        Divider()
                        Button("🚀 Open in Moonlight") {
                            openMoonlight()
                        }
                        Button("🖥️ Open in Microsoft Remote Desktop") {
                            openRDP()
                        }
                        Button("📋 Copy IP Address") {
                            copyIp()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "ellipsis.circle")
                            Text("Actions")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 80)

                    // Close Button
                    Button(action: {
                        session.disconnect()
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // ==================== STREAM / CANVAS AREA ====================
            ZStack {
                Color.black.ignoresSafeArea()

                if let frame = session.latestFrame {
                    RemoteInputCanvas(session: session, image: frame)
                        .aspectRatio(frame.size.width / max(1, frame.size.height), contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.3)

                        Text(session.connectionStatus)
                            .font(.headline)
                            .foregroundColor(.white)

                        if let err = session.errorMessage {
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            Button("Retry Direct Connection") {
                                session.connect()
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                        } else {
                            Text("Connecting directly to \(station.ip ?? "LAN"):48999 over local Wi-Fi...")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(30)
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .onDisappear {
            session.disconnect()
        }
    }

    private func copyIp() {
        if let ip = station.ip {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ip, forType: .string)
        }
    }

    private func openMoonlight() {
        if let ip = station.ip, let url = URL(string: "moonlight://\(ip)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openRDP() {
        if let ip = station.ip, let url = URL(string: "rdp://\(ip)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// ==================== NSVIEW INTERACTIVE CANVAS ====================

struct RemoteInputCanvas: NSViewRepresentable {
    @ObservedObject var session: DirectControlSession
    let image: NSImage

    func makeNSView(context: Context) -> RemoteInputNSView {
        let view = RemoteInputNSView()
        view.session = session
        view.image = image
        return view
    }

    func updateNSView(_ nsView: RemoteInputNSView, context: Context) {
        nsView.session = session
        nsView.image = image
        nsView.needsDisplay = true
    }
}

class RemoteInputNSView: NSView {
    var session: DirectControlSession?
    var image: NSImage?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let img = image else { return }
        img.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
    }

    // ==================== MOUSE EVENTS ====================

    private func getNormalizedPosition(from event: NSEvent) -> (x: Double, y: Double)? {
        guard bounds.width > 0 && bounds.height > 0 else { return nil }
        let location = convert(event.locationInWindow, from: nil)
        let nx = min(max(0.0, location.x / bounds.width), 1.0)
        // Flip Y for macOS coordinate system (bottom-left to top-left for Windows)
        let ny = min(max(0.0, (bounds.height - location.y) / bounds.height), 1.0)
        return (nx, ny)
    }

    override func mouseMoved(with event: NSEvent) {
        if let pos = getNormalizedPosition(from: event) {
            session?.sendMouseMove(xPercent: pos.x, yPercent: pos.y)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let pos = getNormalizedPosition(from: event) {
            session?.sendMouseMove(xPercent: pos.x, yPercent: pos.y)
        }
    }

    override func rightMouseDragged(with event: NSEvent) {
        if let pos = getNormalizedPosition(from: event) {
            session?.sendMouseMove(xPercent: pos.x, yPercent: pos.y)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let pos = getNormalizedPosition(from: event) {
            session?.sendMouseMove(xPercent: pos.x, yPercent: pos.y)
        }
        session?.sendMouseDown(button: "left")
    }

    override func mouseUp(with event: NSEvent) {
        session?.sendMouseUp(button: "left")
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let pos = getNormalizedPosition(from: event) {
            session?.sendMouseMove(xPercent: pos.x, yPercent: pos.y)
        }
        session?.sendMouseDown(button: "right")
    }

    override func rightMouseUp(with event: NSEvent) {
        session?.sendMouseUp(button: "right")
    }

    override func otherMouseDown(with event: NSEvent) {
        session?.sendMouseDown(button: "middle")
    }

    override func otherMouseUp(with event: NSEvent) {
        session?.sendMouseUp(button: "middle")
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = Int(event.deltaY * 30)
        if delta != 0 {
            session?.sendMouseWheel(delta: delta)
        }
    }

    // ==================== KEYBOARD EVENTS ====================

    override func keyDown(with event: NSEvent) {
        if let vk = mapMacKeyToWindowsVK(event.keyCode) {
            session?.sendKeyDown(vk: vk)
        }
    }

    override func keyUp(with event: NSEvent) {
        if let vk = mapMacKeyToWindowsVK(event.keyCode) {
            session?.sendKeyUp(vk: vk)
        }
    }

    private func mapMacKeyToWindowsVK(_ keyCode: UInt16) -> Int? {
        // macOS KeyCode to Windows Virtual-Key code mapping
        switch keyCode {
        case 36: return 0x0D // Return / Enter
        case 53: return 0x1B // Escape
        case 51: return 0x08 // Backspace
        case 48: return 0x09 // Tab
        case 49: return 0x20 // Space
        case 117: return 0x2E // Delete
        case 123: return 0x25 // Left Arrow
        case 124: return 0x27 // Right Arrow
        case 125: return 0x28 // Down Arrow
        case 126: return 0x26 // Up Arrow
        case 56, 60: return 0x10 // Shift
        case 59, 62: return 0x11 // Control
        case 58, 61: return 0x12 // Option / Alt
        case 55, 54: return 0x5B // Command -> Windows Key
        // Letters A-Z
        case 0: return 0x41  // A
        case 11: return 0x42 // B
        case 8: return 0x43  // C
        case 2: return 0x44  // D
        case 14: return 0x45 // E
        case 3: return 0x46  // F
        case 5: return 0x47  // G
        case 4: return 0x48  // H
        case 34: return 0x49 // I
        case 38: return 0x4A // J
        case 40: return 0x4B // K
        case 37: return 0x4C // L
        case 46: return 0x4D // M
        case 45: return 0x4E // N
        case 31: return 0x4F // O
        case 35: return 0x50 // P
        case 12: return 0x51 // Q
        case 15: return 0x52 // R
        case 1: return 0x53  // S
        case 17: return 0x54 // T
        case 32: return 0x55 // U
        case 9: return 0x56  // V
        case 13: return 0x57 // W
        case 7: return 0x58  // X
        case 16: return 0x59 // Y
        case 6: return 0x5A  // Z
        // Numbers 0-9
        case 29: return 0x30 // 0
        case 18: return 0x31 // 1
        case 19: return 0x32 // 2
        case 20: return 0x33 // 3
        case 21: return 0x34 // 4
        case 23: return 0x35 // 5
        case 22: return 0x36 // 6
        case 26: return 0x37 // 7
        case 28: return 0x38 // 8
        case 25: return 0x39 // 9
        default:
            return nil
        }
    }
}
