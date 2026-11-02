import AppKit
import ApplicationServices

/// 辅助功能通道：直接读通知中心横幅。
///
/// 系统把通知写进 usernoted 数据库有 5s 左右延迟，但横幅 UI 是实时的，
/// 所以这里负责「秒级提醒」，内容仍以数据库为准。
///
/// 横幅结构（实测 macOS 27）：
///   AXGroup subrole=AXNotificationCenterBanner id=<UUID>
///     desc="脚本编辑器 微信, 老婆, 正文"     ← App名 + 标题, 副标题, 正文
///     ├ AXStaticText id=title val=微信
///     └ AXStaticText id=body  val=1个通知   ← 分组横幅时正文被折叠
final class AXNotificationWatcher {
    /// title, body, appName, bundleID, 去重 key
    var onBanner: ((String, String, String, String, String) -> Void)?
    /// 通知中心面板里的横幅从「有」变「无」—— 用户点了「清除」，立刻同步清空本地列表。
    /// 不走数据库对账：系统把删除落库要 ~11s，这里走 UI 信号实现秒清。
    var onPanelCleared: (() -> Void)?

    private var timer: Timer?
    private var seen: [String: Date] = [:]
    /// 通知中心面板打开时，面板内横幅组数量；nil = 面板未打开
    private var lastPanelBannerCount: Int?
    /// 横幅归零的连续扫描次数（防渲染闪烁误判）
    private var zeroStreak = 0

    func start() {
        stop()
        let t = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: 扫描

    private func scan() {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        }
        var panelSeen = false
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            for window in elements(of: axApp, attribute: kAXWindowsAttribute as String) {
                collect(window, depth: 0)
                if watchClearPanel(window) { panelSeen = true }
            }
        }
        // 面板关闭：重置状态，避免下次打开渲染间隙误判为「清空」
        if !panelSeen {
            lastPanelBannerCount = nil
            zeroStreak = 0
        }
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 300 }
    }

    // MARK: 通知中心「清除」检测

    /// 监控通知中心面板（标题为 Notification Center 的窗口）：
    /// 面板打开且横幅组从 ≥1 变 0 —— 用户点了「清除」，立即回调 onPanelCleared。
    /// 返回是否见到了 NC 面板。
    private func watchClearPanel(_ window: AXUIElement) -> Bool {
        let title = string(of: window, attribute: kAXTitleAttribute as String) ?? ""
        guard title == "Notification Center" else { return false }
        let count = countBanners(window, depth: 0)

        if let last = lastPanelBannerCount, last >= 1, count == 0 {
            zeroStreak += 1
            if zeroStreak >= 2 {
                onPanelCleared?()
                zeroStreak = 0
                lastPanelBannerCount = count
            }
        } else {
            zeroStreak = 0
            lastPanelBannerCount = count
        }
        return true
    }

    private func countBanners(_ element: AXUIElement, depth: Int) -> Int {
        guard depth < 9 else { return 0 }
        var n = 0
        let subrole = string(of: element, attribute: kAXSubroleAttribute as String) ?? ""
        if subrole == "AXNotificationCenterBannerStack" || subrole == "AXNotificationCenterBanner" {
            n += 1
        }
        for child in elements(of: element, attribute: kAXChildrenAttribute as String) {
            n += countBanners(child, depth: depth + 1)
        }
        return n
    }

    private func collect(_ element: AXUIElement, depth: Int) {
        guard depth < 9 else { return }
        if string(of: element, attribute: kAXSubroleAttribute as String) == "AXNotificationCenterBanner" {
            handle(element)
            return
        }
        for child in elements(of: element, attribute: kAXChildrenAttribute as String) {
            collect(child, depth: depth + 1)
        }
    }

    private func handle(_ banner: AXUIElement) {
        let uuid = string(of: banner, attribute: "AXIdentifier") ?? UUID().uuidString
        let desc = string(of: banner, attribute: "AXAttributedDescription") ?? ""

        var title = ""
        var body = ""
        for child in elements(of: banner, attribute: kAXChildrenAttribute as String) {
            let ident = string(of: child, attribute: "AXIdentifier") ?? ""
            let value = string(of: child, attribute: kAXValueAttribute as String)
                ?? string(of: child, attribute: kAXTitleAttribute as String) ?? ""
            if ident == "title" { title = value }
            if ident == "body" { body = value }
        }

        // 分组横幅的 body 只是「N个通知」，改用 desc 里的完整文案
        if body.hasSuffix("个通知") { body = "" }

        var appName = ""
        var appBundle = ""
        let parts = desc.components(separatedBy: ", ")
        if let head = parts.first, !head.isEmpty {
            if let matched = matchRunningApp(in: head), let name = matched.localizedName {
                appName = name
                appBundle = matched.bundleIdentifier ?? ""
                let rest = String(head.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { title = rest }
            } else if let (name, bundle) = matchInstalledApp(in: head) {
                appName = name
                appBundle = bundle
                let rest = String(head.dropFirst(name.count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { title = rest }
            } else if title.isEmpty {
                title = head
            }
            if body.isEmpty {
                if parts.count >= 3 {
                    // App名+标题, 副标题, 正文 → 只取正文
                    body = parts.dropFirst(2).joined(separator: ", ")
                } else if parts.count == 2 {
                    body = parts[1]
                }
            }
        }

        guard !title.trimmed.isEmpty || !body.trimmed.isEmpty else { return }

        let key = uuid + "|" + desc
        if seen[key] != nil { return }
        seen[key] = Date()

        onBanner?(title, body, appName, appBundle, key)
    }

    /// desc 开头的应用名与运行中的 App 做前缀匹配（取最长命中）
    private func matchRunningApp(in text: String) -> NSRunningApplication? {
        var best: (NSRunningApplication, Int)?
        for app in NSWorkspace.shared.runningApplications {
            guard let name = app.localizedName, !name.isEmpty else { continue }
            if text.hasPrefix(name) {
                if best == nil || name.count > best!.1 {
                    best = (app, name.count)
                }
            }
        }
        return best?.0
    }

    /// 应用没在运行时，按安装目录索引反查
    private func matchInstalledApp(in text: String) -> (String, String)? {
        var best: (String, String)?
        for (name, bundle) in AppInfo.bundleIndex {
            guard !name.isEmpty, text.hasPrefix(name) else { continue }
            if best == nil || name.count > best!.0.count {
                best = (name, bundle)
            }
        }
        return best
    }

    // MARK: AX 取值

    private func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if CFGetTypeID(value) == CFStringGetTypeID() { return value as? String }
        if CFGetTypeID(value) == CFAttributedStringGetTypeID() { return (value as? NSAttributedString)?.string }
        return nil
    }

    private func elements(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        guard let array = value as? [AXUIElement] else { return [] }
        return array
    }
}
