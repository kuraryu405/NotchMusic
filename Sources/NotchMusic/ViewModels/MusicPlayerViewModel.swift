import AppKit
import Combine
import Foundation

/// Observable state for the notch UI.
///
/// Lightweight: all state changes are published on `@MainActor` so SwiftUI
/// only redraws when something actually changes.
@MainActor
final class MusicPlayerViewModel: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool    = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var isExpanded: Bool                = false
    /// True while the card is visible — pill bottom corners flatten to connect flush.
    /// Set false only after card animation fully completes (via NotchWindowManager callback).
    @Published var pillCornersFlat: Bool           = false

    /// Fraction 0…1 of playback progress.
    var progress: Double {
        guard let track = currentTrack, track.duration > 0 else { return 0 }
        return min(elapsed / track.duration, 1)
    }

    private let service: any MusicServiceProtocol

    init(service: any MusicServiceProtocol) {
        self.service = service
        bindService()
    }

    func cleanup() {
        service.stopObserving()
    }

    func startObserving() {
        service.startObserving()
    }

    func togglePlayPause() {
        service.togglePlayPause()
    }

    func nextTrack() {
        service.nextTrack()
    }

    func previousTrack() {
        service.previousTrack()
    }

    func restartObserving() {
        service.stopObserving()
        service.startObserving()
    }

    // MARK: - Private

    private func bindService() {
        // Both MediaRemoteService and this ViewModel are @MainActor,
        // so callbacks are always delivered on the main actor — no Task wrapper needed.
        service.onTrackChanged = { [weak self] track in
            guard let self else { return }
            debugLog("[ViewModel] onTrackChanged: \(track?.title ?? "nil")")
            let previous = currentTrack
            currentTrack = track
            if track == nil { isExpanded = false }
            if track != nil, track != previous { brieflyExpand() }
        }

        service.onPlaybackStateChanged = { [weak self] playing in
            guard let self else { return }
            isPlaying = playing
            if !playing { isExpanded = false }
        }

        service.onProgressChanged = { [weak self] elapsed in
            self?.elapsed = elapsed
        }
    }

    // MARK: - Hover coordination (shared by pill window and card window)

    private var collapseTask: DispatchWorkItem?

    /// Call when the pill window gains hover.
    /// This is the only hover path that is allowed to trigger expansion.
    func onPillHoverEntered() {
        collapseTask?.cancel()
        collapseTask = nil
        if currentTrack != nil, !isExpanded { isExpanded = true }
    }

    /// Call when the card window gains hover.
    /// Card hover should keep an expanded card open, but never open a collapsed one.
    func onCardHoverEntered() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    /// Call when any NotchMusic window loses hover.
    func onHoverLeft() {
        collapseTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.isExpanded = false
        }
        collapseTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    /// Expands for 3 s on track change, then collapses (unless the user is hovering).
    private func brieflyExpand() {
        isExpanded = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.isExpanded { self.isExpanded = false }
        }
    }
}
