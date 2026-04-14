import SwiftUI

/// Two black pills flanking the hardware notch.
///
/// Top corners are flat (flush with screen top edge).
/// Only bottom outer corners are rounded — giving the Dynamic Island feel.
struct DualPillView: View {
    let track: Track
    let isPlaying: Bool
    let geometry: NotchGeometry
    /// True while card is visible — flattens bottom outer corners to connect flush.
    let bottomCornersFlat: Bool

    private var notchW: CGFloat { geometry.notchFrame.width }
    private var sideW: CGFloat { (NotchGeometry.expandedWidth - notchW) / 2 }
    private var h: CGFloat { geometry.notchFrame.height }
    private var outerR: CGFloat { h / 2 }
    private var artSize: CGFloat { h - 10 }
    private var bottomR: CGFloat { bottomCornersFlat ? 0 : outerR }

    var body: some View {
        HStack(spacing: 0) {
            leftPill
            Color.black.frame(width: notchW)
            rightPill
        }
    }

    // Left pill: top flat, bottom-left rounded, right side flat (faces notch)
    private var leftPill: some View {
        Group {
            if let art = track.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: artSize, height: artSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(width: sideW, height: h)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: bottomR,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(Color.black)
        )
    }

    // Right pill: top flat, bottom-right rounded, left side flat (faces notch)
    private var rightPill: some View {
        MusicBarsView(isPlaying: isPlaying, highFPS: bottomCornersFlat)
            .frame(width: 18, height: 12)
            .frame(width: sideW, height: h)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: bottomR,
                    topTrailingRadius: 0
                )
                .fill(Color.black)
            )
    }
}

// MARK: - Animated music bars
//
// Uses TimelineView + Canvas so the animation is paused at zero CPU cost when
// music is not playing, and draws only a single Canvas call (no child view tree).

struct MusicBarsView: View {
    let isPlaying: Bool
    var highFPS: Bool = false   // true while card is open → 20fps, otherwise 5fps

    var body: some View {
        let interval = highFPS ? 1.0 / 20.0 : 1.0 / 5.0
        TimelineView(.animation(minimumInterval: interval, paused: !isPlaying)) { tl in
            BarsCanvas(phase: tl.date.timeIntervalSinceReferenceDate, isPlaying: isPlaying)
        }
    }
}

private struct BarsCanvas: View {
    let phase: TimeInterval
    let isPlaying: Bool

    // Unique frequency per bar so they don't move in sync
    private let freqs: [Double] = [2.7, 3.5, 2.1, 4.1]
    private let offsets: [Double] = [0.0, 0.55, 1.1, 1.7]

    var body: some View {
        Canvas { ctx, size in
            let count    = 4
            let barW: CGFloat = 2.5
            let gap: CGFloat  = 2.0
            let totalW   = CGFloat(count) * barW + CGFloat(count - 1) * gap
            let startX   = (size.width - totalW) / 2

            for i in 0..<count {
                let t = phase + offsets[i]
                let fraction: CGFloat = isPlaying
                    ? CGFloat(0.55 + 0.45 * (sin(t * freqs[i]) * 0.5 + 0.5))
                    : 0.3
                let barH = size.height * fraction
                let x    = startX + CGFloat(i) * (barW + gap)
                let y    = size.height - barH   // anchor to bottom
                let rect = CGRect(x: x, y: y, width: barW, height: barH)
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(.white.opacity(0.85))
                )
            }
        }
    }
}
