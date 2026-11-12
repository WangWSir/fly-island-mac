import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 允许窗口贴到屏幕最顶端（默认会被挤到菜单栏下方）
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil,
           event.type == .leftMouseDown {
            NSLog("FlyIsland: mouseDown inWindow=%@", NSStringFromPoint(event.locationInWindow))
        }
        super.sendEvent(event)
    }
}

/// 只在岛形区域内接收鼠标事件，其余透明区域直接穿透到下层窗口。
final class IslandHostingView: NSHostingView<AnyView> {
    var hitSize: CGSize = .zero

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        let width = min(hitSize.width, bounds.width)
        let height = min(hitSize.height, bounds.height)
        let x = (bounds.width - width) / 2
        let y = isFlipped ? 0 : bounds.height - height
        guard CGRect(x: x, y: y, width: width, height: height).contains(local) else { return nil }
        return super.hitTest(point)
    }
}

final class IslandController {
    private let model: IslandModel
    private var panel: IslandPanel
    private var host: IslandHostingView

    private var hoverTimer: Timer?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var monitors: [Any] = []
    /// 当前是否把鼠标事件让给下层窗口
    private var clickThrough = false
    /// 岛固定所在的屏幕（内置刘海屏）。nil = 当前没有刘海屏，按策略隐藏
    private var targetScreen: NSScreen?
    /// 从状态栏菜单显式唤起时，临时允许贴在当前屏（避免隐藏后菜单点了没反应）
    private var temporarilyOnPrimary = false

    /// 窗口最大尺寸（初始创建时使用，避免频繁重建窗口）
    private let maxWindow = CGSize(width: 660, height: 600)

    init(model: IslandModel) {
        self.model = model

        let screen = ScreenGeometry.notched() ?? ScreenGeometry.primary() ?? NSScreen.main ?? NSScreen.screens[0]
        self.targetScreen = screen
        let frame = NSRect(x: (screen.frame.midX - maxWindow.width / 2).rounded(),
                           y: screen.frame.maxY - maxWindow.height,
                           width: maxWindow.width,
                           height: maxWindow.height)

        panel = IslandPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)

