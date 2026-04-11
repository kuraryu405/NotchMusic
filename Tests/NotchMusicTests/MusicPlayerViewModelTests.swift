import XCTest
@testable import NotchMusic

@MainActor
final class MusicPlayerViewModelTests: XCTestCase {
    // All tests run on the MainActor to match @MainActor service/viewmodel isolation.

    private var service: MockMusicService!
    private var sut: MusicPlayerViewModel!

    override func setUp() {
        super.setUp()
        service = MockMusicService()
        sut     = MusicPlayerViewModel(service: service)
    }

    override func tearDown() {
        sut     = nil
        service = nil
        super.tearDown()
    }

    // MARK: - startObserving

    func test_startObserving_forwardsToService() {
        sut.startObserving()
        XCTAssertTrue(service.didStartObserving)
    }

    // MARK: - Track changes

    func test_whenServiceEmitsTrack_viewModelUpdates() {
        let track = Track(title: "Bohemian Rhapsody", artist: "Queen", album: "A Night at the Opera", duration: 354)
        service.simulateTrack(track)
        XCTAssertEqual(sut.currentTrack, track)
    }

    func test_whenServiceEmitsNilTrack_currentTrackIsNil() {
        service.simulateTrack(nil)
        XCTAssertNil(sut.currentTrack)
    }

    func test_whenTrackBecomesNil_isExpandedCollapses() {
        sut.isExpanded = true
        service.simulateTrack(nil)
        XCTAssertFalse(sut.isExpanded)
    }

    // MARK: - Playback state

    func test_whenServiceEmitsPlaying_isPlayingUpdates() {
        service.simulatePlaying(true)
        XCTAssertTrue(sut.isPlaying)
    }

    func test_whenServiceEmitsPaused_isExpandedCollapses() {
        sut.isExpanded = true
        service.simulatePlaying(false)
        XCTAssertFalse(sut.isExpanded)
    }

    // MARK: - Progress

    func test_progressCalculation_withDuration() {
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 200)
        service.simulateTrack(track)
        service.simulateProgress(50)
        XCTAssertEqual(sut.progress, 0.25, accuracy: 0.001)
    }

    func test_progressCalculation_withZeroDuration_returnsZero() {
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 0)
        service.simulateTrack(track)
        service.simulateProgress(10)
        XCTAssertEqual(sut.progress, 0)
    }

    func test_progressClampsToOne() {
        let track = Track(title: "Test", artist: "Artist", album: "Album", duration: 100)
        service.simulateTrack(track)
        service.simulateProgress(150)
        XCTAssertEqual(sut.progress, 1.0)
    }

    // MARK: - Control delegation

    func test_togglePlayPause_delegatesToService() {
        sut.togglePlayPause()
        XCTAssertEqual(service.togglePlayPauseCount, 1)
    }

    func test_nextTrack_delegatesToService() {
        sut.nextTrack()
        XCTAssertEqual(service.nextTrackCount, 1)
    }

    func test_previousTrack_delegatesToService() {
        sut.previousTrack()
        XCTAssertEqual(service.previousTrackCount, 1)
    }
}
