import Foundation
import ServiceManagement

/// 全部可配置项，落到 UserDefaults。
final class Settings: ObservableObject {
    private let store = UserDefaults.standard

    @Published var hoverExpand: Bool { didSet { store.set(hoverExpand, forKey: "hoverExpand") } }
    @Published var peekOnNotification: Bool { didSet { store.set(peekOnNotification, forKey: "peekOnNotification") } }
    @Published var clipboardEnabled: Bool { didSet { store.set(clipboardEnabled, forKey: "clipboardEnabled") } }
    @Published var captureImages: Bool { didSet { store.set(captureImages, forKey: "captureImages") } }
    @Published var maxClips: Int { didSet { store.set(maxClips, forKey: "maxClips") } }
    @Published var notifyFilterSystem: Bool { didSet { store.set(notifyFilterSystem, forKey: "notifyFilterSystem") } }
    @Published var autoCollapse: Bool { didSet { store.set(autoCollapse, forKey: "autoCollapse") } }
    @Published var showIdleDot: Bool { didSet { store.set(showIdleDot, forKey: "showIdleDot") } }
    @Published var lyricsEnabled: Bool { didSet { store.set(lyricsEnabled, forKey: "lyricsEnabled") } }
    /// 没有刘海屏时（合盖接扩展屏）是否改在扩展屏显示，默认关闭
    @Published var showOnExternalScreen: Bool { didSet { store.set(showOnExternalScreen, forKey: "showOnExternalScreen") } }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "hoverExpand": true,
            "peekOnNotification": true,
            "clipboardEnabled": true,
            "captureImages": true,
            "maxClips": 200,
            "notifyFilterSystem": true,
            "autoCollapse": true,
            "showIdleDot": true,
            "lyricsEnabled": true,
            "showOnExternalScreen": false,
        ])
        hoverExpand = d.bool(forKey: "hoverExpand")
        peekOnNotification = d.bool(forKey: "peekOnNotification")
        clipboardEnabled = d.bool(forKey: "clipboardEnabled")
        captureImages = d.bool(forKey: "captureImages")
        maxClips = d.integer(forKey: "maxClips")
        notifyFilterSystem = d.bool(forKey: "notifyFilterSystem")
        autoCollapse = d.bool(forKey: "autoCollapse")
        showIdleDot = d.bool(forKey: "showIdleDot")
        lyricsEnabled = d.bool(forKey: "lyricsEnabled")
        showOnExternalScreen = d.bool(forKey: "showOnExternalScreen")
    }

    // 开机自启（macOS 13+ SMAppService）
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("FlyIsland: launchAtLogin failed \(error)")
            }
            objectWillChange.send()
        }
    }
}
