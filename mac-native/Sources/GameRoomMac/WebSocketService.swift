import Foundation
import AppKit
import UserNotifications

public class WebSocketService: NSObject, ObservableObject {
    @Published public var isConnected: Bool = false
    @Published public var serverStatus: String = "Connecting..."
    @Published public var stations: [String: Station] = [:]
    
    // Remote Screen State
    @Published public var latestScreenImage: NSImage? = nil
    @Published public var latestScreenStationId: String? = nil
    @Published public var latestScreenTimestamp: Date? = nil

    // Remote File Explorer State
    @Published public var activeFileStationId: String? = nil
    @Published public var drives: [DriveItem] = []
    @Published public var currentDirectory: DirectoryContentResult? = nil
    @Published public var isBrowsingLoading: Bool = false

    // Remote Download State
    @Published public var downloadPercent: Int = 0
    @Published public var isDownloading: Bool = false
    @Published public var downloadStatusMessage: String = ""

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession!
    private var reconnectTimer: Timer?
    private let serverUrlString: String

    public init(serverUrl: String = "wss://gaming-pc-manager.onrender.com/ws/admin") {
        self.serverUrlString = serverUrl
        super.init()
        self.session = URLSession(configuration: .default)
        requestNotificationPermission()
        connect()
    }

    public func connect() {
        guard let url = URL(string: serverUrlString) else { return }
        
        DispatchQueue.main.async {
            self.serverStatus = "Connecting..."
        }

        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()

        // Send a ping to check connection
        webSocketTask?.sendPing { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.isConnected = true
                    self?.serverStatus = "Online (Cloud)"
                } else {
                    self?.handleDisconnect()
                }
            }
        }
    }

    private func handleDisconnect() {
        DispatchQueue.main.async {
            self.isConnected = false
            self.serverStatus = "Disconnected (Retrying)"
            self.updateDockBadge()
        }
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("[WS Error]: \(error.localizedDescription)")
                self.handleDisconnect()

            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseIncomingJson(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseIncomingJson(text)
                    }
                @unknown default:
                    break
                }
                // Keep listening
                self.receiveMessage()
            }
        }
    }

    private func parseIncomingJson(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async {
            self.isConnected = true
            self.serverStatus = "Online (Cloud)"

            switch type {
            case "init":
                if let stationsArray = json["stations"] as? [[String: Any]] {
                    self.stations.removeAll()
                    for dict in stationsArray {
                        if let st = self.decodeStation(from: dict) {
                            self.stations[st.id] = st
                        }
                    }
                    self.updateDockBadge()
                }

            case "station_connected":
                if let dict = json["station"] as? [String: Any],
                   let st = self.decodeStation(from: dict) {
                    self.stations[st.id] = st
                    self.updateDockBadge()
                    self.sendLocalNotification(
                        title: "Gaming Laptop Online 💻",
                        body: "\(st.displayName) has connected to the game room."
                    )
                }

            case "station_update":
                if let dict = json["station"] as? [String: Any],
                   let st = self.decodeStation(from: dict) {
                    self.stations[st.id] = st
                    self.updateDockBadge()
                }

            case "session_tick":
                if let stationsArray = json["stations"] as? [[String: Any]] {
                    for dict in stationsArray {
                        if let st = self.decodeStation(from: dict) {
                            self.stations[st.id] = st
                        }
                    }
                }

            case "screen_frame":
                if let stId = json["stationId"] as? String,
                   let b64 = json["image"] as? String,
                   let imgData = Data(base64Encoded: b64),
                   let nsImg = NSImage(data: imgData) {
                    self.latestScreenStationId = stId
                    self.latestScreenImage = nsImg
                    self.latestScreenTimestamp = Date()
                }

            case "drives_listing":
                if let drivesData = try? JSONSerialization.data(withJSONObject: json["drives"] ?? []),
                   let list = try? JSONDecoder().decode([DriveItem].self, from: drivesData) {
                    self.drives = list
                    print("[WebSocketService] Loaded \(list.count) drives")
                } else {
                    print("[WebSocketService] Failed to parse drives_listing")
                }

            case "dir_listing":
                self.isBrowsingLoading = false
                if let resDict = json["result"] as? [String: Any],
                   let resData = try? JSONSerialization.data(withJSONObject: resDict) {
                    do {
                        let res = try JSONDecoder().decode(DirectoryContentResult.self, from: resData)
                        self.currentDirectory = res
                        print("[WebSocketService] Loaded dir_listing: \(res.CurrentPath) (\(res.safeItems.count) items)")
                    } catch {
                        print("[WebSocketService] Failed to decode dir_listing: \(error)")
                    }
                } else {
                    print("[WebSocketService] Invalid dir_listing data")
                }

            case "download_progress":
                if let p = json["percent"] as? Int {
                    self.downloadPercent = p
                    self.isDownloading = true
                    self.downloadStatusMessage = "Downloading game: \(p)%"
                }

            case "download_status":
                if let status = json["status"] as? String,
                   let msg = json["message"] as? String {
                    self.downloadStatusMessage = msg
                    if status == "completed" {
                        self.isDownloading = false
                        self.downloadPercent = 100
                        self.sendLocalNotification(title: "Download Complete ✅", body: msg)
                    }
                }

            default:
                break
            }
        }
    }

    private func decodeStation(from dict: [String: Any]) -> Station? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(Station.self, from: data)
    }

    private func sendJson(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(str)) { error in
            if let error = error {
                print("[WS Send Error]: \(error.localizedDescription)")
            }
        }
    }

    // ==================== COMMAND ACTIONS ====================

    public func lock(stationId: String) {
        sendJson(["action": "lock", "targetId": stationId, "message": "Station locked by Administrator"])
    }

    public func unlock(stationId: String) {
        sendJson(["action": "unlock", "targetId": stationId])
    }

    public func addTime(stationId: String, seconds: Int) {
        sendJson(["action": "add_time", "targetId": stationId, "seconds": seconds])
    }

    public func sendAlert(stationId: String, title: String, message: String) {
        sendJson(["action": "alert", "targetId": stationId, "title": title, "message": message])
    }

    public func restart(stationId: String) {
        sendJson(["action": "restart", "targetId": stationId])
    }

    public func shutdown(stationId: String) {
        sendJson(["action": "shutdown", "targetId": stationId])
    }

    public func requestScreen(stationId: String) {
        sendJson(["action": "get_screen", "targetId": stationId])
    }

    public func requestDrives(stationId: String) {
        sendJson(["action": "get_drives", "targetId": stationId])
    }

    public func browseDirectory(stationId: String, path: String) {
        DispatchQueue.main.async { self.isBrowsingLoading = true }
        sendJson(["action": "browse_dir", "targetId": stationId, "path": path])
    }

    public func executeFile(stationId: String, filePath: String) {
        sendJson(["action": "exec_file", "targetId": stationId, "filePath": filePath])
    }

    public func createFolder(stationId: String, parentPath: String, name: String) {
        sendJson(["action": "mkdir", "targetId": stationId, "parent": parentPath, "name": name])
    }

    public func deleteItem(stationId: String, path: String, parentPath: String) {
        sendJson(["action": "delete_item", "targetId": stationId, "path": path, "parent": parentPath])
    }

    public func downloadFile(stationId: String, url: String, destinationFolder: String, fileName: String?) {
        var payload: [String: Any] = [
            "action": "download_file",
            "targetId": stationId,
            "url": url,
            "destinationFolder": destinationFolder
        ]
        if let fn = fileName, !fn.isEmpty {
            payload["fileName"] = fn
        }
        sendJson(payload)
    }

    // ==================== DOCK & NOTIFICATIONS ====================

    private func updateDockBadge() {
        let onlineCount = stations.values.filter { $0.isOnline }.count
        if onlineCount > 0 {
            NSApp.dockTile.badgeLabel = "\(onlineCount)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendLocalNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
