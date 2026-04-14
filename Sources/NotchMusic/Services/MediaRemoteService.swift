import AppKit
import Foundation

// MARK: - MediaRemote private framework bridge

private typealias MRMediaRemoteGetNowPlayingInfoFn =
    @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

private typealias MRMediaRemoteRegisterForNowPlayingNotificationsFn =
    @convention(c) (DispatchQueue) -> Void

private typealias MRMediaRemoteSendCommandFn =
    @convention(c) (UInt32, AnyObject?) -> Bool

private enum MRCommand: UInt32 {
    case play           = 0
    case pause          = 1
    case togglePlayPause = 2
    case nextTrack      = 4
    case previousTrack  = 5
}

// MediaRemote notification key
private let kMRNowPlayingPlaybackQueueChangedNotification =
    "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"
private let kMRNowPlayingApplicationChangedNotification =
    "kMRNowPlayingApplicationChangedNotification"

// Info dictionary keys
private let kMRMediaRemoteNowPlayingInfoTitle          = "kMRMediaRemoteNowPlayingInfoTitle"
private let kMRMediaRemoteNowPlayingInfoArtist         = "kMRMediaRemoteNowPlayingInfoArtist"
private let kMRMediaRemoteNowPlayingInfoAlbum          = "kMRMediaRemoteNowPlayingInfoAlbum"
private let kMRMediaRemoteNowPlayingInfoDuration       = "kMRMediaRemoteNowPlayingInfoDuration"
private let kMRMediaRemoteNowPlayingInfoElapsedTime    = "kMRMediaRemoteNowPlayingInfoElapsedTime"
private let kMRMediaRemoteNowPlayingInfoArtworkData    = "kMRMediaRemoteNowPlayingInfoArtworkData"

@MainActor
final class MediaRemoteService: MusicServiceProtocol {
    var onTrackChanged: ((Track?) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onProgressChanged: ((TimeInterval) -> Void)?

    private let bundle: CFBundle?
    private var getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFn?
    private var registerForNotifications: MRMediaRemoteRegisterForNowPlayingNotificationsFn?
    private var sendCommand: MRMediaRemoteSendCommandFn?
    private var progressTimer: Timer?

    init() {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL)
        loadSymbols()
    }

    // MARK: - Symbol loading

    private func loadSymbols() {
        guard let bundle else {
            debugLog("[MediaRemote] bundle is nil!")
            return
        }

        if let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString
        ) {
            getNowPlayingInfo = unsafeBitCast(ptr, to: MRMediaRemoteGetNowPlayingInfoFn.self)
            debugLog("[MediaRemote] getNowPlayingInfo loaded OK")
        } else {
            debugLog("[MediaRemote] getNowPlayingInfo NOT found!")
        }
        if let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString
        ) {
            registerForNotifications = unsafeBitCast(
                ptr, to: MRMediaRemoteRegisterForNowPlayingNotificationsFn.self
            )
        }
        if let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteSendCommand" as CFString
        ) {
            sendCommand = unsafeBitCast(ptr, to: MRMediaRemoteSendCommandFn.self)
        }
    }

    // MARK: - MusicServiceProtocol

    func startObserving() {
        registerForNotifications?(.main)
        subscribeToNotifications()
        fetchNowPlayingInfo()
        startProgressTimer()
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func togglePlayPause() {
        _ = sendCommand?(MRCommand.togglePlayPause.rawValue, nil)
    }

    func nextTrack() {
        _ = sendCommand?(MRCommand.nextTrack.rawValue, nil)
    }

    func previousTrack() {
        _ = sendCommand?(MRCommand.previousTrack.rawValue, nil)
    }

    // MARK: - Private

    private func subscribeToNotifications() {
        let center = NotificationCenter.default
        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"
        ]
        for name in names {
            center.addObserver(
                self,
                selector: #selector(nowPlayingDidChange),
                name: NSNotification.Name(name),
                object: nil
            )
        }

        // Also subscribe to distributed notifications (e.g. Spotify, Music.app)
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            self,
            selector: #selector(nowPlayingDidChange),
            name: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil
        )
        distributed.addObserver(
            self,
            selector: #selector(nowPlayingDidChange),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
    }

    @objc private func nowPlayingDidChange() {
        fetchNowPlayingInfo()
    }

    private func fetchNowPlayingInfo() {
        guard let fn = getNowPlayingInfo else {
            debugLog("[MediaRemote] fetchNowPlayingInfo: fn is nil!")
            return
        }
        debugLog("[MediaRemote] fetchNowPlayingInfo: calling fn")
        fn(.main) { [weak self] info in
            debugLog("[MediaRemote] callback fired, keys: \(info.keys.count)")
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleNowPlayingInfo(info) }
            }
        }
    }

    private func handleNowPlayingInfo(_ info: [String: Any]) {
        debugLog("[MediaRemote] handleNowPlayingInfo keys: \(info.keys.sorted())")
        let title  = info[kMRMediaRemoteNowPlayingInfoTitle]  as? String ?? ""
        let artist = info[kMRMediaRemoteNowPlayingInfoArtist] as? String ?? ""
        debugLog("[MediaRemote] title='\(title)' artist='\(artist)'")
        let album  = info[kMRMediaRemoteNowPlayingInfoAlbum]  as? String ?? ""
        let duration = info[kMRMediaRemoteNowPlayingInfoDuration] as? TimeInterval ?? 0

        var artwork: NSImage?
        if let data = info[kMRMediaRemoteNowPlayingInfoArtworkData] as? Data {
            artwork = NSImage(data: data)
        }

        let elapsed = info[kMRMediaRemoteNowPlayingInfoElapsedTime] as? TimeInterval ?? 0

        if title.isEmpty && artist.isEmpty {
            onTrackChanged?(nil)
            onPlaybackStateChanged?(false)
            return
        }

        let track = Track(title: title, artist: artist, album: album, duration: duration, artwork: artwork)
        debugLog("[MediaRemote] track: \(title) / \(artist) | onTrackChanged set: \(onTrackChanged != nil)")
        onTrackChanged?(track)
        onProgressChanged?(elapsed)
        onPlaybackStateChanged?(true)
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        // Timer fires on the main RunLoop, so MainActor.assumeIsolated is safe here.
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fetchNowPlayingInfo() }
        }
    }
}
