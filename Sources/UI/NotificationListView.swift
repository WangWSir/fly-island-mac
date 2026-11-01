import SwiftUI

struct NotificationListView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var notifications: NotificationService
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(spacing: 8) {
            if !notifications.dbAvailable {
                PermissionCard()
            }

            SectionHeader(title: "最近通知") {
                HStack(spacing: 2) {
                    if notifications.unreadCount > 0 {
                        IslandTextButton(title: "全部已读", symbol: "checkmark.circle") {
                            notifications.markAllRead()
                        }
                    }
                    if !notifications.items.isEmpty {
                        IslandTextButton(title: "清空", symbol: "trash") {
                            withAnimation(IslandAnimation.quick) { notifications.clearAll() }
                        }
                    }
                }
            }

            if notifications.items.isEmpty {
                EmptyState(symbol: "bell.slash",
                           title: "暂无通知",
                           subtitle: notifications.dbAvailable
                            ? "微信、QQ 等应用推送消息时会出现在这里"
                            : "授予权限后即可接收应用通知")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(notifications.items) { item in
                            NotificationRow(item: item)
                                .transition(.opacity.combined(with: .offset(y: -8)))
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .bottomFade()
    }
}

struct NotificationRow: View {
    @EnvironmentObject var notifications: NotificationService
    let item: NotificationItem
    @State private var hover = false

    var body: some View {
        Button {
            notifications.markRead(id: item.id)
            AppInfo.activate(bundleID: item.bundleID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: item.icon)
                    .resizable()
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.appName)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Text(item.timeText)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary.opacity(0.65))
                        if !item.isRead {
                            Circle().fill(Theme.unread).frame(width: 5, height: 5)
                        }
                        Spacer(minLength: 0)
                    }
                    if !item.title.trimmed.isEmpty {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    if !item.body.trimmed.isEmpty {
                        Text(item.body)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if hover {
                    Button {
                        withAnimation(IslandAnimation.quick) { notifications.remove(id: item.id) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hover ? Theme.fill : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 未授权时的引导卡片
struct PermissionCard: View {
    @EnvironmentObject var notifications: NotificationService
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notifications.dbAvailable ? "checkmark.shield" : "lock.shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("需要「完全磁盘访问权限」")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("用于读取系统通知内容（微信、QQ 等），不会联网上传")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                Permissions.openFullDiskAccessSettings()
            } label: {
                Text("去授权")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.accent.opacity(0.85)))
            }
            .buttonStyle(.plain)

            Button {
                notifications.retry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("重新检查权限")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 0.6)
        )
    }
}
