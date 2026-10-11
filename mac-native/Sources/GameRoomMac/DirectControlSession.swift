import Foundation
import AppKit

public class DirectControlSession: NSObject, ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var connectionStatus: String = "Connecting..."
    @Published public var latestFrame: NSImage? = nil
    @Published public var currentFps: Int = 0
    @Published public var pingMs: Int = 0
    @Published public var targetFps: Int = 60
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

    public init(ip: String, port: Int = 48999) {
        self.host = ip
        self.port = port
        super.init()
        self.session = URLSession(configuration: .default)
        connect()
    }

    public func connect() {
        isCancelled = false
        guard let url = URL(string: "ws://\(host):\(port)/control") else {
            self.connectionStatus = "Invalid Address"
            self.errorMessage = "Invalid IP or Port: ws://\(host):\(port)/control"
            return
        }

        self.connectionStatus = "Connecting to \(host):\(port)..."
        self.errorMessage = nil

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveNextMessage()
        startPingTimer()

        // Initial Ping test
        measurePing()
    }

    public func disconnect() {
        isCancelled = true
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
        if let image = NSImage(data: data) {
            DispatchQueue.main.async {
                self.latestFrame = image
                if !self.isConnected {
                    self.isConnected = true
                    self.connectionStatus = "Connected (LAN 60 FPS)"
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
        // Handle optional status messages from agent
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.measurePing()
        }
    }

    private func measurePing() {
        guard let task = webSocketTask, !isCancelled else { return }
        let start = Date()
        task.sendPing { [weak self] error in
            if error == nil {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                DispatchQueue.main.async {
                    self?.pingMs = max(1, ms)
                    if self?.isConnected == false {
                        self?.isConnected = true
                        self?.connectionStatus = "Connected (LAN 60 FPS)"
                    }
                }
            }
        }
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

    private func sendJson(_ dict: [String: Any]) {
        guard let task = webSocketTask, task.state == .running else { return }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let str = String(data: data, encoding: .utf8) {
            task.send(.string(str)) { _ in }
        }
    }
}
