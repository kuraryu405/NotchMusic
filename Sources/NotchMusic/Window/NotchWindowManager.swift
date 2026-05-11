import AppKit
import Combine
import SwiftUI

/// Manages two overlay windows:
///
///   pillWindow  — permanent, never moves, covers the notch strip (pills)
///   cardWindow  — appears below when expanded; content animates inside a fixed window
@MainActor
final class NotchWindowManager {
    private static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient, .ignoresCycle
    ]

    private var pillWindow: NSWindow?
    private var cardWindow: NSWindow?
    private var geometry: NotchGeometry
    private let viewModel: MusicPlayerViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MusicPlayerViewModel) {
        self.viewModel = viewModel
        self.geometry  = NotchGeometry()
        debugLog("[NotchWindow] notchFrame: \(geometry.notchFrame)")
        observeWindowRecoveryEvents()
    }

    func show() {
        if pillWindow == nil { pillWindow = makePillWindow() }
        if cardWindow == nil { cardWindow = makeCardWindow() }
        refreshWindowVisibility(reason: "show")
    }

    // MARK: - Frame helpers

    private func x(for geo: NotchGeometry) -> CGFloat {
        geo.notchFrame.midX - NotchGeometry.expandedWidth / 2
    }

    private func pillFrame(for geo: NotchGeometry) -> NSRect {
        NSRect(x: x(for: geo),
               y: geo.notchFrame.minY,
               width: NotchGeometry.expandedWidth,
               height: geo.notchFrame.height)
    }

    private func cardExpandedFrame(for geo: NotchGeometry) -> NSRect {
        NSRect(x: x(for: geo),
               y: geo.notchFrame.minY - NotchGeometry.expandedHeight,
               width: NotchGeometry.expandedWidth,
               height: NotchGeometry.expandedHeight)
    }

    // MARK: - Window builders

    private func makeWindow(frame: NSRect) -> NSWindow {
        let win = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque             = false
        win.backgroundColor      = .clear
        win.hasShadow            = false
        win.level                = .screenSaver
        win.collectionBehavior   = Self.overlayCollectionBehavior
        win.canHide              = false
        win.isMovable            = false
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents   = false
        win.isFloatingPanel      = true
        win.hidesOnDeactivate    = false
        return win
    }

    private func makePillWindow() -> NSWindow {
        let win = makeWindow(frame: pillFrame(for: geometry))
        win.contentView = NSHostingView(rootView:
            PillView(viewModel: viewModel, geometry: geometry)
        )
        return win
    }

    private func makeCardWindow() -> NSWindow {
        let win = makeWindow(frame: cardExpandedFrame(for: geometry))
        win.alphaValue = 0
        win.ignoresMouseEvents = true
        win.orderOut(nil)

        let hostView = NSHostingView(rootView: CardView(viewModel: viewModel))
        win.contentView = hostView
        configureCardHostView(hostView)
        bindCardExpansion(for: win)
        bindCardTrackCollapse(for: win)
        return win
    }

    private func configureCardHostView(_ hostView: NSHostingView<CardView>) {
        // Round the physical bottom corners of the card at the layer level
        // (SwiftUI clipShape alone isn't reliable in NSHostingView)
        hostView.wantsLayer = true
        hostView.layer?.cornerRadius  = 20
        hostView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        hostView.layer?.masksToBounds = true
    }

    private func bindCardExpansion(for win: NSWindow) {
        viewModel.$isExpanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak win] expanded in
                guard let self, let win else { return }
                self.updateCardWindow(win, expanded: expanded)
            }
            .store(in: &cancellables)
    }

    private func bindCardTrackCollapse(for win: NSWindow) {
        viewModel.$currentTrack
            .map { $0 == nil }
            .removeDuplicates()
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self, weak win] _ in
                guard let self, let win else { return }
                win.setFrame(self.cardExpandedFrame(for: self.geometry), display: false, animate: false)
                win.alphaValue = 0
                win.ignoresMouseEvents = true
                win.orderOut(nil)
                self.viewModel.pillCornersFlat = false
            }
            .store(in: &cancellables)
    }

    private func observeWindowRecoveryEvents() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowVisibility(reason: "screenParametersChanged")
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowVisibility(reason: "activeSpaceDidChange")
                self?.retryRefreshAfterSpaceTransition()
            }
        }
        workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshWindowVisibility(reason: "didWake")
            }
        }
    }

    private func bringOverlayWindowToFront(_ win: NSWindow) {
        win.collectionBehavior = Self.overlayCollectionBehavior
        win.canHide = false
        win.orderFrontRegardless()
    }

    private func refreshWindowVisibility(reason: String) {
        geometry = NotchGeometry()
        debugLog(
            "[NotchWindow] refresh: \(reason), frame: \(geometry.notchFrame), "
                + "expanded: \(viewModel.isExpanded), hasTrack: \(viewModel.currentTrack != nil)"
        )

        if let pillWindow {
            pillWindow.setFrame(pillFrame(for: geometry), display: true, animate: false)
            pillWindow.contentView = NSHostingView(rootView:
                PillView(viewModel: viewModel, geometry: geometry)
            )
            bringOverlayWindowToFront(pillWindow)
        }

        guard let cardWindow else { return }
        cardWindow.setFrame(cardExpandedFrame(for: geometry), display: viewModel.isExpanded, animate: false)
        if viewModel.isExpanded {
            cardWindow.ignoresMouseEvents = false
            cardWindow.alphaValue = 1
            bringOverlayWindowToFront(cardWindow)
        } else {
            cardWindow.ignoresMouseEvents = true
            cardWindow.alphaValue = 0
            cardWindow.orderOut(nil)
        }
    }

    private func updateCardWindow(_ win: NSWindow, expanded: Bool) {
        let geo = geometry

        if expanded {
            win.setFrame(cardExpandedFrame(for: geo), display: false, animate: false)
            bringOverlayWindowToFront(win)
            win.ignoresMouseEvents = false
            viewModel.pillCornersFlat = true
            animateCardWindow(win, alpha: 1)
            return
        }

        win.ignoresMouseEvents = true
        animateCardWindow(win, alpha: 0) { [weak self, weak win] in
            Task { @MainActor [weak self, weak win] in
                self?.viewModel.pillCornersFlat = false
                win?.ignoresMouseEvents = true
                win?.orderOut(nil)
            }
        }
    }

    private func animateCardWindow(
        _ win: NSWindow,
        alpha: CGFloat,
        completion: (@Sendable () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            win.animator().alphaValue = alpha
        }, completionHandler: completion)
    }
}

private extension NotchWindowManager {
    static var spaceRetryDelay: UInt64 { 120_000_000 }
    static var spaceRetryCount: Int { 4 }

    var visibleOverlayWindowsAreOnActiveSpace: Bool {
        guard let pillWindow, pillWindow.isOnActiveSpace else { return false }
        guard viewModel.isExpanded else { return true }
        return cardWindow?.isOnActiveSpace == true
    }

    func retryRefreshAfterSpaceTransition() {
        Task { @MainActor [weak self] in
            for attempt in 1...Self.spaceRetryCount {
                try? await Task.sleep(nanoseconds: Self.spaceRetryDelay)
                guard let self else { return }
                self.refreshWindowVisibility(reason: "activeSpaceDidChangeRetry\(attempt)")
                if self.visibleOverlayWindowsAreOnActiveSpace { return }
            }
        }
    }
}
