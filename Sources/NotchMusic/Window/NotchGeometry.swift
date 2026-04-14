import AppKit

/// Computes the position and size of the notch on the built-in display.
///
/// Strategy (in priority order):
///  1. Find the screen with `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (most precise).
///  2. Fall back to any screen where `safeAreaInsets.top > 0` — centre a fixed-width pill.
///  3. Last resort: place a pill at the top-centre of `NSScreen.main`.
struct NotchGeometry {
    let notchFrame: CGRect
    let hasNotch: Bool
    let screen: NSScreen

    static let compactHeight: CGFloat = 34
    static let compactWidth: CGFloat  = 120
    static let expandedWidth: CGFloat  = 360
    static let expandedHeight: CGFloat = 120

    init() {
        if #available(macOS 12.0, *) {
            // Priority 1: screen that exposes auxiliary areas (the actual notch).
            for candidateScreen in NSScreen.screens {
                if let topLeft  = candidateScreen.auxiliaryTopLeftArea,
                   let topRight = candidateScreen.auxiliaryTopRightArea,
                   topRight.minX > topLeft.maxX { // there IS a gap
                    let notchX      = topLeft.maxX
                    let notchWidth  = topRight.minX - topLeft.maxX
                    let notchHeight = candidateScreen.safeAreaInsets.top
                    let notchY      = candidateScreen.frame.maxY - notchHeight

                    notchFrame = CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
                    hasNotch   = true
                    screen     = candidateScreen
                    debugLog("[NotchGeometry] found notch via auxiliaryAreas on: \(candidateScreen.localizedName)")
                    debugLog("[NotchGeometry] notchFrame: \(notchFrame)")
                    return
                }
            }

            // Priority 2: screen with non-zero top safe area — centre a pill.
            for candidateScreen in NSScreen.screens where candidateScreen.safeAreaInsets.top > 0 {
                let safeAreaTop = candidateScreen.safeAreaInsets.top
                let centerX = candidateScreen.frame.midX
                let topY = candidateScreen.frame.maxY - safeAreaTop
                notchFrame = CGRect(x: centerX - 125, y: topY, width: 250, height: safeAreaTop)
                hasNotch   = true
                screen     = candidateScreen
                debugLog("[NotchGeometry] found notch via safeAreaInsets on: \(candidateScreen.localizedName)")
                debugLog("[NotchGeometry] notchFrame: \(notchFrame)")
                return
            }
        }

        // Priority 3: no notch detected — centre pill on main screen.
        let mainScreen = NSScreen.main ?? NSScreen.screens[0]
        let centerX = mainScreen.frame.midX
        let topY  = mainScreen.frame.maxY - 38
        notchFrame = CGRect(x: centerX - 125, y: topY, width: 250, height: 34)
        hasNotch   = false
        screen     = mainScreen
        debugLog("[NotchGeometry] no notch, fallback on: \(mainScreen.localizedName) frame:\(mainScreen.frame)")
    }

    var compactWindowFrame: CGRect {
        CGRect(
            x: notchFrame.midX - NotchGeometry.compactWidth / 2,
            y: notchFrame.minY,
            width: NotchGeometry.compactWidth,
            height: NotchGeometry.compactHeight
        )
    }

    var expandedWindowFrame: CGRect {
        CGRect(
            x: notchFrame.midX - NotchGeometry.expandedWidth / 2,
            y: notchFrame.minY - (NotchGeometry.expandedHeight - notchFrame.height),
            width: NotchGeometry.expandedWidth,
            height: NotchGeometry.expandedHeight
        )
    }
}
