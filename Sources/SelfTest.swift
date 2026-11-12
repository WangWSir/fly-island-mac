import AppKit
import Foundation

/// 自检：不打开界面，直接验证三条数据链路是否工作。
/// 用法：FlyIsland.app/Contents/MacOS/FlyIsland --selftest
enum SelfTest {
    @MainActor
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--selftest") || CommandLine.arguments.contains("--axtest") else { return false }
        setvbuf(stdout, nil, _IONBF, 0)

        if CommandLine.arguments.contains("--axtest") {
            return runAXTest()
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        print("== 权限 ==")
        print("完全磁盘访问: \(Permissions.fullDiskAccess)")
        print("辅助功能: \(Permissions.accessibility)")
        if let screen = ScreenGeometry.preferred() {
            print("刘海尺寸: \(ScreenGeometry.notchWidth(for: screen)) x \(ScreenGeometry.notchHeight(for: screen))")
        } else {
            print("刘海尺寸: 无刘海屏（当前隐藏）")
        }
        print("笔记本: \(ScreenGeometry.isLaptop)  目标屏: \(ScreenGeometry.preferred()?.localizedName ?? "无")")

        let notifications = NotificationService()
        notifications.start()

        let clipboard = ClipboardService()
        clipboard.start()
        let token = "flyisland-selftest-\(UUID().uuidString.prefix(8))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)

        let media = MediaService()
        media.start()

        var arrivals: [NotificationItem] = []
        let baseline = notifications.items.count
        notifications.onNew = { item in
            arrivals.append(item)
            print(">> 实时到达: [\(item.appName)] \(item.title) → \(item.body)")
        }

        let wait: TimeInterval = CommandLine.arguments.contains("--wait") ? 8 : 2
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            print("== 通知 ==")
            print("数据库可用: \(notifications.dbAvailable) 已载入: \(notifications.items.count) 条 (初始 \(baseline))")
            for item in notifications.items.prefix(3) {
                print("  - [\(item.appName)/\(item.bundleID)] \(item.title) → \(item.body)")
            }
            print("实时新增: \(arrivals.count) 条")

            print("== 剪贴板 ==")
            print("捕获测试文本: \(clipboard.items.contains { $0.text == token })")
            print("记录条数: \(clipboard.items.count)")

            print("== 媒体 ==")
            print("桥接可用: \(media.available)")
            print("当前: \(media.now.title.isEmpty ? "(无)" : media.now.title) / \(media.now.artist) playing=\(media.now.playing) \(Int(media.now.elapsed))/\(Int(media.now.duration))")

            print("== 数据目录 ==")
            print(AppPaths.support.path)
            media.stop()
            clipboard.stop()
            notifications.stop()
            exit(0)
        }

        app.run()
        return true
    }

    /// 只测辅助功能抓横幅：FlyIsland --axtest
    @MainActor
    private static func runAXTest() -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        print("辅助功能: \(AXIsProcessTrusted())")

        if CommandLine.arguments.contains("--axtree") {
            return runAXTreeDump()
        }

        let watcher = AXNotificationWatcher()
        watcher.onBanner = { title, body, appName, bundleID, _ in
            print("BANNER | app=\(appName) | bundle=\(bundleID) | title=\(title) | body=\(body)")
        }
        watcher.start()
        print("开始监听 20s…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            watcher.stop()
            exit(0)
        }
        app.run()
        return true
    }

    /// 打印通知中心进程的 AX 树：FlyIsland --axtest --axtree
    @MainActor
    private static func runAXTreeDump() -> Bool {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var lastSignature = ""

        let timer = Timer(timeInterval: 0.4, repeats: true) { _ in
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == "com.apple.notificationcenterui"
            }
            var lines: [String] = []
            for running in apps {
                let axApp = AXUIElementCreateApplication(running.processIdentifier)
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                   let windows = value as? [AXUIElement] {
                    for (i, w) in windows.enumerated() {
                        walkDump(w, depth: 0, into: &lines, path: "W\(i)")
                    }
                }
            }
            let signature = lines.joined(separator: "\n")
            if !lines.isEmpty && signature != lastSignature {
                lastSignature = signature
                print("=== 快照 \(Date().timeIntervalSince1970) ===")
                print(signature)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        print("打印 AX 树 25s…")

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { exit(0) }
        app.run()
        return true
    }

    private static func walkDump(_ element: AXUIElement, depth: Int, into lines: inout [String], path: String) {
        guard depth < 7 else { return }
        func attr(_ name: String) -> String {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success, let v else { return "" }
            if let s = v as? String { return s }
            if CFGetTypeID(v) == CFAttributedStringGetTypeID() { return (v as? NSAttributedString)?.string ?? "" }
            if let n = v as? NSNumber { return "\(n)" }
            return ""
        }
        let role = attr(kAXRoleAttribute as String)
        let ident = attr("AXIdentifier")
        let title = attr(kAXTitleAttribute as String)
        let desc = attr("AXAttributedDescription")
        let value = attr(kAXValueAttribute as String)
        let subrole = attr(kAXSubroleAttribute as String)
        var text = String(repeating: "  ", count: depth) + "\(path) role=\(role)"
        if !subrole.isEmpty { text += " sub=\(subrole)" }
        if !ident.isEmpty { text += " id=\(ident)" }
        if !title.isEmpty { text += " title=\(title.prefix(40))" }
        if !desc.isEmpty { text += " desc=\(desc.prefix(80))" }
        if !value.isEmpty { text += " val=\(value.prefix(60))" }
        lines.append(text)

        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &v) == .success,
           let children = v as? [AXUIElement] {
            for (i, c) in children.enumerated() {
                walkDump(c, depth: depth + 1, into: &lines, path: "\(path).\(i)")
            }
        }
    }
}
