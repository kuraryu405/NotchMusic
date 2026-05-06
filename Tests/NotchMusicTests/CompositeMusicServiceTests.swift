@testable import NotchMusic
import XCTest

@MainActor
final class CompositeMusicServiceTests: XCTestCase {
    private var appleMusic: MockMusicService!
    private var spotify: MockMusicService!
    private var sut: CompositeMusicService!

    private var receivedTrack: Track?
    private var receivedPlaying: Bool?
    private var receivedElapsed: TimeInterval?

    override func setUp() {
        super.setUp()
        appleMusic = MockMusicService()
        spotify = MockMusicService()
        sut = CompositeMusicService(services: [
            (.appleMusic, appleMusic),
            (.spotify, spotify)
        ])
        sut.onTrackChanged = { [weak self] track in self?.receivedTrack = track }
        sut.onPlaybackStateChanged = { [weak self] playing in self?.receivedPlaying = playing }
        sut.onProgressChanged = { [weak self] elapsed in self?.receivedElapsed = elapsed }
    }

    override func tearDown() {
        receivedTrack = nil
        receivedPlaying = nil
        receivedElapsed = nil
        sut = nil
        spotify = nil
        appleMusic = nil
        super.tearDown()
    }

    func test_startObserving_startsBothServices() {
        sut.startObserving()

        XCTAssertTrue(appleMusic.didStartObserving)
        XCTAssertTrue(spotify.didStartObserving)
    }

    func test_spotifyTrackBecomesActive() {
        let track = Track(title: "Harder Better Faster Stronger", artist: "Daft Punk", album: "Discovery", duration: 224)

        spotify.simulateTrack(track)
        spotify.simulatePlaying(true)

        XCTAssertEqual(receivedTrack, track)
        XCTAssertEqual(receivedPlaying, true)
    }

    func test_trackChangeDoesNotEmitStalePausedState() {
        let track = Track(title: "Harder Better Faster Stronger", artist: "Daft Punk", album: "Discovery", duration: 224)

        spotify.simulateTrack(track)

        XCTAssertEqual(receivedTrack, track)
        XCTAssertNil(receivedPlaying)
    }

    func test_commandsRouteToActiveSource() {
        let track = Track(title: "Nikes", artist: "Frank Ocean", album: "Blonde", duration: 314)
        spotify.simulateTrack(track)

        sut.togglePlayPause()
        sut.nextTrack()
        sut.previousTrack()

        XCTAssertEqual(spotify.togglePlayPauseCount, 1)
        XCTAssertEqual(spotify.nextTrackCount, 1)
        XCTAssertEqual(spotify.previousTrackCount, 1)
        XCTAssertEqual(appleMusic.togglePlayPauseCount, 0)
        XCTAssertEqual(appleMusic.nextTrackCount, 0)
        XCTAssertEqual(appleMusic.previousTrackCount, 0)
    }

    func test_inactiveNilTrackDoesNotClearActiveSource() {
        let track = Track(title: "A-Punk", artist: "Vampire Weekend", album: "Vampire Weekend", duration: 137)
        spotify.simulateTrack(track)

        appleMusic.simulateTrack(nil)

        XCTAssertEqual(receivedTrack, track)
    }

    func test_activeNilTrackFallsBackToPlayingSource() {
        let appleTrack = Track(title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon", duration: 413)
        let spotifyTrack = Track(title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 301)
        appleMusic.simulateTrack(appleTrack)
        appleMusic.simulatePlaying(true)
        spotify.simulateTrack(spotifyTrack)
        spotify.simulatePlaying(true)

        spotify.simulateTrack(nil)

        XCTAssertEqual(receivedTrack, appleTrack)
        XCTAssertEqual(receivedPlaying, true)
    }
}
