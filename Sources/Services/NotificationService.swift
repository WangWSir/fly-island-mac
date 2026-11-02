import AppKit
import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 系统通知接入。
///
/// macOS 没有给第三方开放「读取其他 App 通知」的公开接口，这里用两条通道配合：
///  1. 辅助功能读通知中心横幅 —— 实时（~0.35s），负责「立刻弹预览」
///  2. usernoted 数据库（~/Library/Group Containers/group.com.apple.usernoted/db2/db）
///     —— 事实来源，内容完整、可跳转，但系统落库本身有 ~5s 延迟
///
/// 数据库不可用时，通道 1 会直接把横幅内容塞进列表。
final class NotificationService: ObservableObject {
    @Published private(set) var items: [NotificationItem] = []
    @Published private(set) var dbAvailable = false
    @Published private(set) var axAvailable = false
    @Published private(set) var lastError: String?

    /// 新通知入库（用于刷新列表 + 兜底预览）
    var onNew: ((NotificationItem) -> Void)?
    /// 横幅实时到达（title, body, appName, bundleID），比数据库早约 5s
    var onFastBanner: ((String, String, String, String) -> Void)?

    private var timer: Timer?
    private var bootstrapped = false
    private var axWatcher: AXNotificationWatcher?
    private var failStreak = 0
    /// 已见过的数据库 rec_id 集合。
    /// 不能只用「lastID 单调递增」判定新增：通知中心「清空」会重置 sqlite 自增序列，
    /// 之后新通知的 rec_id 可能比旧的 lastID 还小，会被漏掉。
    private var seenIDs: Set<Int64> = []

    // 文件事件监听：数据库一落盘就立刻拉取，不等轮询
    private var watchers: [DispatchSourceFileSystemObject] = []
    private var pendingPoll: DispatchWorkItem?
    private var lastPollAt = Date.distantPast
    private var minPollInterval: TimeInterval = 0.2

    private static let appleEpoch: Double = 978307200
    /// rec_id 超过这个值的是横幅通道临时造的 id（毫秒时间戳），不参与数据库对账
    private static let dbIDThreshold: Int64 = 1_000_000_000
    /// 只保留最近 7 天的记录 —— 数据库是流水账，通知中心「清空」后系统会删掉对应行，
    /// 但一些守护进程的老记录会一直留着，不按时间过滤会永远挂在列表底部
    private static let retention: TimeInterval = 7 * 24 * 3600

    /// 系统噪音 / 我们自己，不展示
    private static let blocklist: Set<String> = [
        "com.flyisland.mac",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
    ]

    private var dbPath: String {
        // 测试可用 FLYISLAND_DB_PATH 指向副本，模拟「系统清空通知」
        ProcessInfo.processInfo.environment["FLYISLAND_DB_PATH"]
            ?? NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    // MARK: 生命周期

    func start() {
        stop()
        axAvailable = Permissions.accessibility

        let ok = pollOnce(initial: true)
        dbAvailable = ok
        if ok {
            startWatchers()
        }
        // 辅助功能授权就开实时通道（DB 可用时只做提前预览，不可用时兼作数据源）
        if axAvailable {
            startAXWatcher()
        }

        // 兜底轮询：kqueue 漏事件时最多 0.3s 也能补上
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.dbAvailable {
                let ok = self.pollOnce(initial: false)
                if !ok {
                    self.failStreak += 1
                    if self.failStreak >= 3 {
                        self.dbAvailable = false
                        self.stopWatchers()
                    }
                } else {
                    self.failStreak = 0
                }
            } else if Permissions.fullDiskAccess {
                // 用户可能刚在设置里授权，重试
                let ok = self.pollOnce(initial: !self.bootstrapped)
                if ok {
                    self.dbAvailable = true
                    self.startWatchers()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        stopWatchers()
        stopAXWatcher()
        pendingPoll?.cancel()
    }

    /// 权限变化后手动重试
    func retry() {
        let ok = pollOnce(initial: !bootstrapped)
        dbAvailable = ok
        if ok { startWatchers() }
        if axAvailable { startAXWatcher() }
    }

    // MARK: 文件事件监听

    /// 监听通知数据库及其 WAL，落盘即触发一次增量拉取。
    private func startWatchers() {
        stopWatchers()
        for suffix in ["", "-wal"] {
            let path = dbPath + suffix
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .rename, .delete, .attrib],
                queue: DispatchQueue.global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let flags = source.data
                if flags.contains(.rename) || flags.contains(.delete) {
                    // WAL 轮转/重建：稍后重挂监听
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.startWatchers() }
                }
                DispatchQueue.main.async { self.scheduleFastPoll() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
        if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
            NSLog("FlyIsland: 通知库监听已挂载 %d 个", watchers.count)
        }
    }

    private func stopWatchers() {
        for w in watchers { w.cancel() }
        watchers.removeAll()
    }

    private func scheduleFastPoll() {
        guard dbAvailable else { return }
        if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
            NSLog("FlyIsland: watcher 触发 (db 有写入)")
        }
        pendingPoll?.cancel()
        let elapsed = Date().timeIntervalSince(lastPollAt)
        let delay = max(0.02, minPollInterval - elapsed)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dbAvailable else { return }
            self.lastPollAt = Date()
            _ = self.pollOnce(initial: false)
        }
        pendingPoll = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func markAllRead() {
        for i in items.indices { items[i].isRead = true }
    }

    func markRead(id: Int64) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isRead = true
    }

