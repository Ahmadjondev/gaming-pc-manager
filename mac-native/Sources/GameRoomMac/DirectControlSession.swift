import Foundation
import AppKit

public class DirectControlSession: NSObject, ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var connectionStatus: String = "Connecting..."
    @Published public var latestFrame: NSImage? = nil
    @Published public var currentFps: Int = 0
    @Published public var pingMs: Int = 0
    @Published public var targetFps: Int = 60
    @Published public var selectedResolution: Int = 1280
    @Published public var isInputEnabled: Bool = true
    @Published public var errorMessage: String? = nil

    private let host: String
    private let port: Int
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private var isCancelled: Bool = false

    // FPS Calculation
    private var frameCounter: Int = 0
    private var lastFpsCalculationTime: Date = Date()
    private var pingTimer: Timer?
    private var connectTimeoutTimer: Timer?

    public init(ip: String, port: Int = 48999) {
        self.host = ip
        self.port = port
        super.init()
        self.session = URLSession(configuration: .default)
        connect()
    }

    public func connect() {
        isCancelled = false
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil

        guard let url = URL(string: "ws://\(host):\(port)/control") else {
            self.connectionStatus = "Invalid Address"
            self.errorMessage = "Invalid IP or Port: ws://\(host):\(port)/control"
            return
        }

        self.connectionStatus = "Connecting to \(host):\(port)..."
        self.errorMessage = nil

        let localMacIp = Self.getLocalMacIp() ?? "Unknown"
        let sameSubnet = Self.isSameSubnet(ip1: localMacIp, ip2: host)

        // 3.5-second timeout with network mismatch diagnostic
        connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected, !self.isCancelled else { return }
            DispatchQueue.main.async {
                self.connectionStatus = "Connection Failed"
                if !sameSubnet && localMacIp != "Unknown" {
                    self.errorMessage = "⚠️ Wi-Fi Network Mismatch Detected!\n\n• Your Mac is connected to: \(localMacIp)\n• Your Laptop is connected to: \(self.host)\n\nBecause your Mac and Laptop are on different networks, direct LAN streaming cannot reach the laptop.\n\n👉 Fix: Connect both your Mac and Laptop to the SAME Wi-Fi network (or connect your laptop to your iPhone hotspot)."
                } else {
                    self.errorMessage = "Could not reach \(self.host):\(self.port) within 3.5 seconds.\nMake sure GameRoomAgent is running on the laptop and port \(self.port) is open on your firewall."
                }
            }
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveNextMessage()
        startPingTimer()

        // Initial Ping test
        measurePing()
    }

    public func disconnect() {
        isCancelled = true
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionStatus = "Disconnected"
        }
    }

    private func receiveNextMessage() {
        guard !isCancelled, let task = webSocketTask else { return }

        task.receive { [weak self] result in
            guard let self = self, !self.isCancelled else { return }

            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleBinaryFrame(data)
                case .string(let text):
                    self.handleTextMessage(text)
                @unknown default:
                    break
                }
                self.receiveNextMessage()

            case .failure(_):
                DispatchQueue.main.async {
                    if !self.isCancelled {
                        self.isConnected = false
                        self.connectionStatus = "Connection Failed"
                        self.errorMessage = "Could not reach \(self.host):\(self.port). Ensure the laptop is on the same Wi-Fi/LAN."
                    }
                }
            }
        }
    }

    private func handleBinaryFrame(_ data: Data) {
        // Send ACK immediately to clear in-flight state and trigger the next frame
        sendJson(["type": "ack"])

        DispatchQueue.global(qos: .userInteractive).async {
            guard let rep = NSBitmapImageRep(data: data) else { return }
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)

            DispatchQueue.main.async {
                self.latestFrame = image
                if !self.isConnected {
                    self.isConnected = true
                    self.connectionStatus = "Connected (LAN 60 FPS)"
                    self.connectTimeoutTimer?.invalidate()
                    self.connectTimeoutTimer = nil
                }

                // FPS tracking
                self.frameCounter += 1
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastFpsCalculationTime)
                if elapsed >= 1.0 {
                    self.currentFps = Int(Double(self.frameCounter) / elapsed)
                    self.frameCounter = 0
                    self.lastFpsCalculationTime = now
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        if let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = obj["type"] as? String {
            if type == "pong", let t = obj["t"] as? Double {
                let ms = Int((Date().timeIntervalSince1970 - t) * 1000)
                DispatchQueue.main.async {
                    self.pingMs = max(1, ms)
                    if !self.isConnected {
                        self.isConnected = true
                        self.connectionStatus = "Connected (LAN 60 FPS)"
                        self.connectTimeoutTimer?.invalidate()
                        self.connectTimeoutTimer = nil
                    }
                }
            }
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.measurePing()
        }
    }

    private func measurePing() {
        guard !isCancelled else { return }
        sendJson(["type": "ping", "t": Date().timeIntervalSince1970])
    }

    // ==================== REMOTE INPUT INJECTION ====================

    public func sendMouseMove(xPercent: Double, yPercent: Double) {
        guard isConnected, isInputEnabled else { return }
        sendJson(["type": "mouse_move", "x": xPercent, "y": yPercent])
    }

    public func sendMouseDown(button: String) {
        guard isConnected, isInputEnabled else { return }
        sendJson(["type": "mouse_down", "button": button])
    }

    public func sendMouseUp(button: String) {
        guard isConnected, isInputEnabled else { return }
        sendJson(["type": "mouse_up", "button": button])
    }

    public func sendMouseWheel(delta: Int) {
        guard isConnected, isInputEnabled else { return }
        sendJson(["type": "mouse_wheel", "delta": delta])
    }

    public func sendKeyDown(vk: Int) {
        guard isConnected, isInputEnabled else { return }
        sendJson(["type": "key_down", "vk": vk])
    }

    public func sendKeyUp(vk: Int) {
        guard isConnected, isInputEnabled else { return }
        sendJson(["type": "key_up", "vk": vk])
    }

    public func sendSpecialKey(_ key: String) {
        guard isConnected else { return }
        sendJson(["type": "special_key", "key": key])
    }

    public func setFps(_ fps: Int) {
        self.targetFps = fps
        sendJson(["type": "set_fps", "fps": fps])
    }

    public func setQuality(_ quality: Int) {
        sendJson(["type": "set_quality", "quality": quality])
    }

    public func setResolution(_ width: Int) {
        self.selectedResolution = width
        sendJson(["type": "set_resolution", "maxWidth": width])
    }

    private func sendJson(_ dict: [String: Any]) {
        guard let task = webSocketTask, task.state == .running else { return }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            task.send(.string(str)) { _ in }
        }
    }

    public static func isSameSubnet(ip1: String, ip2: String) -> Bool {
        let p1 = ip1.split(separator: ".")
        let p2 = ip2.split(separator: ".")
        guard p1.count == 4 && p2.count == 4 else { return false }
        return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2]
    }

    public static func getLocalMacIp() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        if ip != "127.0.0.1" && !ip.hasPrefix("169.254") {
                            address = ip
                            break
                        }
                    }
                }
            }
        }
        return address
    }
}
