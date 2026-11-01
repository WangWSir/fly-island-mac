import SwiftUI

struct MusicView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var media: MediaService
    @EnvironmentObject var lyrics: LyricsService

    var body: some View {
        Group {
            if media.now.isActive {
                player
            } else {
                EmptyState(symbol: "music.note.list",
                           title: "没有正在播放的内容",
                           subtitle: "在音乐、播客或浏览器里播放音频，这里会自动接管控制")
            }
        }
    }

    private var player: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                artwork
                VStack(alignment: .leading, spacing: 5) {
                    Text(media.now.title.isEmpty ? "未知曲目" : media.now.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !media.now.artist.isEmpty {
                        Text(media.now.artist)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    if !media.now.album.isEmpty {
                        Text(media.now.album)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    if let app = media.now.sourceApp {
                        HStack(spacing: 4) {
                            if let icon = app.icon {
                                Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                            }
                            Text(app.localizedName ?? "")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.top, 1)
                    }
                }
                Spacer(minLength: 0)
            }

            lyricLine

            progressBar

            controls
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 单行歌词（跟随进度切换）
    private var lyricLine: some View {
        let current = lyrics.currentLine(at: media.now.elapsed)
        return ZStack {
            if let current {
                Text(current)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(current)
                    .transition(.opacity)
            } else if lyrics.isLoading {
                Text("歌词加载中…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            } else if !media.now.album.isEmpty {
                Text(media.now.album)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary.opacity(0.7))
                    .lineLimit(1)
            } else {
                Text("暂无歌词")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
            }
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.22), value: current)
    }

    private var artwork: some View {
        ZStack {
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 104, height: 104)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                    )
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: max(0, geo.size.width * media.now.progress))
                }
            }
            .frame(height: 3.5)

            HStack {
                Text(timeText(media.now.elapsed))
                Spacer()
                Text("-" + timeText(max(0, media.now.duration - media.now.elapsed)))
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .monospacedDigit()
        }
        .padding(.horizontal, 2)
    }

    private var controls: some View {
        HStack(spacing: 26) {
            controlButton(symbol: "backward.fill", size: 17, action: { media.send(.previous) })

            Button {
                media.send(.toggle)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: 42, height: 42)
                    Image(systemName: media.now.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.black)
                        .offset(x: media.now.playing ? 0 : 1.2)
                }
            }
            .buttonStyle(.plain)
            .pointerCursor()

            controlButton(symbol: "forward.fill", size: 17, action: { media.send(.next) })
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    private func controlButton(symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
