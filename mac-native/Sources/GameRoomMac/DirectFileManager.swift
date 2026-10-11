import Foundation
import AppKit
import Combine

public class DirectFileManager: NSObject, ObservableObject, URLSessionTaskDelegate {
    public let station: Station
    public let service: WebSocketService

    @Published public var isDirectMode: Bool = false
    @Published public var connectionStatus: String = "Connecting..."
    @Published public var drives: [DriveItem] = []
    @Published public var currentDirectory: DirectoryContentResult? = nil
    @Published public var isLoading: Bool = false
    @Published public var statusMessage: String = ""
    @Published public var isStatusError: Bool = false

    // Progress & Transfer
    @Published public var isTransferring: Bool = false
    @Published public var transferProgress: Double = 0.0
    @Published public var transferStatus: String = ""

    private var session: URLSession!
    private var transferStartTime: Date?
    private var totalBytesToTransfer: Int64 = 0
    private var cancellables = Set<AnyCancellable>()

    public var activeBaseUrl: String = ""

    public var baseUrl: String {
        if !activeBaseUrl.isEmpty { return activeBaseUrl }
        let ip = station.ip ?? "127.0.0.1"
        let port = station.controlPort ?? 48999
        return "http://\(ip):\(port)"
    }

    public init(station: Station, service: WebSocketService) {
        self.station = station
        self.service = service
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 7200 // 2 hours for large game transfers
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)

