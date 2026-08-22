import Foundation
import CoreGraphics

/// Software dimming via the display's gamma transfer function.
///
/// This is the fallback for when the monitor's backlight is unreachable: it
/// darkens the rendered image rather than the lamp, so it cannot go above 100%
/// and is less effective against eye strain than a real backlight change. The UI
/// must say which mode is in use so the distinction isn't hidden from the user.
public final class GammaDimmer {

    /// Never dim past this: below roughly a quarter the screen stops being usable,
    /// and a user who dimmed to zero by accident would have no way to see the
    /// slider to undo it.
    public static let minimumScale: Double = 0.25

    private let displayID: CGDirectDisplayID
    private var isDimmed = false

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    /// Maps a user-facing percentage onto a gamma scale that never bottoms out.
    public static func scale(forPercent percent: Double) -> Double {
        let fraction = max(0, min(100, percent)) / 100
        return minimumScale + (1 - minimumScale) * fraction
    }

    /// - Parameter percent: 0...100, clamped so the display stays legible.
    public func apply(percent: Double) {
        let value = CGGammaValue(Self.scale(forPercent: percent))

        // Scaling only the maximum keeps the curve's shape and black point,
        // which looks like a brightness change rather than a washed-out image.
        CGSetDisplayTransferByFormula(
            displayID,
            0, value, 1,
            0, value, 1,
            0, value, 1
        )
        isDimmed = true
    }

    /// Hands the display back to ColorSync. Must run on quit and on unplug:
    /// gamma is a system-wide setting that outlives the process, so skipping this
    /// leaves the screen stuck dim with no visible cause.
    public func restore() {
        guard isDimmed else { return }
        CGDisplayRestoreColorSyncSettings()
        isDimmed = false
    }

    deinit { restore() }
}
