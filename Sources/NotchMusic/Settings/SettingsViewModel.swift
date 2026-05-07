import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var canConfigureLaunchAtLogin: Bool
    @Published private(set) var launchAtLoginHint: String
    @Published private(set) var appleMusicPermissionStatus: MusicAppPermissionStatus = .unknown
    @Published private(set) var spotifyPermissionStatus: MusicAppPermissionStatus = .unknown
    @Published var alertMessage: String?
    @Published var isShowingPermissionHelp = false

    private let launchAgentManager: LaunchAgentManaging
    private let permissionChecker: MusicAppPermissionChecking

    init(
        launchAgentManager: LaunchAgentManaging = LaunchAgentManager(),
        permissionChecker: MusicAppPermissionChecking = MusicAppPermissionChecker()
    ) {
        self.launchAgentManager = launchAgentManager
        self.permissionChecker = permissionChecker
        self.launchAtLoginEnabled = launchAgentManager.isEnabled
        self.canConfigureLaunchAtLogin = launchAgentManager.canConfigure
        self.launchAtLoginHint = launchAgentManager.configurationHint
    }

    func refreshState() {
        launchAtLoginEnabled = launchAgentManager.isEnabled
        canConfigureLaunchAtLogin = launchAgentManager.canConfigure
        launchAtLoginHint = launchAgentManager.configurationHint
    }

    func refreshPermissionStatus() {
        appleMusicPermissionStatus = permissionChecker.refreshStatus(for: .appleMusic)
        spotifyPermissionStatus = permissionChecker.refreshStatus(for: .spotify)
    }

    func requestAppleMusicAccess() {
        appleMusicPermissionStatus = permissionChecker.requestAccess(for: .appleMusic)
    }

    func requestSpotifyAccess() {
        spotifyPermissionStatus = permissionChecker.requestAccess(for: .spotify)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAgentManager.setEnabled(enabled)
            refreshState()
        } catch {
            refreshState()
            alertMessage = error.localizedDescription
        }
    }

    func openAppleMusic() {
        openMusicApp(.appleMusic)
    }

    func openSpotify() {
        openMusicApp(.spotify)
    }

    private func openMusicApp(_ app: ScriptableMusicApp) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            alertMessage = "\(app.displayName) が見つかりませんでした。"
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openSystemSettings() {
        let url = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        NSWorkspace.shared.open(url)
    }

    func openLogFile() {
        let logURL = URL(fileURLWithPath: "/tmp/notchmusic.log")
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            alertMessage = "まだログファイルがありません。再生や設定確認のあとにもう一度試してください。"
            return
        }
        NSWorkspace.shared.open(logURL)
    }
}

protocol LaunchAgentManaging {
    var canConfigure: Bool { get }
    var configurationHint: String { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

struct LaunchAgentManager: LaunchAgentManaging {
    private static let label = "dev.notchmusic.app"

    private let fileManager: FileManager
    private let bundleURL: URL

    init(fileManager: FileManager = .default, bundleURL: URL = Bundle.main.bundleURL) {
        self.fileManager = fileManager
        self.bundleURL = bundleURL.standardizedFileURL
    }

    var canConfigure: Bool {
        bundleURL.pathExtension == "app"
    }

    var configurationHint: String {
        guard canConfigure else {
            return "自動起動は `NotchMusic.app` として起動しているときに設定できます。"
        }
        return "現在起動中のアプリをログイン時に自動で開きます。"
    }

    var isEnabled: Bool {
        guard let plist = existingLaunchAgent else { return false }
        return plist.appPath == bundleURL.path
    }

    func setEnabled(_ enabled: Bool) throws {
        guard canConfigure else {
            throw LaunchAgentError.requiresAppBundle
        }

        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private func enable() throws {
        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try PropertyListSerialization.data(
            fromPropertyList: launchAgentContents(appPath: bundleURL.path),
            format: .xml,
            options: 0
        )
        _ = try? runLaunchctl("bootout", "gui/\(getuid())", plistURL.path)
        try data.write(to: plistURL, options: .atomic)
        _ = try runLaunchctl("bootstrap", "gui/\(getuid())", plistURL.path)
    }

    private func disable() throws {
        if fileManager.fileExists(atPath: plistURL.path) {
            _ = try? runLaunchctl("bootout", "gui/\(getuid())", plistURL.path)
            try fileManager.removeItem(at: plistURL)
        }
    }

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist", isDirectory: false)
    }

    private var existingLaunchAgent: LaunchAgentDefinition? {
        guard let data = try? Data(contentsOf: plistURL),
              let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = raw["ProgramArguments"] as? [String],
              args.count >= 2 else {
            return nil
        }
        return LaunchAgentDefinition(appPath: args[1])
    }

    private func launchAgentContents(appPath: String) -> [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
    }

    @discardableResult
    private func runLaunchctl(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw LaunchAgentError.launchctlFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}

private struct LaunchAgentDefinition {
    let appPath: String
}

enum LaunchAgentError: LocalizedError {
    case requiresAppBundle
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .requiresAppBundle:
            return "自動起動は `NotchMusic.app` から起動しているときだけ有効化できます。"
        case .launchctlFailed(let output):
            if output.isEmpty {
                return "自動起動の設定に失敗しました。"
            }
            return "自動起動の設定に失敗しました: \(output)"
        }
    }
}

enum ScriptableMusicApp {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic:
            return "Apple Music"
        case .spotify:
            return "Spotify"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .appleMusic:
            return "com.apple.Music"
        case .spotify:
            return "com.spotify.client"
        }
    }

    var appleScriptName: String {
        switch self {
        case .appleMusic:
            return "Music"
        case .spotify:
            return "Spotify"
        }
    }
}

