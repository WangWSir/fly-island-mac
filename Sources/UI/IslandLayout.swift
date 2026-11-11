import AppKit
import SwiftUI

enum IslandTab: String, CaseIterable, Identifiable {
    case notifications
    case clipboard
    case music
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notifications: return "通知"
        case .clipboard: return "剪贴板"
        case .music: return "音乐"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .notifications: return "bell.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .music: return "music.note"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum IslandState: Equatable {
    case collapsed
    case peek
    case expanded
}

/// 岛的几何尺寸。刘海宽度/高度由屏幕实际测量得到。
struct IslandMetrics {
    var width: CGFloat
    var height: CGFloat
    var bottomRadius: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    var wingWidth: CGFloat { max(0, (width - notchWidth) / 2) }
}

enum IslandLayout {
    static let expandedWidth: CGFloat = 560
    static let peekExtraHeight: CGFloat = 86
    static let collapsedExtra: CGFloat = 96
    /// 四个标签页统一高度，切换时不跳动
    static let expandedHeight: CGFloat = 296

    static func expandedHeight(for tab: IslandTab) -> CGFloat { expandedHeight }

    static func metrics(state: IslandState,
                        tab: IslandTab,
                        notchWidth: CGFloat,
                        notchHeight: CGFloat) -> IslandMetrics {
        switch state {
        case .collapsed:
            return IslandMetrics(width: notchWidth + collapsedExtra,
                                 height: notchHeight,
                                 bottomRadius: notchHeight / 2,
                                 notchWidth: notchWidth,
                                 notchHeight: notchHeight)
        case .peek:
            return IslandMetrics(width: max(notchWidth + 200, 420),
                                 height: notchHeight + peekExtraHeight,
                                 bottomRadius: 28,
                                 notchWidth: notchWidth,
                                 notchHeight: notchHeight)
        case .expanded:
            return IslandMetrics(width: max(expandedWidth, notchWidth + 300),
                                 height: expandedHeight(for: tab),
                                 bottomRadius: 30,
                                 notchWidth: notchWidth,
                                 notchHeight: notchHeight)
        }
    }
}

/// 屏幕几何：刘海尺寸与目标屏坐标。
enum ScreenGeometry {
    static func notchWidth(for screen: NSScreen) -> CGFloat {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return 200
        }
        let w = screen.frame.width - left.width - right.width
        return w > 40 && w < 400 ? w : 200
    }

    static func notchHeight(for screen: NSScreen) -> CGFloat {
        let inset = screen.safeAreaInsets.top
        return inset > 10 ? inset : 32
    }

    /// 有刘海（内建屏）。NSScreen.main 会跟随焦点窗口跑到外接屏，不能用它定位岛。
    static func hasNotch(_ screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return false
        }
        let w = screen.frame.width - left.width - right.width
        return w > 40 && w < 400
    }

    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }

    /// 岛固定挂在刘海屏上；没有刘海屏（合盖/外接）时退回内置屏，再退回带菜单栏的主显示器。
    static func preferred() -> NSScreen {
        let screens = NSScreen.screens
        if let notched = screens.first(where: hasNotch) { return notched }
        if let builtIn = screens.first(where: isBuiltIn) { return builtIn }
        return screens.first ?? NSScreen.main ?? screens[0]
    }

    static var main: NSScreen { preferred() }
}
