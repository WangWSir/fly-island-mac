import AppKit
import SwiftUI

enum Theme {
    static let base = Color.black
    static let panel = Color(red: 0.055, green: 0.055, blue: 0.065)

    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary = Color.white.opacity(0.34)

    static let hairline = Color.white.opacity(0.08)
    static let fill = Color.white.opacity(0.06)
    static let fillHover = Color.white.opacity(0.10)
    static let fillActive = Color.white.opacity(0.14)

    static let accent = Color(red: 0.26, green: 0.55, blue: 1.0)
    static let unread = Color(red: 1.0, green: 0.30, blue: 0.28)
    static let success = Color(red: 0.19, green: 0.82, blue: 0.35)
}

/// 上沿贴屏幕顶端、只有下沿圆角的岛形。
struct IslandShape: InsettableShape {
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> IslandShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var p = Path()
        let r = min(radius, rect.height, rect.width / 2)
        // 上沿贴屏幕边缘：顶角保持直角，只做下沿圆角
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 小控件

struct IslandIconButton: View {
    let symbol: String
    var size: CGFloat = 13
    var active: Bool = false
    var help: String = ""
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? Color.white : Theme.textSecondary)
                .frame(width: size * 2.2, height: size * 2.2)
                .background(
                    Circle().fill(hover ? Theme.fillHover : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct IslandTextButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.textSecondary
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hover ? Theme.textPrimary : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? Theme.fillHover : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 播放中的音量柱动画
struct Waveform: View {
    var active: Bool
    var barCount: Int = 4
    var tint: Color = Theme.textPrimary
    var height: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.4) {
                ForEach(0..<barCount, id: \.self) { i in
                    let phase = t * (2.2 + Double(i) * 0.55) + Double(i) * 1.7
                    let wave = active ? (sin(phase) * 0.5 + 0.5) : 0.22
                    Capsule()
                        .fill(tint)
                        .frame(width: 2.4, height: max(3, height * (0.28 + 0.72 * wave)))
                }
            }
            .frame(height: height)
        }
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hover = false
    var radius: CGFloat = 10
    var fill: Color = Theme.fillHover

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hover ? fill : Color.clear)
            )
            .onHover { hover = $0 }
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = 10, fill: Color = Theme.fillHover) -> some View {
        modifier(HoverHighlight(radius: radius, fill: fill))
    }

    func pointerCursor() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    /// 列表底部渐隐，避免滚动内容被圆角硬切
    func bottomFade(height: CGFloat = 26) -> some View {
        overlay(alignment: .bottom) {
            LinearGradient(colors: [Theme.base.opacity(0), Theme.base],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: height)
                .allowsHitTesting(false)
        }
    }
}
