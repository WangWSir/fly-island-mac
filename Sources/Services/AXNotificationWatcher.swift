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

    private var timer: Timer?
    private var seen: [String: Date] = [:]

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
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            for window in elements(of: axApp, attribute: kAXWindowsAttribute as String) {
                collect(window, depth: 0)
            }
        }
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 300 }
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
