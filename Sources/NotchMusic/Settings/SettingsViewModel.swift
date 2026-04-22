import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var canConfigureLaunchAtLogin: Bool
    @Published private(set) var launchAtLoginHint: String
    @Published private(set) var permissionStatus: AppleMusicPermissionStatus = .unknown
    @Published var alertMessage: String?
    @Published var isShowingPermissionHelp = false

    private let launchAgentManager: LaunchAgentManaging
    private let permissionChecker: AppleMusicPermissionChecking

    init(
        launchAgentManager: LaunchAgentManaging = LaunchAgentManager(),
        permissionChecker: AppleMusicPermissionChecking = AppleMusicPermissionChecker()
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
        permissionStatus = permissionChecker.checkStatus(launchIfNeeded: false)
    }

    func requestAppleMusicAccess() {
        permissionStatus = permissionChecker.checkStatus(launchIfNeeded: true)
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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            alertMessage = "Apple Music が見つかりませんでした。"
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

protocol AppleMusicPermissionChecking {
    func checkStatus(launchIfNeeded: Bool) -> AppleMusicPermissionStatus
}

struct AppleMusicPermissionChecker: AppleMusicPermissionChecking {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func checkStatus(launchIfNeeded: Bool) -> AppleMusicPermissionStatus {
        if launchIfNeeded, let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.Music") {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }

        let musicIsRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
        guard musicIsRunning || launchIfNeeded else {
            return .musicClosed
        }

        let source = """
        tell application "Music"
            get player state
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            return .error("Apple Music の権限確認スクリプトを作成できませんでした。")
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)

        guard let error else {
            return .granted
        }

        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = (error[NSAppleScript.errorBriefMessage] as? String)
            ?? (error[NSAppleScript.errorMessage] as? String)
            ?? "Apple Music との通信を確認できませんでした。"

        if code == -1743 {
            return .denied
        }

        return .error(message)
    }
}

enum AppleMusicPermissionStatus: Equatable {
    case unknown
    case musicClosed
    case granted
    case denied
    case error(String)

    var title: String {
        switch self {
        case .unknown:
            return "未確認"
        case .musicClosed:
            return "Apple Music待ち"
        case .granted:
            return "許可済み"
        case .denied:
            return "未許可"
        case .error:
            return "確認失敗"
        }
    }

    var detail: String {
        switch self {
        case .unknown:
            return "Apple Music を開いた状態でアクセス確認を押すと、必要に応じて macOS の許可ダイアログが表示されます。"
        case .musicClosed:
            return "Apple Music が閉じています。開いてからアクセス確認を押すと、権限状態を確認できます。"
        case .granted:
            return "NotchMusic は Apple Music の再生情報を読み取れます。表示が戻らない場合は再接続を試してください。"
        case .denied:
            return "macOS 側で NotchMusic の Apple Music 操作が許可されていません。System Settings の Privacy & Security > Automation で許可してください。"
        case .error(let message):
            return message
        }
    }

    var tint: NSColor {
        switch self {
        case .granted:
            return .systemGreen
        case .musicClosed, .unknown:
            return .systemOrange
        case .denied, .error:
            return .systemRed
        }
    }
}
