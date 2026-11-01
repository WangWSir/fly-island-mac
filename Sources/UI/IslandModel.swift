import AppKit
import Combine
import SwiftUI

/// 应用的中央状态：UI 状态 + 各服务实例。
final class IslandModel: ObservableObject {
    let settings: Settings
    let media: MediaService
    let notifications: NotificationService
    let clipboard: ClipboardService
    let lyrics = LyricsService()

    @Published var state: IslandState = .collapsed
    @Published var tab: IslandTab = .notifications
    @Published var peekItem: NotificationItem?
    @Published var toast: String?
    @Published var hovering: Bool = false

    var notchWidth: CGFloat = 200
    var notchHeight: CGFloat = 38
    var openedByClick = false

    /// 尺寸变化回调（controller 用来更新点击命中区域）
    var onLayoutChange: (() -> Void)?

    private var peekWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    /// 最近一次弹出的内容，用于 AX 通道与数据库通道去重
    private var lastPeek: (signature: String, at: Date)?

    init() {
        settings = Settings()
        media = MediaService()
        notifications = NotificationService()
        clipboard = ClipboardService()
    }

    func start() {
        let screen = ScreenGeometry.main
        notchWidth = ScreenGeometry.notchWidth(for: screen)
        notchHeight = ScreenGeometry.notchHeight(for: screen)

        clipboard.maxItems = { [weak self] in self?.settings.maxClips ?? 200 }
        clipboard.captureImages = { [weak self] in self?.settings.captureImages ?? true }
        clipboard.isEnabled = { [weak self] in self?.settings.clipboardEnabled ?? true }
        clipboard.start()

        media.start()
        notifications.start()

        lyrics.isEnabled = { [weak self] in self?.settings.lyricsEnabled ?? true }
        media.$now
            .map { "\($0.title)|\($0.artist)|\(Int($0.duration))" }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.lyrics.update(title: self.media.now.title,
                                   artist: self.media.now.artist,
                                   duration: self.media.now.duration,
                                   album: self.media.now.album)
            }
            .store(in: &cancellables)

        notifications.onNew = { [weak self] item in
            self?.handleIncoming(item)
        }
        notifications.onFastBanner = { [weak self] title, body, appName, bundleID in
            self?.handleFastBanner(title: title, body: body, appName: appName, bundleID: bundleID)
        }
    }

    // MARK: 通知到达

    /// 横幅实时通道：比数据库早约 5s，只负责弹预览，不进列表
    private func handleFastBanner(title: String, body: String, appName: String, bundleID: String) {
        guard settings.peekOnNotification else { return }
        guard !hovering, state == .collapsed || state == .peek else { return }

        let signature = "\(appName)|\(title)"
        if let last = lastPeek, last.signature == signature,
           Date().timeIntervalSince(last.at) < 10 { return }
        lastPeek = (signature, Date())

        let bundle = bundleID.isEmpty ? guessBundleID(appName) : bundleID
        let item = NotificationItem(id: -Int64(Date().timeIntervalSince1970 * 1000),
                                    bundleID: bundle,
                                    title: title.trimmed.isEmpty ? appName : title,
                                    body: body,
                                    date: Date(),
                                    isRead: false)
        showPeek(item)
    }

    private func guessBundleID(_ appName: String) -> String {
        AppInfo.bundleID(forAppNamed: appName) ?? "com.apple.notificationcenterui"
    }

    private func handleIncoming(_ item: NotificationItem) {
        if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
            NSLog("FlyIsland: 收到通知 [%@] %@ — %@ (state=%@)",
                  item.appName, item.title, item.body, String(describing: state))
        }
        if state == .expanded {
            if tab == .notifications {
                // 已经看着通知列表，直接就是已读
                notifications.markRead(id: item.id)
            }
            return
        }
        guard settings.peekOnNotification, !hovering, state == .collapsed || state == .peek else { return }
        // 横幅通道已经弹过同一条内容时不再重复
        let signature = "\(item.appName)|\(item.title)"
        if let last = lastPeek, last.signature == signature,
           Date().timeIntervalSince(last.at) < 10 { return }
        lastPeek = (signature, Date())
        showPeek(item)
    }

    private func showPeek(_ item: NotificationItem) {
        peekItem = item
        withAnimation(IslandAnimation.spring) {
            state = .peek
        }
        onLayoutChange?()
        schedulePeekDismiss()
    }

    private func schedulePeekDismiss() {
        peekWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .peek, !self.hovering else { return }
            withAnimation(IslandAnimation.spring) {
                self.state = .collapsed
                self.peekItem = nil
            }
            self.onLayoutChange?()
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.6, execute: work)
    }

    // MARK: 状态切换

    func expand(tab newTab: IslandTab? = nil, byClick: Bool) {
        peekWork?.cancel()
        if let newTab { tab = newTab }
        if byClick { openedByClick = true }
        if !byClick && state == .expanded { return }
        withAnimation(IslandAnimation.spring) {
            state = .expanded
            peekItem = nil
        }
        onLayoutChange?()
        if tab == .notifications {
            notifications.markAllRead()
        }
    }

    func collapse() {
        peekWork?.cancel()
        openedByClick = false
        withAnimation(IslandAnimation.spring) {
            state = .collapsed
            peekItem = nil
        }
        onLayoutChange?()
    }

    func toggle(byClick: Bool) {
        if state == .expanded { collapse() } else { expand(byClick: byClick) }
    }

    func select(tab newTab: IslandTab) {
        withAnimation(IslandAnimation.snappy) {
            tab = newTab
        }
        onLayoutChange?()
        if newTab == .notifications {
            notifications.markAllRead()
        }
    }

    /// 调试用：绕过数据库直接走一次通知到达流程
    func debugInjectNotification() {
        let item = NotificationItem(id: -1, bundleID: "com.tencent.xinWeChat",
                                    title: "老婆", body: "端到端预览测试：这条应该弹出 4 秒",
                                    date: Date(), isRead: false)
        notifications.prependPreview(item)
        handleIncoming(item)
    }

    // MARK: 轻提示

    func showToast(_ text: String) {
        toastWork?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { toast = text }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: 派生

    var metrics: IslandMetrics {
        IslandLayout.metrics(state: state, tab: tab, notchWidth: notchWidth, notchHeight: notchHeight)
    }

    var unreadCount: Int { notifications.unreadCount }
}

enum IslandAnimation {
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.85)
    static let quick = Animation.spring(response: 0.26, dampingFraction: 0.9)
}