        let root = AnyView(
            IslandRootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.media)
                .environmentObject(model.notifications)
                .environmentObject(model.clipboard)
                .environmentObject(model.lyrics)
        )
        host = IslandHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]

        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // 注意：isFloatingPanel 会把 level 重置为 floating，必须先设它再设 level
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = false
        panel.setFrame(frame, display: false)
    }

    // MARK: 展示

    func show() {
        model.onLayoutChange = { [weak self] in self?.syncHitRegion() }
        applyScreen(force: true)
        syncHitRegion()
        startHoverTracking()
        installMonitors()
        observeScreenChanges()
        // 初始状态：光标不在岛上就立刻让出鼠标事件
        updateClickThrough(inside: islandScreenRect().contains(NSEvent.mouseLocation))
    }

    var window: NSWindow { panel }

    /// 选屏：刘海屏优先；没有刘海屏时（合盖/纯外接）默认不显示，非笔记本贴在主屏。
    private func resolveScreen() -> NSScreen? {
        if let notched = ScreenGeometry.notched() { return notched }
        if temporarilyOnPrimary, let primary = ScreenGeometry.primary() { return primary }
        if model.settings.showOnExternalScreen { return ScreenGeometry.primary() }
        return ScreenGeometry.isLaptop ? nil : ScreenGeometry.primary()
    }

    /// 把窗口搬到目标屏；无目标屏则隐藏，但不影响后台服务（通知/剪贴板/媒体照常跑）
    private func applyScreen(force: Bool = false) {
        let screen = resolveScreen()
        let changed = screen?.frame != targetScreen?.frame || force
        targetScreen = screen

        guard let screen else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if changed {
            model.notchWidth = ScreenGeometry.notchWidth(for: screen)
            model.notchHeight = ScreenGeometry.notchHeight(for: screen)
            panel.setFrame(frame(for: model.metrics), display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func syncHitRegion() {
        let m = model.metrics
        // 加一点余量，避免动画过程中指针正好落在边缘
        host.hitSize = CGSize(width: m.width + 6, height: m.height + 6)
        resizePanel()
        if model.state == .expanded, model.openedByClick, !panel.isKeyWindow {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    /// 窗口只覆盖「岛 + 阴影」，缩小视野、少挡下层应用的鼠标事件；
    /// 状态切换时先按并集放大，动画结束后再收缩到目标尺寸。
    private func resizePanel() {
        let m = model.metrics
        let target = frame(for: m)
        shrinkWork?.cancel()

        if !panel.frame.equalTo(target) {
            let union = panel.frame.union(target)
            if !panel.frame.equalTo(union) {
                panel.setFrame(union, display: true)
            }
            NSLog("FlyIsland: panel %@ (state=%@)", NSStringFromRect(target), String(describing: model.state))
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.panel.frame.equalTo(target) else { return }
                self.panel.setFrame(target, display: true)
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private func frame(for metrics: IslandMetrics) -> NSRect {
        guard let screen = targetScreen else { return panel.frame }
        let width = min(maxWindow.width, metrics.width + 90)
        let height = min(maxWindow.height, metrics.height + 90)
        return NSRect(x: (screen.frame.midX - width / 2).rounded(),
                      y: screen.frame.maxY - height,
                      width: width,
                      height: height)
    }

    private func reposition() {
        applyScreen(force: true)
        syncHitRegion()
        // 显示器配置变化后 NSScreen 要过一会儿才稳定，补两次校正
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.applyScreen() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.applyScreen() }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
    }

    // MARK: 悬停

    /// 岛在屏幕坐标系里的矩形（NSEvent.mouseLocation 同为左下原点）
    private func islandScreenRect() -> CGRect {
        let m = model.metrics
        let f = panel.frame
        return CGRect(x: f.midX - m.width / 2,
                      y: f.maxY - m.height,
                      width: m.width,
                      height: m.height)
    }

    private func startHoverTracking() {
        hoverTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.pollHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func pollHover() {
        healScreenIfNeeded()

        // 隐藏态（无刘海屏）下不参与悬停
        guard panel.isVisible, targetScreen != nil else {
            if model.hovering { model.hovering = false }
            updateClickThrough(inside: false)
            return
        }

        let point = NSEvent.mouseLocation
        let inside = islandScreenRect().insetBy(dx: -4, dy: -2).contains(point)

        updateClickThrough(inside: inside)

        if inside != model.hovering {
            model.hovering = inside
            if inside {
                scheduleExpand()
            } else {
                scheduleCollapse()
            }
        }
    }

    /// 窗口为画阴影比岛大一圈（左右下各 45pt）。这圈透明区域若不处理，
    /// 点击会被窗口吃掉、传不到下面的菜单栏和别的应用 —— 按光标位置动态开关穿透。
    private func updateClickThrough(inside: Bool) {
        if inside {
            if clickThrough {
                clickThrough = false
                panel.ignoresMouseEvents = false
            }
            return
        }
        // 按住鼠标（拖拽/划选）期间不切换，避免打断手势
        guard NSEvent.pressedMouseButtons == 0 else { return }
        if !clickThrough {
            clickThrough = true
            panel.ignoresMouseEvents = true
        }
    }

    /// 窗口被系统搬到别的屏（切 Space、改分辨率、系统偏好设置里改主屏）时拉回来
    private func healScreenIfNeeded() {
        let resolved = resolveScreen()
        if resolved?.frame != targetScreen?.frame {
            applyScreen()
            return
        }
        guard let screen = resolved, panel.isVisible else { return }
        if panel.screen?.frame != screen.frame {
            panel.setFrame(frame(for: model.metrics), display: true)
        }
    }

    private func scheduleExpand() {
        collapseWork?.cancel()
        expandWork?.cancel()
        guard model.state == .collapsed, model.settings.hoverExpand else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.hovering, self.model.state == .collapsed else { return }
            self.model.expand(byClick: false)
        }
        expandWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func scheduleCollapse() {
        expandWork?.cancel()
        collapseWork?.cancel()
        // 预览态由自己的计时器收起，鼠标路过不应打断
        guard model.state == .expanded else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.hovering else { return }
            guard !self.model.openedByClick, self.model.settings.autoCollapse else { return }
            self.model.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: 事件

    private func installMonitors() {
        // 光标移动时立即更新穿透状态（0.1s 轮询对快速划过不够快）
        if let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            guard let self else { return }
            let inside = self.islandScreenRect().insetBy(dx: -4, dy: -2).contains(NSEvent.mouseLocation)
            self.updateClickThrough(inside: inside)
        }) {
            monitors.append(moved)
        }

        // 点击岛外收起
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            guard !self.islandScreenRect().contains(point) else { return }
            if self.model.state != .collapsed {
                DispatchQueue.main.async { self.model.collapse() }
            }
        }) {
            monitors.append(global)
        }

        // Esc 收起（本窗口为 key 时生效）
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53, self?.model.state != .collapsed {
                self?.model.collapse()
                return nil
            }
            return event
        }) {
            monitors.append(local)
        }

        // 全局 Esc（需要辅助功能权限）
        if Permissions.accessibility,
           let globalKey = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
               if event.keyCode == 53, self?.model.state != .collapsed {
                   DispatchQueue.main.async { self?.model.collapse() }
               }
           }) {
            monitors.append(globalKey)
        }
    }

    func expand(tab: IslandTab) {
        // 隐藏态（合盖接扩展屏）下从菜单唤起：临时贴到当前主屏，否则点了没反应
        if targetScreen == nil || !panel.isVisible {
            temporarilyOnPrimary = true
            applyScreen(force: true)
            syncHitRegion()
        }
        model.expand(tab: tab, byClick: true)
    }

    func collapse() {
        model.collapse()
    }
}
