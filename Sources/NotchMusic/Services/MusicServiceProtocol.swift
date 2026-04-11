import Foundation

@MainActor
protocol MusicServiceProtocol: AnyObject {
    /// Called when now-playing state changes.
    var onTrackChanged: ((Track?) -> Void)? { get set }
    var onPlaybackStateChanged: ((Bool) -> Void)? { get set }
    var onProgressChanged: ((TimeInterval) -> Void)? { get set }

    func startObserving()
    func stopObserving()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
}