    func clearAll() {
        items.removeAll()
    }

    func remove(id: Int64) {
        items.removeAll { $0.id == id }
    }

    var unreadCount: Int { items.filter { !$0.isRead }.count }

    /// 仅供离屏渲染预览使用
    func seedPreview(_ items: [NotificationItem], available: Bool = true) {
        self.items = items
        self.dbAvailable = available
    }

    /// 调试用：手动插入一条记录
    func prependPreview(_ item: NotificationItem) {
        items.insert(item, at: 0)
    }

    // MARK: 数据库读取

    @discardableResult
    private func pollOnce(initial: Bool) -> Bool {
        guard let rows = readRows(initial: initial) else {
            lastError = "无法读取系统通知数据库"
            return false
        }
        lastError = nil

        // 对账：数据库是事实来源。用户在通知中心「清空」后系统会删掉对应记录，
        // 这里把本地已经不在库里的条目一并删掉，保持与系统通知中心一致。
        if let ids = currentRecIDs() {
            reconcile(with: ids)
        }

        // 维护 seenIDs，只保留仍在库里的 id，避免无限增长
        if let ids = currentRecIDs() {
            seenIDs.formIntersection(ids)
        }

        guard !rows.isEmpty else {
            bootstrapped = true
            return true
        }

        // 启动：把最近的历史铺进列表，全部标记已读，不弹预览
        if !bootstrapped {
            items = rows
                .filter { !Self.blocklist.contains($0.bundleID) }
                .filter { $0.date.timeIntervalSinceNow > -Self.retention }
                .filter { !$0.title.trimmed.isEmpty || !$0.body.trimmed.isEmpty }
                .map { NotificationItem(id: $0.id, bundleID: $0.bundleID, title: $0.title,
                                        body: $0.body, date: $0.date, isRead: true) }
            seenIDs.formUnion(items.map(\.id))
            bootstrapped = true
            return true
        }

        // 新增判定：用 seenIDs 集合（而非 lastID 单调递增），清空重置自增序列也不漏
        var fresh: [NotificationItem] = []
        for row in rows where !seenIDs.contains(row.id) {
            guard !Self.blocklist.contains(row.bundleID) else { continue }
            guard !row.title.trimmed.isEmpty || !row.body.trimmed.isEmpty else { continue }
            fresh.append(NotificationItem(id: row.id, bundleID: row.bundleID, title: row.title,
                                          body: row.body, date: row.date, isRead: false))
        }
        seenIDs.formUnion(rows.map(\.id))
        guard !fresh.isEmpty else { return true }

        if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
            for item in fresh {
                NSLog("FlyIsland: 通知入库 [%@] %@ · 投递到检测 %.2fs",
                      item.appName, item.title, Date().timeIntervalSince(item.date))
            }
        }

