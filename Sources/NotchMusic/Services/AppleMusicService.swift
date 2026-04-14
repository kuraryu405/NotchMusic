import AppKit
import Foundation

/// Reads now-playing state from Apple Music via AppleScript and
/// distributed notifications.  This avoids reliance on MediaRemote,
/// which macOS 26 restricts for ad-hoc signed apps.
@MainActor
final class AppleMusicService: MusicServiceProtocol {
    var onTrackChanged: ((Track?) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgressChanged: ((TimeInterval) -> Void)?

    private var pollTimer: Timer?

    // Track the last-known full data so same-track polls only update progress.
    private var lastTrackID: String = ""
    private var lastFullTrack: Track?   // includes artwork once fetched

    func startObserving() {
        subscribeToDistributedNotifications()
        fetchCurrentTrack()
        // Poll timer is started/stopped dynamically based on playback state
    }

    func stopObserving() {
        DistributedNotificationCenter.default().removeObserver(self)
        stopPollTimer()
    }

    func togglePlayPause() { runAppleScript("tell application \"Music\" to playpause") }
    func nextTrack() { runAppleScript("tell application \"Music\" to next track") }
    func previousTrack() { runAppleScript("tell application \"Music\" to previous track") }

    // MARK: - Distributed notifications

    private func subscribeToDistributedNotifications() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(musicPlayerStateChanged(_:)),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
        debugLog("[AppleMusic] subscribed to distributed notifications")
    }

    @objc private func musicPlayerStateChanged(_ note: NSNotification) {
        guard let info = note.userInfo else { return }

        let state = info["Player State"] as? String ?? ""
        let isPlaying = (state == "Playing")

        if !isPlaying {
            onPlaybackStateChanged?(false)
            if state == "Stopped" { onTrackChanged?(nil) }
            stopPollTimer()   // no need to poll while paused/stopped
            return
        }

        let title    = info["Name"]   as? String ?? ""
        let artist   = info["Artist"] as? String ?? ""
        let album    = info["Album"]  as? String ?? ""
        let duration = (info["Total Time"]   as? Double ?? 0) / 1000.0
        let elapsed  = (info["Elapsed Time"] as? Double ?? 0) / 1000.0
        let trackID  = "\(title)-\(artist)"

        if trackID != lastTrackID {
            lastTrackID = trackID
            let track = Track(title: title, artist: artist, album: album, duration: duration)
            lastFullTrack = track
            onTrackChanged?(track)
            fetchArtwork(for: title, artist: artist)
        }
        onProgressChanged?(elapsed)
        onPlaybackStateChanged?(true)
        startPollTimer()   // ensure timer running while playing
    }

    // MARK: - AppleScript polling (progress + initial state)

    private func fetchCurrentTrack() {
        let src = """
        tell application "Music"
            if player state is playing then
                set t to current track
                return (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & ((duration of t) as string) & "|" & ((player position) as string)
            else
                return ""
            end if
        end tell
        """
        guard let script = NSAppleScript(source: src) else { return }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        let raw = result.stringValue ?? ""
        debugLog("[AppleMusic] AppleScript result: '\(raw)'")

        guard !raw.isEmpty else {
            onPlaybackStateChanged?(false)
            return
        }

        let parts = raw.components(separatedBy: "|")
        guard parts.count >= 4 else { return }

        let title    = parts[0]
        let artist   = parts[1]
        let album    = parts[2]
        let duration = Double(parts[3]) ?? 0
        let elapsed  = parts.count > 4 ? Double(parts[4]) ?? 0 : 0
        let trackID  = "\(title)-\(artist)"

        if trackID != lastTrackID {
            // New track: emit and fetch artwork
            lastTrackID = trackID
            let track = Track(title: title, artist: artist, album: album, duration: duration)
            lastFullTrack = track
            onTrackChanged?(track)
            fetchArtwork(for: title, artist: artist)
        }
        // Same track: only update progress (don't overwrite track with no artwork)
        onProgressChanged?(elapsed)
        onPlaybackStateChanged?(true)
        startPollTimer()   // ensure timer running when we confirm playing state
    }

    // MARK: - Artwork via iTunes Search API

    private func fetchArtwork(for title: String, artist: String) {
        let trackID = "\(title)-\(artist)"
        let query = "\(artist) \(title)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&limit=5") else { return }

        debugLog("[AppleMusic] fetching artwork for: \(query)")

        URLSession.shared.dataTask(with: searchURL) { [weak self] data, _, error in
            guard let self else { return }
            if let error { debugLog("[AppleMusic] iTunes search error: \(error)"); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]],
                  let first = results.first,
                  let artStr = first["artworkUrl100"] as? String else {
                debugLog("[AppleMusic] no artwork results for: \(query)")
                return
            }
            let hiRes = artStr.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            guard let artURL = URL(string: hiRes) else { return }

            URLSession.shared.dataTask(with: artURL) { [weak self] imgData, _, _ in
                guard let self,
                      let imgData,
                      let image = NSImage(data: imgData) else { return }
                debugLog("[AppleMusic] artwork loaded for: \(trackID)")

                Task { @MainActor [weak self] in
                    guard let self,
                          self.lastTrackID == trackID,          // still same track?
                          let base = self.lastFullTrack else { return }
                    // Merge artwork into the last known full track (preserves album/duration)
                    let artTrack = Track(
                        title: base.title, artist: base.artist,
                        album: base.album, duration: base.duration, artwork: image
                    )
                    self.lastFullTrack = artTrack
                    self.onTrackChanged?(artTrack)
                }
            }.resume()
        }.resume()
    }

    @discardableResult
    private func runAppleScript(_ src: String) -> String {
        guard let script = NSAppleScript(source: src) else { return "" }
        var err: NSDictionary?
        return script.executeAndReturnError(&err).stringValue ?? ""
    }

    private func startPollTimer() {
        guard pollTimer == nil else { return }   // already running
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchCurrentTrack() }
        }
    }

    private func stopPollTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
