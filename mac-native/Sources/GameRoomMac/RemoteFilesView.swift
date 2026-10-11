import SwiftUI

public struct RemoteFileBrowserSheet: View {
    public let station: Station
    @ObservedObject public var service: WebSocketService
    @Environment(\.dismiss) private var dismiss

    @State private var downloadUrlText: String = ""
    @State private var customFileNameText: String = ""
    @State private var selectedDriveName: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                    Text("Remote Files & Game Installer: \(station.displayName)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(nsColor: NSColor.windowBackgroundColor))

            Divider()

            // Drives Toolbar
            HStack(spacing: 8) {
                Text("Drives:")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)

                if service.drives.isEmpty {
                    Text("Scanning drives...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(service.drives) { drive in
                        Button {
                            selectedDriveName = drive.Name
                            service.browseDirectory(stationId: station.id, path: drive.Name)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive")
                                Text("\(drive.Name) (\(Int(drive.FreeGb)) GB free)")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedDriveName == drive.Name ? .cyan : .secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))

            Divider()

            // Navigation Bar (Up + Current Path)
            HStack(spacing: 8) {
                Button {
                    if let parent = service.currentDirectory?.ParentPath {
                        service.browseDirectory(stationId: station.id, path: parent)
                    }
                } label: {
                    Image(systemName: "arrow.up")
                    Text("Up")
                }
                .buttonStyle(.bordered)
                .disabled(service.currentDirectory?.ParentPath == nil)

                Text(service.currentDirectory?.CurrentPath ?? "Loading...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(4)

                Button {
                    if let current = service.currentDirectory?.CurrentPath {
                        service.browseDirectory(stationId: station.id, path: current)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // File Table / List
            ZStack {
                Color(nsColor: NSColor.controlBackgroundColor)

                if service.isBrowsingLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Reading laptop file system...")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                } else if let error = service.currentDirectory?.Error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                } else if let items = service.currentDirectory?.Items, !items.isEmpty {
                    List(items) { item in
                        HStack {
                            if item.IsDirectory {
                                Button {
                                    service.browseDirectory(stationId: station.id, path: item.FullPath)
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

                            Text(item.IsDirectory ? "<DIR>" : (item.SizeFormatted ?? "-"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)

                            Text(item.LastModified ?? "")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 140, alignment: .trailing)

                            if item.IsExecutable ?? false {
                                Button("▶ Run / Install") {
                                    confirmExecute(item.FullPath)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.small)
                            } else {
                                Text("-")
                                    .frame(width: 90)
                                    .foregroundColor(.clear)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listStyle(.inset)
                } else {
                    Text("Folder is empty.")
                        .foregroundColor(.gray)
                }
            }
            .frame(minHeight: 280)

            Divider()

            // Remote Downloader Tool
            VStack(alignment: .leading, spacing: 8) {
                Text("⚡ Download & Install Game / Software Remotely")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.cyan)

                HStack(spacing: 8) {
                    TextField("Paste direct download URL (e.g. https://.../setup.exe)", text: $downloadUrlText)
                        .textFieldStyle(.roundedBorder)

                    TextField("Filename (optional)", text: $customFileNameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                    Button("⬇ Download to Laptop") {
                        startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(downloadUrlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if service.isDownloading || !service.downloadStatusMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(service.downloadPercent), total: 100.0)
                        Text(service.downloadStatusMessage)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: NSColor.windowBackgroundColor))
        }
        .frame(width: 850, height: 620)
        .onAppear {
            service.requestDrives(stationId: station.id)
            service.browseDirectory(stationId: station.id, path: "")
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
            service.executeFile(stationId: station.id, filePath: path)
        }
    }

    private func startDownload() {
        guard let current = service.currentDirectory?.CurrentPath else { return }
        service.downloadFile(
            stationId: station.id,
            url: downloadUrlText.trimmingCharacters(in: .whitespaces),
            destinationFolder: current,
            fileName: customFileNameText.isEmpty ? nil : customFileNameText
        )
        downloadUrlText = ""
        customFileNameText = ""
    }

    private func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case ".exe", ".msi", ".bat", ".cmd": return "gearshape.fill"
        case ".zip", ".rar", ".7z", ".iso": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}
