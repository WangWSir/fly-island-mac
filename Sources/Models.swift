import AppKit

// MARK: - 通知

struct NotificationItem: Identifiable, Equatable {
    let id: Int64            // usernoted record id
    let bundleID: String
    let title: String
    let body: String
    let date: Date
    var isRead: Bool

    var appName: String { AppInfo.name(for: bundleID) }
    var icon: NSImage { AppInfo.icon(for: bundleID) }
    var timeText: String { RelativeTime.string(from: date) }
}

// MARK: - 剪贴板

enum ClipKind: String, Codable {
    case text
    case image
}

struct ClipItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ClipKind
    var text: String?          // text 内容，或图片的备注
    var imageFile: String?     // 图片文件名（存在数据目录）
    var date: Date = Date()
    var pinned: Bool = false
    var source: String?

    var previewText: String {
        guard let t = text, !t.isEmpty else {
            return kind == .image ? "图片" : ""
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var singleLine: String {
        previewText.replacingOccurrences(of: "\n", with: " ")
    }

    var timeText: String { RelativeTime.string(from: date) }
}

// MARK: - 媒体

struct NowPlaying: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Double = 0
    var elapsed: Double = 0
    var rate: Double = 0
    var playing: Bool = false
    var pid: Int = 0

    var isActive: Bool { !title.isEmpty || !artist.isEmpty }
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }
    var sourceApp: NSRunningApplication? {
        pid > 0 ? NSRunningApplication(processIdentifier: pid_t(pid)) : nil
    }
    var sourceName: String {
        sourceApp?.localizedName ?? (artist.isEmpty ? "" : artist)
    }
}

// MARK: - 工具

enum RelativeTime {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func string(from date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "刚刚" }
        if delta < 3600 { return "\(Int(delta / 60)) 分钟前" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return formatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨天" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = delta < 86400 * 7 ? "M月d日" : "M月d日"
        return f.string(from: date)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
