import AppKit
@testable import NotchMusic
import XCTest

final class MusicPlayerViewModelTests: XCTestCase {
    @MainActor
    func test_startObserving_forwardsToService() {
        let harness = makeHarness()

        harness.sut.startObserving()

        XCTAssertTrue(harness.service.didStartObserving)
    }

    @MainActor
    func test_whenServiceEmitsTrack_viewModelUpdates() {
        let harness = makeHarness()
        let track = Track(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", duration: 354)

        harness.service.simulateTrack(track)

        XCTAssertEqual(harness.sut.currentTrack, track)
    }

    @MainActor
    func test_whenServiceEmitsNilTrack_currentTrackIsNil() {
        let harness = makeHarness()

        harness.service.simulateTrack(nil)

        XCTAssertNil(harness.sut.currentTrack)
    }

    @MainActor
    func test_whenTrackBecomesNil_isExpandedCollapses() {
        let harness = makeHarness()
        harness.sut.isExpanded = true

        harness.service.simulateTrack(nil)

        XCTAssertFalse(harness.sut.isExpanded)
    }

    @MainActor
    func test_transientNilTrackKeepsLastTrackDuringGracePeriod() {
        let harness = makeHarness(missingTrackGracePeriod: .seconds(1))
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)

        harness.service.simulateTrack(track)
        harness.service.simulateTrack(nil)

        XCTAssertEqual(harness.sut.currentTrack, track)
    }

    @MainActor
    func test_whenTrackChangesBeforePlaybackStarts_expandsAfterPlayingEvent() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)

        harness.service.simulateTrack(track)
        XCTAssertFalse(harness.sut.isExpanded)

        harness.service.simulatePlaying(true)
        XCTAssertTrue(harness.sut.isExpanded)
    }

    @MainActor
    func test_whenPausedClearsPendingTrackExpansion() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)

        harness.service.simulateTrack(track)
        harness.service.simulatePlaying(false)
        harness.service.simulatePlaying(true)

        XCTAssertFalse(harness.sut.isExpanded)
    }

    @MainActor
    func test_whenArtworkUpdatesWhilePaused_doesNotExpand() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)
        let trackWithArtwork = Track(
            title: "Test",
            artist: "Artist",
            album: "Album",
            duration: 200,
            artwork: NSImage(size: NSSize(width: 10, height: 10))
        )

        harness.service.simulateTrack(track)
        harness.service.simulatePlaying(false)
        harness.service.simulateTrack(trackWithArtwork)

        XCTAssertFalse(harness.sut.isExpanded)
    }

    @MainActor
    func test_whenServiceEmitsPlaying_isPlayingUpdates() {
        let harness = makeHarness()

        harness.service.simulatePlaying(true)

        XCTAssertTrue(harness.sut.isPlaying)
    }

    @MainActor
    func test_whenServiceEmitsPaused_isExpandedCollapses() {
        let harness = makeHarness()
        harness.sut.isExpanded = true

        harness.service.simulatePlaying(false)

        XCTAssertFalse(harness.sut.isExpanded)
    }

    @MainActor
    func test_whenPausedWhileHovering_keepsExpanded() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)
        harness.service.simulateTrack(track)
        harness.sut.onPillHoverEntered()

        harness.service.simulatePlaying(false)

        XCTAssertTrue(harness.sut.isExpanded)
    }

    @MainActor
    func test_progressCalculation_withDuration() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)

        harness.service.simulateTrack(track)
        harness.service.simulateProgress(50)

        XCTAssertEqual(harness.sut.progress, 0.25, accuracy: 0.001)
    }

    @MainActor
    func test_progressCalculation_withZeroDuration_returnsZero() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 0)

        harness.service.simulateTrack(track)
        harness.service.simulateProgress(10)

        XCTAssertEqual(harness.sut.progress, 0)
    }

    @MainActor
    func test_progressClampsToOne() {
        let harness = makeHarness()
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 100)

        harness.service.simulateTrack(track)
        harness.service.simulateProgress(150)

        XCTAssertEqual(harness.sut.progress, 1.0)
    }

    @MainActor
    func test_togglePlayPause_delegatesToService() {
        let harness = makeHarness()

        harness.sut.togglePlayPause()

        XCTAssertEqual(harness.service.togglePlayPauseCount, 1)
    }

    @MainActor
    func test_nextTrack_delegatesToService() {
        let harness = makeHarness()

        harness.sut.nextTrack()

        XCTAssertEqual(harness.service.nextTrackCount, 1)
    }

    @MainActor
    func test_previousTrack_delegatesToService() {
        let harness = makeHarness()

        harness.sut.previousTrack()

        XCTAssertEqual(harness.service.previousTrackCount, 1)
    }

    @MainActor
    private func makeHarness(
        missingTrackGracePeriod: Duration = .zero
    ) -> MusicPlayerViewModelHarness {
        MusicPlayerViewModelHarness(missingTrackGracePeriod: missingTrackGracePeriod)
    }
}

@MainActor
private final class MusicPlayerViewModelHarness {
    let service = MockMusicService()
    let sut: MusicPlayerViewModel

    init(missingTrackGracePeriod: Duration) {
        sut = MusicPlayerViewModel(
            service: service,
            missingTrackGracePeriod: missingTrackGracePeriod
        )
    }
}