protocol MusicAppPermissionChecking {
    func refreshStatus(for app: ScriptableMusicApp) -> MusicAppPermissionStatus
    func requestAccess(for app: ScriptableMusicApp) -> MusicAppPermissionStatus
}

struct MusicAppPermissionChecker: MusicAppPermissionChecking {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func refreshStatus(for app: ScriptableMusicApp) -> MusicAppPermissionStatus {
        guard workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier) != nil else {
            return .notInstalled
        }

        let appIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
        return appIsRunning ? .unknown : .appClosed
    }

    func requestAccess(for app: ScriptableMusicApp) -> MusicAppPermissionStatus {
        checkAutomationStatus(for: app, launchIfNeeded: true)
    }

    private func checkAutomationStatus(for app: ScriptableMusicApp, launchIfNeeded: Bool) -> MusicAppPermissionStatus {
        guard let url = workspace.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            return .notInstalled
        }

        if launchIfNeeded {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }

        let appIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
        guard appIsRunning || launchIfNeeded else {
            return .appClosed
        }

        let source = """
        tell application "\(app.appleScriptName)"
            get player state
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return .error("\(app.displayName) の権限確認スクリプトを作成できませんでした。")
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)

        guard let error else {
            return .granted
        }

        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = (error[NSAppleScript.errorBriefMessage] as? String)
            ?? (error[NSAppleScript.errorMessage] as? String)
            ?? "\(app.displayName) との通信を確認できませんでした。"

        if code == -1743 {
            return .denied
        }

        return .error(message)
    }
}

enum MusicAppPermissionStatus: Equatable {
    case unknown
    case notInstalled
    case appClosed
    case granted
    case denied
    case error(String)

    func title(for app: ScriptableMusicApp) -> String {
        switch self {
        case .unknown:
            return "未確認"
        case .notInstalled:
            return "未検出"
        case .appClosed:
            return "\(app.displayName)待ち"
        case .granted:
            return "許可済み"
        case .denied:
            return "未許可"
        case .error:
            return "確認失敗"
        }
    }

    func detail(for app: ScriptableMusicApp) -> String {
        switch self {
        case .unknown:
            return "\(app.displayName) を開いた状態でアクセス確認を押すと、必要に応じて macOS の許可ダイアログが表示されます。"
        case .notInstalled:
            return "\(app.displayName) が見つかりませんでした。インストール済みの場合は一度起動してから再確認してください。"
        case .appClosed:
            return "\(app.displayName) が閉じています。開いてからアクセス確認を押すと、権限状態を確認できます。"
        case .granted:
            return "NotchMusic は \(app.displayName) の再生情報を読み取れます。表示が戻らない場合は再接続を試してください。"
        case .denied:
            return "macOS 側で NotchMusic の \(app.displayName) 操作が許可されていません。System Settings の Privacy & Security > Automation で許可してください。"
        case .error(let message):
            return message
        }
    }

    var tint: NSColor {
        switch self {
        case .granted:
            return .systemGreen
        case .appClosed, .notInstalled, .unknown:
            return .systemOrange
        case .denied, .error:
            return .systemRed
        }
    }
}
