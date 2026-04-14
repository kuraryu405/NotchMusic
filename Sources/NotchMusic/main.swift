import AppKit

/// Lightweight logger — writes to /tmp/notchmusic.log in debug builds only.
func debugLog(_ msg: String) {
    #if DEBUG
    let line = msg + "\n"
    if let data = line.data(using: .utf8) {
        if let fileHandle = FileHandle(forWritingAtPath: "/tmp/notchmusic.log") {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            FileManager.default.createFile(atPath: "/tmp/notchmusic.log", contents: data)
        }
    }
    #endif
}

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
