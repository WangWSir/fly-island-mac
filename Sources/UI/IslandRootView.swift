import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var notifications: NotificationService
    @EnvironmentObject var clipboard: ClipboardService
    @EnvironmentObject var settings: Settings

    private var m: IslandMetrics { model.metrics }

    var body: some View {
        VStack(spacing: 0) {
            card
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var card: some View {
        ZStack(alignment: .top) {
            IslandShape(radius: m.bottomRadius)
                .fill(Theme.base)

            content
                .frame(width: m.width, height: m.height, alignment: .top)
        }
        .frame(width: m.width, height: m.height, alignment: .top)
        .clipShape(IslandShape(radius: m.bottomRadius))
        .overlay(
            IslandShape(radius: m.bottomRadius)
                .strokeBorder(Theme.hairline, lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.55), radius: 26, x: 0, y: 12)
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
        // 注意：这里不能挂 onTapGesture —— 父级手势会吞掉展开态里所有按钮的点击，
        // 展开/收起所需的点击手势改为只挂在折叠态和预览态上。
        .animation(IslandAnimation.spring, value: model.state)
        .animation(IslandAnimation.snappy, value: model.tab)
        .animation(IslandAnimation.snappy, value: model.notchWidth)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .collapsed:
            CollapsedContent(metrics: m)
                .contentShape(IslandShape(radius: m.bottomRadius))
                .onTapGesture { model.expand(byClick: true) }
                .transition(.opacity)
        case .peek:
            PeekContent(metrics: m, item: model.peekItem)
                .contentShape(Rectangle())
                .onTapGesture { model.expand(byClick: true) }
                .transition(.opacity.combined(with: .offset(y: -6)))
        case .expanded:
            ExpandedContent(metrics: m)
                .transition(.opacity)
        }
    }
}

// MARK: - 折叠态

struct CollapsedContent: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var notifications: NotificationService
    let metrics: IslandMetrics

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: metrics.wingWidth, height: metrics.height)
            Color.clear.frame(width: metrics.notchWidth, height: metrics.height)
            rightWing
                .frame(width: metrics.wingWidth, height: metrics.height)
        }
        .frame(width: metrics.width, height: metrics.height)
    }

    private var leftWing: some View {
        HStack {
            Spacer(minLength: 0)
            Group {
                if media.now.isActive, let art = media.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .transition(.scale.combined(with: .opacity))
                } else if media.now.isActive {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                } else if let latest = notifications.items.first {
                    Image(nsImage: latest.icon)
                        .resizable()
                        .frame(width: 17, height: 17)
                        .opacity(0.85)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.26))
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.trailing, 9)
        }
    }

    private var rightWing: some View {
        HStack(spacing: 5) {
            if notifications.unreadCount > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Theme.unread).frame(width: 5, height: 5)
                    Text("\(min(notifications.unreadCount, 99))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .monospacedDigit()
                }
            } else if media.now.isActive {
                Waveform(active: media.now.playing, barCount: 3, tint: Theme.textPrimary.opacity(0.75), height: 12)
            } else {
                // 空闲时显示时间，让岛始终有存在感
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.clock.string(from: context.date))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 9)
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - 通知预览态

struct PeekContent: View {
    @EnvironmentObject var model: IslandModel
    let metrics: IslandMetrics
    let item: NotificationItem?

    @State private var lineProgress: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchHeight)
            if let item {
                HStack(alignment: .center, spacing: 11) {
                    Image(nsImage: item.icon)
                        .resizable()
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.appName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                            Text(item.timeText)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary.opacity(0.7))
                        }
                        Text(item.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(item.body)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .frame(height: metrics.height - metrics.notchHeight - 6, alignment: .top)

                // 自动消失进度
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: geo.size.width * lineProgress, height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .padding(.horizontal, 22)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
        }
        .onAppear {
            lineProgress = 1
            withAnimation(.linear(duration: 4.4)) { lineProgress = 0 }
        }
        .onChange(of: item?.id) { _ in
            lineProgress = 1
            withAnimation(.linear(duration: 4.4)) { lineProgress = 0 }
        }
    }
}
