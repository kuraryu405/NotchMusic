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
    }

    func show() {
        if pillWindow == nil { pillWindow = makePillWindow() }
        if cardWindow == nil { cardWindow = makeCardWindow() }
        pillWindow?.orderFrontRegardless()
        cardWindow?.orderFrontRegardless()
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
        win.collectionBehavior   = [.canJoinAllSpaces, .stationary, .ignoresCycle]
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

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self, weak win] _ in
            Task { @MainActor [weak self, weak win] in
                guard let self, let win else { return }
                self.geometry = NotchGeometry()
                win.setFrame(self.pillFrame(for: self.geometry), display: true, animate: false)
            }
        }
        return win
    }

    private func makeCardWindow() -> NSWindow {
        let win = makeWindow(frame: cardCollapsedFrame(for: geometry))
        win.alphaValue = 0

        let hostView = NSHostingView(rootView: CardView(viewModel: viewModel))
        win.contentView = hostView

        // Round the physical bottom corners of the card at the layer level
        // (SwiftUI clipShape alone isn't reliable in NSHostingView)
        hostView.wantsLayer = true
        hostView.layer?.cornerRadius  = 20
        hostView.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        hostView.layer?.masksToBounds = true

        // Animate card when expansion changes
        viewModel.$isExpanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self, weak win] expanded in
                guard let self, let win else { return }
                let geo = self.geometry

                if expanded {
                    // Flatten pill corners immediately, then open card
                    self.viewModel.pillCornersFlat = true
                    let target = self.cardExpandedFrame(for: geo)
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration       = 0.4
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                        win.animator().setFrame(target, display: true)
                        win.animator().alphaValue = 1
                    }
                } else {
                    // Close card first, THEN round pill corners in completion
                    let target = self.cardCollapsedFrame(for: geo)
                    NSAnimationContext.runAnimationGroup({ ctx in
                        ctx.duration       = 0.4
                        ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
                        win.animator().setFrame(target, display: true)
                        win.animator().alphaValue = 0
                    }, completionHandler: {
                        Task { @MainActor [weak self] in
                            self?.viewModel.pillCornersFlat = false
                        }
                    })
                }
            }
            .store(in: &cancellables)

        // Instant collapse on track stop
        viewModel.$currentTrack
            .map { $0 == nil }
            .removeDuplicates()
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self, weak win] _ in
                guard let self, let win else { return }
                win.setFrame(self.cardCollapsedFrame(for: self.geometry), display: false, animate: false)
                win.alphaValue = 0
                self.viewModel.pillCornersFlat = false
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self, weak win] _ in
            Task { @MainActor [weak self, weak win] in
                guard let self, let win else { return }
                self.geometry = NotchGeometry()
                let f = self.viewModel.isExpanded
                    ? self.cardExpandedFrame(for: self.geometry)
                    : self.cardCollapsedFrame(for: self.geometry)
                win.setFrame(f, display: true, animate: false)
            }
        }
        return win
    }
}
