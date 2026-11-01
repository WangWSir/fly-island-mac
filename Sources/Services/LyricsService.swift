import AppKit
import Foundation
import CryptoKit

struct LyricLine: Codable, Equatable {
    let time: Double
    let text: String
}

/// 歌词：曲目变化时异步拉取，按播放进度取当前行。
///
/// 数据源（可关闭）：
///  1. 网易云音乐搜索 + 歌词接口（覆盖华语歌，带时间轴）
///  2. LRCLIB 开放歌词库（兜底，部分歌曲只有纯文本，按行均分时间）
///
/// 只发送「歌名 / 歌手 / 时长」，不涉及账号与播放记录。结果缓存在本机。
final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var isLoading = false
    @Published private(set) var sourceLabel = ""

    var isEnabled: () -> Bool = { true }

    private var currentKey = ""
    private var cache: [String: [LyricLine]] = [:]
    private var pending: DispatchWorkItem?
    private var task: URLSessionDataTask?
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 FlyIsland/1.0"]
        return URLSession(configuration: cfg)
    }()

    // MARK: 对外

    func update(title: String, artist: String, duration: Double, album: String) {
        guard isEnabled() else {
            if !lines.isEmpty { lines = [] }
            return
        }
        let key = "\(title)|\(artist)|\(Int(duration))"
        guard key != currentKey else { return }
        currentKey = key
        lines = []
        sourceLabel = ""
        guard !title.isEmpty else { return }

        pending?.cancel()
        task?.cancel()

        if let cached = cache[key] {
            lines = cached
            return
        }
        if let disk = loadCached(key: key) {
            cache[key] = disk
            lines = disk
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.fetch(title: title, artist: artist, album: album, duration: duration, key: key)
        }
        pending = work
        // 去抖：连续切歌时只请求最后一首
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// 当前应显示的一行
    func currentLine(at elapsed: Double) -> String? {        guard !lines.isEmpty else { return nil }
        var result: String?
        for line in lines {
            if line.time <= elapsed + 0.35 {
                if !line.text.isEmpty { result = line.text }
            } else {
                break
            }
        }
        return result
    }

    // MARK: 拉取

    private func fetch(title: String, artist: String, album: String, duration: Double, key: String) {
        isLoading = true
        fetchNetease(title: title, artist: artist) { [weak self] result in
            guard let self else { return }
            if let (lines, label) = result, !lines.isEmpty {
                self.finish(key: key, lines: lines, label: label)
                return
            }
            self.fetchLRCLIB(title: title, artist: artist, album: album, duration: duration) { result in
                if let (lines, label) = result, !lines.isEmpty {
                    self.finish(key: key, lines: lines, label: label)
                } else {
                    self.isLoading = false
                }
            }
        }
    }

    private func finish(key: String, lines: [LyricLine], label: String) {
        cache[key] = lines
        saveCached(key: key, lines: lines)
        guard key == currentKey else { return }   // 期间又切歌了
        self.lines = lines
        self.sourceLabel = label
        self.isLoading = false
    }

    // MARK: 磁盘缓存

    private func cacheURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(24)
        return AppPaths.cacheDir.appendingPathComponent("lyrics-\(hash).json")
    }

    private func loadCached(key: String) -> [LyricLine]? {
        guard let data = try? Data(contentsOf: cacheURL(for: key)) else { return nil }
        return try? JSONDecoder().decode([LyricLine].self, from: data)
    }

    private func saveCached(key: String, lines: [LyricLine]) {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        try? data.write(to: cacheURL(for: key))
    }

    // MARK: 网易云

    private func fetchNetease(title: String, artist: String, completion: @escaping (([LyricLine], String)?) -> Void) {
        let query = artist.isEmpty ? title : "\(title) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://music.163.com/api/search/get/web?s=\(encoded)&type=1&limit=5") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [String: Any],
                  let songs = result["songs"] as? [[String: Any]],
                  !songs.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 优先名字命中且歌手匹配的那首
            let normalizedTitle = title.lowercased()
            let matched = songs.first { song in
                let name = (song["name"] as? String ?? "").lowercased()
                return name == normalizedTitle || name.contains(normalizedTitle)
            } ?? songs[0]
            guard let songID = matched["id"] as? Int,
                  let lyricURL = URL(string: "https://music.163.com/api/song/lyric?id=\(songID)&lv=1&kv=1&tv=-1") else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var lyricRequest = URLRequest(url: lyricURL)
            lyricRequest.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
            self?.session.dataTask(with: lyricRequest) { data, _, _ in
                var output: ([LyricLine], String)?
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let lrc = json["lrc"] as? [String: Any],
                   let text = lrc["lyric"] as? String {
                    let parsed = LyricsService.parseLRC(text)
                    if !parsed.isEmpty { output = (parsed, "网易云") }
                }
                DispatchQueue.main.async { completion(output) }
            }.resume()
        }.resume()
    }

    // MARK: LRCLIB

    private func fetchLRCLIB(title: String, artist: String, album: String, duration: Double,
                             completion: @escaping (([LyricLine], String)?) -> Void) {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if !album.isEmpty { items.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        components?.queryItems = items
        guard let url = components?.url else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("FlyIsland/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, _, _ in
            var output: ([LyricLine], String)?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                    let parsed = LyricsService.parseLRC(synced)
                    if !parsed.isEmpty { output = (parsed, "LRCLIB") }
                } else if let plain = json["plainLyrics"] as? String, !plain.isEmpty, duration > 0 {
                    let rows = plain.components(separatedBy: .newlines)
                        .map { $0.trimmed }
                        .filter { !$0.isEmpty }
                    if !rows.isEmpty {
                        let step = duration / Double(rows.count)
                        let parsed = rows.enumerated().map { LyricLine(time: Double($0.offset) * step, text: $0.element) }
                        output = (parsed, "LRCLIB")
                    }
                }
            }
            DispatchQueue.main.async { completion(output) }
        }.resume()
    }

    /// 仅供离屏渲染预览使用
    func seedPreview(_ lines: [LyricLine]) {
        self.lines = lines
        self.sourceLabel = "预览"
    }

    // MARK: LRC 解析
    static func parseLRC(_ text: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let pattern = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        for raw in text.components(separatedBy: .newlines) {
            let ns = raw as NSString
            let matches = pattern.matches(in: raw, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { continue }
            let content = pattern.stringByReplacingMatches(in: raw,
                                                           range: NSRange(location: 0, length: ns.length),
                                                           withTemplate: "").trimmed
            guard !content.isEmpty else { continue }
            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let digits = ns.substring(with: m.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                result.append(LyricLine(time: minutes * 60 + seconds + fraction, text: content))
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}
