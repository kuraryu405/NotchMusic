import AppKit
import Foundation

struct Track: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var artwork: NSImage?

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.title    == rhs.title  &&
        lhs.artist   == rhs.artist &&
        lhs.album    == rhs.album  &&
        lhs.artwork  === rhs.artwork   // reference equality — new NSImage triggers redraw
    }
}

extension Track {
    @MainActor
    static let placeholder = Track(
        title: "Not Playing",
        artist: "—",
        album: "",
        duration: 0,
        artwork: nil
    )
}
