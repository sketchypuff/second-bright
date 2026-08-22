import Foundation
import CoreGraphics
import AppKit
import Observation

/// Owns the brightness level and decides how to deliver it to the monitor.
@MainActor
@Observable
public final class BrightnessController {

    /// How brightness is actually being applied.
    public enum Mode: Equatable {
        /// Real backlight control over DDC/CI, with gamma finishing the last
        /// stretch down to black.
        case ddc
        /// Gamma dimming alone, because the panel's backlight is unreachable.
        case software
        /// No external display attached.
        case unavailable
    }

    /// Where the cursor lands the screen when it wakes a blacked-out display.
    /// Bright enough to find the slider, dim enough not to be a shock.
    public static let wakePercent: Double = 25

    /// How far the cursor must travel before it counts as "the user is looking
    /// for the screen" rather than a hand resting on the mouse.
    public static let wakeDistance: Double = 60

    /// Quiet period after the popover closes before the cursor can wake anything.
    /// Without it, the hand that just let go of the slider undoes the setting.
    public static let wakeGrace: Duration = .milliseconds(1500)

    public private(set) var mode: Mode = .unavailable
    public private(set) var displayName: String = ""

    /// 0...100. Setting this drives the monitor, throttled.
    public var percent: Double = 100 {
        didSet {
            guard percent != oldValue else { return }
            persist()
            scheduleApply()
            updateCursorWatch()
        }
    }

    /// Serial queue for DDC: the protocol needs paced, ordered, blocking I/O that
    /// must not run on the main thread or the slider would stutter.
    private let ddcQueue = DispatchQueue(label: "com.yashshenai.SecondBright.ddc")
    private var ddc: DDCService?
    /// What the panel reports as full luminance. Not always 100.
    private var ddcMaximum: UInt16 = 100
    private var dimmer: GammaDimmer?
    private var identity: DisplayIdentity?
    private var applyTask: Task<Void, Never>?
    private var cursorWatch: Task<Void, Never>?
    private var didClearStaleGamma = false
    private var isPopoverOpen = false

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Display lifecycle

    /// Re-detects the display and re-probes how it can be controlled.
    ///
    /// Called at launch and on every display reconfiguration, so unplugging the
    /// monitor, waking from sleep, or toggling HDR all converge on the right mode
    /// without the user restarting anything.
    public func refresh() {
        // A run that was force-killed while the screen was black leaves gamma
        // dark with nothing left to undo it. Clearing once at launch is the only
        // chance to rescue that user.
        if !didClearStaleGamma {
            didClearStaleGamma = true
            GammaDimmer.restoreAll()
        }

        applyTask?.cancel()
        cursorWatch?.cancel()
        cursorWatch = nil
        dimmer?.restore()
        dimmer = nil
        ddc = nil
        ddcMaximum = 100

        guard let display = DisplayIdentity.primaryExternal() else {
            identity = nil
            displayName = ""
            mode = .unavailable
            return
        }

        identity = display
        displayName = display.name
        percent = restored(for: display)

        // Probe rather than assume: a display can advertise DDC and still refuse
        // it (HDR, locked firmware, a cable that drops the I2C pair).
        if let service = DDCService.forExternalDisplay(), let reading = service.read(.luminance) {
            ddc = service
            ddcMaximum = reading.maximum
            mode = .ddc
        } else {
            mode = .software
        }

        // Both modes need gamma now: software mode for the whole range, DDC mode
        // for the stretch below the backlight's own floor.
        dimmer = GammaDimmer(displayID: display.displayID)

        applyNow()
        updateCursorWatch()
    }

    /// Restores gamma. Must be called before the process exits.
    public func shutdown() {
        applyTask?.cancel()
        cursorWatch?.cancel()
        cursorWatch = nil
        dimmer?.restore()
        dimmer = nil
    }

    // MARK: - Applying

