import Foundation
import SwiftUI

// MARK: - CloudProvider
enum CloudProvider: String, CaseIterable, Codable, Identifiable {
    case onedrive    = "onedrive"
    case googledrive = "drive"
    case dropbox     = "dropbox"
    case s3          = "s3"
    case sftp        = "sftp"
    case box         = "box"
    case mega        = "mega"
    case backblaze   = "b2"
    case azureblob   = "azureblob"
    case generic     = "generic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onedrive:    return "OneDrive"
        case .googledrive: return "Google Drive"
        case .dropbox:     return "Dropbox"
        case .s3:          return "Amazon S3"
        case .sftp:        return "SFTP"
        case .box:         return "Box"
        case .mega:        return "MEGA"
        case .backblaze:   return "Backblaze B2"
        case .azureblob:   return "Azure Blob"
        case .generic:     return "Otro"
        }
    }

    var icon: String {
        switch self {
        case .onedrive:    return "cloud.fill"
        case .googledrive: return "externaldrive.connected.to.line.below.fill"
        case .dropbox:     return "shippingbox.fill"
        case .s3:          return "server.rack"
        case .sftp:        return "terminal.fill"
        case .box:         return "square.fill"
        case .mega:        return "m.circle.fill"
        case .backblaze:   return "flame.fill"
        case .azureblob:   return "cloud.bolt.fill"
        case .generic:     return "externaldrive.fill"
        }
    }

    var color: Color {
        switch self {
        case .onedrive:    return Color(hex: "#0078D4")
        case .googledrive: return Color(hex: "#4285F4")
        case .dropbox:     return Color(hex: "#0061FF")
        case .s3:          return Color(hex: "#FF9900")
        case .sftp:        return Color(hex: "#6B7280")
        case .box:         return Color(hex: "#0061D5")
        case .mega:        return Color(hex: "#D9272E")
        case .backblaze:   return Color(hex: "#E05C34")
        case .azureblob:   return Color(hex: "#0089D6")
        case .generic:     return Color(hex: "#6B7280")
        }
    }

    static func detect(from remoteName: String, rcloneType: String?) -> CloudProvider {
        let type = rcloneType?.lowercased() ?? remoteName.lowercased()
        for provider in CloudProvider.allCases {
            if type.contains(provider.rawValue) { return provider }
        }
        if type.contains("google") { return .googledrive }
        if type.contains("azure")  { return .azureblob }
        return .generic
    }
}

// MARK: - MountStatus
enum MountStatus: Equatable {
    case unmounted
    case mounting
    case mounted
    case unmounting
    case error(String)

    var label: String {
        switch self {
        case .unmounted:        return "No montado"
        case .mounting:         return "Montando..."
        case .mounted:          return "Montado"
        case .unmounting:       return "Desmontando..."
        case .error(let msg):   return "Error: \(msg)"
        }
    }

    var color: Color {
        switch self {
        case .unmounted:   return .secondary
        case .mounting:    return .blue
        case .mounted:     return .green
        case .unmounting:  return .orange
        case .error:       return .red
        }
    }

    var isBusy: Bool { self == .mounting || self == .unmounting }
    var isMounted: Bool { self == .mounted }
}

// MARK: - DriveInfo
struct DriveInfo {
    var total: Int64 = 0
    var used: Int64 = 0
    var free: Int64 = 0

    var usedPercent: Double {
        guard total > 0 else { return 0 }
        return Double(used) / Double(total)
    }

    static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useKB]
        return f.string(fromByteCount: bytes)
    }
}

// MARK: - Account
class Account: ObservableObject, Identifiable, Codable {
    let id: UUID
    var remoteName: String
    var label: String
    var provider: CloudProvider
    var autoMount: Bool
    var mountPath: String
    var notes: String

    @Published var status: MountStatus = .unmounted
    @Published var driveInfo: DriveInfo? = nil
    @Published var lastError: String? = nil
    @Published var cloudFree: Int64? = nil
    @Published var cloudTotal: Int64? = nil
    @Published var localSize: Int64? = nil

    var isMounted: Bool { status.isMounted }

    var resolvedMountPath: String {
        mountPath.isEmpty ? "\(NSHomeDirectory())/CloudMounts/\(remoteName)" : mountPath
    }

    init(id: UUID = UUID(),
         remoteName: String,
         label: String,
         provider: CloudProvider,
         autoMount: Bool = false,
         mountPath: String = "",
         notes: String = "") {
        self.id = id
        self.remoteName = remoteName
        self.label = label
        self.provider = provider
        self.autoMount = autoMount
        self.mountPath = mountPath
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, remoteName, label, provider, autoMount, mountPath, notes
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decode(UUID.self, forKey: .id)
        remoteName = try c.decode(String.self, forKey: .remoteName)
        label      = try c.decode(String.self, forKey: .label)
        provider   = try c.decode(CloudProvider.self, forKey: .provider)
        autoMount  = try c.decode(Bool.self, forKey: .autoMount)
        mountPath  = try c.decodeIfPresent(String.self, forKey: .mountPath) ?? ""
        notes      = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,         forKey: .id)
        try c.encode(remoteName, forKey: .remoteName)
        try c.encode(label,      forKey: .label)
        try c.encode(provider,   forKey: .provider)
        try c.encode(autoMount,  forKey: .autoMount)
        try c.encode(mountPath,  forKey: .mountPath)
        try c.encode(notes,      forKey: .notes)
    }
}

// MARK: - LogEntry
struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let level: Level

    enum Level { case info, success, warning, error }

    var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Color hex helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
