import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: IslandModel!
    private var controller: IslandController!
    private var statusItem: NSStatusItem?
    private let loginItem = NSMenuItem(title: "开机自启动", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = IslandModel()
        controller = IslandController(model: model)
        model.start()
        controller.show()
        setupStatusItem()
        setupMainMenu()

        // 后台预热「应用名 → bundle id」索引，避免首次横幅到达时卡主线程
        DispatchQueue.global(qos: .utility).async { _ = AppInfo.bundleIndex }

        // 启动 2s 后回报通道状态，方便排查权限问题
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            NSLog("FlyIsland: 通知通道 db=%@ ax=%@ 已载入=%d",
                  self.model.notifications.dbAvailable ? "on" : "off",
                  self.model.notifications.axAvailable ? "on" : "off",
                  self.model.notifications.items.count)
            let status: [String: Any] = [
                "dbAvailable": self.model.notifications.dbAvailable,
                "axAvailable": self.model.notifications.axAvailable,
                "loaded": self.model.notifications.items.count,
                "fullDiskAccess": Permissions.fullDiskAccess,
                "accessibility": Permissions.accessibility,
                "checkedAt": ISO8601DateFormatter().string(from: Date()),
            ]
            if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted]) {
                try? data.write(to: AppPaths.support.appendingPathComponent("status.json"))
            }
        }

        // 首次启动把焦点让给用户当前的应用
        NSApp.activate(ignoringOtherApps: false)

        // 调试：FlyIsland --demo 自动展开一次，便于检查真实窗口几何
        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.controller.expand(tab: .notifications)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                self?.controller.expand(tab: .clipboard)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { [weak self] in
                self?.controller.expand(tab: .music)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 11) { [weak self] in
                self?.controller.collapse()
            }
        }

        // 调试：直接展开音乐页并保持，便于验证控制按钮
        if CommandLine.arguments.contains("--demo-music") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.controller.expand(tab: .music)
            }
        }

        // 调试：注入一条假通知，验证「到达 → 预览 → 自动收起」
        if CommandLine.arguments.contains("--demo-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.model.debugInjectNotification()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.media.stop()
        model.clipboard.stop()
        model.notifications.stop()
    }

    // MARK: 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Fly Island")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Fly Island"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "展开灵动岛", action: #selector(expandIsland), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let clip = NSMenuItem(title: "剪贴板历史", action: #selector(openClipboard), keyEquivalent: "")
        clip.target = self
        menu.addItem(clip)

        let music = NSMenuItem(title: "正在播放", action: #selector(openMusic), keyEquivalent: "")
        music.target = self
        menu.addItem(music)

        let settings = NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        loginItem.state = model.settings.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        let permission = NSMenuItem(title: "通知权限检查", action: #selector(checkPermission), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Fly Island", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    /// 搜索框需要标准的编辑菜单才能用 ⌘C / ⌘V
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Fly Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = main
    }

    // MARK: 动作

    @objc private func expandIsland() {
        controller.expand(tab: .notifications)
    }

    @objc private func openClipboard() {
        controller.expand(tab: .clipboard)
    }

    @objc private func openMusic() {
        controller.expand(tab: .music)
    }

    @objc private func openSettings() {
        controller.expand(tab: .settings)
    }

    @objc private func toggleLoginItem() {
        model.settings.launchAtLogin.toggle()
        loginItem.state = model.settings.launchAtLogin ? .on : .off
    }

    @objc private func checkPermission() {
        model.notifications.retry()
        controller.expand(tab: model.notifications.dbAvailable ? .notifications : .settings)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
