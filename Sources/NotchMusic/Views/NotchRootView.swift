import SwiftUI

/// Content of the static pill window — never moves.
struct PillView: View {
    @ObservedObject var viewModel: MusicPlayerViewModel
    let geometry: NotchGeometry

    var body: some View {
        Group {
            if let track = viewModel.currentTrack {
                DualPillView(
                    track: track,
                    isPlaying: viewModel.isPlaying,
                    geometry: geometry,
                    bottomCornersFlat: viewModel.pillCornersFlat
                )
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.8),
                    value: viewModel.pillCornersFlat
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { viewModel.onHoverEntered() } else { viewModel.onHoverLeft() }
        }
    }
}

/// Content of the animated card window — appears below the notch when expanded.
struct CardView: View {
    @ObservedObject var viewModel: MusicPlayerViewModel

    private var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 20,
            bottomTrailingRadius: 20, topTrailingRadius: 0
        )
    }

    var body: some View {
        ExpandedView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardShape.fill(Color.black))
            .clipShape(cardShape)
            .overlay(cardShape.strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { viewModel.onHoverEntered() } else { viewModel.onHoverLeft() }
            }
    }
}
