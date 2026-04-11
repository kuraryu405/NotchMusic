import SwiftUI

struct ExpandedView: View {
    @ObservedObject var viewModel: MusicPlayerViewModel
    @State private var hoveredControl: String?
    @State private var seekHovered = false

    var body: some View {
        HStack(spacing: 14) {
            artworkView
            infoColumn
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let image = viewModel.currentTrack?.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.13)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.white.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    // MARK: - Info column

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            trackInfo
            progressSection
            controls
        }
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.currentTrack?.title ?? "—")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(viewModel.currentTrack?.artist ?? "")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Progress bar (2px, white / white 20%)

    private var progressSection: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.20))
                        .frame(height: seekHovered ? 4 : 2)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: proxy.size.width * CGFloat(viewModel.progress),
                               height: seekHovered ? 4 : 2)
                        .animation(.linear(duration: 0.5), value: viewModel.progress)

                    if seekHovered {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .offset(x: proxy.size.width * CGFloat(viewModel.progress) - 4.5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: seekHovered)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)
            .contentShape(Rectangle())
            .onHover { h in
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { seekHovered = h }
            }

            HStack {
                Text(formatTime(viewModel.elapsed))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.30))
                Spacer()
                Text(formatTime(viewModel.currentTrack?.duration ?? 0))
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.30))
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 0) {
            Spacer()
            controlButton(id: "prev", systemName: "backward.fill", size: 13) {
                viewModel.previousTrack()
            }
            Spacer()
            controlButton(id: "play",
                          systemName: viewModel.isPlaying ? "pause.fill" : "play.fill",
                          size: 16) {
                viewModel.togglePlayPause()
            }
            Spacer()
            controlButton(id: "next", systemName: "forward.fill", size: 13) {
                viewModel.nextTrack()
            }
            Spacer()
        }
    }

    private func controlButton(id: String, systemName: String, size: CGFloat,
                                action: @escaping () -> Void) -> some View {
        let hovered = hoveredControl == id
        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(hovered ? .white : .white.opacity(0.65))
                .frame(width: 34, height: 34)
                .background(Circle().fill(hovered ? Color.white.opacity(0.14) : Color.clear))
                .scaleEffect(hovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.18, dampingFraction: 0.65), value: hovered)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .onHover { h in hoveredControl = h ? id : nil }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
