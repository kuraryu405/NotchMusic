@testable import NotchMusic
import XCTest

final class SettingsViewModelTests: XCTestCase {
    @MainActor
    func test_refreshPermissionStatusUsesPromptSafeRefresh() {
        let permissionChecker = MockMusicAppPermissionChecker()
        permissionChecker.appleMusicRefreshStatus = .appClosed
        permissionChecker.spotifyRefreshStatus = .unknown
        let sut = makeViewModel(permissionChecker: permissionChecker)

        sut.refreshPermissionStatus()

        XCTAssertEqual(sut.appleMusicPermissionStatus, .appClosed)
        XCTAssertEqual(sut.spotifyPermissionStatus, .unknown)
        XCTAssertEqual(permissionChecker.refreshedApps, [.appleMusic, .spotify])
        XCTAssertTrue(permissionChecker.requestedApps.isEmpty)
    }

    @MainActor
    func test_requestAccessUsesPromptCapableCheck() {
        let permissionChecker = MockMusicAppPermissionChecker()
        permissionChecker.appleMusicRequestStatus = .granted
        permissionChecker.spotifyRequestStatus = .denied
        let sut = makeViewModel(permissionChecker: permissionChecker)

        sut.requestAppleMusicAccess()
        sut.requestSpotifyAccess()

        XCTAssertEqual(sut.appleMusicPermissionStatus, .granted)
        XCTAssertEqual(sut.spotifyPermissionStatus, .denied)
        XCTAssertEqual(permissionChecker.requestedApps, [.appleMusic, .spotify])
        XCTAssertTrue(permissionChecker.refreshedApps.isEmpty)
    }

    @MainActor
    private func makeViewModel(
        permissionChecker: MusicAppPermissionChecking
    ) -> SettingsViewModel {
        SettingsViewModel(
            launchAgentManager: MockLaunchAgentManager(),
            permissionChecker: permissionChecker
        )
    }
}

private final class MockMusicAppPermissionChecker: MusicAppPermissionChecking {
    var appleMusicRefreshStatus: MusicAppPermissionStatus = .unknown
    var spotifyRefreshStatus: MusicAppPermissionStatus = .unknown
    var appleMusicRequestStatus: MusicAppPermissionStatus = .unknown
    var spotifyRequestStatus: MusicAppPermissionStatus = .unknown
    private(set) var refreshedApps: [ScriptableMusicApp] = []
    private(set) var requestedApps: [ScriptableMusicApp] = []

    func refreshStatus(for app: ScriptableMusicApp) -> MusicAppPermissionStatus {
        refreshedApps.append(app)
        switch app {
        case .appleMusic:
            return appleMusicRefreshStatus
        case .spotify:
            return spotifyRefreshStatus
        }
    }

    func requestAccess(for app: ScriptableMusicApp) -> MusicAppPermissionStatus {
        requestedApps.append(app)
        switch app {
        case .appleMusic:
            return appleMusicRequestStatus
        case .spotify:
            return spotifyRequestStatus
        }
    }
}

private final class MockLaunchAgentManager: LaunchAgentManaging {
    var canConfigure = true
    var configurationHint = "test"
    var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}