        // Observe cloud service drives when in Cloud Relay mode
        service.$drives
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDrives in
                guard let self = self, !self.isDirectMode else { return }
                if !newDrives.isEmpty {
                    self.drives = newDrives
                }
            }
            .store(in: &cancellables)

        // Observe cloud service currentDirectory when in Cloud Relay mode
        service.$currentDirectory
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newDir in
                guard let self = self, !self.isDirectMode else { return }
                if let dir = newDir {
                    self.currentDirectory = dir
                    self.isLoading = false
                    if let err = dir.Error, !err.isEmpty {
                        self.statusMessage = "Directory Error: \(err)"
                        self.isStatusError = true
                    }
                }
            }
            .store(in: &cancellables)

        // Observe cloud service loading state
        service.$isBrowsingLoading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loading in
                guard let self = self, !self.isDirectMode else { return }
                self.isLoading = loading
            }
            .store(in: &cancellables)
    }

    // ==================== INITIALIZATION & CONNECTIVITY ====================

    public func initialize() {
        var candidates: [String] = []
        if let lanIp = station.ip, !lanIp.isEmpty {
            candidates.append(lanIp)
        }
        if let tailscaleIp = station.tailscaleIp, !tailscaleIp.isEmpty, !candidates.contains(tailscaleIp) {
            candidates.append(tailscaleIp)
        }
        if let publicIp = station.publicIp, !publicIp.isEmpty, !candidates.contains(publicIp) {
            candidates.append(publicIp)
        }

        if candidates.isEmpty {
            fallbackToCloud()
            return
        }

        tryCandidate(candidates: candidates, index: 0)
    }

    private func tryCandidate(candidates: [String], index: Int) {
        guard index < candidates.count else {
            fallbackToCloud()
            return
        }

        let ip = candidates[index]
        let port = station.controlPort ?? 48999
        let candidateBase = "http://\(ip):\(port)"
        connectionStatus = "Checking Direct (\(ip):\(port))..."
        isLoading = true

        guard let statusUrl = URL(string: "\(candidateBase)/status") else {
            tryCandidate(candidates: candidates, index: index + 1)
            return
        }

        var req = URLRequest(url: statusUrl)
        req.timeoutInterval = 1.8

        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    self.activeBaseUrl = candidateBase
                    self.isDirectMode = true
                    let modeName = (ip == self.station.ip) ? "⚡ Direct LAN" : "⚡ Direct WAN"
                    self.connectionStatus = "\(modeName) (\(ip):\(port))"
                    self.loadDrives()
                    self.browseDirectory(path: "")
                } else {
                    self.tryCandidate(candidates: candidates, index: index + 1)
                }
            }
        }
        task.resume()
    }

    private func fallbackToCloud() {
        self.isDirectMode = false
        self.connectionStatus = "☁️ Cloud Relay Mode"
        self.isLoading = true
        self.service.requestDrives(stationId: station.id)
        self.service.browseDirectory(stationId: station.id, path: "")
    }

    // ==================== DRIVES & BROWSING ====================

    public func loadDrives() {
        if !isDirectMode {
            service.requestDrives(stationId: station.id)
            return
        }

        guard let url = URL(string: "\(baseUrl)/api/files/drives") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data else { return }
            do {
                let items = try JSONDecoder().decode([DriveItem].self, from: data)
                DispatchQueue.main.async {
                    self.drives = items
                }
            } catch {
                print("[DirectFiles] Drives decode error: \(error)")
            }
        }.resume()
    }

    public func browseDirectory(path: String) {
        isLoading = true
        statusMessage = ""
        isStatusError = false

        if !isDirectMode {
            service.browseDirectory(stationId: station.id, path: path)
            return
        }

        var components = URLComponents(string: "\(baseUrl)/api/files/list")
        components?.queryItems = [URLQueryItem(name: "path", value: path)]

        guard let url = components?.url else { 
            isLoading = false
            return 
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.statusMessage = "Error: \(error.localizedDescription)"
                    self.isStatusError = true
                    return
                }

                guard let data = data else { return }
                do {
                    let result = try JSONDecoder().decode(DirectoryContentResult.self, from: data)
                    self.currentDirectory = result
                    self.statusMessage = ""
                } catch {
                    self.statusMessage = "Failed to parse folder content: \(error.localizedDescription)"
                    self.isStatusError = true
                }
            }
        }.resume()
    }

    // ==================== EXECUTE REMOTE PROGRAM ====================

    public func executeFile(path: String, args: String? = nil) {
        if !isDirectMode {
            service.executeFile(stationId: station.id, filePath: path)
            statusMessage = "⚡ Launch command sent via Cloud Relay for \(URL(fileURLWithPath: path).lastPathComponent)"
            isStatusError = false
            return
        }

        guard let url = URL(string: "\(baseUrl)/api/files/exec") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["filePath": path, "args": args ?? ""]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.statusMessage = "Exec error: \(error.localizedDescription)"
                    self.isStatusError = true
                    return
                }
                guard let data = data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

                let msg = obj["message"] as? String ?? "Launched"
                self.statusMessage = "▶ \(msg)"
                self.isStatusError = !(obj["success"] as? Bool ?? false)
            }
        }.resume()
    }

    // ==================== DIRECT LAN FILE UPLOAD (Mac -> Laptop) ====================

    public func uploadFile(localUrl: URL, targetFolder: String) {
        if !isDirectMode {
            statusMessage = "Direct LAN or WAN connection is required for multi-megabyte file uploads to laptop."
            isStatusError = true
            return
        }

        let filename = localUrl.lastPathComponent

        var components = URLComponents(string: "\(baseUrl)/api/files/upload")
        components?.queryItems = [
            URLQueryItem(name: "folder", value: targetFolder),
            URLQueryItem(name: "filename", value: filename)
        ]

        guard let url = components?.url else { return }

        guard let fileAttrs = try? FileManager.default.attributesOfItem(atPath: localUrl.path),
              let fileSize = fileAttrs[.size] as? Int64 else {
            statusMessage = "Cannot read local file size"
            isStatusError = true
            return
        }

        self.totalBytesToTransfer = fileSize
        self.transferStartTime = Date()
        self.isTransferring = true
        self.transferProgress = 0.0
        self.transferStatus = "Preparing to upload \(filename) (\(formatBytes(fileSize)))..."

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let task = session.uploadTask(with: req, fromFile: localUrl) { [weak self] data, response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isTransferring = false
                if let error = error {
                    self.statusMessage = "Upload failed: \(error.localizedDescription)"
                    self.isStatusError = true
                    return
                }

                if let data = data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = obj["message"] as? String {
                    self.statusMessage = "✅ \(msg)"
                    self.isStatusError = false
                } else {
                    self.statusMessage = "✅ Upload completed for \(filename)"
                    self.isStatusError = false
                }

                // Refresh current folder to show the newly uploaded file immediately
                self.browseDirectory(path: targetFolder)
            }
        }
        task.resume()
    }

    // ==================== DIRECT LAN FILE DOWNLOAD (Laptop -> Mac) ====================

    public func downloadFileToMac(remotePath: String, filename: String) {
        if !isDirectMode {
            statusMessage = "Direct LAN required for direct file download. For web games/files, use the URL downloader below."
            isStatusError = true
            return
        }

        var components = URLComponents(string: "\(baseUrl)/api/files/download")
        components?.queryItems = [URLQueryItem(name: "path", value: remotePath)]

        guard let url = components?.url else { return }

        isTransferring = true
        transferProgress = 0.0
        transferStatus = "Downloading \(filename) from laptop directly over LAN..."

        let task = session.downloadTask(with: url) { [weak self] tempUrl, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.statusMessage = "Download failed: \(error.localizedDescription)"
                    self.isStatusError = true
                }
                return
            }

            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode >= 400 {
                var errMsg = "Server returned HTTP \(httpResp.statusCode)"
                if let temp = tempUrl, let text = try? String(contentsOf: temp, encoding: .utf8), !text.isEmpty {
                    errMsg = text
                }
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.statusMessage = "Download failed: \(errMsg)"
                    self.isStatusError = true
                }
                return
            }

            guard let tempUrl = tempUrl, FileManager.default.fileExists(atPath: tempUrl.path) else {
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.statusMessage = "Download failed: Temporary file not found"
                    self.isStatusError = true
                }
                return
            }

            // Target destination in ~/Downloads
            let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            try? FileManager.default.createDirectory(at: downloadsUrl, withIntermediateDirectories: true)

            var destUrl = downloadsUrl.appendingPathComponent(filename)
            var counter = 1
            while FileManager.default.fileExists(atPath: destUrl.path) {
                let ext = (filename as NSString).pathExtension
                let base = (filename as NSString).deletingPathExtension
                let newName = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
                destUrl = downloadsUrl.appendingPathComponent(newName)
                counter += 1
            }

            // CRITICAL: Must copy/move BEFORE the completion handler returns,
            // otherwise CFNetwork deletes the temporary file immediately!
            do {
                try FileManager.default.copyItem(at: tempUrl, to: destUrl)
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.statusMessage = "✅ Saved to Downloads/\(destUrl.lastPathComponent)"
                    self.isStatusError = false
                    NSWorkspace.shared.activateFileViewerSelecting([destUrl])
                }
            } catch {
                DispatchQueue.main.async {
                    self.isTransferring = false
                    self.statusMessage = "Failed saving file: \(error.localizedDescription)"
                    self.isStatusError = true
                }
            }
        }
        task.resume()
    }

    // ==================== CREATE FOLDER & DELETE ====================

    public func createFolder(parentPath: String, name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        if !isDirectMode {
            isLoading = true
            service.createFolder(stationId: station.id, parentPath: parentPath, name: name)
            return
        }

        guard let url = URL(string: "\(baseUrl)/api/files/mkdir") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["parent": parentPath, "name": name]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.statusMessage = "Create folder error: \(error.localizedDescription)"
                    self.isStatusError = true
                    return
                }
                self.browseDirectory(path: parentPath)
            }
        }.resume()
    }

    public func deleteItem(path: String, parentPath: String) {
        if !isDirectMode {
            isLoading = true
            service.deleteItem(stationId: station.id, path: path, parentPath: parentPath)
            return
        }

        guard let url = URL(string: "\(baseUrl)/api/files/delete") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["path": path]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.statusMessage = "Delete error: \(error.localizedDescription)"
                    self.isStatusError = true
                    return
                }
                self.browseDirectory(path: parentPath)
            }
        }.resume()
    }

    // ==================== DOWNLOAD FROM WEB URL ====================

    public func downloadFromUrl(url: String, destFolder: String, fileName: String?) {
        if !isDirectMode {
            service.downloadFile(stationId: station.id, url: url, destinationFolder: destFolder, fileName: fileName)
            return
        }

        guard let endpoint = URL(string: "\(baseUrl)/api/files/download_url") else { return }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["url": url, "destinationFolder": destFolder]
        if let fn = fileName, !fn.isEmpty {
            body["fileName"] = fn
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    self.statusMessage = "Download trigger failed: \(error.localizedDescription)"
                    self.isStatusError = true
                } else {
                    self.statusMessage = "⚡ Background download started on laptop!"
                    self.isStatusError = false
                }
            }
        }.resume()
    }

    // ==================== URLSESSION DELEGATE (PROGRESS TRACKING) ====================

    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            guard totalBytesExpectedToSend > 0 else { return }
            let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            self.transferProgress = fraction

            var speedStr = ""
            if let start = self.transferStartTime {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > 0.5 {
                    let speedBytesPerSec = Double(totalBytesSent) / elapsed
                    speedStr = " • \(self.formatBytes(Int64(speedBytesPerSec)))/s"
                }
            }

            let pct = Int(fraction * 100)
            self.transferStatus = "Uploading: \(pct)% (\(self.formatBytes(totalBytesSent)) of \(self.formatBytes(totalBytesExpectedToSend)))\(speedStr)"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        if b < 1024 * 1024 { return String(format: "%.1f KB", b / 1024.0) }
        if b < 1024 * 1024 * 1024 { return String(format: "%.1f MB", b / (1024.0 * 1024.0)) }
        return String(format: "%.2f GB", b / (1024.0 * 1024.0 * 1024.0))
    }
}
