import Foundation
import AppKit

public struct Station: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String?
    public var hostname: String?
    public var os: String?
    public var ip: String?
    public var status: String? // "online" / "offline"
    public var isLocked: Bool?
    public var sessionSeconds: Int?
    public var sessionTotalSeconds: Int?
    public var cpu: Int?
    public var ram: Int?
    public var ramTotalGb: Double?
    public var ramUsedGb: Double?
    public var battery: Int?
    public var isCharging: Bool?
    public var batteryStatus: String?
    public var activeWindow: String?
    public var lastSeen: Double?

    public var isOnline: Bool {
        return status == "online"
    }

    public var displayName: String {
        return name ?? id
    }

    public var formattedSessionTime: String {
        guard let sec = sessionSeconds, sec > 0 else { return "00:00:00" }
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

public struct DriveItem: Identifiable, Codable, Hashable {
    public var id: String { Name }
    public var Name: String
    public var Label: String
    public var TotalGb: Double
    public var FreeGb: Double
    public var DriveType: String
}

public struct FileSystemEntry: Identifiable, Codable, Hashable {
    public var id: String { FullPath }
    public var Name: String
    public var FullPath: String
    public var IsDirectory: Bool
    public var SizeBytes: Int64?
    public var SizeFormatted: String?
    public var Extension: String?
    public var IsExecutable: Bool?
    public var LastModified: String?
}

public struct DirectoryContentResult: Codable {
    public var CurrentPath: String
    public var ParentPath: String?
    public var Items: [FileSystemEntry]
    public var Error: String?
}
