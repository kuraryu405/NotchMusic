import AppKit
import Foundation

/// Reads now-playing state from Spotify via AppleScript and distributed
/// notifications.
@MainActor
final class SpotifyMusicService: MusicServiceProtocol {
    var onTrackChanged: ((Track?) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgressChanged: ((TimeInterval) -> Void)?

    private static let bundleIdentifier = "com.spotify.client"

    private var pollTimer: Timer?
    private var lastTrackID: String = ""
    private var lastFullTrack: Track?

    func startObserving() {
        subscribeToDistributedNotifications()
        fetchCurrentTrack()
    }

    func stopObserving() {
        DistributedNotificationCenter.default().removeObserver(self)
        stopPollTimer()
    }

    func togglePlayPause() {
        runAppleScript("tell application \"Spotify\" to playpause")
    }

    func nextTrack() {
        runAppleScript("tell application \"Spotify\" to next track")
    }

    func previousTrack() {
        runAppleScript("tell application \"Spotify\" to previous track")
    }

    // MARK: - Distributed notifications

    private func subscribeToDistributedNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(spotifyPlayerStateChanged(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        debugLog("[Spotify] subscribed to distributed notifications")
    }

    @objc private func spotifyPlayerStateChanged(_ note: NSNotification) {
        guard let info = note.userInfo else { return }

        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" {
            lastTrackID = ""
            lastFullTrack = nil
            onPlaybackStateChanged?(false)
            onTrackChanged?(nil)
            stopPollTimer()
            return
        }

        let title = info["Name"] as? String ?? ""
        let artist = info["Artist"] as? String ?? ""
        let album = info["Album"] as? String ?? ""
        let duration = normalizedDuration(from: numberValue(info["Duration"]))
        let elapsed = numberValue(info["Playback Position"] ?? info["Position"])
        let trackID = info["Track ID"] as? String ?? "\(title)-\(artist)"
        let artworkURL = info["Artwork URL"] as? String

        if title.isEmpty && artist.isEmpty {
            onPlaybackStateChanged?(false)
            return
        }

        updateTrackIfNeeded(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            trackID: trackID,
            artworkURL: artworkURL
        )
        onProgressChanged?(elapsed)

        let isPlaying = state == "playing"
        onPlaybackStateChanged?(isPlaying)
        if isPlaying {
            startPollTimer()
        } else {
            stopPollTimer()
        }

        if artworkURL == nil {
            fetchCurrentTrack()
        }
    }

    // MARK: - AppleScript polling

    private func fetchCurrentTrack() {
        guard spotifyIsRunning else {
            lastTrackID = ""
            lastFullTrack = nil
            onPlaybackStateChanged?(false)
            onTrackChanged?(nil)
            stopPollTimer()
            return
        }

        let src = """
        tell application "Spotify"
            if player state is stopped then
                return {}
            end if
            set t to current track
            return {name of t, artist of t, album of t, duration of t, player position, artwork url of t, player state as string}
        end tell
        """

        guard let descriptor = runAppleScriptDescriptor(src), descriptor.numberOfItems >= 7 else {
            onPlaybackStateChanged?(false)
            stopPollTimer()
            return
        }

        let title = stringValue(at: 1, in: descriptor)
        let artist = stringValue(at: 2, in: descriptor)
        let album = stringValue(at: 3, in: descriptor)
        let duration = normalizedDuration(from: doubleValue(at: 4, in: descriptor))
        let elapsed = doubleValue(at: 5, in: descriptor)
        let artworkURL = stringValue(at: 6, in: descriptor)
        let state = stringValue(at: 7, in: descriptor).lowercased()
        let trackID = "\(title)-\(artist)-\(album)"

        guard !title.isEmpty || !artist.isEmpty else {
            onPlaybackStateChanged?(false)
            return
        }

        updateTrackIfNeeded(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            trackID: trackID,
            artworkURL: artworkURL.isEmpty ? nil : artworkURL
        )
        onProgressChanged?(elapsed)

        let isPlaying = state == "playing"
        onPlaybackStateChanged?(isPlaying)
        if isPlaying {
            startPollTimer()
        } else {
            stopPollTimer()
        }
    }

    private var spotifyIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    private func updateTrackIfNeeded(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        trackID: String,
        artworkURL: String?
    ) {
        if trackID == lastTrackID {
            return
        }

        lastTrackID = trackID
        let track = Track(title: title, artist: artist, album: album, duration: duration)
        lastFullTrack = track
        onTrackChanged?(track)

        if let artworkURL {
            fetchArtwork(from: artworkURL, for: trackID)
        }
    }

    private func fetchArtwork(from artworkURL: String, for trackID: String) {
        guard let url = URL(string: artworkURL) else { return }
        debugLog("[Spotify] fetching artwork: \(artworkURL)")

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                debugLog("[Spotify] artwork error: \(error)")
                return
            }
            guard let data, let image = NSImage(data: data) else { return }

            Task { @MainActor [weak self] in
                guard let self,
                      self.lastTrackID == trackID,
                      let base = self.lastFullTrack else { return }
                let artTrack = Track(
                    title: base.title,
                    artist: base.artist,
                    album: base.album,
                    duration: base.duration,
                    artwork: image
                )
                self.lastFullTrack = artTrack
                self.onTrackChanged?(artTrack)
            }
        }.resume()
    }

    @discardableResult
    private func runAppleScript(_ src: String) -> String {
        runAppleScriptDescriptor(src)?.stringValue ?? ""
    }

    private func runAppleScriptDescriptor(_ src: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: src) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err {
            debugLog("[Spotify] AppleScript error: \(err)")
            return nil
        }
        return result
    }

    private func stringValue(at index: Int, in descriptor: NSAppleEventDescriptor) -> String {
        descriptor.atIndex(index)?.stringValue ?? ""
    }

    private func doubleValue(at index: Int, in descriptor: NSAppleEventDescriptor) -> Double {
        let item = descriptor.atIndex(index)
        if let value = item?.stringValue.flatMap(Double.init) {
            return value
        }
        return item?.doubleValue ?? 0
    }

    private func numberValue(_ raw: Any?) -> Double {
        switch raw {
        case let value as Double:
            return value
        case let value as Float:
            return Double(value)
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value) ?? 0
        default:
            return 0
        }
    }

    private func normalizedDuration(from value: Double) -> TimeInterval {
        value > 10_000 ? value / 1000.0 : value
    }

    private func startPollTimer() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchCurrentTrack() }
        }
    }

    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
