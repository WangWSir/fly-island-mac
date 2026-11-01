import AppKit
import SwiftUI

/// 离屏渲染：把各个状态画成 PNG，便于在没有屏幕录制权限时检查视觉。
enum RenderMode {
    @MainActor
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render") else { return false }
        let outDir = idx + 1 < args.count ? args[idx + 1] : "/tmp/flyisland-render"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        NSApplication.shared.setActivationPolicy(.prohibited)

        let model = IslandModel()
        model.notchWidth = 220
        model.notchHeight = 38
        seed(model)

        let scenarios: [(String, IslandState, IslandTab)] = [
            ("01-collapsed-idle", .collapsed, .notifications),
            ("02-collapsed-playing", .collapsed, .music),
            ("03-peek", .peek, .notifications),
            ("04-expanded-notifications", .expanded, .notifications),
            ("05-expanded-clipboard", .expanded, .clipboard),
            ("06-expanded-music", .expanded, .music),
            ("07-expanded-settings", .expanded, .settings),
        ]

        for (name, state, tab) in scenarios {
            model.state = state
            model.tab = tab
            if state == .peek { model.peekItem = previewNotifications().first }
            // playing 场景才放媒体
            if name.contains("playing") || tab == .music {
                model.media.seedPreview(previewNowPlaying(), cover: albumArt())
            } else {
                model.media.seedPreview(NowPlaying(), cover: nil)
            }
            if name.contains("unread") {
                model.notifications.seedPreview(previewNotifications())
            }
            render(model: model, to: "\(outDir)/\(name).png", dark: false)
        }

        // 深色桌面下的展开态
        model.state = .expanded
        model.tab = .notifications
        render(model: model, to: "\(outDir)/08-expanded-dark.png", dark: true)

        print("rendered to \(outDir)")
        return true
    }

    // MARK: 渲染

    @MainActor
    private static func render(model: IslandModel, to path: String, dark: Bool) {
        let canvas = CGSize(width: 660, height: 600)
        let content = ZStack(alignment: .top) {
            (dark ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.90, green: 0.90, blue: 0.91))
                .frame(width: canvas.width, height: canvas.height)
            // 模拟菜单栏
            VStack(spacing: 0) {
                (dark ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color(red: 0.96, green: 0.96, blue: 0.96))
                    .frame(height: 38)
                Spacer(minLength: 0)
            }
            .frame(width: canvas.width, height: canvas.height)
            IslandRootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.media)
                .environmentObject(model.notifications)
                .environmentObject(model.clipboard)
                .environmentObject(model.lyrics)
                .frame(width: canvas.width, height: canvas.height, alignment: .top)
        }
        .frame(width: canvas.width, height: canvas.height)

        let host = NSHostingView(rootView: content)
        host.frame = CGRect(origin: .zero, size: canvas)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = host
        window.isOpaque = true
        let topScreen = NSScreen.screens.first?.frame.maxY ?? 1000
        window.setFrameOrigin(NSPoint(x: 0, y: topScreen + 300))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("render failed: \(path)")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        window.orderOut(nil)
    }

    // MARK: 假数据

    private static func previewNotifications() -> [NotificationItem] {
        [
            NotificationItem(id: 1, bundleID: "com.tencent.xinWeChat", title: "老婆",
                             body: "我也躺好了，你早点睡", date: Date().addingTimeInterval(-30), isRead: false),
            NotificationItem(id: 2, bundleID: "com.tencent.qq", title: "产品设计组",
                             body: "张工：设计稿 V3 已经上传到蓝湖，麻烦今天看一版", date: Date().addingTimeInterval(-260), isRead: false),
            NotificationItem(id: 3, bundleID: "com.tencent.xinWeChat", title: "前端技术交流群",
                             body: "李雷：这个动画用 SwiftUI 的 spring 就够了吧", date: Date().addingTimeInterval(-900), isRead: true),
            NotificationItem(id: 4, bundleID: "com.apple.mail", title: "Apple Developer",
                             body: "Your membership expires in 30 days", date: Date().addingTimeInterval(-3600), isRead: true),
            NotificationItem(id: 5, bundleID: "com.tencent.qq", title: "王小美",
                             body: "明天上午十点评审，记得带上 Demo", date: Date().addingTimeInterval(-7200), isRead: true),
        ]
    }

    private static func previewNowPlaying() -> NowPlaying {
        var now = NowPlaying()
        now.title = "夜空中最亮的星"
        now.artist = "逃跑计划"
        now.album = "世界"
        now.duration = 252
        now.elapsed = 96
        now.rate = 1
        now.playing = true
        now.pid = 0
        return now
    }

    private static func albumArt() -> NSImage {
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.22, green: 0.16, blue: 0.45, alpha: 1),
            NSColor(calibratedRed: 0.86, green: 0.28, blue: 0.36, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 60)
        let text = "夜" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 120, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let textSize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attrs)
        image.unlockFocus()
        return image
    }

    private static func previewClips() -> [ClipItem] {
        var items: [ClipItem] = []
        let texts = [
            "git commit -m \"fix: 灵动岛展开动画的 spring 参数\"",
            "https://github.com/flyl1u/fly-island",
            "SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON r.app_id = a.app_id;",
            "会议纪要：\n1. 灵动岛常驻顶部，默认折叠\n2. 悬停展开，点击查看详情\n3. 通知、剪贴板、媒体三个入口",
            "老婆：晚上想吃什么？",
        ]
        for (i, t) in texts.enumerated() {
            items.append(ClipItem(kind: .text, text: t, date: Date().addingTimeInterval(Double(-i * 120)), pinned: i == 0))
        }
        return items
    }

    private static func seed(_ model: IslandModel) {
        model.notifications.seedPreview(previewNotifications())
        model.clipboard.seedPreview(previewClips())
        model.media.seedPreview(previewNowPlaying(), cover: albumArt())
        model.lyrics.seedPreview([
            LyricLine(time: 0, text: "夜空中最亮的星 能否听清"),
            LyricLine(time: 24, text: "那仰望的人 心底的孤独和叹息"),
            LyricLine(time: 48, text: "我祈祷拥有一颗透明的心灵"),
            LyricLine(time: 72, text: "和会流泪的眼睛"),
            LyricLine(time: 96, text: "给我再去相信的勇气"),
            LyricLine(time: 120, text: "越过谎言去拥抱你"),
        ])
    }
}
