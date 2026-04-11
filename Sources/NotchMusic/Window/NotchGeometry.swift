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
            for s in NSScreen.screens {
                if let topLeft  = s.auxiliaryTopLeftArea,
                   let topRight = s.auxiliaryTopRightArea,
                   topRight.minX > topLeft.maxX          // there IS a gap
                {
                    let notchX      = topLeft.maxX
                    let notchWidth  = topRight.minX - topLeft.maxX
                    let notchHeight = s.safeAreaInsets.top
                    let notchY      = s.frame.maxY - notchHeight

                    notchFrame = CGRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
                    hasNotch   = true
                    screen     = s
                    debugLog("[NotchGeometry] found notch via auxiliaryAreas on: \(s.localizedName)")
                    debugLog("[NotchGeometry] notchFrame: \(notchFrame)")
                    return
                }
            }

            // Priority 2: screen with non-zero top safe area — centre a pill.
            for s in NSScreen.screens {
                if s.safeAreaInsets.top > 0 {
                    let h      = s.safeAreaInsets.top
                    let cx     = s.frame.midX
                    let y      = s.frame.maxY - h
                    notchFrame = CGRect(x: cx - 125, y: y, width: 250, height: h)
                    hasNotch   = true
                    screen     = s
                    debugLog("[NotchGeometry] found notch via safeAreaInsets on: \(s.localizedName)")
                    debugLog("[NotchGeometry] notchFrame: \(notchFrame)")
                    return
                }
            }
        }

        // Priority 3: no notch detected — centre pill on main screen.
        let s = NSScreen.main ?? NSScreen.screens[0]
        let cx = s.frame.midX
        let y  = s.frame.maxY - 38
        notchFrame = CGRect(x: cx - 125, y: y, width: 250, height: 34)
        hasNotch   = false
        screen     = s
        debugLog("[NotchGeometry] no notch, fallback on: \(s.localizedName) frame:\(s.frame)")
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
