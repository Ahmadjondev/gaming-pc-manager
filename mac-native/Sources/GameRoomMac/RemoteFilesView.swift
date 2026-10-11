import SwiftUI
import AppKit

public struct RemoteFileBrowserSheet: View {
    public let station: Station
    @ObservedObject public var service: WebSocketService
    @Environment(\.dismiss) private var dismiss

    @StateObject private var fileManager: DirectFileManager
    @State private var downloadUrlText: String = ""
    @State private var customFileNameText: String = ""
    @State private var selectedDriveName: String = ""
    @State private var searchText: String = ""
    @State private var showHiddenFiles: Bool = true // Default true to show hidden files

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

                let currentDrives = !fileManager.drives.isEmpty ? fileManager.drives : service.drives

                if currentDrives.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning drives...")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
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

                // Hidden Files Visibility Toggle
                Button {
                    showHiddenFiles.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showHiddenFiles ? "eye.fill" : "eye.slash")
                        Text(showHiddenFiles ? "Hidden Files: Shown" : "Hidden Files: Hidden")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(showHiddenFiles ? .purple : .secondary)
                .help("Toggle visibility of hidden and system files")

                // Search filter in current directory
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Filter...", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 120)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
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
            let activeDir = fileManager.currentDirectory ?? service.currentDirectory

            HStack(spacing: 8) {
                Button {
                    if let parent = activeDir?.ParentPath, !parent.isEmpty {
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
                .disabled(activeDir?.ParentPath == nil || activeDir?.ParentPath?.isEmpty == true)

                HStack {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.cyan)

                    Text(activeDir?.CurrentPath ?? "Scanning directory...")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.35))
                .cornerRadius(4)

                Button {
                    let cur = activeDir?.CurrentPath ?? ""
                    fileManager.browseDirectory(path: cur)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh directory")
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

                let loading = fileManager.isLoading || (!fileManager.isDirectMode && service.isBrowsingLoading)

                if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(fileManager.isDirectMode ? "Reading laptop file system directly..." : "Loading directory via Cloud Relay...")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = activeDir?.Error, !error.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                        Text("Error: \(error)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                        Button("Retry") {
                            fileManager.browseDirectory(path: activeDir?.CurrentPath ?? "")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let active = activeDir {
                    let rawItems = active.safeItems
                    let items = rawItems.filter { item in
                        if !showHiddenFiles && (item.IsHidden == true) {
                            return false
                        }
                        if !searchText.isEmpty {
                            return item.Name.localizedCaseInsensitiveContains(searchText)
                        }
                        return true
                    }

                    if items.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text(searchText.isEmpty ? "This directory is empty." : "No matching files or folders.")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))

                            if !showHiddenFiles && rawItems.contains(where: { $0.IsHidden == true }) {
                                Button("Show \(rawItems.filter { $0.IsHidden == true }.count) Hidden Items") {
                                    showHiddenFiles = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.purple)
                                .font(.system(size: 11))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(items) { item in
                            let isHiddenItem = (item.IsHidden == true)
                            let isSystemItem = (item.IsSystem == true)

                            HStack(spacing: 8) {
                                // Icon & Name
                                if item.IsDirectory {
                                    Button {
                                        fileManager.browseDirectory(path: item.FullPath)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: isHiddenItem ? "folder.badge.gearshape" : "folder.fill")
                                                .foregroundColor(isHiddenItem ? .cyan.opacity(0.65) : .cyan)
                                            Text(item.Name)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(isHiddenItem ? .cyan.opacity(0.75) : .cyan)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: fileIcon(for: item.Extension ?? ""))
                                            .foregroundColor(isHiddenItem ? .gray.opacity(0.6) : .gray)
                                        Text(item.Name)
                                            .font(.system(size: 13))
                                            .foregroundColor(isHiddenItem ? .secondary : .primary)
                                    }
                                }

                                // Badges for hidden / system files
                                if isHiddenItem {
                                    Text("HIDDEN")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.25))
                                        .foregroundColor(.purple)
                                        .cornerRadius(3)
                                }
                                if isSystemItem {
                                    Text("SYS")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.25))
                                        .foregroundColor(.orange)
                                        .cornerRadius(3)
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

                                // Actions
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
                            .opacity(isHiddenItem ? 0.75 : 1.0)
                        }
                        .listStyle(.inset)
                    }
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Connecting to laptop...")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            let activeDir = fileManager.currentDirectory ?? service.currentDirectory
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
            let activeDir = fileManager.currentDirectory ?? service.currentDirectory
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
            let activeDir = fileManager.currentDirectory ?? service.currentDirectory
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
        let activeDir = fileManager.currentDirectory ?? service.currentDirectory
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