    /// Coalesces slider traffic down to something DDC can survive, while
    /// guaranteeing the final value always lands.
    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            self?.applyNow()
        }
    }

    private func applyNow() {
        let value = percent
        switch mode {
        case .ddc:
            // Gamma first on the way down and it doesn't matter on the way up:
            // both land within a frame, and the DDC write is the slow half.
            dimmer?.apply(scale: GammaDimmer.rampScale(forPercent: value))
            guard let ddc else { return }
            let luminance = Self.luminance(forPercent: value, maximum: ddcMaximum)
            ddcQueue.async {
                ddc.write(.luminance, value: luminance)
            }
        case .software:
            dimmer?.apply(scale: GammaDimmer.scale(forPercent: value))
        case .unavailable:
            break
        }
    }

    /// Maps a user-facing percentage onto the panel's own luminance register.
    ///
    /// The maximum is whatever the display reported, which is routinely something
    /// other than 100 — writing the percentage straight through would cap a
    /// 0...255 panel at about 39% of its range.
    nonisolated public static func luminance(forPercent percent: Double, maximum: UInt16) -> UInt16 {
        let ceiling = Double(maximum > 0 ? maximum : 100)
        let fraction = max(0, min(100, percent)) / 100
        return UInt16((fraction * ceiling).rounded())
    }

    // MARK: - Waking a blacked-out screen

    /// The popover tells us when it is on screen.
    ///
    /// This matters more than it looks: on a Mac where the external monitor is
    /// the *main* display, the menu bar and this popover sit on the very screen
    /// being blacked out, so the cursor that just dragged the slider to zero is
    /// by definition on the managed display and moving. Waking during that drag
    /// makes zero unreachable.
    public func setPopoverOpen(_ open: Bool) {
        guard open != isPopoverOpen else { return }
        isPopoverOpen = open
        updateCursorWatch()
    }

    /// At zero the screen is black, which used to be the argument for never
    /// letting it get there. Instead: moving the cursor onto that display brings
    /// it back to a visible level, so the way out is the thing you'd reach for
    /// anyway.
    private func updateCursorWatch() {
        let wanted = percent == 0 && mode != .unavailable && !isPopoverOpen
        guard wanted != (cursorWatch != nil) else { return }

        guard wanted else {
            cursorWatch?.cancel()
            cursorWatch = nil
            return
        }

        // Polling the cursor rather than installing a global event monitor: the
        // position is readable with no Accessibility permission and no
        // entitlement, and this only runs while the screen is black.
        cursorWatch = Task { [weak self] in
            try? await Task.sleep(for: Self.wakeGrace)
            guard !Task.isCancelled else { return }

            // Anchored after the grace period, not before: the reference point
            // has to be where the cursor came to rest, not where it was when the
            // user was still working the slider.
            let anchor = NSEvent.mouseLocation
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }

                // Distance from the anchor rather than frame-to-frame movement:
                // a hand resting on the mouse jitters continuously, and that
                // should not count as reaching for the screen.
                let location = NSEvent.mouseLocation
                guard hypot(location.x - anchor.x, location.y - anchor.y) > Self.wakeDistance,
                      self.cursorIsOnManagedDisplay(location)
                else { continue }

                self.percent = Self.wakePercent
                return
            }
        }
    }

    private func cursorIsOnManagedDisplay(_ location: NSPoint) -> Bool {
        guard let screen = identity?.screen else { return false }
        return screen.frame.contains(location)
    }

    // MARK: - Persistence

    private func persist() {
        guard let identity else { return }
        defaults.set(percent, forKey: Self.defaultsKey(for: identity.key))
    }

    private func restored(for display: DisplayIdentity) -> Double {
        let key = Self.defaultsKey(for: display.key)
        guard defaults.object(forKey: key) != nil else { return 100 }
        return min(100, max(0, defaults.double(forKey: key)))
    }

    /// Pure, so it stays off the main actor and can be exercised directly in tests.
    nonisolated public static func defaultsKey(for displayKey: String) -> String {
        "brightness.\(displayKey)"
    }
}
