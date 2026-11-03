import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var notifications: NotificationService

    @State private var launchAtLogin = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(v)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    content
                }
                // 留出渐隐带的高度，滚到底时最后一行能完整露出
                .padding(.bottom, 22)
            }
            .bottomFade(height: 26)

            footer
        }
        .onAppear { launchAtLogin = settings.launchAtLogin }
        .onChange(of: launchAtLogin) { newValue in
            if newValue != settings.launchAtLogin {
                settings.launchAtLogin = newValue
            }
        }
    }

    /// 固定的底部操作栏：不参与滚动，也不受渐隐遮罩影响
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.11))
                .frame(height: 0.5)

            HStack(spacing: 6) {
                IslandTextButton(title: "清空通知", symbol: "bell.slash") {
                    notifications.clearAll()
                }
                IslandTextButton(title: "清空剪贴板", symbol: "trash") {
                    model.clipboard.clearAll()
                }
                Spacer(minLength: 0)
                Text(version)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary.opacity(0.8))
                IslandTextButton(title: "退出", symbol: "power") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 26)
        }
        .background(Theme.base)
        // 让底栏离开岛的圆角弧线，避免被下沿裁到
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
                group("常规") {
                    settingRow("悬停展开", subtitle: "鼠标停在岛上时自动展开") {
                        IslandToggle(isOn: $settings.hoverExpand)
                    }
                    settingRow("通知预览", subtitle: "新消息到达时弹出一段预览") {
                        IslandToggle(isOn: $settings.peekOnNotification)
                    }
                    settingRow("自动收起", subtitle: "鼠标移开后回到折叠状态") {
                        IslandToggle(isOn: $settings.autoCollapse)
                    }
                    settingRow("开机自启动") {
                        IslandToggle(isOn: $launchAtLogin)
                    }
                }

                group("剪贴板") {
                    settingRow("记录剪贴板", subtitle: "复制内容时自动保存历史") {
                        IslandToggle(isOn: $settings.clipboardEnabled)
                    }
                    settingRow("记录图片", subtitle: "图片会占用更多磁盘空间") {
                        IslandToggle(isOn: $settings.captureImages)
                    }
                    settingRow("保留条数", subtitle: "最多 \(settings.maxClips) 条普通记录") {
                        CompactStepper(value: $settings.maxClips, range: 20...500, step: 20)
                    }
                }

                group("媒体") {
                    settingRow("显示歌词", subtitle: "仅发送歌名与歌手，用于匹配歌词") {
                        IslandToggle(isOn: $settings.lyricsEnabled)
                    }
                }

                group("权限") {
                    permissionRow(title: "读取系统通知",
                                  detail: "完全磁盘访问权限",
                                  granted: notifications.dbAvailable,
                                  action: { Permissions.openFullDiskAccessSettings() })
                    permissionRow(title: "辅助功能",
                                  detail: "读取通知横幅与全局快捷键",
                                  granted: Permissions.accessibility,
                                  action: { Permissions.requestAccessibility() })
                }
    }

    // MARK: 组件

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .kerning(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)

            VStack(spacing: 0) { content() }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        }
    }

    private func settingRow<Control: View>(_ title: String,
                                           subtitle: String? = nil,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            control()
        }
        .frame(height: subtitle == nil ? 32 : 38)
        .padding(.horizontal, 2)
    }

    private func permissionRow(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(granted ? Theme.success : Theme.unread)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                Text(granted ? "已授权" : detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if !granted {
                IslandTextButton(title: "去开启", tint: Theme.accent, action: action)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 2)
    }
}

struct IslandToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? Color.white.opacity(0.92) : Color.white.opacity(0.16))
                .frame(width: 32, height: 19)
            Circle()
                .fill(isOn ? Color(white: 0.08) : Color.white)
                .frame(width: 15, height: 15)
                .padding(2)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .frame(width: 32, height: 19)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) { isOn.toggle() }
        }
        .pointerCursor()
    }
}

struct CompactStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            button("minus") { value = max(range.lowerBound, value - step) }
            Text("\(value)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 24)
            button("plus") { value = min(range.upperBound, value + step) }
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
