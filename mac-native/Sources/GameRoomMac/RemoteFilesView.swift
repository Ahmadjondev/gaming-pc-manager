import SwiftUI
import AppKit

public struct RemoteFileBrowserSheet: View {
    public let station: Station
    public let service: WebSocketService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var fileManager: DirectFileManager
    @State private var downloadUrlText: String = ""
    @State private var customFileNameText: String = ""
    @State private var selectedDriveName: String = ""
    @State private var searchText: String = ""

    public init(station: Station, service: WebSocketService) {
        self.station = station
        self.service = service
        _fileManager = StateObject(wrappedValue: DirectFileManager(station: station, service: service))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ==================== HEADER ====================
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.cyan)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Files & Games: \(station.displayName)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(fileManager.isDirectMode ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)

                            Text(fileManager.connectionStatus)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(fileManager.isDirectMode ? .green : .orange)
                        }
                    }
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 8) {
                    Button(action: selectAndUploadFile) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.doc.fill")
                            Text("⬆ Upload to Laptop")
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    Button(action: promptNewFolder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                            Text("New Folder")
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)

                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(14)
            .background(Color(nsColor: NSColor.windowBackgroundColor))

            Divider()

            // ==================== DRIVES TOOLBAR ====================
            HStack(spacing: 8) {
                Text("Drives:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.gray)

                let currentDrives = fileManager.isDirectMode ? fileManager.drives : service.drives

                if currentDrives.isEmpty {
                    Text("Scanning drives...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(currentDrives) { drive in
                        Button {
                            selectedDriveName = drive.Name
                            fileManager.browseDirectory(path: drive.Name)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive.fill")
                                Text("\(drive.Name) (\(Int(drive.FreeGb)) GB free)")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedDriveName == drive.Name ? .cyan : .secondary)
                    }
                }

                Spacer()

                // Search filter in current directory
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Filter...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 120)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.02))

            Divider()

            // ==================== NAVIGATION / BREADCRUMBS ====================
            let activeDir = fileManager.isDirectMode ? fileManager.currentDirectory : service.currentDirectory

            HStack(spacing: 8) {
                Button {
                    if let parent = activeDir?.ParentPath {
                        fileManager.browseDirectory(path: parent)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                        Text("Up")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .disabled(activeDir?.ParentPath == nil)

                Text(activeDir?.CurrentPath ?? "Loading directory...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(4)

                Button {
                    if let current = activeDir?.CurrentPath {
                        fileManager.browseDirectory(path: current)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            Divider()

            // ==================== TRANSFER PROGRESS BAR ====================
            if fileManager.isTransferring {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView(value: fileManager.transferProgress, total: 1.0)
                        Text(fileManager.transferStatus)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.cyan.opacity(0.12))

                Divider()
            }

            // ==================== STATUS BANNER ====================
            if !fileManager.statusMessage.isEmpty {
                HStack {
                    Text(fileManager.statusMessage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(fileManager.isStatusError ? .red : .green)
                    Spacer()
                    Button("Dismiss") {
                        fileManager.statusMessage = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background((fileManager.isStatusError ? Color.red : Color.green).opacity(0.12))

                Divider()
            }

            // ==================== FILE TABLE / LIST ====================
            ZStack {
                Color(nsColor: NSColor.controlBackgroundColor)

                let loading = fileManager.isDirectMode ? fileManager.isLoading : service.isBrowsingLoading

                if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Reading laptop file system directly...")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                } else if let error = activeDir?.Error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                } else if let allItems = activeDir?.Items {
                    let items = searchText.isEmpty
                        ? allItems
                        : allItems.filter { $0.Name.localizedCaseInsensitiveContains(searchText) }

                    if items.isEmpty {
                        Text(searchText.isEmpty ? "Folder is empty." : "No matching files.")
                            .foregroundColor(.gray)
                    } else {
                        List(items) { item in
                            HStack(spacing: 8) {
                                // Icon & Name
                                if item.IsDirectory {
                                    Button {
                                        fileManager.browseDirectory(path: item.FullPath)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "folder.fill")
                                                .foregroundColor(.cyan)
                                            Text(item.Name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.cyan)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: fileIcon(for: item.Extension ?? ""))
                                            .foregroundColor(.gray)
                                        Text(item.Name)
                                            .font(.system(size: 13))
                                    }
                                }

                                Spacer()

                                // Size
                                Text(item.IsDirectory ? "<DIR>" : (item.SizeFormatted ?? "-"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .trailing)

                                // Date Modified
                                Text(item.LastModified ?? "")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 130, alignment: .trailing)

                                // Direct Actions
                                HStack(spacing: 6) {
                                    if !item.IsDirectory {
                                        // Download to Mac button
                                        Button(action: {
                                            fileManager.downloadFileToMac(remotePath: item.FullPath, filename: item.Name)
                                        }) {
                                            Image(systemName: "arrow.down.circle")
                                                .font(.system(size: 13))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.cyan)
                                        .help("Download to Mac")
                                    }

                                    if item.IsExecutable ?? false {
                                        Button("▶ Run") {
                                            confirmExecute(item.FullPath)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.green)
                                        .controlSize(.small)
                                    }

                                    // Delete button
                                    Button(action: {
                                        confirmDelete(item: item)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.red.opacity(0.7))
                                    .help("Delete")
                                }
                                .frame(width: 130, alignment: .trailing)
                            }
                            .padding(.vertical, 2)
                        }
                        .listStyle(.inset)
                    }
                } else {
                    Text("Ready")
                        .foregroundColor(.gray)
                }
            }
            .frame(minHeight: 320)

            Divider()

            // ==================== WEB URL DOWNLOADER ====================
            VStack(alignment: .leading, spacing: 6) {
                Text("⚡ Download from Web URL Directly to Laptop")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)

                HStack(spacing: 8) {
                    TextField("Paste direct download URL (e.g. https://.../game-installer.exe)", text: $downloadUrlText)
                        .textFieldStyle(.roundedBorder)

                    TextField("Filename (optional)", text: $customFileNameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    Button("⬇ Start Download") {
                        startUrlDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(downloadUrlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            .background(Color(nsColor: NSColor.windowBackgroundColor))
        }
        .frame(width: 900, height: 650)
        .onAppear {
            fileManager.initialize()
        }
    }

    // ==================== ACTIONS ====================

    private func selectAndUploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Upload to Laptop"
        panel.message = "Choose a file to transfer directly to the laptop folder"

        if panel.runModal() == .OK, let selectedUrl = panel.url {
            let activeDir = fileManager.isDirectMode ? fileManager.currentDirectory : service.currentDirectory
            let currentPath = activeDir?.CurrentPath ?? "C:\\"
            fileManager.uploadFile(localUrl: selectedUrl, targetFolder: currentPath)
        }
    }

    private func promptNewFolder() {
        let alert = NSAlert()
        alert.messageText = "Create New Folder"
        alert.informativeText = "Enter a name for the new folder:"
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = "New Folder"
        alert.accessoryView = input

        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            let activeDir = fileManager.isDirectMode ? fileManager.currentDirectory : service.currentDirectory
            if let current = activeDir?.CurrentPath {
                fileManager.createFolder(parentPath: current, name: name)
            }
        }
    }

    private func confirmDelete(item: FileSystemEntry) {
        let alert = NSAlert()
        alert.messageText = "Delete \(item.IsDirectory ? "Folder" : "File")?"
        alert.informativeText = "Are you sure you want to permanently delete:\n\(item.FullPath)?"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let activeDir = fileManager.isDirectMode ? fileManager.currentDirectory : service.currentDirectory
            let parent = activeDir?.CurrentPath ?? ""
            fileManager.deleteItem(path: item.FullPath, parentPath: parent)
        }
    }

    private func confirmExecute(_ path: String) {
        let alert = NSAlert()
        alert.messageText = "Run Program on Laptop?"
        alert.informativeText = "Are you sure you want to execute:\n\(path)\non \(station.displayName)?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Run / Install")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            fileManager.executeFile(path: path)
        }
    }

    private func startUrlDownload() {
        let activeDir = fileManager.isDirectMode ? fileManager.currentDirectory : service.currentDirectory
        guard let current = activeDir?.CurrentPath else { return }

        fileManager.downloadFromUrl(
            url: downloadUrlText.trimmingCharacters(in: .whitespaces),
            destFolder: current,
            fileName: customFileNameText.isEmpty ? nil : customFileNameText
        )
        downloadUrlText = ""
        customFileNameText = ""
    }

    private func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case ".exe", ".msi", ".bat", ".cmd": return "gearshape.fill"
        case ".zip", ".rar", ".7z", ".iso", ".tar", ".gz": return "archivebox.fill"
        case ".png", ".jpg", ".jpeg", ".gif", ".bmp": return "photo.fill"
        case ".mp4", ".mkv", ".avi", ".mov": return "film.fill"
        case ".mp3", ".wav", ".flac": return "music.note"
        case ".txt", ".log", ".json", ".xml", ".ini", ".cfg": return "doc.text.fill"
        default: return "doc.fill"
        }
    }
}
