import SwiftUI

struct ExpandedContent: View {
    @EnvironmentObject var model: IslandModel
    let metrics: IslandMetrics

    var body: some View {
        VStack(spacing: 0) {
            TopBar(metrics: metrics)

            Group {
                switch model.tab {
                case .notifications: NotificationListView()
                case .clipboard: ClipboardListView()
                case .music: MusicView()
                case .settings: SettingsView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .top)
    }
}

private struct TopBar: View {
    @EnvironmentObject var model: IslandModel
    let metrics: IslandMetrics

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                TabChip(tab: .notifications)
                TabChip(tab: .clipboard)
            }
            .padding(.leading, 10)
            .frame(width: metrics.wingWidth, alignment: .leading)

            Color.clear.frame(width: metrics.notchWidth)

            HStack(spacing: 2) {
                TabChip(tab: .music)
                TabChip(tab: .settings)
            }
            .padding(.trailing, 10)
            .frame(width: metrics.wingWidth, alignment: .trailing)
        }
        .frame(height: metrics.notchHeight)
    }
}

private struct TabChip: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var settings: Settings
    let tab: IslandTab
    @State private var hover = false

    private var selected: Bool { model.tab == tab }

    var body: some View {
        Button {
            model.select(tab: tab)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Theme.textPrimary : (hover ? Theme.textSecondary : Theme.textTertiary))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? Color.white.opacity(0.13) : (hover ? Color.white.opacity(0.06) : Color.clear))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 标题栏内的分区标题
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
                .kerning(0.4)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: 20)
        .padding(.horizontal, 2)
    }
}

/// 空状态
struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 12)
    }
}