        // fresh 为升序，插到最前面时要倒序
        items.insert(contentsOf: fresh.reversed(), at: 0)
        if items.count > 120 { items.removeLast(items.count - 120) }
        for item in fresh.reversed() {
            onNew?(item)
        }
        return true
    }

    private struct Row {
        let id: Int64
        let bundleID: String
        let title: String
        let body: String
        let date: Date
    }

    /// 把 WAL 数据库连文件一起拷到缓存目录再读，避免干扰系统进程
    private func snapshotDatabase() -> URL? {
        let fm = FileManager.default
        let dest = AppPaths.cacheDir.appendingPathComponent("nc.db")
        guard fm.isReadableFile(atPath: dbPath) else { return nil }
        do {
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try fm.copyItem(atPath: dbPath, toPath: dest.path)
            for suffix in ["-wal", "-shm"] {
                let src = dbPath + suffix
                let dst = dest.path + suffix
                if fm.fileExists(atPath: dst) { try? fm.removeItem(atPath: dst) }
                if fm.fileExists(atPath: src) { try? fm.copyItem(atPath: src, toPath: dst) }
            }
            return dest
        } catch {
            return nil
        }
    }

    private func readRows(initial: Bool) -> [Row]? {
        // 优先直接只读打开原库（零拷贝，几十微秒）；失败再退回快照
        if let rows = query(at: dbPath, initial: initial) { return rows }
        guard let snapshot = snapshotDatabase() else { return nil }
        defer { try? FileManager.default.removeItem(at: snapshot) }
        return query(at: snapshot.path, initial: initial)
    }

    private func query(at path: String, initial: Bool) -> [Row]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "PRAGMA query_only=1;", nil, nil, nil)

        // 每次都读「近 7 天」全部记录（量很小），新增与否由 seenIDs 集合判定，
        // 不依赖 rec_id 单调递增 —— 清空会重置自增序列，rec_id 可能回绕。
        let order = initial ? "DESC" : "ASC"
        let sql = """
        SELECT r.rec_id, a.identifier, r.delivered_date, r.data
        FROM record r JOIN app a ON r.app_id = a.app_id
        WHERE r.delivered_date > ?
        ORDER BY r.rec_id \(order) LIMIT 500;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970 - Self.retention - Self.appleEpoch)

        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let recID = sqlite3_column_int64(stmt, 0)
            let bundle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let delivered = sqlite3_column_double(stmt, 2)

            var title = ""
            var body = ""
            if let blob = sqlite3_column_blob(stmt, 3) {
                let len = Int(sqlite3_column_bytes(stmt, 3))
                let data = Data(bytes: blob, count: len)
                if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                   let req = plist["req"] as? [String: Any] {
                    title = (req["titl"] as? String) ?? ""
                    body = (req["body"] as? String) ?? ""
                    if body.isEmpty, let sub = req["subt"] as? String { body = sub }
                }
            }
            let date = Date(timeIntervalSince1970: delivered + Self.appleEpoch)
            rows.append(Row(id: recID, bundleID: bundle, title: title, body: body, date: date))
        }
        return rows
    }

    /// 当前数据库里仍存在的记录 id（限最近 retention 窗口内，量很小）
    private func currentRecIDs() -> Set<Int64>? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT rec_id FROM record WHERE delivered_date > ? LIMIT 500;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970 - Self.retention - Self.appleEpoch)
        var ids = Set<Int64>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.insert(sqlite3_column_int64(stmt, 0))
        }
        return ids
    }

    /// 让本地列表与数据库对账：系统通知中心被清空/单条移除时，这边同步消失
    private func reconcile(with ids: Set<Int64>) {
        var removed = 0
        items.removeAll { item in
            let shouldRemove: Bool
            if item.id > Self.dbIDThreshold {
                // 横幅通道临时条目：按时间过期
                shouldRemove = item.date.timeIntervalSinceNow < -Self.retention
            } else {
                shouldRemove = !ids.contains(item.id)
            }
            if shouldRemove { removed += 1 }
            return shouldRemove
        }
        if removed > 0, ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
            NSLog("FlyIsland: 与系统通知对账，移除 %d 条", removed)
        }
    }

    // MARK: 辅助功能实时通道

    private func startAXWatcher() {
        guard axWatcher == nil else { return }
        guard AXIsProcessTrusted() else { return }
        axAvailable = true
        let w = AXNotificationWatcher()
        w.onBanner = { [weak self] title, body, appName, bundleID, _ in
            guard let self else { return }
            if self.dbAvailable {
                // 数据库通道会随后补齐正式记录，这里只负责提前预览
                self.onFastBanner?(title, body, appName, bundleID)
            } else {
                let item = NotificationItem(
                    id: Int64(Date().timeIntervalSince1970 * 1000),
                    bundleID: bundleID.isEmpty ? "com.apple.notificationcenterui" : bundleID,
                    title: title.isEmpty ? appName : title,
                    body: body,
                    date: Date(),
                    isRead: false
                )
                guard !item.title.trimmed.isEmpty || !item.body.trimmed.isEmpty else { return }
                self.items.insert(item, at: 0)
                if self.items.count > 120 { self.items.removeLast(self.items.count - 120) }
                self.onNew?(item)
            }
        }
        w.onPanelCleared = { [weak self] in
            guard let self, !self.items.isEmpty else { return }
            self.items.removeAll()
            if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
                NSLog("FlyIsland: 通知中心面板已清空，本地同步清空（不等数据库落盘）")
            }
        }
        w.start()
        axWatcher = w
    }

    private func stopAXWatcher() {
        axWatcher?.stop()
        axWatcher = nil
    }
}
