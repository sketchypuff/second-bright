import Foundation
import CoreGraphics
import Observation

/// Owns the brightness level and decides how to deliver it to the monitor.
@MainActor
@Observable
public final class BrightnessController {

    /// How brightness is actually being applied.
    public enum Mode: Equatable {
        /// Real backlight control over DDC/CI.
        case ddc
        /// Gamma dimming, because the panel's backlight is unreachable.
        case software
        /// No external display attached.
        case unavailable
    }

    public private(set) var mode: Mode = .unavailable
    public private(set) var displayName: String = ""

    /// 0...100. Setting this drives the monitor, throttled.
    public var percent: Double = 100 {
        didSet {
            guard percent != oldValue else { return }
            persist()
            scheduleApply()
        }
    }

    /// Serial queue for DDC: the protocol needs paced, ordered, blocking I/O that
    /// must not run on the main thread or the slider would stutter.
    private let ddcQueue = DispatchQueue(label: "com.yashshenai.SecondBright.ddc")
    private var ddc: DDCService?
    private var dimmer: GammaDimmer?
    private var identity: DisplayIdentity?
    private var applyTask: Task<Void, Never>?

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
        applyTask?.cancel()
        dimmer?.restore()
        dimmer = nil
        ddc = nil

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
        if let service = DDCService.forExternalDisplay(), service.read(.luminance) != nil {
            ddc = service
            mode = .ddc
        } else {
            dimmer = GammaDimmer(displayID: display.displayID)
            mode = .software
        }
        applyNow()
    }

    /// Restores gamma. Must be called before the process exits.
    public func shutdown() {
        applyTask?.cancel()
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
            guard let ddc else { return }
            ddcQueue.async {
                ddc.write(.luminance, value: UInt16(value.rounded()))
            }
        case .software:
            dimmer?.apply(percent: value)
        case .unavailable:
            break
        }
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
