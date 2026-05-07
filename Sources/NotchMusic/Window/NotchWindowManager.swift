import AppKit
import Combine
import SwiftUI

/// Manages two overlay windows:
///
///   pillWindow  — permanent, never moves, covers the notch strip (pills)
///   cardWindow  — appears below when expanded, animates height only
@MainActor
final class NotchWindowManager {
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

    private func cardCollapsedFrame(for geo: NotchGeometry) -> NSRect {
        NSRect(x: x(for: geo),
               y: geo.notchFrame.minY - 1,
               width: NotchGeometry.expandedWidth,
               height: 1)
    }

    // MARK: - Window builders

    private func makeWindow(frame: NSRect) -> NSWindow {
        let win = NSWindow(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        win.isOpaque             = false
        win.backgroundColor      = .clear
        win.hasShadow            = false
        win.level                = .screenSaver
        win.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.isMovable            = false
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents   = false
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
        let win = makeWindow(frame: cardCollapsedFrame(for: geometry))
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
                win.setFrame(self.cardCollapsedFrame(for: self.geometry), display: false, animate: false)
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
            pillWindow.orderFrontRegardless()
        }

        guard let cardWindow else { return }
        let frame = viewModel.isExpanded
            ? cardExpandedFrame(for: geometry)
            : cardCollapsedFrame(for: geometry)
        cardWindow.setFrame(frame, display: viewModel.isExpanded, animate: false)
        if viewModel.isExpanded {
            cardWindow.ignoresMouseEvents = false
            cardWindow.alphaValue = 1
            cardWindow.orderFrontRegardless()
        } else {
            cardWindow.ignoresMouseEvents = true
            cardWindow.alphaValue = 0
            cardWindow.orderOut(nil)
        }
    }

    private func updateCardWindow(_ win: NSWindow, expanded: Bool) {
        let geo = geometry

        if expanded {
            win.orderFrontRegardless()
            win.setFrame(cardCollapsedFrame(for: geo), display: false, animate: false)
            win.alphaValue = 0
            win.ignoresMouseEvents = false
            viewModel.pillCornersFlat = true
            animateCardWindow(win, targetFrame: cardExpandedFrame(for: geo), alpha: 1)
            return
        }

        win.ignoresMouseEvents = true
        animateCardWindow(
            win,
            targetFrame: cardCollapsedFrame(for: geo),
            alpha: 0
        ) { [weak self, weak win] in
            Task { @MainActor [weak self, weak win] in
                self?.viewModel.pillCornersFlat = false
                win?.ignoresMouseEvents = true
                win?.orderOut(nil)
            }
        }
    }

    private func animateCardWindow(
        _ win: NSWindow,
        targetFrame: NSRect,
        alpha: CGFloat,
        completion: (@Sendable () -> Void)? = nil
    ) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration       = 0.4
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            win.animator().setFrame(targetFrame, display: true)
            win.animator().alphaValue = alpha
        }, completionHandler: completion)
    }
}
