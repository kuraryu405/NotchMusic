import Foundation
@testable import NotchMusic

@MainActor
final class MockMusicService: MusicServiceProtocol {
    var onTrackChanged: ((Track?) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgressChanged: ((TimeInterval) -> Void)?

    private(set) var didStartObserving    = false
    private(set) var didStopObserving     = false
    private(set) var togglePlayPauseCount = 0
    private(set) var nextTrackCount       = 0
    private(set) var previousTrackCount   = 0

    func startObserving() { didStartObserving = true }
    func stopObserving() { didStopObserving  = true }
    func togglePlayPause() { togglePlayPauseCount += 1 }
    func nextTrack() { nextTrackCount += 1 }
    func previousTrack() { previousTrackCount += 1 }

    // Test helpers — simulate events from the service.
    func simulateTrack(_ track: Track?) { onTrackChanged?(track) }
    func simulatePlaying(_ playing: Bool) { onPlaybackStateChanged?(playing) }
    func simulateProgress(_ elapsed: TimeInterval) { onProgressChanged?(elapsed) }
}
