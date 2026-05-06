import Foundation

enum MusicServiceSource: CaseIterable {
    case appleMusic
    case spotify
}

@MainActor
final class CompositeMusicService: MusicServiceProtocol {
    var onTrackChanged: ((Track?) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgressChanged: ((TimeInterval) -> Void)?

    private struct SourceState {
        var track: Track?
        var isPlaying = false
        var elapsed: TimeInterval = 0
        var lastUpdated = Date.distantPast
    }

    private let services: [MusicServiceSource: any MusicServiceProtocol]
    private var states: [MusicServiceSource: SourceState]
    private var activeSource: MusicServiceSource?

    init(
        services: [(MusicServiceSource, any MusicServiceProtocol)] = [
            (.appleMusic, AppleMusicService()),
            (.spotify, SpotifyMusicService())
        ]
    ) {
        self.services = Dictionary(uniqueKeysWithValues: services)
        self.states = Dictionary(uniqueKeysWithValues: services.map { ($0.0, SourceState()) })
        bindServices()
    }

    func startObserving() {
        services.values.forEach { $0.startObserving() }
    }

    func stopObserving() {
        services.values.forEach { $0.stopObserving() }
    }

    func togglePlayPause() {
        commandService?.togglePlayPause()
    }

    func nextTrack() {
        commandService?.nextTrack()
    }

    func previousTrack() {
        commandService?.previousTrack()
    }

    // MARK: - Private

    private func bindServices() {
        for (source, service) in services {
            service.onTrackChanged = { [weak self] track in
                self?.handleTrackChanged(track, from: source)
            }
            service.onPlaybackStateChanged = { [weak self] isPlaying in
                self?.handlePlaybackStateChanged(isPlaying, from: source)
            }
            service.onProgressChanged = { [weak self] elapsed in
                self?.handleProgressChanged(elapsed, from: source)
            }
        }
    }

    private var commandService: (any MusicServiceProtocol)? {
        if let activeSource, let service = services[activeSource] {
            return service
        }
        guard let source = mostRecentSource(where: { $0.track != nil }) else {
            return nil
        }
        return services[source]
    }

    private func handleTrackChanged(_ track: Track?, from source: MusicServiceSource) {
        updateState(for: source) { state in
            state.track = track
        }

        if let track {
            activeSource = source
            onTrackChanged?(track)
            if let state = states[source] {
                onProgressChanged?(state.elapsed)
            }
            return
        }

        guard activeSource == source else { return }

        if let fallback = mostRecentSource(where: { $0.isPlaying && $0.track != nil }),
           let fallbackState = states[fallback],
           let fallbackTrack = fallbackState.track {
            activeSource = fallback
            onTrackChanged?(fallbackTrack)
            onProgressChanged?(fallbackState.elapsed)
            onPlaybackStateChanged?(fallbackState.isPlaying)
        } else {
            activeSource = nil
            onTrackChanged?(nil)
            onProgressChanged?(0)
            onPlaybackStateChanged?(false)
        }
    }

    private func handlePlaybackStateChanged(_ isPlaying: Bool, from source: MusicServiceSource) {
        updateState(for: source) { state in
            state.isPlaying = isPlaying
        }

        if isPlaying {
            activeSource = source
            if let track = states[source]?.track {
                onTrackChanged?(track)
            }
            onPlaybackStateChanged?(true)
            return
        }

        if activeSource == source {
            onPlaybackStateChanged?(false)
        }
    }

    private func handleProgressChanged(_ elapsed: TimeInterval, from source: MusicServiceSource) {
        updateState(for: source) { state in
            state.elapsed = elapsed
        }

        if activeSource == source {
            onProgressChanged?(elapsed)
        }
    }

    private func updateState(
        for source: MusicServiceSource,
        _ update: (inout SourceState) -> Void
    ) {
        var state = states[source] ?? SourceState()
        update(&state)
        state.lastUpdated = Date()
        states[source] = state
    }

    private func mostRecentSource(where matches: (SourceState) -> Bool) -> MusicServiceSource? {
        states
            .filter { matches($0.value) }
            .max { $0.value.lastUpdated < $1.value.lastUpdated }?
            .key
    }
}
