import AppKit

// 离屏渲染模式（调试用）：FlyIsland --render <目录>
let renderRequested = MainActor.assumeIsolated { RenderMode.runIfRequested() }
if renderRequested {
    exit(0)
}

// 自检模式：FlyIsland --selftest
let selfTestRequested = MainActor.assumeIsolated { SelfTest.runIfRequested() }
if selfTestRequested {
    exit(0)
}

// 单实例：已在运行时直接退出
let bundleID = Bundle.main.bundleIdentifier ?? "com.flyisland.mac"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
