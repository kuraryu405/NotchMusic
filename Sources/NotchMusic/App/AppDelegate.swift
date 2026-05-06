import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let hasShownInitialSettings = "hasShownInitialSettings"
    }

    private var windowManager: NotchWindowManager?
    private var viewModel: MusicPlayerViewModel?
    private var statusItem: NSStatusItem?
    private var settingsViewModel: SettingsViewModel?
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory app (no Dock icon, no main window).
        NSApp.setActivationPolicy(.accessory)

        let service = CompositeMusicService()
        let playerViewModel = MusicPlayerViewModel(service: service)
        viewModel = playerViewModel
        settingsViewModel = SettingsViewModel()

        let manager = NotchWindowManager(viewModel: playerViewModel)
        windowManager = manager
        manager.show()

        playerViewModel.startObserving()

        setupStatusBarMenu()
        showInitialSettingsIfNeeded()
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

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit NotchMusic",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
    }

    @objc
    private func openSettings() {
        guard let viewModel, let settingsViewModel else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsViewModel: settingsViewModel,
                playerViewModel: viewModel
            )
        }
        settingsWindowController?.present()
    }

    private func showInitialSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.hasShownInitialSettings) == false else { return }
        defaults.set(true, forKey: DefaultsKey.hasShownInitialSettings)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.openSettings()
        }
    }
}
