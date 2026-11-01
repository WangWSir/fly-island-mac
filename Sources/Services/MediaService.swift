import AppKit
import Foundation

/// 媒体信息与控制系统。
///
/// macOS 15.4 起 mediaremoted 只对 bundle id 为 com.apple.* 的进程返回 NowPlaying，
/// 因此这里走 /usr/bin/perl（bundle id = com.apple.perl）加载 gMediaRemote 适配库，
/// 由 perl 长驻进程把元数据以 JSON 逐行写到 stdout。
final class MediaService: ObservableObject {
    @Published private(set) var now = NowPlaying()
    @Published private(set) var artwork: NSImage?
    @Published private(set) var available = false

    private var process: Process?
    private var outHandle: FileHandle?
    private var buffer = String()
    private var ticker: Timer?
    private var lastArtworkPath: String?
    private var lastArtworkStamp: Date?
    private var restartWork: DispatchWorkItem?
    private var verifyWork: DispatchWorkItem?

    // MARK: 路径

    private var scriptPath: String? {
        Bundle.main.path(forResource: "mediaremote", ofType: "pl", inDirectory: "media")
            ?? Bundle.main.path(forResource: "mediaremote", ofType: "pl")
    }

    private var libPath: String? {
        Bundle.main.path(forResource: "libislandmedia", ofType: "dylib", inDirectory: "media")
            ?? Bundle.main.path(forResource: "libislandmedia", ofType: "dylib")
    }

    // MARK: 生命周期

    func start() {
        guard scriptPath != nil, libPath != nil else {
            NSLog("FlyIsland: media bridge resources missing")
            return
        }
        launchStream()
        startTicker()
    }

    func stop() {
        restartWork?.cancel()
        verifyWork?.cancel()
        ticker?.invalidate()
        ticker = nil
        outHandle?.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    private func launchStream() {
        guard let scriptPath, let libPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        env["MR_LIB"] = libPath
        env["MR_FN"] = "mr_stream"
        env["MR_COMMAND"] = nil
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.ingest(text) }
        }

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.available = false
                self.scheduleRestart()
            }
        }

        do {
            try p.run()
            process = p
            outHandle = pipe.fileHandleForReading
            NSLog("FlyIsland: media bridge started pid=%d", p.processIdentifier)
        } catch {
            NSLog("FlyIsland: media bridge failed \(error)")
            scheduleRestart()
        }
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.launchStream() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: 数据

    private func ingest(_ chunk: String) {
        buffer += chunk
        while let idx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx]).trimmed
            buffer = String(buffer[buffer.index(after: idx)...])
            guard !line.isEmpty, line != "null" else { continue }
            handle(line: line)
        }
        if buffer.count > 65536 { buffer = "" }
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var next = NowPlaying()
        next.title = (obj["title"] as? String ?? "").trimmed
        next.artist = (obj["artist"] as? String ?? "").trimmed
        next.album = (obj["album"] as? String ?? "").trimmed
        next.duration = obj["duration"] as? Double ?? 0
        next.elapsed = obj["elapsed"] as? Double ?? 0
        next.rate = obj["rate"] as? Double ?? 0
        next.pid = obj["pid"] as? Int ?? 0
        let playingFlag = obj["playing"] as? Bool ?? false
        next.playing = playingFlag || (next.rate > 0)

        available = true

        // 曲目变化时刷新封面
        let artPath = obj["artwork"] as? String ?? ""
        if !artPath.isEmpty {
            let changed = artPath != lastArtworkPath || next.title != now.title
            if changed { loadArtwork(at: artPath) }
            lastArtworkPath = artPath
        } else if next.title != now.title {
            artwork = nil
            lastArtworkPath = nil
        }

        // 播放器切换时清空
        if next.title.isEmpty && next.artist.isEmpty {
            artwork = nil
            lastArtworkPath = nil
        }

        if next.title != now.title || next.artist != now.artist {
            lastArtworkStamp = Date()
        }
        now = next
    }

    private func loadArtwork(at path: String, attempt: Int = 0) {
        if let image = NSImage(contentsOfFile: path) {
            artwork = image
            return
        }
        // 切歌瞬间封面文件可能还没写完，稍后重试
        guard attempt < 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.loadArtwork(at: path, attempt: attempt + 1)
        }
    }

    // MARK: 进度补间

    private func startTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.now.playing, self.now.duration > 0 else { return }
            let next = min(self.now.duration, self.now.elapsed + 0.5)
            if next != self.now.elapsed {
                self.now.elapsed = next
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    // MARK: 控制

    /// 仅供离屏渲染预览使用
    func seedPreview(_ playing: NowPlaying, cover: NSImage?) {
        now = playing
        artwork = cover
        available = true
    }

    enum Command: Int {
        case play = 0
        case pause = 1
        case toggle = 2
        case next = 4
        case previous = 5
    }

    func send(_ command: Command) {
        if ProcessInfo.processInfo.environment["FLYISLAND_DEBUG"] != nil {
            NSLog("FlyIsland: 媒体命令 %d（accessibility=%@）",
                  command.rawValue, Permissions.accessibility ? "on" : "off")
        }

        switch command {
        case .toggle, .play, .pause: MediaKeys.post(.playPause)
        case .next: MediaKeys.post(.next)
        case .previous: MediaKeys.post(.previous)
        }

        // 没有辅助功能权限时投递媒体键会被系统静默丢弃，退回 MediaRemote 命令
        if !Permissions.accessibility {
            sendViaMediaRemote(command)
            return
        }

        // 个别播放器会忽略媒体键，稍后核对一次
        if command == .toggle || command == .play || command == .pause {
            scheduleVerify(command)
        }

        // 乐观更新，让 UI 立刻有反馈
        switch command {
        case .toggle:
            now.playing.toggle()
            now.rate = now.playing ? 1 : 0
        case .play:
            now.playing = true
            now.rate = 1
        case .pause:
            now.playing = false
            now.rate = 0
        default:
            break
        }

        // 主动拉一次真实状态，切歌时不用等下一轮轮询
        refreshNow()
    }

    /// 命令下发后单独跑一次 mr_run 把最新状态读回来
    private func refreshNow(after delay: TimeInterval = 0.35) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let scriptPath, let libPath else { return }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [scriptPath]
            var env = ProcessInfo.processInfo.environment
            env["MR_LIB"] = libPath
            env["MR_FN"] = "mr_run"
            env["MR_COMMAND"] = nil
            p.environment = env
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self.ingest(text) }
            }
            do { try p.run() } catch { /* 读不到就等轮询 */ }
        }
    }

    /// 媒体键未生效时兜底走一次 MediaRemote
    private func scheduleVerify(_ command: Command) {
        verifyWork?.cancel()
        let expected: Bool
        switch command {
        case .play: expected = true
        case .pause: expected = false
        default: expected = !now.playing
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.now.playing != expected else { return }
            NSLog("FlyIsland: 媒体键未生效，改用 MediaRemote")
            self.sendViaMediaRemote(command)
        }
        verifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    private func sendViaMediaRemote(_ command: Command) {
        guard let scriptPath, let libPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        env["MR_LIB"] = libPath
        env["MR_FN"] = "mr_command"
        env["MR_COMMAND"] = String(command.rawValue)
        p.environment = env
        p.standardOutput = Pipe()
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            NSLog("FlyIsland: media command failed \(error)")
        }
    }
}
