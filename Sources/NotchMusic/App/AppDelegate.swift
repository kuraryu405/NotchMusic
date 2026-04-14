import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: NotchWindowManager?
    private var viewModel: MusicPlayerViewModel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory app (no Dock icon, no main window).
        NSApp.setActivationPolicy(.accessory)

        let service = AppleMusicService()
        let playerViewModel = MusicPlayerViewModel(service: service)
        viewModel = playerViewModel

        let manager = NotchWindowManager(viewModel: playerViewModel)
        windowManager = manager
        manager.show()

        playerViewModel.startObserving()

        setupStatusBarMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        false
    }

    // MARK: - Status bar (quit menu)

    @MainActor
    private func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "NotchMusic")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit NotchMusic",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
    }
}
