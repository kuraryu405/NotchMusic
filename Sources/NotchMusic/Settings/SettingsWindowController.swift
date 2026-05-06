import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settingsViewModel: SettingsViewModel

    init(settingsViewModel: SettingsViewModel, playerViewModel: MusicPlayerViewModel) {
        self.settingsViewModel = settingsViewModel

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NotchMusic Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setFrameAutosaveName("NotchMusicSettings")
        window.contentView = NSHostingView(
            rootView: SettingsView(
                settingsViewModel: settingsViewModel,
                playerViewModel: playerViewModel
            )
        )

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        settingsViewModel.refreshState()
        settingsViewModel.refreshPermissionStatus()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
