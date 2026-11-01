import AppKit
import ApplicationServices

/// 应用元信息：名称、图标、路径，带缓存。
enum AppInfo {
    private static var nameCache: [String: String] = [:]
    private static var iconCache: [String: NSImage] = [:]
    private static let fallbackIcon: NSImage = {
        let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) ?? NSImage()
    }()

    /// 少数 bundle id 与显示名对不上，做一次兜底映射
    private static let aliases: [String: String] = [
        "com.tencent.xinwechat": "微信",
        "com.tencent.xinWeChat": "微信",
        "com.tencent.qq": "QQ",
        "com.apple.mail": "邮件",
        "com.apple.MobileSMS": "信息",
        "com.tencent.workbuddy.mac": "WorkBuddy",
        "com.apple.notificationcenterui": "系统",
    ]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        if let alias = aliases[bundleID] { return alias }
        if let cached = nameCache[bundleID] { return cached }
        var name: String?
        if let url = url(for: bundleID) {
            let display = FileManager.default.displayName(atPath: url.path)
            name = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        }
        if name == nil {
            // 兜底：bundle id 最后一段
            name = bundleID.split(separator: ".").last.map(String.init) ?? "通知"
        }
        let value = name ?? "通知"
        nameCache[bundleID] = value
        return value
    }

    /// 应用显示名 → bundle id 索引（横幅里只给名字，需要反查图标与跳转目标）
    static let bundleIndex: [String: String] = {
        var index: [String: String] = [:]
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier else { continue }
                let display = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                index[display] = id
                if let n = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { index[n] = id }
                if let n = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String { index[n] = id }
            }
        }
        return index
    }()

    /// 按显示名找 bundle id：先看正在运行的（最准），再查安装索引
    static func bundleID(forAppNamed name: String) -> String? {
        let trimmed = name.trimmed
        guard !trimmed.isEmpty else { return nil }
        for app in NSWorkspace.shared.runningApplications {
            if app.localizedName == trimmed, let id = app.bundleIdentifier { return id }
            if let n = app.localizedName, !n.isEmpty, trimmed.hasPrefix(n), let id = app.bundleIdentifier { return id }
        }
        if let id = bundleIndex[trimmed] { return id }
        for (key, id) in bundleIndex where trimmed.hasPrefix(key) { return id }
        return nil
    }

    static func icon(for bundleID: String) -> NSImage {
        if let cached = iconCache[bundleID] { return cached }
        var image: NSImage?
        if let url = url(for: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        if image == nil, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            image = app.icon
        }
        let value = image ?? fallbackIcon
        iconCache[bundleID] = value
        return value
    }

    static func activate(bundleID: String) {
        guard let url = url(for: bundleID) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg, completionHandler: nil)
    }
}

/// 各类系统权限的检测与引导。
enum Permissions {
    /// 完全磁盘访问权限：能否读到 usernoted 数据库
    static var fullDiskAccess: Bool {
        let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        do {
            _ = try fh.read(upToCount: 16)
            return true
        } catch {
            return false
        }
    }

    /// 辅助功能权限
    static var accessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

/// 数据目录管理。
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("FlyIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var clipsFile: URL { support.appendingPathComponent("clips.json") }
    static var imagesDir: URL = {
        let dir = support.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static var cacheDir: URL = {
        let dir = support.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}
