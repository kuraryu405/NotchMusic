import AppKit

/// Lightweight logger — writes to /tmp/notchmusic.log in debug builds,
/// or in release builds when NOTCHMUSIC_DEBUG=1 is set.
func debugLog(_ msg: String) {
    #if !DEBUG
    guard ProcessInfo.processInfo.environment["NOTCHMUSIC_DEBUG"] == "1" else { return }
    #endif

    let line = "\(Date()) \(msg)\n"
    if let data = line.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: "/tmp/notchmusic.log") {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            FileManager.default.createFile(atPath: "/tmp/notchmusic.log", contents: data)
        }
    }
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
