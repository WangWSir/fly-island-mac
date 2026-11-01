import AppKit

/// 系统媒体键事件。
///
/// `MRMediaRemoteSendCommand` 对部分第三方播放器（实测汽水音乐 `com.soda.music`）
/// 返回 true 但没有任何实际动作；而 NX_KEYTYPE 媒体键走系统路由，由 mediaremoted
/// 派发给当前 NowPlaying 应用，兼容性最好，与物理键盘上按 F8/F9/F10 等价。
///
/// 注意：向 `.cghidEventTap` 投递事件需要「辅助功能」授权，否则会被系统静默丢弃。
enum MediaKeys {
    enum Key: Int32 {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    static func post(_ key: Key) {
        // data1 低 16 位为键码，bit8-15 为 0xA(按下)/0xB(抬起)
        guard let down = event(key, flags: 0xA), let up = event(key, flags: 0xB) else { return }
        down.cgEvent?.post(tap: .cghidEventTap)
        usleep(40_000)
        up.cgEvent?.post(tap: .cghidEventTap)
    }

    private static func event(_ key: Key, flags: Int) -> NSEvent? {
        let data1 = (Int(key.rawValue) << 16) | (flags << 8)
        return NSEvent.otherEvent(with: .systemDefined,
                                  location: .zero,
                                  modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: 0,
                                  context: nil,
                                  subtype: 8,
                                  data1: data1,
                                  data2: -1)
    }
}
