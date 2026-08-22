import Foundation
import CoreGraphics

/// Darkens a display by scaling its gamma transfer function.
///
/// This does two jobs. In software mode it is the whole brightness control, used
/// when the monitor's backlight is unreachable. In DDC mode it is the bottom of
/// the range: the backlight has a floor of its own well above black, so gamma
/// takes over below `crossoverPercent` and carries the picture the rest of the
/// way down.
///
/// On an LCD "black" means black pixels with the backlight still lit, so a faint
/// panel glow remains; on OLED it is genuinely black.
public final class GammaDimmer {

    /// Below this percentage the backlight is already at its floor, so gamma
    /// finishes the descent to black. Above it gamma stays out of the way and
    /// the backlight does the work alone.
    ///
    /// 20 leaves the ramp enough of the slider to stay controllable while
    /// keeping most of the travel on the real backlight.
    public static let crossoverPercent: Double = 20

    private let displayID: CGDirectDisplayID
    private var isDimmed = false

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    /// Full-range mapping, for software mode: 0% is black, 100% is untouched.
    ///
    /// Deliberately linear in gamma-encoded space rather than in emitted light.
    /// `CGSetDisplayTransferByFormula` scales the encoded value, and light output
    /// goes as roughly the 2.2 power of that, so a linear slider here already
    /// reads as perceptually even.
    public static func scale(forPercent percent: Double) -> Double {
        clampedFraction(percent)
    }

    /// Bottom-of-range mapping, for DDC mode: 1.0 (untouched) at and above the
    /// crossover, ramping to 0.0 at zero.
    public static func rampScale(forPercent percent: Double) -> Double {
        let value = clampedPercent(percent)
        guard value < crossoverPercent else { return 1 }
        return value / crossoverPercent
    }

    /// - Parameter scale: 0...1, from one of the mappings above.
    public func apply(scale: Double) {
        let value = CGGammaValue(max(0, min(1, scale)))

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
    /// leaves the screen stuck dark with no visible cause.
    public func restore() {
        guard isDimmed else { return }
        Self.restoreAll()
        isDimmed = false
    }

    /// Clears gamma for every display whether or not *this* object set it.
    ///
    /// Runs once at launch: if a previous run was force-killed while the screen
    /// was black, nothing else will ever undo it, and the user is left staring at
    /// a dark monitor with no way to know why.
    public static func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
    }

    private static func clampedPercent(_ percent: Double) -> Double {
        max(0, min(100, percent))
    }

    private static func clampedFraction(_ percent: Double) -> Double {
        clampedPercent(percent) / 100
    }

    deinit { restore() }
}
