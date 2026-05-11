import AppKit
@testable import NotchMusic
import XCTest

final class CompositeMusicServiceTests: XCTestCase {
    @MainActor
    func test_startObserving_startsBothServices() {
        let harness = makeHarness()

        harness.sut.startObserving()

        XCTAssertTrue(harness.appleMusic.didStartObserving)
        XCTAssertTrue(harness.spotify.didStartObserving)
    }

    @MainActor
    func test_spotifyTrackBecomesActive() {
        let harness = makeHarness()
        let track = Track(title: "Harder Better Faster Stronger", artist: "Daft Punk", album: "Discovery", duration: 224)

        harness.spotify.simulateTrack(track)
        harness.spotify.simulatePlaying(true)

        XCTAssertEqual(harness.receivedTrack, track)
        XCTAssertEqual(harness.receivedPlaying, true)
    }

    @MainActor
    func test_trackChangeDoesNotEmitStalePausedState() {
        let harness = makeHarness()
        let track = Track(title: "Harder Better Faster Stronger", artist: "Daft Punk", album: "Discovery", duration: 224)

        harness.spotify.simulateTrack(track)

        XCTAssertEqual(harness.receivedTrack, track)
        XCTAssertNil(harness.receivedPlaying)
    }

    @MainActor
    func test_commandsRouteToActiveSource() {
        let harness = makeHarness()
        let track = Track(title: "Nikes", artist: "Frank Ocean", album: "Blonde", duration: 314)
        harness.spotify.simulateTrack(track)

        harness.sut.togglePlayPause()
        harness.sut.nextTrack()
        harness.sut.previousTrack()

        XCTAssertEqual(harness.spotify.togglePlayPauseCount, 1)
        XCTAssertEqual(harness.spotify.nextTrackCount, 1)
        XCTAssertEqual(harness.spotify.previousTrackCount, 1)
        XCTAssertEqual(harness.appleMusic.togglePlayPauseCount, 0)
        XCTAssertEqual(harness.appleMusic.nextTrackCount, 0)
        XCTAssertEqual(harness.appleMusic.previousTrackCount, 0)
    }

    @MainActor
    func test_inactiveNilTrackDoesNotClearActiveSource() {
        let harness = makeHarness()
        let track = Track(title: "A-Punk", artist: "Vampire Weekend", album: "Vampire Weekend", duration: 137)
        harness.spotify.simulateTrack(track)

        harness.appleMusic.simulateTrack(nil)

        XCTAssertEqual(harness.receivedTrack, track)
    }

    @MainActor
    func test_activeNilTrackFallsBackToPlayingSource() {
        let harness = makeHarness()
        let appleTrack = Track(title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413)
        let spotifyTrack = Track(title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 301)
        harness.appleMusic.simulateTrack(appleTrack)
        harness.appleMusic.simulatePlaying(true)
        harness.spotify.simulateTrack(spotifyTrack)
        harness.spotify.simulatePlaying(true)

        harness.spotify.simulateTrack(nil)

        XCTAssertEqual(harness.receivedTrack, appleTrack)
        XCTAssertEqual(harness.receivedPlaying, true)
    }

    @MainActor
    func test_activePausedTrackFallsBackToPlayingSourceAndRoutesCommands() {
        let harness = makeHarness()
        let appleTrack = Track(title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413)
        let spotifyTrack = Track(title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 301)
        harness.appleMusic.simulateTrack(appleTrack)
        harness.appleMusic.simulatePlaying(true)
        harness.spotify.simulateTrack(spotifyTrack)
        harness.spotify.simulatePlaying(true)

        harness.spotify.simulatePlaying(false)
        harness.sut.togglePlayPause()

        XCTAssertEqual(harness.receivedTrack, appleTrack)
        XCTAssertEqual(harness.receivedPlaying, true)
        XCTAssertEqual(harness.appleMusic.togglePlayPauseCount, 1)
        XCTAssertEqual(harness.spotify.togglePlayPauseCount, 0)
    }

    @MainActor
    func test_inactiveArtworkUpdateDoesNotStealActivePlayingSource() {
        let harness = makeHarness()
        let appleTrack = Track(title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413)
        let appleTrackWithArtwork = Track(
            title: "Time",
            artist: "Pink Floyd",
            album: "The Dark Side of the Moon",
            duration: 413,
            artwork: NSImage(size: NSSize(width: 10, height: 10))
        )
        let spotifyTrack = Track(title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 301)
        harness.appleMusic.simulateTrack(appleTrack)
        harness.appleMusic.simulatePlaying(false)
        harness.spotify.simulateTrack(spotifyTrack)
        harness.spotify.simulatePlaying(true)

        harness.appleMusic.simulateTrack(appleTrackWithArtwork)
        harness.sut.togglePlayPause()

        XCTAssertEqual(harness.receivedTrack, spotifyTrack)
        XCTAssertEqual(harness.receivedPlaying, true)
        XCTAssertEqual(harness.spotify.togglePlayPauseCount, 1)
        XCTAssertEqual(harness.appleMusic.togglePlayPauseCount, 0)
    }

    @MainActor
    func test_inactiveArtworkUpdateDoesNotStealSourceThatIsPlayingBeforeTrackArrives() {
        let harness = makeHarness()
        let appleTrack = Track(title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413)
        let appleTrackWithArtwork = Track(
            title: "Time",
            artist: "Pink Floyd",
            album: "The Dark Side of the Moon",
            duration: 413,
            artwork: NSImage(size: NSSize(width: 10, height: 10))
        )
        harness.appleMusic.simulateTrack(appleTrack)
        harness.appleMusic.simulatePlaying(false)
        harness.spotify.simulatePlaying(true)

        harness.appleMusic.simulateTrack(appleTrackWithArtwork)
        harness.sut.togglePlayPause()

        XCTAssertNotEqual(harness.receivedTrack, appleTrackWithArtwork)
        XCTAssertEqual(harness.receivedPlaying, true)
        XCTAssertEqual(harness.spotify.togglePlayPauseCount, 1)
        XCTAssertEqual(harness.appleMusic.togglePlayPauseCount, 0)
    }

    @MainActor
    private func makeHarness() -> CompositeMusicServiceHarness {
        CompositeMusicServiceHarness()
    }
}

@MainActor
private final class CompositeMusicServiceHarness {
    let appleMusic = MockMusicService()
    let spotify = MockMusicService()
    let sut: CompositeMusicService

    var receivedTrack: Track?
    var receivedPlaying: Bool?
    var receivedElapsed: TimeInterval?

    init() {
        sut = CompositeMusicService(services: [
            (.appleMusic, appleMusic),
            (.spotify, spotify)
        ])
        sut.onTrackChanged = { [weak self] track in self?.receivedTrack = track }
        sut.onPlaybackStateChanged = { [weak self] playing in self?.receivedPlaying = playing }
        sut.onProgressChanged = { [weak self] elapsed in self?.receivedElapsed = elapsed }
    }
}
