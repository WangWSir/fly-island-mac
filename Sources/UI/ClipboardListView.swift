import SwiftUI

struct ClipboardListView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var clipboard: ClipboardService
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            searchBar

            SectionHeader(title: clipboard.pinnedCount > 0 ? "历史 · \(clipboard.pinnedCount) 条收藏" : "历史记录") {
                if !clipboard.items.isEmpty {
                    IslandTextButton(title: "清空", symbol: "trash") {
                        withAnimation(IslandAnimation.quick) { clipboard.clearAll() }
                    }
                }
            }

            if clipboard.filtered.isEmpty {
                EmptyState(symbol: clipboard.items.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                           title: clipboard.items.isEmpty ? "剪贴板还没有内容" : "没有匹配的记录",
                           subtitle: clipboard.items.isEmpty ? "复制文字或图片后会自动记录在这里" : nil)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(clipboard.filtered) { item in
                            ClipRow(item: item)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .bottomFade()
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("搜索剪贴板", text: $clipboard.query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
            if !clipboard.query.isEmpty {
                Button {
                    clipboard.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(searchFocused ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // 非激活面板要拿到键盘输入，需要先激活应用
            NSApp.activate(ignoringOtherApps: true)
            searchFocused = true
        }
    }
}

struct ClipRow: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var clipboard: ClipboardService
    let item: ClipItem
    @State private var hover = false

    var body: some View {
        Button {
            clipboard.copyToPasteboard(item)
            model.showToast("已复制")
        } label: {
            HStack(alignment: .center, spacing: 9) {
                if item.kind == .image, let image = clipboard.image(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                } else {
                    Image(systemName: icon(for: item))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.singleLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        if let source = item.source, item.kind == .image {
                            Text(source)
                        }
                        Text(item.timeText)
                    }
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textTertiary.opacity(0.8))
                }

                Spacer(minLength: 0)

                if hover || item.pinned {
                    HStack(spacing: 1) {
                        Button {
                            clipboard.togglePin(item)
                        } label: {
                            Image(systemName: item.pinned ? "star.fill" : "star")
                                .font(.system(size: 9))
                                .foregroundStyle(item.pinned ? Color.yellow.opacity(0.9) : Theme.textTertiary)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)

                        if hover {
                            Button {
                                withAnimation(IslandAnimation.quick) { clipboard.delete(item) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8.5, weight: .bold))
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
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

    private func icon(for item: ClipItem) -> String {
        if item.kind == .image { return "photo" }
        let t = item.previewText
        if t.hasPrefix("http") { return "link" }
        if t.contains("\n") { return "text.alignleft" }
        return "text.quote"
    }
}
